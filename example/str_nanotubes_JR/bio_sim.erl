-module(bio_sim).
-export([start/0, stop/1, connect/0, model/1, p_base/0, p_skst/0, p_set/3, ids/3, submit/3, status/3, delete/3, result/3, series/1]).
-export([print_J/2, print_J/3, print_j/2, print_j/3]).
-export([kmapp/1, kmapp/2, kmapp_J/1, kmapp_SJ/1, kmapp_find/2, kmapp_KM/1]).
-include("bio_ers.hrl").
-record(p, {
    d1, d2, d3, d4, s0, e0, alpha, k1, k2,
    de, dn, theta2r, theta3r, theta2z, theta3z, eta, rho
    }).

-record(s, {name, vars = [], vectors = [], model}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%%  Control functions.
%%
start() ->
    application:start(crypto),
    application:start(ssh),
    io:format("~n%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%~n"),
    io:format("rr(bio_sim).~n"),
    io:format("PID = bio_sim:connect().~n"),
    io:format("Model = bio_sim:model(PID).~n"),
    io:format("bio_sim:ids(Model, [bio_sim:p_base()], []).~n"),
    io:format("ok = bio_ers_queue_mifcl2_ssh_chan:check(PID).~n"),
    io:format("% bio_sim:submit(PID, Model, [bio_sim:p_set(bio_sim:p_base(), #p.s0, 5)]).~n"),
    io:format("% bio_sim:status(PID, Model, [bio_sim:p_set(bio_sim:p_base(), #p.s0, 5)]).~n"),
    io:format("% bio_sim:stop(PID).~n"),
    io:format("%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%~n"),
    ok.

connect() ->
    {ok, PID} = bio_ers_queue_mifcl2_ssh_chan:start_link(),
    PID.

model(PID) ->
    Model = bio_ers_model:read_model("model-1D-k2fin-diffE-t5.xml", kp1_xml),
    #model{definition = ModelDef} = Model,
    ModelId = bio_ers:get_id(Model),
    bio_ers_queue_mifcl2_ssh_chan:store_config(PID, ModelId, ModelDef),
    Model.

%%
%% rp(bio_sim:ids(Model, bio_sim:series({exp_v2, neskiesta}), [#p.s0, #p.alpha])).
%%
ids(Model, ParamVectors, ParamIndexes) ->
    Output = fun (Params) ->
        ID = bio_ers_queue_mifcl2:get_simulation_id(mk_simulation(Model, Params)),
        ParamValues = [ element(Index, Params) || Index <- ParamIndexes ],
        { ID, ParamValues }
    end,
    [ Output(Params) || Params <- ParamVectors ].

submit(PID, Model, ParamVectors) ->
    [ bio_ers_queue_mifcl2_ssh_chan:submit_simulation(PID, mk_simulation(Model, Params)) || Params <- ParamVectors ].

status(PID, Model, ParamVectors) ->
    [ bio_ers_queue_mifcl2_ssh_chan:simulation_status(PID, mk_simulation(Model, Params)) || Params <- ParamVectors ].

delete(PID, Model, ParamVectors) ->
    [ bio_ers_queue_mifcl2_ssh_chan:delete_simulation(PID, mk_simulation(Model, Params)) || Params <- ParamVectors ].

result(PID, Model, ParamVectors) ->
    Save = fun (Simulation) ->
        case bio_ers_queue_mifcl2_ssh_chan:simulation_result(PID, Simulation) of
            {ok, SimulationId, Data} ->
                ok = file:write_file("bio_sim.result/" ++ SimulationId ++ ".tar.gz", Data),  
                {ok, SimulationId};
            {error, SimulationId, Reason} ->
                {error, SimulationId, Reason}
        end
    end,
    [ Save(mk_simulation(Model, Params)) || Params <- ParamVectors ].

stop(PID) ->
    ok = bio_ers_queue_mifcl2_ssh_chan:stop(PID),
    init:stop().


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%%  Various PRINTs.
%%


%%  
%%  file:write_file("___base_v2_neskiesta", bio_sim:print_J(#s{model=Model, vectors=bio_sim:series({exp_v2, neskiesta})}, [#p.s0, #p.alpha])).
%%  X=1; echo -ne "#xx\n1 1 a\n1 2 b\n2 1 c\n2 2 d\n" | sort -sgk $X | awk -v k=$X 'INIT{v="x"} /^#/{print; next} {v2 = $k; if (v != v2) {printf("\n\n"); v = v2}; print}'
%%
print_J(_Series = #s{ model = Model, vectors = ParamVectors}, OutputParams, Filter) when is_list(ParamVectors) ->
    [ print_J(mk_simulation(Model, Params), [ element(I, Params) || I <- OutputParams ])
        || Params <- ParamVectors, Filter(Params) ].

%%
%%
%%
print_J(Series, OutputParams) when is_record(Series, s) ->
    print_J(Series, OutputParams, fun (_) -> true end);

%%
%%  Print one line to the output.
%%
print_J(Simulation, OutputParamValues) when is_record(Simulation, simulation) ->
    SimulationId = bio_ers_queue_mifcl2:get_simulation_id(Simulation),
    Prefix = [ io_lib:format("~p\t", [P]) || P <- OutputParamValues ],
    ExtractedFile = erl_tar:extract(
        "bio_sim.result/" ++ SimulationId ++ ".tar.gz", 
        [compressed, memory, {files, [SimulationId ++ "/currentDensity"]}]
    ),
    case ExtractedFile of
        {ok, [{_, Data}]} ->
            LastLine = lists:last(binary:split(Data, <<"\n">>, [global, trim])),
            io_lib:format("~s~s\n", [Prefix, LastLine]);
        {error, _} ->
            Prefix ++ "nan\tnan\tnan\n"
    end.


%%
%%
%%
print_j(_Series = #s{ model = Model, vectors = ParamVectors}, OutputParams, Filter) when is_list(ParamVectors) ->
    [ print_j(mk_simulation(Model, Params), [ element(I, Params) || I <- OutputParams ])
        || Params <- ParamVectors, Filter(Params) ].

%%
%%
%%
print_j(Series, OutputParams) when is_record(Series, s) ->
    print_j(Series, OutputParams, fun (_) -> true end);

%%
%%  Print one j-vs-t to the output
%%
print_j(Simulation, OutputParams) when is_record(Simulation, simulation) ->
    SimulationId = bio_ers_queue_mifcl2:get_simulation_id(Simulation),
    {ok, [{_, Data}]} = erl_tar:extract(
        "bio_sim.result/" ++ SimulationId ++ ".tar.gz",
        [compressed, memory, {files, [SimulationId ++ "/currentDensity"]}]
    ),
    [
        "\n\n# ParamValues: ",
        [ io_lib:format("~p\t", [P]) || P <- OutputParams ],
        "\n",
        io_lib:format("~s\n", [Data])
    ].


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%%
%%

kmapp(Series) when is_record(Series, s)->
    kmapp_KM(kmapp_SJ(Series)).

kmapp(Model, test) ->
    BS = {exp_v2, neskiesta, 'd2/2', 'K_M_app'},
    Vectors = lists:filter(fun (#p{e0=0.0050, alpha=0.04})->true; (_)->false end, series(BS)),
    SJ = kmapp_SJ(#s{model = Model, vectors = Vectors}),
    KM = kmapp_KM(SJ),
    {KM, SJ};
kmapp(Model, calculate) ->
    BS = {exp_v2, neskiesta, 'd2/2', 'K_M_app'},
    F1 = fun (E0, Alpha) ->
        Vectors = lists:filter(
            fun (#p{e0=MyE0, alpha=MyAlpha}) ->
                case {MyE0, MyAlpha} of
                    {E0, Alpha} -> true;
                     _ -> false
                end
            end,
            series(BS)),
        SJ = kmapp_SJ(#s{model = Model, vectors = Vectors}),
        KM = kmapp_KM(SJ),
        {E0, Alpha, KM, SJ}
    end,
    {_, Alphas} = def_alpha(v5),
    {_, E0s} = def_e0(v3),
    [F1(E, A) || E <- E0s, A <- Alphas];
kmapp(Model, calculate_and_save) ->
    Data = [ [E0, Alpha, KM] || {E0, Alpha, KM, _} <- kmapp(Model, calculate) ],
    {ok, File} = file:open("bio_sim.dat/exp_v2__neskiesta__d2-2__K_M_app.dat", [write]),
    file:write(File, "#E0\tAlpha\tKMapp\n"),
    lists:map(fun (Row) -> file:write(File, io_lib:format("~p\t~p\t~p\n", Row)) end, Data),
    file:close(File).

%%
%% Simulation -> J
%%
kmapp_J(Simulation) ->
    Tokens = string:tokens(lists:flatten(print_J(Simulation, [])), " \t\n"),
    [_Time, _Iteration, J] = [ Y || {Y, _} <- lists:map(fun string:to_float/1, [ X ++ ".0" || X <- Tokens] ) ],
    J.

%%
%% Series -> [{S, J}]
%%
kmapp_SJ(#s{model = Model, vectors = Vectors}) ->
    JS = lists:sort([ {V#p.s0, kmapp_J(mk_simulation(Model, V))} || V <- Vectors ]),
    [ {0.0, 0.0} | JS ].

%%
%% [{S, J}] -> KMapp
%%
kmapp_KM(SJ) ->
    {_, JMax} = lists:last(SJ),
    case JMax of
        error ->
            error;
        _ ->
            %io:fwrite("JMAX=~p~n", [JMax]),
            J05 = JMax * 0.5,
            case kmapp_find(SJ, J05) of
                {KM, _ }             -> KM;
                [{SA, JA}, {SB, JB}] -> SA + (J05 - JA) * (SB - SA) / (JB - JA); % Linear interpolation
                error                -> error
            end
    end.

%%
%%  This must find a point (fails otherwise).
%%
kmapp_find([A = {_, JA}              | _   ], J) when JA == J  -> A;
kmapp_find([A = {_, JA}, B = {_, JB} | _   ], J) when is_number(JA), is_number(JB), JA <  J, J < JB -> [A, B];
kmapp_find([_,           B           | Tail], J)  -> kmapp_find([B | Tail], J);
kmapp_find(_, _) -> error.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%%  Series.
%%
def_s0(v1) -> {#p.s0, [0.099, 0.199, 0.299, 0.490, 0.990, 1.960, 2.920]};  % Pirmų experimentinių rezultatų S0 aibė.
def_s0(v2) -> {#p.s0, [       0.199,        0.490, 0.990,        2.960]};  % S0 aibė, kai tikrinta su skiestu ir pakartotinai neskiestu E (su didesne preoksidacija).
def_s0(v3) -> {#p.s0, [                                   1.960       ]};  % Cia skaiciuosim J-alpha-E0
def_s0(v4) -> {#p.s0, [0.1, 0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5, 6, 7, 8, 9, 10, 20, 30, 40, 50, 60, 100, 200, 300]}. % K_M_app skaiciavimui
def_alpha(v1) -> {#p.alpha, [                                       0.1,       0.2, 0.3,       0.4, 0.5, 0.6,       0.7, 0.8, 0.9, 1.0]};
def_alpha(v2) -> {#p.alpha, [        0.005, 0.01, 0.02, 0.04, 0.08, 0.1, 0.16, 0.2, 0.3, 0.32, 0.4, 0.5, 0.6, 0.64, 0.7, 0.8, 0.9, 1.0]};
def_alpha(v3) -> {#p.alpha, [0.0025, 0.005, 0.01, 0.02, 0.04, 0.08,      0.16,           0.32,                0.64,                1.0]};
def_alpha(v4) -> {#p.alpha, [        0.005, 0.01, 0.02, 0.04, 0.08,      0.16                                                         ]};
def_alpha(v5) -> {#p.alpha, [6.25e-4, 0.00125, 0.0025, 0.005, 0.01, 0.02, 0.04, 0.08, 0.16, 0.32, 0.64, 1.0]}.
def_e0(v3) -> {#p.e0, [0.0005, 0.0050, 0.0500, 0.5000, 5.0000, 50.0000]}.
def_k2(v1) -> {#p.k2, [552, 600, 700]}.

%% bio_sim:submit(PID, Model, bio_sim:series({exp_v2, neskiesta, 'd2/2', 'k2'})).
%% bio_sim:submit(PID, Model, bio_sim:series({exp_v2,   skiesta, 'd2/2', 'k2'})).
%%
%% rp(bio_sim:status(PID, Model, bio_sim:series({exp_v2, neskiesta, 'd2/2', 'k2'}))).
%% rp(bio_sim:status(PID, Model, bio_sim:series({exp_v2,   skiesta, 'd2/2', 'k2'}))).
%%
%% ## rp(bio_sim:result(PID, Model, bio_sim:print_J({Model, bio_sim:series(base_v2_neskiesta_CNTx05)}, #p.s0, #p.alpha))).
%% ## X=F64F0A5C8276EE1DB3850C80E4C738B70C7D0516; tar -Oxzf bio_sim.result/$X.tar.gz $X/model-actual.xml | less
%
% file:write_file("bio_sim.dat/exp_v2__neskiesta__d2-2.dat", bio_sim:print_J(#s{model=Model, vectors=bio_sim:series({exp_v2, neskiesta, 'd2/2'})}, [#p.s0, #p.alpha])).
% file:write_file("bio_sim.dat/exp_v2__neskiesta.dat",       bio_sim:print_J(#s{model=Model, vectors=bio_sim:series({exp_v2, neskiesta        })}, [#p.s0, #p.alpha])).
%
%% file:write_file("bio_sim.dat/exp_v2__neskiesta__d2-2__k2_600.dat",                bio_sim:print_J(#s{model=Model, vectors=bio_sim:series({exp_v2, neskiesta, 'd2/2', 'k2'})}, [#p.s0, #p.alpha], fun (#p{k2=600})->true; (_)->false end)).
%% file:write_file("bio_sim.dat/exp_v2__neskiesta__d2-2__k2_600__alpha-0-04-st.dat", bio_sim:print_j(#s{model=Model, vectors=bio_sim:series({exp_v2, neskiesta, 'd2/2', 'k2'})}, [#p.s0, #p.alpha], fun (#p{k2=600, alpha=0.04})->true; (_)->false end)).
%% file:write_file("bio_sim.dat/exp_v2__neskiesta__d2-2__k2_700.dat", bio_sim:print_J(#s{model=Model, vectors=bio_sim:series({exp_v2, neskiesta, 'd2/2', 'k2'})}, [#p.s0, #p.alpha], fun (#p{k2=700})->true; (_)->false end)).
%% file:write_file("bio_sim.dat/exp_v2__skiesta__d2-2__k2_600.dat", bio_sim:print_J(#s{model=Model, vectors=bio_sim:series({exp_v2, skiesta, 'd2/2', 'k2'})}, [#p.s0, #p.alpha], fun (#p{k2=600})->true; (_)->false end)).
%%
%% f(FP), f(BS), FP="bio_sim.dat/exp_v2__neskiesta__d2-2__K_M_app__", BS={exp_v2, neskiesta, 'd2/2', 'K_M_app'}.
%% file:write_file(FP++"e0_00050.dat", bio_sim:print_J(#s{model=Model, vectors=bio_sim:series({BS, e0_00050})}, [#p.s0, #p.e0, #p.alpha])).
%% file:write_file(FP++"e0_00500.dat", bio_sim:print_J(#s{model=Model, vectors=bio_sim:series({BS, e0_00500})}, [#p.s0, #p.e0, #p.alpha])).
%% file:write_file(FP++"e0_05000.dat", bio_sim:print_J(#s{model=Model, vectors=bio_sim:series({BS, e0_05000})}, [#p.s0, #p.e0, #p.alpha])).

series({exp_v2, neskiesta}) ->               Base = p_base(),                         mk_series(Base, [def_s0(v2), def_alpha(v2)]);
series({exp_v2, neskiesta, 'd2/2'}) ->       Base = p_set(p_base(), #p.d2, 0.002E-4), mk_series(Base, [def_s0(v2), def_alpha(v2)]);
series({exp_v2, neskiesta, 'd2/2', 'k2'}) -> Base = p_set(p_base(), #p.d2, 0.002E-4), mk_series(Base, [def_s0(v2), def_alpha(v4), def_k2(v1)]);
series({exp_v2,   skiesta, 'd2/2', 'k2'}) -> Base = p_set(p_skst(), #p.d2, 0.002E-4), mk_series(Base, [def_s0(v2), def_alpha(v1), def_k2(v1)]);

% rp(bio_sim:status(PID, Model, bio_sim:series({exp_v2, neskiesta, 'd2/2', 'alpha=0.04'}))).
% file:write_file("bio_sim.dat/exp_v2__neskiesta__d2-2__alpha-0-04-st.dat", bio_sim:print_j(#s{model=Model, vectors=bio_sim:series({exp_v2, neskiesta, 'd2/2', 'alpha=0.04'})}, [#p.s0, #p.alpha])).
series({exp_v2, neskiesta, 'd2/2', 'alpha=0.04'}) ->
    lists:filter(
        fun (#p{alpha = 0.04}) -> true; (_) -> false end,
        series({exp_v2, neskiesta, 'd2/2'})
    );

series({exp_v2, neskiesta, 'd2/2', 'J-alpha-E0'}) ->
    Base = p_set(p_base(), #p.d2, 0.002E-4),
    mk_series(Base, [def_s0(v3), def_alpha(v3), def_e0(v3)]);

series({exp_v2, neskiesta, 'd2/2', 'K_M_app'}) ->
    Base = p_set(p_base(), #p.d2, 0.002E-4),
    mk_series(Base, [def_s0(v4), def_alpha(v5), def_e0(v3)]);
series({{exp_v2, neskiesta, 'd2/2', 'K_M_app'}, e0_00050}) -> lists:filter(fun (#p{e0=0.0050})->true; (_)->false end, series({exp_v2, neskiesta, 'd2/2', 'K_M_app'}));
series({{exp_v2, neskiesta, 'd2/2', 'K_M_app'}, e0_00500}) -> lists:filter(fun (#p{e0=0.0500})->true; (_)->false end, series({exp_v2, neskiesta, 'd2/2', 'K_M_app'}));
series({{exp_v2, neskiesta, 'd2/2', 'K_M_app'}, e0_05000}) -> lists:filter(fun (#p{e0=0.5000})->true; (_)->false end, series({exp_v2, neskiesta, 'd2/2', 'K_M_app'})).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%%  Parameter calculation.
%%


%%
%%
%%
mk_series(Base, [ ]) ->
    [ Base ];

mk_series(Base, [ {Param, Values} ]) ->
    [ p_set(Base, [ {Param, Value} ]) || Value <- Values];

mk_series(Base, [ {Param1, Values1}, {Param2, Values2} ]) ->
    [ p_set(Base, [ {Param1, Value1}, {Param2, Value2} ]) ||
        Value1 <- Values1,
        Value2 <- Values2 ];

mk_series(Base, [ {Param1, Values1}, {Param2, Values2}, {Param3, Values3} ]) ->
    [ p_set(Base, [ {Param1, Value1}, {Param2, Value2}, {Param3, Value3} ]) ||
        Value1 <- Values1,
        Value2 <- Values2,
        Value3 <- Values3 ].



%%
%%
%%
mk_simulation(Model, Params) ->
    #simulation{model = Model, params = mk_params(Params)}.

%%
%%
%%
mk_params(P) ->
    #p{
        d1 = D1, d2 = D2, d3 = D3, d4 = D4,
        e0 = E0, alpha = Alpha, de = De, dn = Dn,
        theta2r = Theta2r, theta3r = Theta3r, theta2z = Theta2z, theta3z = Theta3z,
        eta = Eta, rho = Rho
        } = P,

    Alpha2 = Theta2z / Theta2r,
    Alpha3 = Theta3z / Theta3r,

    D1r = De,
    D2r = Theta2r * (Eta * De + (1 - Eta) * Dn),
    D3r = Theta3r * Dn,
    D4r = Dn,

    D1z = D1r,
    D2z = D2r * Alpha2,
    D3z = D3r * Alpha3,
    D4z = D4r,

    Diff1 = D1z,
    Diff2 = D2z,
    Diff3 = D3z * Rho,
    Diff4 = D4z,

    Eox1 = E0,
    Eox2 = (1 - Alpha) * Eta * E0,
    Eeox2 = Alpha * Eta * E0,

    [
        #param{name = 'y_0',   value = 0.0},
        #param{name = 'y_1',   value = D1},
        #param{name = 'y_2',   value = D1 + D2},
        #param{name = 'y_3',   value = D1 + D2 + D3},
        #param{name = 'y_4',   value = D1 + D2 + D3 + D4},
        #param{name = 'D_1',   value = Diff1},
        #param{name = 'D_2',   value = Diff2},
        #param{name = 'D_3',   value = Diff3},
        #param{name = 'D_4',   value = Diff4},
        #param{name = 'alpha', value = Alpha3}, %% Also used for Alpha2
        #param{name = 'E_0',   value = Eox1},
        #param{name = 'E_1',   value = Eox2},
        #param{name = 'E_1a',  value = Eeox2},
        #param{name = 'S_0',   value = P#p.s0},
        #param{name = 'k_1',   value = P#p.k1},
        #param{name = 'k_2',   value = P#p.k2}
    ].

p_base() ->
    #p{
        d1 = 0.001E-4,
        d2 = 0.004E-4,
        d3 = 0.100E-4,
        d4 = 3.000E-4,
        s0 = undefined,    % undefined
        e0 = 0.0455,
        alpha = 1/200 = 0.005,
        k1 = 6.9E2,
        k2 = 552,
        de = 3.0E-10,
        dn = 6.0E-10,
        theta2r = 0.125*4/3 = 1/6,  % unused in 1D
        theta3r = 0.25,             % unused in 1D
        theta2z = 0.25*4/3 = 1/3,
        theta3z = 0.5,
        eta = 0.5,
        rho = math:pow(0.25, 2)
        }.

% E0 Skiesta 100x
p_skst() ->
    Def = p_base(),
    Def#p{e0 = 4.55E-4}.

%%
%% p_set(Base, #p.s0, 5.0).
%%
p_set(P, Index, Value) ->
    setelement(Index, P, Value).

p_set(P, []) ->
    P;
p_set(P, [{Index, Value} | Tail]) ->
    p_set(p_set(P, Index, Value), Tail).
