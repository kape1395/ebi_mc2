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
-export([   % API
    init/0,
    add_call/2,
    parse_lines/2
]).
-include("ebi.hrl").
-include("ebi_mc2.hrl").


%% =============================================================================
%%  Internal state
%% =============================================================================

-record(cmd, {
    call_ref,       % Command call (instance / execurion) reference / ID.
    name,           % Command name,
    from            % Originator of the command.
}).
-record(state, {
    res,            % Response of the command `cmd'
    cmd :: #cmd{},  % Current command name (head of cmds).
    cmds            % Queue of commands.
}).



%% =============================================================================
%%  API.
%% =============================================================================

%%
%%  Initialization.
%%
init() ->
    State = #state{
        res = undefined,
        cmd = undefined,
        cmds = queue:new()
    },
    {ok, State}.


%%
%%  Add command who's response should be parsed.
%%
add_call({CallRef, Command, From}, State = #state{cmd = CurrentCmd, cmds = Cmds}) ->
    NewCurrentCommand = case CurrentCmd of
        undefined -> Command;
        _ -> CurrentCmd
    end,
    Cmd = #cmd{call_ref = CallRef, name = Command, from = From},
    NewState = State#state{
        cmd = NewCurrentCommand,
        cmds = queue:snoc(Cmds, Cmd)
    },
    {ok, NewState}.


%%
%%  Parse response line.
%%
-spec parse_lines([binary()], #state{}) -> {ok, list(), #state{}}.
parse_lines(RawResponseLines, State) ->
    InputLines = [{line, L} || L <- RawResponseLines],
    {ok, ParsedResponses, NewState} = lists:foldl(fun parse/2, {ok, [], State}, InputLines),
    {ok, lists:reverse(ParsedResponses), NewState}.



%% =============================================================================
%%  Callbacks for GEN_FSM.
%% =============================================================================


%%
%%  Parses raw input.
%%
parse({line, ResponseLine}, {ok, Parsed, State = #state{cmds = Commands}}) ->
    case ResponseLine of
        <<"#CLUSTER:LGN(0000000000000000000000000000000000000000)==>", _Msg/binary>> ->
            {ok, Parsed, State};

        <<"#CLUSTER:OUT(", CallRefBin:40/binary, ")==>", Msg/binary>> ->
            CallRef = binary:bin_to_list(CallRefBin),
            #cmd{call_ref = CommandCallRef} = queue:head(Commands),
            case CallRef of
                CommandCallRef ->
                    parse({out, Msg}, {ok, Parsed, State});
                _ ->
                    log_err("line(OUT): wrong call ref, expected ~p, line=~p", [CommandCallRef, ResponseLine]),
                    {error, Parsed, State}
            end;

        <<"#CLUSTER:ERR(", CallRefBin:40/binary, ")==>", ErrCode:3/binary, ":", ErrMsg/binary>> ->
            log_err("line(ERR): ref=~p, code=~p, msg=~p", [CallRefBin, ErrCode, ErrMsg]),
            CallRef = binary:bin_to_list(CallRefBin),
            #cmd{call_ref = CommandCallRef} = queue:head(Commands),
            case CallRef of
                CommandCallRef ->
                    respond_and_process_next(error, {ok, Parsed, State});
                _ ->
                    log_err("line(ERR): wrong call ref, expected ~p, line=~p", [CommandCallRef, ResponseLine]),
                    {error, Parsed, State}
            end;

        <<"#DATA:", Msg/binary>> ->
            parse({data, Msg}, {ok, Parsed, State});

        <<"#", _Msg/binary>> ->
            log_err("line(#??): ~p", [ResponseLine]),
            {ok, Parsed, State};

        _ ->
            log_err("line(???): ~p", [ResponseLine]),
            {ok, Parsed, State}
    end;

%%
%%  Handles IDLE state.
%%
parse(_Event, {ok, Parsed, State = #state{cmd = undefined}}) ->
    {error, Parsed, State};


%%
%%  Handles output of the "store_config" command.
%%
parse(Event, {ok, Parsed, State = #state{cmd = store_config}}) ->
    Response = case Event of
        {out, <<"STORED">>} ->
            stored;

        {out, <<"EXISTING">>} ->
            existing
    end,
    respond_and_process_next(Response, {ok, Parsed, State});


%%
%%  Handles output of the "cluster_status" command.
%%
parse(Event, {ok, Parsed, State = #state{cmd = cluster_status, res = Res}}) ->
    case Event of
        {out, <<"CLUSTER_STATUS:START">>} ->
            {ok, Parsed, State#state{res = []}};
        
        {out, <<"CLUSTER_STATUS:END">>} ->
            respond_and_process_next({cluster_status, Res}, {ok, Parsed, State#state{res = undefined}});
        
        {data, <<Type:2/binary, ":", SimulationId:40/binary, ":", StatusAndJobId/binary>>} ->
            StatusType = case Type of
                <<"FS">> -> fs;
                <<"RT">> -> rt
            end,
            [Status, _JobId] = binary:split(StatusAndJobId, <<":">>),
            StatusRecord = {StatusType,
                binary_to_list(SimulationId),
                binary_to_list(Status)
            },
            {ok, Parsed, State#state{res = [StatusRecord | Res]}}
    end;


%%
%%  Handles output of the "submit_simulation" command.
%%
parse(Event, {ok, Parsed, State = #state{cmd = submit_simulation}}) ->
    ok = case Event of
        {out, <<"SUBMITTED:", _SimulationId:40/binary, ":", _JobId/binary>>} ->
            ok;

        {out, <<"DUPLICATE:", _SimulationId:40/binary>>} ->
            ok
    end,
    respond_and_process_next(ok, {ok, Parsed, State});


%%
%%  Handles output of the "delete_simulation" command.
%%
parse(Event, {ok, Parsed, State = #state{cmd = delete_simulation}}) ->
    case Event of
        {out, <<"DELETED:", _SimulationId:40/binary>>} ->
            ok;

        {out, <<"DELETE:", SimulationId:40/binary, ":SIM_RUNNING">>} ->
            log_err("Simulation ~s not deleted (still running)", [SimulationId])
    end,
    respond_and_process_next(ok, {ok, Parsed, State});


%%
%%  Handles output of the "cancel_simulation" command.
%%
parse(Event, {ok, Parsed, State = #state{cmd = cancel_simulation}}) ->
    case Event of
        {out, <<"CANCELED:", _SimulationId:40/binary>>} ->
            ok
    end,
    respond_and_process_next(ok, {ok, Parsed, State});


%%
%%  Handles output of the "simulation_result" command.
%%
parse(Event, {ok, Parsed, State = #state{cmd = simulation_result, res = Res}}) ->
    case Event of
        {out, <<"RESULT:", _SimulationId:40/binary, ":SIM_RUNNING">>} ->
            respond_and_process_next({error, running}, {ok, Parsed, State});

        {out, <<"RESULT:", _SimulationId:40/binary, ":NOT_FOUND">>} ->
            respond_and_process_next({error, not_found}, {ok, Parsed, State});

        {out, <<"RESULT:", _SimulationId:40/binary, ":START">>} ->
            {ok, Parsed, State#state{res = []}};

        {out, <<"RESULT:", _SimulationId:40/binary, ":END">>} ->
            respond_and_process_next(lists:reverse(Res), {ok, Parsed, State#state{res = undefined}});

        {data, MsgBase64} ->
            DecodedMsg = base64:decode(MsgBase64),
            {ok, Parsed, State#state{res = [DecodedMsg | Res]}}
    end.



%% =============================================================================
%%  Internal functions
%% =============================================================================


%%
%%  Send the call response to the cluster and proceed with next command. 
%%
respond_and_process_next(Response, {ok, Parsed, State = #state{cmds = Commands}}) ->
    Command = queue:head(Commands),
    NewCommands = queue:tail(Commands),
    NewParsed = case Command of
        #cmd{from = undefined} ->
            Parsed;
        #cmd{from = From} ->
            [{response, Response, From} | Parsed]
    end,
    case queue:is_empty(NewCommands) of
        true ->
            {ok, NewParsed, State#state{cmd = undefined, cmds = NewCommands}};
        false ->
            #cmd{name = NewCommandName} = queue:head(NewCommands),
            {ok, NewParsed, State#state{cmd = NewCommandName, cmds = NewCommands, res = undefined}}
    end.


%%
%%  Logs errors in a uniform way. 
%%
log_err(Msg, Args) ->
    error_logger:error_msg("~s: " ++ Msg ++ "~n", [?MODULE | Args]).

