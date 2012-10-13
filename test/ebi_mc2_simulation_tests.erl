-module(ebi_mc2_simulation_tests).
-include_lib("eunit/include/eunit.hrl").
-include("ebi_mc2.hrl").

startup_test() ->
    SID = "startup_test::SID",
    Queue = 'startup_test::Queue',
    Cluster = 'startup_test::Cluster',
    Partition = 'startup_test::Partition',
    SimulationDef = "startup_test::SimulationDef",
    Simulation = #ebi_mc2_sim{
        simulation_id = SID,
        simulation = SimulationDef,
        commands = [],
        state = {pending, undefined, undefined},
        target = {Cluster, Partition}
    },
    meck:new(ebi_mc2_queue),
    meck:new(ebi_mc2_cluster),
    meck:expect(ebi_mc2_queue, register_simulation, fun (Q, S, _) when Q == Queue, S == SID -> {ok, Simulation} end),
    meck:expect(ebi_mc2_queue, simulation_status_updated, fun (Q, S, {running, starting, false}) when Q == Queue, S == SID -> ok end),
    meck:expect(ebi_mc2_cluster, submit_simulation, fun (C, P, S) when C == Cluster, P == Partition, S == SimulationDef -> ok end),
    {ok, _PID} = ebi_mc2_simulation:start_link(SID, Queue),
    ?assert(meck:validate([ebi_mc2_queue, ebi_mc2_cluster])),
    meck:unload([ebi_mc2_queue, ebi_mc2_cluster]).

