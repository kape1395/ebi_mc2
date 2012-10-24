-module(ebi_mc2_cluster_resp_tests).
-include_lib("eunit/include/eunit.hrl").
-include("ebi_mc2.hrl").

%%
%%  Simulation started and completed.
%%
simple_test() ->
    Cluster = ebi_mc2_cluster_test,
    {CR1, CMD1, FROM1} = {"0000000000000000000000000000000000000001", store_config,      from_01},
    {CR2, CMD2, FROM2} = {"0000000000000000000000000000000000000002", cluster_status,    from_02},
    {CR3, CMD3, FROM3} = {"0000000000000000000000000000000000000003", submit_simulation, from_03},
    {CR4, CMD4, FROM4} = {"0000000000000000000000000000000000000004", cancel_simulation, from_04},
    {CR5, CMD5, FROM5} = {"0000000000000000000000000000000000000005", delete_simulation, from_05},
    {CR6, CMD6, FROM6} = {"0000000000000000000000000000000000000006", simulation_result, from_06},

    %%
    %%  Mocks for CLUSTER
    %%
    meck:new(ebi_mc2_cluster),
    meck:expect(ebi_mc2_cluster, response, fun (C, _R, _F) when C == Cluster -> ok  end),

    %%
    %%  Test scenario
    %%
    {ok, PID} = ebi_mc2_cluster_resp:start_link(Cluster),
    ok = ebi_mc2_cluster_resp:add_call(PID, CR1, CMD1, FROM1),
    ok = ebi_mc2_cluster_resp:add_call(PID, CR2, CMD2, FROM2),
    ok = ebi_mc2_cluster_resp:add_call(PID, CR3, CMD3, FROM3),
    ok = ebi_mc2_cluster_resp:add_call(PID, CR4, CMD4, FROM4),
    ok = ebi_mc2_cluster_resp:add_call(PID, CR5, CMD5, FROM5),
    ok = ebi_mc2_cluster_resp:add_call(PID, CR6, CMD6, FROM6),
    ok = ebi_mc2_cluster_resp:response_lines(PID, [
        <<"#CLUSTER:OUT(0000000000000000000000000000000000000001)==>EXISTING">>,
        <<"#CLUSTER:OUT(0000000000000000000000000000000000000002)==>CLUSTER_STATUS:START">>,
        <<"#DATA:FS:SID01:RUNNING:258">>,
        <<"#CLUSTER:OUT(0000000000000000000000000000000000000002)==>CLUSTER_STATUS:END">>,
        <<"#CLUSTER:OUT(0000000000000000000000000000000000000003)==>SUBMITTED:SID03:556">>,
        <<"#CLUSTER:OUT(0000000000000000000000000000000000000004)==>CANCELED:SID04">>,
        <<"#CLUSTER:OUT(0000000000000000000000000000000000000005)==>DELETED:SIM05">>,
        <<"#CLUSTER:OUT(0000000000000000000000000000000000000006)==>RESULT:SIM06:SIM_RUNNING">>
    ]),

    receive after 1000 -> ok end,
    Hist = meck:history(ebi_mc2_cluster),
    ?debugFmt("HIST=~p~n", [Hist]),
    
    %%
    %%  Validation
    %%
    ?assert(meck:validate([ebi_mc2_cluster])),
    meck:unload(ebi_mc2_cluster),
    ok.

