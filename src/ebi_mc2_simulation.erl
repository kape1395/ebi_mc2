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
%%  @private
%%  Implements one running simulation. This process acts as a mediator between
%%  the queue and the corresponding cluster. Its main tasks are:
%%    * Send commands to the ebi_mc2_cluster.
%%    * Handle timeouts and retries. 
%%    * Fetch result of the simulation and store it locally.
%%    * Cleanup cluster via ebi_mc2_cluster.
%%
%%  States -> Events:
%%  (I) initializing         -> AllStateEvents, {initialize} 
%%      starting             -> AllStateEvents, timeout
%%      running              -> AllStateEvents, timeout
%%      canceling            -> AllStateEvents, timeout
%%      cleaningup_restart   -> AllStateEvents, timeout
%%      cleaningup_completed -> AllStateEvents, timeout
%%      cleaningup_canceled  -> AllStateEvents, timeout
%%      cleaningup_failed    -> AllStateEvents, timeout
%%  (F) completed
%%  (F) canceled
%%  (F) failed
%%
%%  AllStateEvents:
%%      {cluster_status, SimulationId, RuntimeStatus, FilesystemStatus}
%%      {cancel}
%%
%%  TODO: Suprasti, kaip cia reikia elgtis su timeout'ais.
%%
-module(ebi_mc2_simulation).
-behaviour(gen_fsm).
-export([ % API
    start_link/4,
    cancel/1,
    status_update/4,
    terminated/1,
    status/1
]).
-export([ % Callbacks for FSM
    init/1,
    handle_event/3,
    handle_sync_event/4,
    handle_info/3,
    terminate/3,
    code_change/4
]).
-export([ % Callbacks for FSM - States
    initializing/2,
    starting/2,
    running/2,
    canceling/2,
    cleaningup_restart/2,
    cleaningup_completed/2,
    cleaningup_canceled/2,
    cleaningup_failed/2
]).
-include("ebi.hrl").
-include("ebi_mc2.hrl").
-define(DEFAUL_TIMEOUT, 60000).



%% =============================================================================
%%  API Function Definitions
%% =============================================================================


%%
%%
%%
-spec start_link(string(), pid(), atom(), atom()) -> {ok, pid()} | term().
start_link(SimulationId, Queue, Cluster, Partition) ->
    gen_fsm:start_link(?MODULE, {SimulationId, Queue, Cluster, Partition}, []).


%%
%%
%%
cancel(PID) ->
    ok = gen_fsm:send_all_state_event(PID, {cancel}),
    ok.


%%
%%  Called from the queue when it gets a status report from the cluster.
%%
status_update(PID, SimulationId, RuntimeStatus, FilesystemStatus) ->
    ok = gen_fsm:send_all_state_event(PID, {cluster_status, SimulationId, RuntimeStatus, FilesystemStatus}),
    ok.


%%
%%  Tells, if the simulation is terminated by its status.
%%
terminated(StateName) ->
    case StateName of
        completed -> true;
        canceled -> true;
        failed -> true;
        _ -> false
    end.


%%
%%  Converts local state names to the global ones, as defined in ebi.hrl.
%%
status(StateName) ->
    case StateName of
        initializing            -> running;
        starting                -> running;
        running                 -> running;
        canceling               -> running;
        cleaningup_restart      -> running;
        cleaningup_completed    -> running;
        cleaningup_canceled     -> running;
        cleaningup_failed       -> running;
        completed               -> completed;
        canceled                -> canceled;
        failed                  -> failed;
        undefined               -> undefined
    end.



%% =============================================================================
%%  Internal state.
%% =============================================================================


-record(state, {
    simulation_id,
    simulation,
    queue       :: pid(),   % PID of the queue.
    cluster     :: atom(),  % Name of the cluster (the process is registered with this name)
    partition   :: atom()   % Partition name
}).



%% =============================================================================
%%  Callbacks for gen_fsm.
%% =============================================================================

%%
%%  @doc Initializes the FSM.
%%
init({SimulationId, Queue, Cluster, Partition}) ->
    gen_fsm:send_event(self(), {initialize}),
    {ok, initializing, #state{
        simulation_id = SimulationId,
        simulation = undefined,
        queue = Queue,
        cluster = Cluster,
        partition = Partition
    }}.


%%
%%  This state is a starting point of the FSM.
%%  The `initialize' event is sent from the {@link init/1}.
%%
%%  This function will restore previously stored state and send last command
%%  to self, if there was any.
%%
initializing({initialize}, State) ->
    #state{queue = Queue, simulation_id = SimulationId} = State,
    {ok, EBISim} = ebi_mc2_queue:register_simulation(Queue, SimulationId, self()),
    #ebi_mc2_sim{
        simulation = Simulation,
        state_name = SavedStateName,
        commands = Commands
    } = EBISim,
    FullState = State#state{simulation = Simulation},
    case Commands of
        [] -> ok;
        [LastCommand | _] -> gen_fsm:send_event(self(), LastCommand)
    end,
    case SavedStateName of
        undefined ->
            %% This is first start
            do_start(FullState);
        _ ->
            %% Here we have process restarts.
            {next_state, SavedStateName, FullState}
    end.


starting(timeout, StateData) ->
    {next_state, starting, StateData}.


running(timeout, StateData) ->
    {next_state, running, StateData}.


canceling(timeout, StateData) ->
    {next_state, canceling, StateData}.


cleaningup_restart(timeout, StateData) ->
    {next_state, cleaningup_restart, StateData}.


cleaningup_completed(timeout, StateData) ->
    {next_state, cleaningup_completed, StateData}.


cleaningup_canceled(timeout, StateData) ->
    {next_state, cleaningup_canceled, StateData}.


cleaningup_failed(timeout, StateData) ->
    {next_state, cleaningup_failed, StateData}.


%%
%%  Handle all state events.
%%
handle_event({cluster_status, SimulationId, RTStatus, FSStatus}, StateName, StateData) ->
    #state{simulation_id = SimulationId, queue = Queue, cluster = Cluster} = StateData,
    RT = {_RTStatusCode, _RTStatusGroup} = slurm_job_status(RTStatus),
    FS = {_FSStatusCode, _FSStatusGroup} = slurm_sim_status(FSStatus),
    Action = case {StateName, RT, FS} of
        {starting,  {_, undefined}, _}              -> ignore;
        {starting,  {_, running},   _}              -> {next_state, running, StateData};
        {starting,  {_, failed},    _}              -> {finalize, failed};
        {starting,  {_, completed}, _}              -> {finalize, completed};
        {running,   {_, undefined}, {_, undefined}} -> restart;
        {running,   {_, undefined}, {_, started}}   -> clean_restart;
        {running,   {_, undefined}, {compleetd, _}} -> {finalize, completed};
        {running,   {_, undefined}, {failed, _}}    -> {finalize, failed};
        {running,   {_, running},   _}              -> ignore;
        {running,   {_, failed},    _}              -> {finalize, failed};
        {running,   {_, completed}, _}              -> {finalize, completed};
        {canceling, {_, undefined}, _}              -> {finalize, canceled};
        {canceling, {_, running},   _}              -> ignore;
        {canceling, {_, failed},    _}              -> {finalize, canceled};
        {canceling, {_, completed}, _}              -> {finalize, canceled};
        {cleaningup_restart, _,     {_, undefined}} -> restart;
        {cleaningup_restart, _,     {_, _}}         -> ignore;
        {cleaningup_completed, _,   {_, undefined}} -> {finished, completed};
        {cleaningup_completed, _,   {_, _}}         -> ignore;
        {cleaningup_canceled, _,    {_, undefined}} -> {finished, canceled};
        {cleaningup_canceled, _,    {_, _}}         -> ignore;
        {cleaningup_failed, _,      {_, undefined}} -> {finished, failed};
        {cleaningup_failed, _,      {_, _}}         -> ignore
    end,
    case Action of
        {next_state, NextState, _}    ->
            ok = ebi_mc2_queue:simulation_status_updated(Queue, SimulationId, NextState),
            Action;
        {next_state, NextState, _, _} ->
            ok = ebi_mc2_queue:simulation_status_updated(Queue, SimulationId, NextState),
            Action;
        {finalize, ResultStatus} ->
            {ok, SimulationId, ResultData} = ebi_mc2_cluster:simulation_result(Cluster, SimulationId),
            ok = ebi_mc2_queue:simulation_result_generated(Queue, SimulationId, ResultStatus, ResultData),
            do_cleanup(StateData, ResultStatus);
        {finished, TerminalState} ->
            ok = ebi_mc2_queue:simulation_status_updated(Queue, SimulationId, TerminalState),
            ok = ebi_mc2_queue:unregister_simulation(Queue, SimulationId),
            {stop, normal, StateData};
        ignore ->
            {next_state, StateName, StateData};
        clean_restart ->
            do_cleanup(StateData, restart);
        restart ->
            do_start(StateData)
    end;


handle_event({cancel}, StateName, StateData) ->
    Action = case StateName of
        starting             -> cancel;
        running              -> cancel;
        canceling            -> ignore;
        cleaningup_restart   -> cancel;
        cleaningup_completed -> ignore;
        cleaningup_canceled  -> ignore;
        cleaningup_failed    -> ignore
    end,
    case Action of
        cancel -> do_cancel(StateData);
        ignore -> {next_state, StateName, StateData}
    end.


%%
%%  The following callbacks are unused here.
%%
handle_sync_event(_Event, _From, StateName, State) -> {reply, ok, StateName, State}.
handle_info(_Info, StateName, State) -> {next_state, StateName, State}.
terminate(_Reason, _StateName, _State) -> ok.
code_change(_OldVsn, StateName, State, _Extra) -> {ok, StateName, State}.



%% =============================================================================
%%  Internal functions.
%% =============================================================================


%%
%%
%%
do_start(StateData) ->
    #state{
        cluster = Cluster, partition = Partition, simulation = Simulation,
        simulation_id = SimulationId, queue = Queue
    } = StateData,
    NextState = starting,
    ok = ebi_mc2_cluster:submit_simulation(Cluster, Partition, Simulation),
    ok = ebi_mc2_queue:simulation_status_updated(Queue, SimulationId, NextState),
    {next_state, NextState, StateData, ?DEFAUL_TIMEOUT}.


%%
%%
%%
do_cleanup(StateData, NextStateName) ->
    #state{cluster = Cluster, queue = Queue, simulation_id = SimulationId} = StateData,
    ok = ebi_mc2_cluster:delete_simulation(Cluster, SimulationId),
    CleanupState = case NextStateName of
        restart   -> cleaningup_restart;
        completed -> cleaningup_completed;
        canceled  -> cleaningup_canceled;
        failed    -> cleaningup_failed
    end,
    ok = ebi_mc2_queue:simulation_status_updated(Queue, SimulationId, CleanupState),
    {next_state, CleanupState, StateData}.


%%
%%
%%
do_cancel(StateData) ->
    #state{simulation_id = SimulationId, cluster = Cluster, queue = Queue} = StateData,
    NextState = canceling,
    ok = ebi_mc2_cluster:cancel_simulation(Cluster, SimulationId),
    ok = ebi_mc2_queue:simulation_status_updated(Queue, SimulationId, NextState),
    {next_state, NextState, StateData, ?DEFAUL_TIMEOUT}.


%%
%%  Maps SLURM job status codes to some erlang atoms.
%%  See https://computing.llnl.gov/linux/slurm/squeue.html.
%%
-spec slurm_job_status(string()) -> {Code :: atom(), State :: (undefined | failed | completed | running)}.
slurm_job_status(Status) ->
    case Status of
        undefined ->
            % Artifical: cluster has no info about the simulation.
            {undefined, undefined};
        "UNKNOWN" ->
            % Artifical: cluster has no info about the simulation.
            {undefined, undefined};
        "CANCELLED" ->
            % Job was explicitly cancelled by the user or system administrator.
            % The job may or may not have been initiated.
            {canceled, failed};
        "COMPLETED" ->
            % Job has terminated all processes on all nodes.
            {completed, completed};
        "CONFIGURING" ->
            % Job has been allocated resources, but are waiting for
            % them to become ready for use (e.g. booting).
            {configuring, running};
        "COMPLETING" ->
            % Job is in the process of completing.
            % Some processes on some nodes may still be active.
            {completing, running};
        "FAILED" ->
            % Job terminated with non-zero exit code or other failure condition.
            {failed, failed};
        "NODE_FAIL" ->
            % Job terminated due to failure of one or more allocated nodes.
            {node_fail, failed};
        "PENDING" ->
            % Job is awaiting resource allocation.
            {pending, running};
        "PREEMPTED" ->
            % Job terminated due to preemption.
            {preempted, failed};
        "RUNNING" ->
            % Job currently has an allocation.
            {running, running};
        "SUSPENDED" ->
            % Job has an allocation, but execution has been suspended.
            {suspended, running};
        "TIMEOUT" ->
            % Job terminated upon reaching its time limit.
            {timeout, running}
    end.


%%
%%  Maps simulation status (stored on the filesystem) to some erlang atoms.
%%
slurm_sim_status(Status) ->
    case Status of
        undefined ->
            {undefined, undefined};
        "UNKNOWN" ->
            {undefined, undefined};
        "STARTED" ->
            {started, started};
        "STOPPED_SUCCESSFUL" ->
            {completed, stopped};
        "STOPPED_FAILED" ->
            {failed, stopped};
        "STOPPED_" ->
            {failed, stopped}
    end.

