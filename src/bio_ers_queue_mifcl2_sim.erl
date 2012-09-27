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
-module(bio_ers_queue_mifcl2_sim).
-behaviour(gen_fsm).
-export([start_link/3]). % API
-export([init/2, starting/2]). % FSM States
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).
-include("bio_ers.hrl").

-define(SERVER, ?MODULE).
-define(SSH, bio_ers_queue_mifcl2_ssh_chan).
-define(START_TIMEOUT, 10000).

-record(cfg, {dir}).
-record(state, {id, sim, ssh, cfg=#cfg{}}).


%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link(Queue, SshChan, Simulation) ->      % FIXED according to supervisor.
    gen_fsm:start_link(?MODULE, {Queue, SshChan, Simulation}, []).



%% ------------------------------------------------------------------
%% gen_fsm Function Definitions
%% ------------------------------------------------------------------

%%
%%  @spec init({Simulation::#simulation{}, SshChannel::pid(), Cfg::config()}) -> State::#state{}
%%  where
%%      config() = {Dir::string()}
%%
%%  @doc Initializes the FSM.
%%  Here Dir stands for a directory name, where the simulation results should be stored.
%%
init({Simulation, SshChannel, Cfg}) ->
    ID = bio_ers_queue_mifcl2:get_simulation_id(Simulation),
    gen_fsm:send_event(self(), run),
    {ok, init, #state{
        id = ID,
        sim = Simulation#simulation{id = ID},
        ssh = SshChannel,
        cfg = Cfg
    }}.


%%
%%  @spec init(Event, State::#state{}) -> Transition
%%  where
%%      Event = run
%%
%%  @doc FSM State `init'. It is used as a starting point in the fsm.
%%  The `run' event is sent from the {@link init/1}.
%%
init(run, State = #state{id = ID, sim = Sim, ssh = Ssh, cfg = #cfg{dir = Dir}}) ->
   %%
   %%  XXX: Neteisingai. Cia dubliuojam visas kitas busenas.
   %%  Nusipaisyti FSM, paziureti, koks rysys tarp MIF ir mano serverio.
   %%

%XXX

    NextState = case ?SSH:simulation_status(Ssh, Sim) of
        {ok, Sim, unknown} ->
            ok = ?SSH:submit_simulation(Ssh, Sim),
            starting;
        {ok, Sim, pending} ->
            running;
        {ok, Sim, running} ->
            running;
        {ok, Sim, failed} ->                                  % ??? RESTART NEEDED?
            ok = ?SSH:delete_simulation(Ssh, Sim),
            ok = ?SSH:submit_simulation(Ssh, Sim),
            starting;
        {ok, Sim, done} ->
            case ?SSH:simulation_result(Ssh, Sim) of
                {ok, ID, Result} ->
                    ok = save_result(ID, Result, Dir),
                    done;
                {error, ID, _Reason} ->
                    failed
            end
    end,
    {next_state, NextState, State, ?START_TIMEOUT}.


starting(timeout, State = #state{sim = Sim, ssh = Ssh}) ->
    ?SSH:submit_simulation(Ssh, Sim),
    {next_state, starting, State, ?START_TIMEOUT}.

running(Event, State) ->
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

save_result(ID, Data, Dir) ->
    ok = file:write_file(Dir ++ "/" ++ ID ++ ".tar.gz", Data).


