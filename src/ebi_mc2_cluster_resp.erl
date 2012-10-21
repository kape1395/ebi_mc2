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

%%  @doc Cluster response parser.
%%  States:
%%  (i) idle
%%      store_config
%%      cluster_status
%%      submit_simulation
%%      delete_simulation
%%      cancel_simulation
%%      simulation_result
%%
-module(ebi_mc2_cluster_resp).
-behaviour(gen_fsm).
-export([   % API
    start_link/1,
    add_call/4,
    response_lines/2
]).
-export([   % FSM states
    idle/2,
    store_config/2,
    cluster_status/2,
    submit_simulation/2,
    delete_simulation/2,
    cancel_simulation/2,
    simulation_result/2
]).
-export([   % FSM other callbacks
    init/1,
    terminate/3,
    code_change/4,
    handle_event/3,
    handle_sync_event/4,
    handle_info/3
]).
-include("ebi.hrl").
-include("ebi_mc2.hrl").

%% =============================================================================
%%  API.
%% =============================================================================


%%
%%  Start the cluster connection.
%%
start_link(Cluster) ->
    gen_fsm:start_link(?MODULE, {Cluster}, []).


%%
%%  Add command who's response should be parsed.
%%
-spec add_call(pid(), string(), atom(), term()) -> ok.
add_call(PID, CallRef, Command, From) ->
    gen_fsm:sync_send_all_state_event(PID, {add_call, CallRef, Command, From}).


%%
%%  Parse response line.
%%
-spec response_lines(pid(), [binary()]) -> ok.
response_lines(PID, ResponseLines) ->
    lists:foreach(fun (L) -> gen_fsm:send_all_state_event(PID, {line, L}) end, ResponseLines),
    ok.



%% =============================================================================
%%  Internal state
%% =============================================================================

-record(cmd, {
    call_ref,       % Command call (instance / execurion) reference / ID.
    name,           % Command name,
    from            % Originator of the command.
}).
-record(state, {
    cluster,        % Cluster, which commands are processes
    cmd :: #cmd{},  % Current command.
    res,            % Response of the command `cmd'.
    cmds            % Queue of commands.
}).



%% =============================================================================
%%  Callbacks for GEN_FSM.
%% =============================================================================


%%
%%  Initialization.
%%
init({Cluster}) ->
    StateData = #state{
        cluster = Cluster,
        cmd = undefined,
        cmds = queue:new()
    },
    {ok, idle, StateData}.


%%
%%  Handles IDLE state.
%%
idle(_Event, StateData) ->
    {stop, error, idle, StateData}.


%%
%%  Handles output of the "store_config" command.
%%
store_config({out, <<"STORED">>}, StateData) ->
    respond_and_process_next(stored, StateData);

store_config({out, <<"EXISTING">>}, StateData) ->
    respond_and_process_next(existing, StateData).


%%
%%  Handles output of the "cluster_status" command.
%%
cluster_status({out, <<"CLUSTER_STATUS:START">>}, StateData) ->
    {next_state, cluster_status, StateData#state{res = []}};

cluster_status({out, <<"CLUSTER_STATUS:END">>}, StateData = #state{res = Res}) ->
    respond_and_process_next({cluster_status, Res}, StateData#state{res = undefined});

cluster_status({data, <<Type:2/binary, ":", SimulationId:40/binary, ":", StatusAndJobId/binary>>}, StateData) ->
    #state{res = Res} = StateData,
    StatusType = case Type of
        <<"FS">> -> fs;
        <<"RT">> -> rt
    end,
    [Status, _JobId] = binary:split(StatusAndJobId, <<":">>),
    StatusRecord = {StatusType,
        binary_to_list(SimulationId),
        binary_to_list(Status)
    },
    {next_state, simulation_result, StateData#state{res = [StatusRecord | Res]}}.


%%
%%  Handles output of the "submit_simulation" command.
%%
submit_simulation({out, <<"SUBMITTED:", _SimulationId:40/binary, ":", _JobId/binary>>}, StateData) ->
    respond_and_process_next(ok, StateData);

submit_simulation({out, <<"DUPLICATE:", _SimulationId:40/binary>>}, StateData) ->
    respond_and_process_next(ok, StateData).


%%
%%  Handles output of the "delete_simulation" command.
%%
delete_simulation({out, <<"DELETED:", _SimulationId:40/binary>>}, StateData) ->
    respond_and_process_next(ok, StateData);

delete_simulation({out, <<"DELETE:", SimulationId:40/binary, ":SIM_RUNNING">>}, StateData) ->
    log_err("Simulation ~s not deleted (still running)", [SimulationId]),
    respond_and_process_next(ok, StateData).


%%
%%  Handles output of the "cancel_simulation" command.
%%
cancel_simulation({out, <<"CANCELLED:", _SimulationId:40/binary>>}, StateData) ->
    respond_and_process_next(ok, StateData).


%%
%%  Handles output of the "simulation_result" command.
%%
simulation_result({out, <<"RESULT:", _SimulationId:40/binary, ":SIM_RUNNING">>}, StateData) ->
    respond_and_process_next(error, StateData);

simulation_result({out, <<"RESULT:", _SimulationId:40/binary, ":NOT_FOUND">>}, StateData) ->
    respond_and_process_next(error, StateData);

simulation_result({out, <<"RESULT:", _SimulationId:40/binary, ":START">>}, StateData) ->
    {next_state, simulation_result, StateData#state{res = []}};

simulation_result({out, <<"RESULT:", _SimulationId:40/binary, ":END">>}, StateData = #state{res = ResultLines}) ->
    respond_and_process_next(lists:reverse(ResultLines), StateData#state{res = undefined});

simulation_result({data, MsgBase64}, StateData = #state{res = ResultLines}) ->
    DecodedMsg = base64:decode(MsgBase64),
    {next_state, simulation_result, StateData#state{res = [DecodedMsg | ResultLines]}}.



%% =============================================================================
%%  FSM all state events.
%% =============================================================================


%%
%%  Synchronous all state events: add_call.
%%
handle_sync_event({add_call, CallRef, Command, From}, _SyncFrom, idle, StateData) ->
    Cmd = #cmd{call_ref = CallRef, name = Command, from = From},
    {reply, ok, Command, StateData#state{cmd = Cmd}}.


%%
%%  Handles response line event.
%%
handle_event({line, ResponseLine}, StateName, StateData = #state{cmd = Command}) ->
    case ResponseLine of
        <<"#CLUSTER:LGN(0000000000000000000000000000000000000000)==>", _Msg/binary>> ->
            {next_state, StateName, StateData};
        <<"#CLUSTER:OUT(", CallRefBin:40/binary, ")==>", Msg/binary>> ->
            CallRef = binary:bin_to_list(CallRefBin),
            #cmd{call_ref = CommandCallRef} = Command,
            case CallRef of
                CommandCallRef ->
                    gen_fsm:send_event(self(), {out, Msg}),
                    {next_state, StateName, StateData};
                _ ->
                    log_err("line(OUT): wrong call ref, expected ~p, line=~p", [CommandCallRef, ResponseLine]),
                    {stop, error, StateName, StateData}
            end;
        <<"#CLUSTER:ERR(", CallRefBin:40/binary, ")==>", ErrCode:3/binary, ":", ErrMsg/binary>> ->
            log_err("line(ERR): ref=~p, code=~p, msg=~p", [CallRefBin, ErrCode, ErrMsg]),
            CallRef = binary:bin_to_list(CallRefBin),
            #cmd{call_ref = CommandCallRef} = Command,
            case CallRef of
                CommandCallRef ->
                    respond_and_process_next(error, StateData);
                _ ->
                    log_err("line(ERR): wrong call ref, expected ~p, line=~p", [CommandCallRef, ResponseLine]),
                    {stop, error, StateName, StateData}
            end;
        <<"#DATA:", MsgBase64/binary>> ->
            gen_fsm:send_event(self(), {data, MsgBase64}),
            {next_state, StateName, StateData};
        <<"#", _Msg/binary>> ->
            log_err("line(#??): ~p", [ResponseLine]),
            {next_state, StateName, StateData};
        _ ->
            log_err("line(???): ~p", [ResponseLine]),
            {next_state, StateName, StateData}
    end.



%% =============================================================================
%%  Internal functions
%% =============================================================================


%%
%%  Send the call response to the cluster and proceed with next command. 
%%
respond_and_process_next(Response, StateData = #state{cluster = Cluster, cmd = Command, cmds = Commands}) ->
    case Command of
        #cmd{from = undefined} ->
            ok;
        #cmd{from = From} ->
            ok = ebi_mc2_cluster:response(Cluster, Response, From)
    end,
    case queue:is_empty(Commands) of
        true ->
            {next_state, idle, StateData#state{cmd = undefined, res = undefined}};
        false ->
            NewCommand = queue:head(Commands),
            NewStateData = StateData#state{cmd = NewCommand, res = undefined, cmds = queue:tail(Commands)},
            #cmd{name = NewCommandName} = NewCommand,
            {next_state, NewCommandName, NewStateData}
    end.


%%
%%  Logs errors in a uniform way. 
%%
log_err(Msg, Args) ->
    error_logger:error_msg("~s: " ++ Msg ++ "~n", [?MODULE | Args]).



%% =============================================================================
%%  Other FSM callbacks.
%% =============================================================================


handle_info(_Event, _StateName, StateData) ->
    {stop, error, StateData}.


terminate(_Reason, _StateName, _StateData) ->
    ok.


code_change(_OldVsn, StateName, StateData, _Extra) ->
    {ok, StateName, StateData}.


