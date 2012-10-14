-module(ebi_mc2_simulation_tests).
-include_lib("eunit/include/eunit.hrl").
-include("ebi_mc2.hrl").

%%
%%  Simulation started and completed.
%%
simple_test() ->
    SID = "startup_test::SID",
    Queue = 'startup_test::Queue',
    Cluster = 'startup_test::Cluster',
    Partition = 'startup_test::Partition',
    SimulationDef = "startup_test::SimulationDef",
    SimulationRes = "startup_test::SimulationRes",
    Simulation = #ebi_mc2_sim{
        simulation_id = SID,
        simulation = SimulationDef,
        commands = [],
        state = {pending, undefined, undefined},
        target = {Cluster, Partition}
    },
    %%
    %%  Mocks for QUEUE
    %%
    meck:new(ebi_mc2_queue),
    meck:expect(ebi_mc2_queue, register_simulation, fun
        (Q, S, _) when Q == Queue, S == SID -> {ok, Simulation}
    end),
    meck:expect(ebi_mc2_queue, unregister_simulation, fun
        (Q, S) when Q == Queue, S == SID -> ok
    end),
    meck:expect(ebi_mc2_queue, simulation_status_updated, fun
        (Q, S, {running,   starting,             false}) when Q == Queue, S == SID -> ok;
        (Q, S, {running,   running,              false}) when Q == Queue, S == SID -> ok;
        (Q, S, {running,   cleaningup_completed, false}) when Q == Queue, S == SID -> ok;
        (Q, S, {completed, completed,            true})  when Q == Queue, S == SID -> ok
    end),
    meck:expect(ebi_mc2_queue, simulation_result_generated, fun
        (Q, S, {completed, completed, true}, R)  when Q == Queue, S == SID, R == SimulationRes -> ok
    end),
    %%
    %%  Mocks for CLUSTER
    %%
    meck:new(ebi_mc2_cluster),
    meck:expect(ebi_mc2_cluster, submit_simulation, fun
        (C, P, S) when C == Cluster, P == Partition, S == SimulationDef -> ok
    end),
    meck:expect(ebi_mc2_cluster, delete_simulation, fun
        (C, S) when C == Cluster, S == SID -> ok
    end),
    meck:expect(ebi_mc2_cluster, simulation_result, fun
        (C, S) when C == Cluster, S == SID -> {ok, SID, SimulationRes}
    end),
    %%
    %%  Test scenario
    %%
    {ok, PID} = ebi_mc2_simulation:start_link(SID, Queue),
    ok = ebi_mc2_simulation:status_update(PID, SID, "RUNNING", "STARTED"),
    ok = ebi_mc2_simulation:status_update(PID, SID, "UNKNOWN", "STOPPED_SUCCESSFUL"),
    ok = ebi_mc2_simulation:status_update(PID, SID, "UNKNOWN", "UNKNOWN"),
    receive none -> ok after 1000 -> ok end, 
    %%
    %%  Validation
    %%
    ?assert(meck:validate([ebi_mc2_queue, ebi_mc2_cluster])),
    meck:unload(ebi_mc2_queue),
    meck:unload(ebi_mc2_cluster),
    ok.

