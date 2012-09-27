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

%%
%%  @doc Queue implementation for delegating calculations to the "MIF cluster v2".
%%  A structure of this module is the following:
%%  ``` OUTDATED:
%%  + bio_ers_queue_mifcl2_sup.erl (main supervisor)
%%    |       Supervisor for all the queue implementation (mifcl2).
%%    |
%%    + bio_ers_queue_mifcl2.erl  (api)
%%    |       Interfafe module for all the queue implementation.
%%    |       A user should invoke functions in this module only.
%%    |
%%    +bio_ers_queue_mifcl2_ssh_sup.erl (ssh supervisor)
%%      |     Supervisor for the ssh channel.
%%      |     It is needed becase ssh channel is crashing for some reason
%%      |     after some time of inactivity.
%%      |
%%      + bio_ers_queue_mifcl2_ssh_chan.erl (ssh channel)
%%            Implementation of the communication via SSH.
%%  '''
%%
%%  The main task for this module (apart from being interface) is to store
%%  all ongoing calls for the case, if the {@link bio_ers_queue_mifcl2_ssh_chan. SSH channel}
%%  is restarted and should redo the operations, that were performed at that time.
%%
-module(bio_ers_queue_mifcl2).
-behaviour(bio_ers_queue).
-export([start_link/3]). % API
-export([handle_submit/2, handle_delete/2, handle_cancel/2, handle_status/2, handle_result/2]). % CB
-export([init/1, terminate/2, handle_call/3, handle_cast/2, handle_info/2]). % CB
-export([get_simulation_id/1]).
-include("bio_ers.hrl").
-include("bio_ers_queue_mifcl2.hrl").


-record(state, {cfg = #cfg{}, running = [], pending = []}).


%% =============================================================================
%%  API.
%% =============================================================================

%%
%%  @doc Create this queue.
%%  Configuration in its external form should be passed here as the `ExternalCfg'
%%  parameter, and its structure should be as follows.
%%  ````
%%      {bio_ers_queue_mifcl2, QueueName, [
%%          {partition, PartitionName,
%%              SshHost, SshPort, SshUser, LocalUserDir,
%%              ClusterCommand, ClusterPartition,
%%              MaxParallelJobs, StatusCheckMS
%%          }
%%      ]}
%%  ''''
%%  Multiple partitions can be listed here.
%%
-spec start_link(term(), term(), pid()) -> {ok, pid()} | term().
start_link(Name, ExternalCfg, Supervisor) ->
    bio_ers_queue:start_link(Name, ?MODULE, {Name, ExternalCfg, Supervisor}).



%% =============================================================================
%%  Callbacks.
%% =============================================================================


%%
%%
init({_Name, ExternalCfg, Supervisor}) ->
    State = #state{
        cfg = mk_cfg(ExternalCfg),
        pending = [],
        running = []
    },
    self() ! {configure_supervisor, Supervisor},
    {ok, State}.


%%
%%
%%
terminate(_Reason, _State) ->
    ok.


%%
%%
%%
handle_submit(_Simulation, State) ->
    {ok, State}.


%%
%%
%%
handle_cancel(_Simulation, State) ->
    {ok, State}.


%%
%%
%%
handle_delete(_Simulation, State) ->
    {ok, State}.


%%
%%
%%
handle_result(_Simulation, State) ->
    {error, undefined, State}.


%%
%%
%%
handle_status(_Simulation, State) ->
    {ok, undefined, State}.


%%
%%  Sync calls.
%%
handle_call(_Message, _From, State) ->
    {stop, badarg, State}.


%%
%%  Async calls.
%%
handle_cast(_Message, State) ->
    {noreply, State}.


%%
%%  Other messages:
%%    configure_supervisor -- start ssh_sup and pass out PID to it.
%%
handle_info({configure_supervisor, Supervisor}, State = #state{cfg = Cfg}) ->
    #cfg{partitions = PartitionCfgs} = Cfg,
    bio_ers_queue_mifcl2_sup:create_partitions(Supervisor, PartitionCfgs, self()),
    {noreply, State}.



%% =============================================================================
%%  Other.
%% =============================================================================

mk_cfg(ExternalCfg) ->
    {Name, Partitions} = ExternalCfg,
    #cfg{
        name = Name,
        partitions = [ mk_part_cfg(EPC) || EPC <- Partitions ]
    }.

mk_part_cfg(ExternalPartitionCfg) ->
    {Name, Host, Port, User, LUDir, CCmd, CPart, MPJ, SCMS} = ExternalPartitionCfg,
    #part_cfg{
        name = Name,
        ssh_host = Host,
        ssh_port = Port,
        ssh_user = User,
        local_user_dir = LUDir,
        cluster_command = CCmd,
        cluster_partition = CPart,
        max_parallel_jobs = MPJ,
        status_check_ms = SCMS
    }.

%%
%%  @doc Get simulation id, or generate it.
%%  @spec get_simulation_id(Simulation | SimulationId) -> SimulationId
%%
get_simulation_id(Simulation) when is_record(Simulation, simulation) ->
    case Simulation#simulation.id of
        undefined -> bio_ers:get_id(Simulation);
        SimId     -> SimId
    end;
get_simulation_id(SimulationId) when is_list(SimulationId) ->
    SimulationId.

