%
% Copyright 2012 Karolis Petrauskas
%
% Licensed under the Apache License, Version 2.0 (the "License");
% you may not use this file except in compliance with the License.
% You may obtain a copy of the License at
%
%     http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS,
% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
% See the License for the specific language governing permissions and
% limitations under the License.
%

%%  @doc
%%
%%  A queue implementation for delegating calculations to the "MIF cluster v2".
%%  A structure of this module is the following:
%%  ````
%%  + ebi_mc2_sup.erl (supervisor)
%%    |       Supervisor for all the queue implementation (ebi_mc2).
%%    |
%%    + ebi_mc2_queue.erl  (ebi_queue)
%%    |       Interfafe module and all the queue implementation.
%%    |       A user should invoke functions in this module only.
%%    |
%%    +ebi_mc2_simulation_sup.erl (supervisor)
%%    | |     Supervisor for the simulation processes (FSMs).
%%    | |
%%    | + ebi_mc2_simulation.erl (gen_fsm)
%%    |       Implementation of the communication via SSH.
%%    |
%%    + ebi_mc2_cluster_sup.erl (supervisor)
%%      |     Supervisor for all the cluster ssh connections.
%%      |
%%      + ebi_mc2_cluster.erl (ssh_channel)
%%            Implementation of the communication via SSH.
%%  ''''
%%
%%  Apart from implementing a queue interface, this module is responsible for persistence of the
%%  submitted jobs and limitation parallel jobs submitted to the cluster.
%%
%%  The module should be started by attaching a child specification returned by the function
%%  {@link start_link_spec/2} to the application's supervision tree. The parameters for this
%%  module (Args) should be in the following form:
%%  ````
%%      {queue,
%%          [{cluster,
%%              ClusterName,
%%              SshHost, SshPort, SshUser,
%%              LocalUserDir,
%%              ClusterCommand,
%%              StatusCheckMS,
%%              [{partition,
%%                  PartitionName,
%%                  MaxParallel,
%%              }] :: ebi_mc2_arg_partition()
%%          }] :: ebi_mc2_arg_cluster()
%%      } :: ebi_mc2_arg()
%%  ''''
%%  A name for the queue is passed as a Name argument to the function {@link start_link_spec/2},
%%  therefore it is not presented in the structure above.
%% 
%%  Only one cluster is currently supported. The ClusterName parameter is similarily used
%%  for the internal ssh_channel processes, so both names should be atoms.
%%
%%  The queue maintains a connection per cluster. It connects to the cluster using SSH with
%%  SshUser@SshHost:SshPort/LocalUserDir.
%%
%%  ClusterCommand is used to specify a program or script implementing the communication protocol.
%%
%%  StatusCheckMS is used to setup timer for batch status checks of the currently running simulations.
%%
%%  The cluster can have multiple queues. The {partition, ...} part specified, what partitions should
%%  be used and how many parallel jobs should be delegated to each of them.
%%
%%  @headerfile ebi_mc2.hrl
%%
-module(ebi_mc2_queue).
-behaviour(ebi_queue).
-export([start_link/2, cluster_state_updated/2, simulation_status_updated/3, register_simulation/3]). % API
-export([start_link_spec/2, handle_submit/2, handle_delete/2, handle_cancel/2, handle_status/2, handle_result/2]). % CB
-export([init/1, terminate/2, handle_call/3, handle_cast/2, handle_info/2]). % CB
-export([get_simulation_id/1]).
-include("ebi.hrl").
-include("ebi_mc2.hrl").



%% =============================================================================
%%  API.
%% =============================================================================


%%
%%  @doc Create this queue.
%%  Invoked by the {@link ebi_mc2_sup}.
%%
-spec start_link(#config{}, pid()) -> {ok, pid()} | term().
start_link(Config = #config{name = Name}, Supervisor) ->
    ebi_queue:start_link({local, Name}, ?MODULE, {Config, Supervisor}).


%%
%%  Invoked by the {@link ebi_mc2_cluster} periodically passing current state
%%  of all cluster simulations.
%%
-spec cluster_state_updated(pid(), term()) -> ok.
cluster_state_updated(Queue, ClusterState) ->
    gen_server:cast(Queue, {ebi_mc2_queue, cluster_state_updated, ClusterState}).
    

%%
%%  Saves the state of the simulation.
%%
-spec simulation_status_updated(pid(), string(), atom()) -> ok.
simulation_status_updated(Queue, SimulationId, Status) ->
    gen_server:cast(Queue, {ebi_mc2_queue, simulation_status_updated, SimulationId, Status}).


%%
%%  Returns simulation status and the definition as well as
%%  registers the caller as a responsible for the simulation.
%%
-spec register_simulation(pid(), string(), pid()) -> {ok, #ebi_mc2_sim{}}.
register_simulation(Queue, SimulationId, SimulationPID) ->
    gen_server:call(Queue, {ebi_mc2_queue, register_simulation, SimulationId, SimulationPID}).



%% =============================================================================
%%  Internal data structures.
%% =============================================================================


-record(state, {
    sim_sup,
    all,        % Simulations and statuses: {SimulationId, Simulation, Status}
    running,    % Currently running sims:   {SimulationId, PID}.
   %ord_tbl,    % Simulations order:        {SubmitDateTime, SimulationId}
    pending = [],
    clusters
}).



%% =============================================================================
%%  Callbacks for ebi_queue.
%% =============================================================================

%%
%%  @doc Here is the entry point to this application.
%%
-spec start_link_spec(atom(), ebi_mc2_arg()) -> SupervisorSpec :: tuple().
start_link_spec(Name, Args) ->
    Config = convert_config(Name, Args),
    ebi_mc2_sup:start_link_spec(Config).


%%  @doc
%%  Initializes this queue process.
%%
init({Config, Supervisor}) ->
    self() ! {configure_supervisor, Supervisor, Config},
    State = #state{
        sim_sup  = undefined,
        all      = ets:new(ebi_mc2_queue_all, [private]),
        running  = ets:new(ebi_mc2_queue_running, [private]),
        clusters = Config#config.clusters
    },
    {ok, State}.


%%  @doc
%%  Invoked, when the queue is terminating.
%%
terminate(_Reason, _State) ->
    ok.


%%
%%  Starts new simulation:
%%    Stores the simulation info locally and
%%    spawns new simulation process. 
%%
handle_submit(Simulation, State = #state{all = AllTable, sim_sup = SimSup, clusters = Clusters}) ->
    SimulationId = get_simulation_id(Simulation),
    {ok, Cluster, Partition} = find_available_partition(undefined, Clusters, AllTable),
    ok = sim_all_add(AllTable, Simulation),
    {ok, _PID} = ebi_mc2_simulation_sup:start_simulation(SimSup, SimulationId, self(), Cluster, Partition),
    {ok, State}.


%%
%%  Cancels the simulation:
%%    Stores the cancel command along with the simulation data and
%%    Informs last-known simulation process about new command.
%%
handle_cancel(Simulation, State) ->
    SimulationId = get_simulation_id(Simulation),
    {ok, PID} = sim_running_get(State#state.running, SimulationId),
    ok = sim_all_add_command(State#state.all, SimulationId, cancel),
    ok = ebi_mc2_simulation:cancel(PID),
    {ok, State}.


%%
%%
%%
handle_delete(Simulation, State) ->
    SimulationId = get_simulation_id(Simulation),
    {ok, #ebi_mc2_sim{status = Status}} = sim_all_get(State#state.all, SimulationId),
    case Status of  % TODO: Handle all states correctly.
        done -> ok
    end,
    % TODO: delete is made locally. Remote cleanup should be done by ebi_mc2_simulation.
    {ok, State}.


%%
%%
%%
handle_result(Simulation, State) ->
    {error, undefined, State}.


%%
%%  Done.
%%
handle_status(Simulation, State) ->
    SimulationId = get_simulation_id(Simulation),
    {ok, #ebi_mc2_sim{status = Status}} = sim_all_get(State#state.all, SimulationId),
    {ok, Status, State}.


%%
%%  Sync calls.
%%
handle_call({ebi_mc2_queue, register_simulation, SimulationId, SimulationPID}, _From, State) ->
    ok = sim_running_add(State#state.running, SimulationId, SimulationPID),
    {ok, MC2Sim} = sim_all_get(State#state.all, SimulationId),
    {reply, {ok, MC2Sim}, State}.


%%
%%  Async calls.
%%
handle_cast({ebi_mc2_queue, simulation_status_updated, SimulationId, Status}, State) ->
    ok = sim_all_set_status(State#state.all, SimulationId, Status),
    {noreply, State};

handle_cast({ebi_mc2_queue, cluster_state_updated, ClusterState}, State) ->
    % TODO: Make diff here.
    {noreply, State}.


%%
%%  @doc Other messages:
%%    `configure_supervisor` -- start the cluster and simulation supervisors.
%%
handle_info({configure_supervisor, Supervisor, #config{clusters = Clusters}}, State) ->
    {ok, _ClusterSup} = ebi_mc2_sup:add_cluster_sup(Supervisor, Clusters),
    {ok, SimulationSup} = ebi_mc2_sup:add_simulation_sup(Supervisor), 
    {noreply, State#state{sim_sup = SimulationSup}}.



%% =============================================================================
%%  Helper functions: Configuration
%% =============================================================================


%%
%%  Converts configuration to the internal formats (tuples to records).
%%
convert_config(Name, {queue, Clusters}) ->
    #config{
        name = Name,
        clusters = [ convert_config(Name, C) || C <- Clusters ]
    };

convert_config(Name, {cluster, ClusterName, SshHost, SshPort, SshUser, LUD, CC, SCMS, Partitions}) ->
    #config_cluster{
        name = ClusterName,
        ssh_host = SshHost,
        ssh_port = SshPort,
        ssh_user = SshUser,
        local_user_dir = LUD,
        cluster_command = CC,
        status_check_ms = SCMS,
        partitions = [ convert_config(Name, P) || P <- Partitions ]
    };

convert_config(_Name, {partition, PartitionName, MaxParallel}) ->
    #config_partition{
        name = PartitionName,
        max_parallel = MaxParallel
    }.


%% =============================================================================
%%  Helper functions: ETS
%% =============================================================================

%%
%%  Add new simulation to the store.
%%  TODO: Move to the ebi_mc2_store.
%%
sim_all_add(Table, Simulation) ->
    SimulationId = get_simulation_id(Simulation),
    true = ets:insert(Table, {SimulationId, Simulation, pending, [submit]}),
    ok.


%%
%%  Get a simulation by ID.
%%  TODO: Move to the ebi_mc2_store.
%%
sim_all_get(Table, SimulationId) ->
    case ets:lookup(Table, SimulationId) of
        [{SID, Sim, Status, Commands}] -> {ok, #ebi_mc2_sim{id = SID, sim = Sim, status = Status, cmds = Commands}};
        [] -> {error, not_found}
    end.


%%
%%  Update simulation status by ID.
%%  TODO: Move to the ebi_mc2_store.
%%
sim_all_set_status(Table, SimulationId, Status) ->
    true = ets:update_element(Table, SimulationId, {3, Status}),
    ok.


sim_all_add_command(Table, SimulationId, Command) ->
    Tuple = ets:lookup(Table, SimulationId),
    Commands = [Command | Tuple#ebi_mc2_sim.cmds],
    true = ets:update_element(Table, SimulationId, {4, Commands}),
    ok.


sim_running_add(Table, SimulationId, PID) ->
    true = ets:insert(Table, {SimulationId, PID}),
    ok.


sim_running_get(Table, SimulationId) ->
    case ets:lookup(Table, SimulationId) of
        [{_SID, PID}] -> {ok, PID};
        [] -> {error, not_found}
    end.


%% =============================================================================
%%  Helper functions: Misc
%% =============================================================================

%%
%%  @doc Get simulation id, or generate it.
%%
-spec get_simulation_id(#simulation{} | list()) -> list().
get_simulation_id(Simulation) when is_record(Simulation, simulation) ->
    case Simulation#simulation.id of
        undefined -> ebi:get_id(Simulation);
        SimId     -> SimId
    end;

get_simulation_id(SimulationId) when is_list(SimulationId) ->
    SimulationId.


%%
%%
%%
find_available_partition(undefined, [], _Table) ->
    {error, not_found};

find_available_partition(Found, [#config_cluster{partitions = []} | Clusters], Table) ->
    find_available_partition(Found, Clusters, Table);

find_available_partition(undefined, Clusters, Table) ->
    [FirstCluster | OtherClusters] = Clusters,
    [FirstPartition | OtherPartitions] = FirstCluster#config_cluster.partitions,
    % TODO: Check.
    NewFound = case z of
        a -> {ok, FirstCluster, FirstPartition};
        z -> {error, full}
    end,
    NewClusters = [FirstCluster#config_cluster{partitions = OtherPartitions} | OtherClusters],
    find_available_partition(NewFound, NewClusters, Table).

