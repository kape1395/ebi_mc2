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
%%  States:
%%  (I) initializing
%%          run -> starting | running.
%%      starting
%%          cancel_command ->
%%          status_updated ->
%%      running
%%          cancel_command ->
%%          status_updated ->
%%      canceling
%%          cancel_command ->
%%          status_updated ->
%%      saving_results ->
%%          cancel_command ->
%%          status_updated ->
%%      cleaning_up (done, failed, canceled) ->
%%          cancel_command ->
%%          status_updated ->
%%  (F) done
%%  (F) failed
%%  (F) canceled
%%
%%  Events:
%%      {run} -- from self
%%      {status_changed, old_status, new_status} -- from cluster
%%      {cancel}
%%
%%
-module(ebi_mc2_simulation).
-behaviour(gen_fsm).
-export([start_link/4, cancel/1]). % API
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).
-export([ % FSM States
    initializing/2,
    starting/2,
    running/2,
    canceling/2,
    saving_results/2,
    cleaning_up/2
]).
-include("ebi.hrl").
-include("ebi_mc2.hrl").
-define(DEFAUL_TIMEOUT, 60000).



%% =============================================================================
%%  API Function Definitions
%% =============================================================================


start_link(SimulationId, Queue, Cluster, Partition) ->
    gen_fsm:start_link(?MODULE, {SimulationId, Queue, Cluster, Partition}, []).


cancel(PID) ->
    gen_fsm:send_event(PID, cancel_command),
    ok.


%% =============================================================================
%%  Internal state.
%% =============================================================================


-record(state, {
    simulation_id,
    simulation,
    queue,
    cluster,
    partition
}).



%% =============================================================================
%%  Callbacks for gen_fsm.
%% =============================================================================

%%
%%  @doc Initializes the FSM.
%%
init({SimulationId, Queue, Cluster, Partition}) ->
    gen_fsm:send_event(self(), run),
    {ok, initializing, #state{
        simulation_id = SimulationId,
        simulation = undefined,
        queue = Queue,
        cluster = Cluster,
        partition = Partition
    }}.


%%
%%  This state is a starting point of the FSM.
%%  The `run' event is sent from the {@link init/1}.
%%
initializing(run, State = #state{queue = Queue, simulation_id = SID}) ->
    {ok, EBISim} = ebi_mc2_queue:register_simulation(Queue, SID, self()),
    #ebi_mc2_sim{sim = Sim, status = Status, cmds = Cmds} = EBISim,
    [LastCommand | _] = Cmds,
    case LastCommand of
        submit ->
            case Status of
                pending -> {starting};
                starting -> {starting};
                running -> {running};
                canceling -> {canceling};
                saving_results -> {result, saving_results};
                cleaning_up -> {ok};
                done -> {ok};
                failed -> {ok};
                canceled -> {ok}
            end;
        cancel ->
            ok
    end,
    case Status of
        pending -> {start, starting};
        starting -> {start, starting};
        running -> {none, running};
        canceling -> {cancel, canceling};
        saving_results -> {result, saving_results};
        cleaning_up -> ok;
        done -> ok;
        failed -> ok;
        canceled -> ok
    end,
    {next_state, initializing, State#state{simulation = Sim}, ?DEFAUL_TIMEOUT}.


starting(timeout, State) ->
    %?SSH:submit_simulation(Ssh, Sim),
    {next_state, starting, State, ?DEFAUL_TIMEOUT}.

running(_Event, State) ->
    {next_state, running, State}.

canceling(_Event, State) ->
    {next_state, running, State}.

saving_results(_Event, State) ->
    {next_state, running, State}.

cleaning_up(_Event, State) ->
    {next_state, running, State}.


% done      -- terminal
% failed    -- terminal


%%
%%  Unused.
%%
handle_event(_Event, StateName, State) ->
    {next_state, StateName, State}.

%%
%%  Unused.
%%
handle_sync_event(_Event, _From, StateName, State) ->
    {reply, ok, StateName, State}.

%%
%%  Unused.
%%
handle_info(_Info, StateName, State) ->
    {next_state, StateName, State}.

%%
%%  Unused.
%%
terminate(_Reason, _StateName, _State) ->
    ok.

%%
%%  Unused.
%%
code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

%%
%%  Save result to the file system.
%%
save_result(ID, Data, Dir) ->
    ok = file:write_file(Dir ++ "/" ++ ID ++ ".tar.gz", Data).


