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
%%  @doc Implementation of the actual communication with the cluster via SSH.
%%  The following are the main tasks for this module:
%%    * Forward the `submit`, `delete`, `cancel` and `result` commans to the cluster.
%%    * Periodically get status of the cluster and send it to the queue.
%%
-module(ebi_mc2_cluster).
-behaviour(ssh_channel).
-export([ % API
    start_link/3,
    submit_simulation/3,
    delete_simulation/2,
    cancel_simulation/2,
    simulation_result/2
]).
-export([response/3]).
-export([init/1, terminate/2, handle_ssh_msg/2, handle_msg/2]).
-export([handle_call/3, handle_cast/2, code_change/3]).
-include("ebi.hrl").
-include("ebi_mc2.hrl").
-define(TIMEOUT, 10000).


%% =============================================================================
%%  Public API.
%% =============================================================================


%%
%%  Start the cluster connection.
%%
-spec start_link(#config_cluster{}, pid(), pid()) -> {ok, pid()} | term(). 
start_link(Config, Queue, Supervisor) ->
    #config_cluster{
        ssh_host = Host,
        ssh_port = Port,
        ssh_user = User,
        local_user_dir = UserDir
    } = Config,
    {ok, CRef} = ssh:connect(Host, Port, [
        {user_dir, UserDir},
        {user, User},
        {silently_accept_hosts, true},
        {connect_timeout, ?TIMEOUT}
    ], ?TIMEOUT),
    {ok, Chan} = ssh_connection:session_channel(CRef, ?TIMEOUT),
    ssh_channel:start_link(CRef, Chan, ?MODULE, {Config, CRef, Chan, Queue, Supervisor}).


%%
%%  Submit new simulation to the cluster, to the specified partition.
%%
-spec submit_simulation(atom(), atom(), #simulation{}) -> ok.
submit_simulation(Ref, Partition, Simulation) when is_record(Simulation, simulation) ->
    ssh_channel:cast(Ref, {store_config_and_submit_simulation, Simulation, Partition}).

%%
%%  Delete the specified simulation from the cluster.
%%
-spec delete_simulation(atom(), string()) -> ok.
delete_simulation(Ref, SimulationId) ->
    ssh_channel:cast(Ref, {delete_simulation, SimulationId}).


%%
%%  Cancel the specified simulation in the cluster.
%%
-spec cancel_simulation(atom(), string()) -> ok.
cancel_simulation(Ref, SimulationId) ->
    ssh_channel:cast(Ref, {cancel_simulation, SimulationId}).


%%
%%  Get the simulation results.
%%
-spec simulation_result(atom(), string()) -> {ok, SimulationId :: list(), ResponseLines :: list()}.
simulation_result(Ref, SimulationId) ->
    ssh_channel:call(Ref, {simulation_result, SimulationId}).


%% =============================================================================
%%  API for ebi_mc2_cluster_resp.
%% =============================================================================


%%
%%  Invoked by the response parser when the call response is collected.
%%
-spec response(atom(), term(), term()) -> ok.
response(Ref, {cluster_status, ClusterStatus}, ?MODULE) ->
    Ref ! {have_cluster_status, ClusterStatus},
    ok;

response(_Ref, Response, From) ->
    ssh_channel:reply(From, Response),
    ok.



%% =============================================================================
%%  Internal state
%% =============================================================================


-record(state, {
    cfg,            % Cluster config
    tref,           % Timer reference
    cref,           % SSH Connection reference
    chan,           % SSH Channel ID
    cmd,            % Command to execute on the server
    line_buf,       % Partial line got from the ssh server
    known_sim_defs, % Known simulation definitions (sha1 sums of xml files).
    resp,           % Response parser.
    queue           % Corresponding queue.
}).



%% =============================================================================
%%  Callbacks for ssh_channel.
%% =============================================================================


%%
%%  Initialization.
%%
init({Config = #config_cluster{cluster_command = Cmd, status_check_ms = Interval}, CRef, Chan, Queue, Supervisor}) ->
    self() ! {start_cluster_resp, Supervisor},
    ok = ssh_connection:shell(CRef, Chan),
    {ok, TRef} = timer:send_interval(Interval, {check_cluster_status}),
    State = #state{
        cfg = Config,
        tref = TRef,
        cref = CRef,
        chan = Chan,
        cmd = Cmd,
        line_buf = <<>>,
        known_sim_defs = [],
        resp = undefined,
        queue = Queue
    },
    {ok, State}.


%%
%%  Termination.
%%
terminate(Reason, #state{tref = TRef, cref = CRef, chan = Chan}) ->
    error_logger:info_msg("~s: destroy(reason=~p)~n", [?MODULE, Reason]),
    timer:cancel(TRef),
    ssh_connection:close(CRef, Chan),
    ssh:close(CRef),
    ok.


%%
%%  Handle all synchronous commands.
%%
handle_call(Command, From, State) ->
    invoke_cluster_command(Command, From, State).


%%
%%  Async commands.
%%
handle_cast(Command, State) ->
    invoke_cluster_command(Command, undefined, State).
    

%%
%%  Messages comming from the SSH server.
%%  In the first case the function splits input into lines and checks whether the
%%  last line was complete (ending with \n).
%%
handle_ssh_msg({ssh_cm, _Ref, {data, _Chan, _Type, BinaryData}}, State) ->
    #state{line_buf = LineBuf, resp = Resp} = State,
    DataWithBuf = <<LineBuf/binary, BinaryData/binary>>,
    [ PartialLine | FullLines ] = lists:reverse(binary:split(DataWithBuf, <<"\n">>, [global])),
    ok = ebi_mc2_cluster_resp:response_lines(Resp, lists:reverse(FullLines)),
    {ok, State#state{line_buf = PartialLine}};

handle_ssh_msg(Msg, State) ->
    error_logger:info_msg("~s: handle_ssh_msg(msg=~p)~n", [?MODULE, Msg]),
    {ok, State}.


%%
%%  Initialize the response parser.
%%
handle_msg({start_cluster_resp, Supervisor}, State) ->
    {ok, PID} = ebi_mc2_cluster_sup:start_cluster_resp(Supervisor, self()),
    {ok, State#state{resp = PID}};

%%
%%  Here we get notification from timer to check the cluster state.
%%
handle_msg({check_cluster_status}, State) ->
    {ok, NewState} = invoke_cluster_command({cluster_status}, ?MODULE, State),
    {ok, NewState};

%%
%%  Here we are getting cluster status from the response/3 function, invoked by the response parser.
%%
handle_msg({have_cluster_status, ClusterStatus}, State = #state{queue = Queue}) ->
    ok = ebi_mc2_queue:cluster_status_updated(Queue, ClusterStatus),
    {ok, State};

%%
%%  Here we getting the channel up event.
%%
handle_msg({ssh_channel_up, _Chan, _CRef}, State) ->
    {ok, State};

%%
%%  Terminate on timeout.
%%
handle_msg(timeout, State = #state{chan = Chan}) ->
    error_logger:info_msg("~s: handle_msg(timeout)~n", [?MODULE]),
    {stop, Chan, State};

%%
%%  Ignore all the rest.
%%
handle_msg(Msg, State) ->
    error_logger:info_msg("~s: handle_msg(msg=~p)~n", [?MODULE, Msg]),
    {ok, State}.


%%
%%  Code change.
%%
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%% =============================================================================
%%  Internal functions.
%% =============================================================================


%%
%%  Invokes command in the cluster.
%%  All the communication is done in the async way, so there is not much of
%%  difference between call and cast operation.
%%  The difference is in the response parses.
%%
invoke_cluster_command({store_config_and_submit_simulation, Simulation, _Partition}, From, State) ->
    #simulation{model = Model} = Simulation,
    #model{type = ModelType} = Model,
    #state{known_sim_defs = KnownSimDefs} = State,
    SimDefId = ebi:get_id(Model),
    NewState = case {lists:member(SimDefId, KnownSimDefs), ModelType} of
        {true, _} ->
            State;
        {false, reference} ->
            State;    % Hope its already stored.
        {false, kp1_xml} ->
            StateWithDimDefId = State#state{known_sim_defs = [SimDefId | KnownSimDefs]},
            {ok, StateAfterStore} = invoke_cluster_command({store_config, Simulation}, From, StateWithDimDefId),
            StateAfterStore
    end,
    {ok, StateAfterSubmit} = invoke_cluster_command({submit_simulation, Simulation}, From, NewState),
    {noreply, StateAfterSubmit, ?TIMEOUT};
    
invoke_cluster_command(CommandRequest, From, State) ->
    #state{cref = CRef, chan = Chan, resp = Resp} = State,
    CallRef = ebi:get_id(unique),
    Command = element(1, CommandRequest),
    ok = ebi_mc2_cluster_resp:add_call(Resp, CallRef, Command, From),
    case CommandRequest of
        {store_config, #simulation{model = Model}} ->
            #model{definition = ConfigData} = Model,
            ConfigName = ebi:get_id(Model),
            CmdLine = make_cmd(State, CallRef, "store_config", [ConfigName]),
            ssh_connection:send(CRef, Chan, CmdLine),
            ssh_connection:send(CRef, Chan, bin_to_base64(ConfigData)),
            ssh_connection:send(CRef, Chan, ["#END_OF_FILE__store_config__", CallRef, "\n"]),
            {ok, State};
        {cluster_status} ->
            CmdLine = make_cmd(State, CallRef, "cluster_status", []),
            ssh_connection:send(CRef, Chan, CmdLine),
            {noreply, State, ?TIMEOUT};
        {submit_simulation, Simulation, Partition} ->
            #simulation{id = SimulationName, model = Model, params = Params} = Simulation,
            CmdLine = make_cmd(State, CallRef, "submit_simulation", [
                SimulationName,                              % sim_name
                ebi:get_id(Model),                           % cfg_name
                Partition,                                   % partition
                [param_to_option(Param) || Param <- Params]  % params
            ]),
            ssh_connection:send(CRef, Chan, CmdLine),
            {noreply, State, ?TIMEOUT};
        {delete_simulation, SimulationId} ->
            CmdLine = make_cmd(State, CallRef, "delete_simulation", [SimulationId]),
            ssh_connection:send(CRef, Chan, CmdLine),
            {noreply, State, ?TIMEOUT};
        {cancel_simulation, SimulationId} ->
            CmdLine = make_cmd(State, CallRef, "cancel_simulation", [SimulationId]),
            ssh_connection:send(CRef, Chan, CmdLine),
            {noreply, State, ?TIMEOUT};
        {simulation_result, SimulationId} ->
            CmdLine = make_cmd(State, CallRef, "simulation_result", [SimulationId]),
            ssh_connection:send(CRef, Chan, CmdLine),
            {noreply, State, ?TIMEOUT}
    end.


%%
%%  Format command line.
%%
make_cmd(#state{cmd = Cmd}, Ref, Command, Args) ->
    [Cmd, " ", Ref, " ", Command, " ", [ [" \"", A, "\"" ] || A <- Args ], "\n"].


%%
%%  Function for converting binary to the wrapped base64.
%%
bin_to_base64(Binary) when is_binary(Binary) ->
    Base64 = base64:encode(Binary),
    lists:reverse(bin_to_base64_wrap(Base64, [])).

bin_to_base64_wrap(<<Line:76/binary, Tail/binary>>, Lines) ->
    bin_to_base64_wrap(Tail, [ <<Line/binary, "\n">> | Lines ]);

bin_to_base64_wrap(<<LastLine/binary>>, Lines) ->
    [ <<LastLine/binary, "\n">> | Lines ].


%%
%%  Converts model parameters to options to be passed when invoking the solver.
%%
param_to_option(Param = #param{name = Name, value = Value}) when is_record(Param, param), is_float(Value) ->
    io_lib:format(" -S~p=~p", [atom_to_list(Name), Value]);
param_to_option(Param = #param{name = Name, value = Value}) when is_record(Param, param), is_integer(Value) ->
    [" -S", atom_to_list(Name), "=", integer_to_list(Value)].


