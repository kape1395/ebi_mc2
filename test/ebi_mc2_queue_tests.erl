-module(ebi_mc2_queue_tests).
-include_lib("eunit/include/eunit.hrl").
-include("ebi_mc2.hrl").

-define(sc(S), {_, {_,start_simulation, [_,S, _]}, _}).

%% =============================================================================
%%  Queue started with 2 simulations running.
%%  Third simulation is submitted and first two are canceled.
%%  First simulation registered self to the queue, while second one - not (yet). 
%%
simple_test() ->
    MainSup = 'MainSup',
    ClusterSup = 'ClusterSup',
    SimulationSup = 'SimulationSup',
    Store = 'Store',
    SID1 = "SimulationId-1", SPID1 = "SimulationPID-1", Sim1 = #simulation{id = SID1},
    SID2 = "SimulationId-2", SPID2 = "SimulationPID-2", Sim2 = #simulation{id = SID2},
    SID3 = "SimulationId-3", SPID3 = "SimulationPID-3", Sim3 = #simulation{id = SID3},
    ClusterConfig = #config_cluster{
        name = c1,
        ssh_host = "host", ssh_port = 22, ssh_user = "user",
        local_user_dir = "/home/user", cluster_command = "/home/user/bin/cluster",
        status_check_ms = 10000,
        partitions = [
            #config_partition{name = p1, max_parallel = 1},
            #config_partition{name = p2, max_parallel = 5}
        ]
    },
    Config = #config{
        name = q1,
        clusters = [ClusterConfig],
        result_dir = "."
    },
    %%
    %%  Mocks for main supervisor
    %%
    meck:new(ebi_mc2_sup),
    meck:expect(ebi_mc2_sup, add_cluster_setsup, fun
        (Sup, Cl, _Q) when Sup == MainSup, Cl == [ClusterConfig] -> {ok, ClusterSup}
    end),
    meck:expect(ebi_mc2_sup, add_simulation_setsup, fun
        (Sup) when Sup == MainSup -> {ok, SimulationSup}
    end),
    %%
    %%  Mocks for simulations supervisor
    %%
    {ok, QTS} = mock_store_new(),
    meck:new(ebi_mc2_simulation_setsup),
    meck:expect(ebi_mc2_simulation_setsup, start_simulation, fun
        (Sup, SID, _Q) when Sup == SimulationSup, SID == SID1 -> {ok, SPID1};
        (Sup, SID, _Q) when Sup == SimulationSup, SID == SID2 -> {ok, SPID2};
        (Sup, SID, _Q) when Sup == SimulationSup, SID == SID3 -> {ok, SPID3}
    end),
    %%
    %%  Mocks for simulation
    %%
    meck:new(ebi_mc2_simulation),
    meck:expect(ebi_mc2_simulation, cancel, fun
        (SPID) when SPID == SPID1 -> ok
    end),
    %%
    %%  Mocks for the queue store
    %%
    meck:new(ebi_mc2_queue_store),
    meck:expect(ebi_mc2_queue_store, init, fun
        () -> Store
    end),
    meck:expect(ebi_mc2_queue_store, add, fun
        (St, S = #simulation{id = SID}) when St == Store, S == Sim3 -> mock_store_add(QTS, SID)
    end),
    meck:expect(ebi_mc2_queue_store, get, fun
        (St, S) when St == Store, S == SID1 -> {ok, #ebi_mc2_sim{simulation_id = SID1}};
        (St, S) when St == Store, S == SID2 -> {ok, #ebi_mc2_sim{simulation_id = SID2}}
    end),
    meck:expect(ebi_mc2_queue_store, add_command, fun
        (St, S, cancel) when St == Store, S == SID1 -> ok;
        (St, S, cancel) when St == Store, S == SID2 -> ok
    end),
    meck:expect(ebi_mc2_queue_store, get_running, fun
        (St) when St == Store -> [{SID1, {c1, p1}}, {SID2, {c1, p2}}]
    end),
    meck:expect(ebi_mc2_queue_store, get_next_pending, fun
        (St) when St == Store -> mock_store_get(QTS)
    end),
    meck:expect(ebi_mc2_queue_store, set_target, fun
        (St, S, {c1, p2}) when St == Store, S == SID3 -> ok
    end),
    %%
    %%  Test scenario
    %%
    {ok, PID} = ebi_queue:start_link(ebi_mc2_queue, {Config, MainSup}),
    ebi_queue:submit(PID, Sim3),
    ebi_mc2_queue:register_simulation(PID, SID1, SPID1),
    ebi_queue:cancel(PID, Sim1),
    ebi_queue:cancel(PID, Sim2),
    receive none -> ok after 1000 -> ok end, 
    %%
    %%  Validation
    %%
    MockedModules = [ebi_mc2_sup, ebi_mc2_simulation_setsup, ebi_mc2_queue_store, ebi_mc2_simulation],
    ?assert(meck:validate(MockedModules)),
    meck:unload(MockedModules),
    mock_store_stop(QTS),
    ok.


%% =============================================================================
%%  Check if limiting of parallel simulations works.
%%
queueing_test() ->
    MainSup = 'MainSup',
    ClusterSup = 'ClusterSup',
    SimulationSup = 'SimulationSup',
    Store = 'Store',
    SID01 = "SimulationId-01", Sim01 = #simulation{id = SID01},
    SID02 = "SimulationId-02", Sim02 = #simulation{id = SID02},
    SID03 = "SimulationId-03", Sim03 = #simulation{id = SID03},
    SID04 = "SimulationId-04", Sim04 = #simulation{id = SID04},
    SID05 = "SimulationId-05", Sim05 = #simulation{id = SID05},
    SID06 = "SimulationId-06", Sim06 = #simulation{id = SID06},
    SID07 = "SimulationId-07", Sim07 = #simulation{id = SID07},
    ClusterConfig = #config_cluster{
        name = c1, ssh_host = "host", ssh_port = 22, ssh_user = "user",
        local_user_dir = "/home/user", cluster_command = "/home/user/bin/cluster", status_check_ms = 10000,
        partitions = [
            #config_partition{name = p1, max_parallel = 1},
            #config_partition{name = p2, max_parallel = 2}
        ]
    },
    Config = #config{name = q1, clusters = [ClusterConfig], result_dir = "."},
    %%
    %%  Mocks
    %%
    {ok, QTS} = mock_store_new(),
    meck:new   (ebi_mc2_sup),
    meck:expect(ebi_mc2_sup, add_cluster_setsup, 3, {ok, ClusterSup}),
    meck:expect(ebi_mc2_sup, add_simulation_setsup, 1, {ok, SimulationSup}),
    meck:new   (ebi_mc2_simulation_setsup),
    meck:expect(ebi_mc2_simulation_setsup, start_simulation, fun (_, SID, _)  -> {ok, _SPID = SID} end),
    meck:new   (ebi_mc2_simulation),
    meck:expect(ebi_mc2_simulation, cancel, 1, ok),
    meck:new   (ebi_mc2_queue_store),
    meck:expect(ebi_mc2_queue_store, init, 0, Store),
    meck:expect(ebi_mc2_queue_store, add, fun (_, #simulation{id = SID}) -> mock_store_add(QTS, SID) end),
    meck:expect(ebi_mc2_queue_store, get, fun (_, SID) -> {ok, #ebi_mc2_sim{simulation_id = SID}} end),
    meck:expect(ebi_mc2_queue_store, add_command, 3, ok),
    meck:expect(ebi_mc2_queue_store, get_running, 1, []), % No simulations are running on startup
    meck:expect(ebi_mc2_queue_store, get_next_pending, fun (_) -> mock_store_get(QTS) end),
    meck:expect(ebi_mc2_queue_store, set_target, 3, ok),
    meck:expect(ebi_mc2_queue_store, set_status, 3, ok),
    %%
    %%  Test scenario
    %%
    {ok, PID} = ebi_queue:start_link(ebi_mc2_queue, {Config, MainSup}),
    
    ebi_queue:submit(PID, Sim01),
    ebi_queue:submit(PID, Sim02),
    ebi_queue:submit(PID, Sim03),
    ebi_queue:submit(PID, Sim04),
    ebi_queue:submit(PID, Sim05), sleep(100),
    [?sc(SID01), ?sc(SID02), ?sc(SID03)] = meck:history(ebi_mc2_simulation_setsup),

    ebi_queue:submit(PID, Sim06), sleep(100),
    [?sc(SID01), ?sc(SID02), ?sc(SID03)] = meck:history(ebi_mc2_simulation_setsup),

    ebi_mc2_queue:simulation_status_updated(PID, SID02, {completed, completed, true}), sleep(100),
    [?sc(SID01), ?sc(SID02), ?sc(SID03), ?sc(SID04)] = meck:history(ebi_mc2_simulation_setsup),
    
    ebi_mc2_queue:simulation_status_updated(PID, SID01, {completed, completed, true}),
    ebi_mc2_queue:simulation_status_updated(PID, SID03, {completed, completed, true}),
    ebi_mc2_queue:simulation_status_updated(PID, SID04, {completed, completed, true}), sleep(100),
    [?sc(SID01), ?sc(SID02), ?sc(SID03), ?sc(SID04), ?sc(SID05), ?sc(SID06)] = meck:history(ebi_mc2_simulation_setsup),
    
    ebi_mc2_queue:simulation_status_updated(PID, SID05, {completed, completed, true}), sleep(100),
    [?sc(SID01), ?sc(SID02), ?sc(SID03), ?sc(SID04), ?sc(SID05), ?sc(SID06)] = meck:history(ebi_mc2_simulation_setsup),

    ebi_queue:submit(PID, Sim07), sleep(100),
    [?sc(SID01), ?sc(SID02), ?sc(SID03), ?sc(SID04), ?sc(SID05), ?sc(SID06), ?sc(SID07)] = meck:history(ebi_mc2_simulation_setsup),
    
    %%
    %%  Validation
    %%
    MockedModules = [ebi_mc2_sup, ebi_mc2_simulation_setsup, ebi_mc2_queue_store, ebi_mc2_simulation],
    ?assert(meck:validate(MockedModules)),
    meck:unload(MockedModules),
    mock_store_stop(QTS),
    ok.


%% =============================================================================
%%  Helper functions
%%
sleep(MS) ->
    receive none -> ok after MS -> ok end.

mock_store_new() -> {ok, spawn(fun () -> mock_store([]) end)}.
mock_store_add(QTS, SID) -> QTS ! {add, SID}, ok.
mock_store_get(QTS) -> QTS ! {get, self()}, receive {qts, R} -> R end.
mock_store_stop(QTS) -> QTS ! stop.
mock_store(Q) ->
    receive
        {get, From} ->
            case Q of
                [] ->
                    From ! {qts, {error, empty}},
                    mock_store(Q);
                [Head|Tail] ->
                    From ! {qts, {ok, Head}},
                    mock_store(Tail)
            end;
        {add, SID} ->
            mock_store(Q ++ [SID]);
        stop ->
            ok
        after 10000 ->
            timeout
    end.

