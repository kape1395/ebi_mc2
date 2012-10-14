-module(ebi_mc2_queue_tests).
-include_lib("eunit/include/eunit.hrl").
-include("ebi_mc2.hrl").

%%
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
    meck:expect(ebi_mc2_sup, add_cluster_sup, fun
        (Sup, Cl) when Sup == MainSup, Cl == [ClusterConfig] -> {ok, ClusterSup}
    end),
    meck:expect(ebi_mc2_sup, add_simulation_sup, fun
        (Sup) when Sup == MainSup -> {ok, SimulationSup}
    end),
    %%
    %%  Mocks for simulations supervisor
    %%
    meck:new(ebi_mc2_simulation_sup),
    meck:expect(ebi_mc2_simulation_sup, start_simulation, fun
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
        (St, S) when St == Store, S == Sim3 -> ok
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
        (St) when St == Store -> [SID1, SID2]
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
    MockedModules = [ebi_mc2_sup, ebi_mc2_simulation_sup, ebi_mc2_queue_store, ebi_mc2_simulation],
    ?assert(meck:validate(MockedModules)),
    meck:unload(MockedModules),
    ok.

