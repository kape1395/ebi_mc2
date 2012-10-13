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
%%  TODO: Move this documentation to the overview page, or maybe README.md.
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
%%      {queue, [
%%          {clusters, [
%%              {cluster,
%%                  ClusterName,
%%                  SshHost, SshPort, SshUser,
%%                  LocalUserDir,
%%                  ClusterCommand,
%%                  StatusCheckMS,
%%                  [{partition,
%%                      PartitionName,
%%                      MaxParallel,
%%                  }] :: ebi_mc2_arg_partition()
%%              } :: ebi_mc2_arg_cluster(),
%%          ]},
%%          {result_dir, ResultDir}
%%      ]} :: ebi_mc2_arg()
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
%%
%%  The partition load is managed based on cluster reports on currently running tasks.
%%
%%  @headerfile ebi_mc2.hrl
%%
-module(ebi_mc2_queue).
-behaviour(ebi_queue).
-export([ %% API for supervisor. 
    start_link/2
]).
-export([ %% API for ebi_mc2_simulation.
    simulation_result_generated/4,
    simulation_status_updated/3,
    register_simulation/3,
    unregister_simulation/2
]).
-export([ %% API for ebi_mc2_cluster.
    cluster_state_updated/2
]).
-export([ %% Callbacks for ebi_queue.
    start_link_spec/2,
    handle_submit/2,
    handle_delete/2,
    handle_cancel/2,
    handle_status/2,
    handle_result/2,
    init/1,
    terminate/2,
    handle_call/3,
    handle_cast/2,
    handle_info/2
]).
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
    ok = gen_server:cast(Queue, {ebi_mc2_queue, cluster_state_updated, ClusterState}),
    ok.
    

%%
%%  Invoked by ebi_mc2_simulation, when the simulation is done.
%%
-spec simulation_result_generated(pid(), list(), (completed | failed | canceled), list()) -> ok.
simulation_result_generated(Queue, SimulationId, ResultStatus, ResultData) ->
    ok = gen_server:call(Queue, {ebi_mc2_queue, simulation_result_generated, SimulationId, ResultStatus, ResultData}),
    ok.

%%
%%  Saves the state of the simulation.
%%
-spec simulation_status_updated(pid(), string(), atom()) -> ok.
simulation_status_updated(Queue, SimulationId, Status) ->
    ok = gen_server:cast(Queue, {ebi_mc2_queue, simulation_status_updated, SimulationId, Status}),
    ok.


%%
%%  Returns simulation status and the definition as well as
%%  registers the caller as a responsible for the simulation.
%%
-spec register_simulation(pid(), string(), pid()) -> {ok, #ebi_mc2_sim{}}.
register_simulation(Queue, SimulationId, SimulationPID) ->
    {ok, Simulation} = gen_server:call(Queue, {
        ebi_mc2_queue, register_simulation,
        SimulationId, SimulationPID
    }),
    {ok, Simulation}.


%%
%%  Unregisters simulation process, when it is done with it.
%%
-spec unregister_simulation(pid(), string()) -> ok.
unregister_simulation(Queue, SimulationId) ->
    ok = gen_server:cast(Queue, {ebi_mc2_queue, unregister_simulation, SimulationId}),
    ok.



%% =============================================================================
%%  Internal data structures.
%% =============================================================================


-record(target, {
    cluster     :: atom(),                  % Cluster name
    partition   :: atom(),                  % Partition name
    max         :: integer(),               % Maximum number of concurrently running simulations.
    active      :: (undefined | integer())  % Actual number of concurrently running simulations.
}).

-record(state, {
    sim_sup     :: pid(),
    all         :: reference(), % Simulations and statuses: {SimulationId, Simulation, Status, Cluster, Partition}
    running     :: reference(), % Currently running sims:   {SimulationId, PID}.
    targets     :: [#target{}], % A list of available targets.
    result_dir  :: string()     % Here all the data will be stored on the local file system.
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
init({Config = #config{clusters = Clusters, result_dir = ResultDir}, Supervisor}) ->
    self() ! {configure_supervisor, Supervisor, Config},
    CollectTargets = fun (#config_cluster{name = C, partitions = Partitions}) ->
        [#target{cluster = C, partition = P, max = M, active = undefined}
            || #config_partition{name = P, max_parallel = M} <- Partitions]
    end,
    State = #state{
        sim_sup     = undefined,
        all         = ets:new(ebi_mc2_queue_all, [private]),
        running     = ets:new(ebi_mc2_queue_running, [private]),
        targets     = lists:flatmap(CollectTargets, Clusters),
        result_dir  = ResultDir
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
handle_submit(Simulation, State = #state{all = All, sim_sup = SimSup, targets = Targets}) ->
    SimulationId = get_simulation_id(Simulation),
    ok = sim_all_add(All, Simulation),
    case find_available_target(Targets) of
        {ok, Cluster, Partition} ->
            ok = sim_all_set_target(All, SimulationId, Cluster, Partition),
            {ok, _PID} = ebi_mc2_simulation_sup:start_simulation(SimSup, SimulationId, self(), Cluster, Partition);
        {error, not_found} ->
            % Ignore this case. The simulation will be started later.
            ok
    end,
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
%%  Deletes the simulation, if it is already completed, failed or canceled.
%%
handle_delete(Simulation, State = #state{all = TableAll, result_dir = ResultDir}) ->
    SimulationId = get_simulation_id(Simulation),
    {ok, #ebi_mc2_sim{state_name = StateName}} = sim_all_get(TableAll, SimulationId),
    case ebi_mc2_simulation:terminated(StateName) of
        true ->
            ok = sim_all_delete(TableAll, SimulationId),
            ResultFile = result_file(SimulationId, ResultDir),
            case file:delete(ResultFile) of
                ok -> ok;
                {error, _Reason} -> ok
            end;
        false ->
            ok
    end,
    {ok, State}.


%%
%%  Returns results of the simulation.
%%
handle_result(Simulation, State = #state{all = TableAll, result_dir = ResultDir}) ->
    SimulationId = get_simulation_id(Simulation),
    {ok, #ebi_mc2_sim{state_name = StateName}} = sim_all_get(TableAll, SimulationId),
    case ebi_mc2_simulation:terminated(StateName) of
        true ->
            case load_result(SimulationId, ResultDir) of
                {ok, Data} -> {ok, Data, State};
                {error, Reason} -> {error, Reason, State}
            end;
        false ->
            {error, running, State}
    end.


%%
%%  Returns status of the simulation.
%%
handle_status(Simulation, State) ->
    SimulationId = get_simulation_id(Simulation),
    {ok, #ebi_mc2_sim{state_name = StateName}} = sim_all_get(State#state.all, SimulationId),
    {ok, ebi_mc2_simulation:status(StateName), State}.


%%
%%  Sync calls.
%%
handle_call({ebi_mc2_queue, register_simulation, SimulationId, SimulationPID}, _From, State) ->
    ok = sim_running_add(State#state.running, SimulationId, SimulationPID),
    {ok, MC2Sim} = sim_all_get(State#state.all, SimulationId),
    {reply, {ok, MC2Sim}, State};

handle_call({ebi_mc2_queue, simulation_result_generated, SimulationId, _ResultStatus, ResultData}, _From, State) ->
    #state{result_dir = ResultDir} = State,
    {ok, _FileName} = save_result(SimulationId, ResultData, ResultDir),
    {reply, ok, State}.


%%
%%  Async calls.
%%
handle_cast({ebi_mc2_queue, simulation_status_updated, SimulationId, Status}, State) ->
    ok = sim_all_set_status(State#state.all, SimulationId, Status),
    {noreply, State};

handle_cast({ebi_mc2_queue, unregister_simulation, SimulationId}, State) ->
    ok = sim_running_del(State#state.running, SimulationId),
    {noreply, State};

handle_cast({ebi_mc2_queue, cluster_state_updated, ClusterState}, State = #state{running = RunningSims}) ->
    F = fun (SimulationStatus = {SimulationId, RuntimeStatus, FilesystemStatus}) ->
        case sim_running_get(RunningSims, SimulationId) of
            {ok, PID} ->
                ok = ebi_mc2_simulation:status_update(PID, SimulationId, RuntimeStatus, FilesystemStatus);
            {error, not_found} ->
                error_logger:warning_msg(
                    "Simulation ~s is not running, but the report ~p came from the cluster for it.~n",
                    [SimulationId, SimulationStatus]),
                ok
        end
    end,
    ok = lists:foreach(F, ClusterState),
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
convert_config(Name, {queue, PropList}) ->
    Clusters = proplists:get_value(clusters, PropList, []),
    ResultDir = proplists:get_value(result_dir, PropList),
    #config{
        name = Name,
        clusters = [ convert_config(Name, C) || C <- Clusters ],
        result_dir = ResultDir
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
%%  Helper functions: ETS::all
%%  TODO: Move to separate module.
%% =============================================================================

%%
%%  Add new simulation to the store.
%%
sim_all_add(Table, Simulation) ->
    SimulationId = get_simulation_id(Simulation),
    true = ets:insert(Table, {SimulationId, Simulation, pending, [submit], undefined, undefined}),
    ok.


%%
%%  Delete simulation from the store.
%%
sim_all_delete(Table, SimulationId) ->
    true = ets:delete(Table, SimulationId),
    ok.

%%
%%  Get a simulation by ID.
%%
sim_all_get(Table, SimulationId) ->
    case ets:lookup(Table, SimulationId) of
        [{SID, Sim, StateName, Commands, _Cluster, _Partition}] ->
            {ok, #ebi_mc2_sim{
                simulation_id = SID,
                simulation = Sim,
                state_name = StateName,
                commands = Commands
            }};
        [] ->
            {error, not_found}
    end.


%%
%%  Update simulation status by ID.
%%
sim_all_set_status(Table, SimulationId, Status) ->
    true = ets:update_element(Table, SimulationId, {3, Status}),
    ok.


%%
%%  Update simulation target by id.
%%  The assigned target cluster and the corresponding partition are used
%%  on restart of the queue. The same simulations should be assigned to
%%  the same clusters to avoid duplicated simulations. 
%%
sim_all_set_target(Table, SimulationId, Cluster, Partition) ->
    true = ets:update_element(Table, SimulationId, [
        {5, Cluster},
        {6, Partition}
    ]),
    ok.


sim_all_add_command(Table, SimulationId, Command) ->
    Tuple = ets:lookup(Table, SimulationId),
    Commands = [Command | Tuple#ebi_mc2_sim.commands],
    true = ets:update_element(Table, SimulationId, {4, Commands}),
    ok.


%% =============================================================================
%%  Helper functions: ETS::running
%% =============================================================================


sim_running_add(Table, SimulationId, PID) ->
    true = ets:insert(Table, {SimulationId, PID}),
    ok.


sim_running_del(Table, SimulationId) ->
    true = ets:delete(Table, SimulationId),
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
find_available_target(Targets) ->
    Filter = fun
        (#target{max = M, active = A}) when A < M -> true;
        (_) -> false
    end,
    case lists:filter(Filter, Targets) of
        [] -> {error, not_found};
        [ #target{cluster = C, partition = P} | _] -> {ok, C, P}
    end.


%%
%%  Save result to the file system.
%%
save_result(SimulationId, ResultData, ResultDir) when is_list(ResultData) ->
    FileName = result_file(SimulationId, ResultDir),
    ok = file:write_file(FileName, binary:list_to_bin(ResultData)),
    {ok, FileName}.


%%
%%  Load simulation results from the file system.
%%
load_result(SimulationId, ResultDir) ->
    FileName = result_file(SimulationId, ResultDir),
    case file:read_file(FileName) of
        {ok, Binary} -> {ok, Binary};
        {error, Reason} -> {error, Reason}
    end.


%%
%%  Maps simulation ID to the name of the file, containing results of the simulation.
%%
result_file(SimulationId, ResultDir) ->
    FileName = lists:flatten([ResultDir, "/", SimulationId, ".tar.gz"]),
    FileName.


