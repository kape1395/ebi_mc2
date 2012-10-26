-module(ebi_mc2_cluster_resp_tests).
-include_lib("eunit/include/eunit.hrl").
-include("ebi_mc2.hrl").

%%
%%  Simulation started and completed.
%%
simple_test() ->
    {CR1, CMD1, FROM1} = {"0000000000000000000000000000000000000001", store_config,      from_01},
    {CR2, CMD2, FROM2} = {"0000000000000000000000000000000000000002", cluster_status,    from_02},
    {CR3, CMD3, FROM3} = {"0000000000000000000000000000000000000003", submit_simulation, from_03},
    {CR4, CMD4, FROM4} = {"0000000000000000000000000000000000000004", cancel_simulation, undefined},
    {CR5, CMD5, FROM5} = {"0000000000000000000000000000000000000005", delete_simulation, from_05},
    {CR6, CMD6, FROM6} = {"0000000000000000000000000000000000000006", simulation_result, from_06},

    %%
    %%  Test scenario
    %%
    {ok, State00} = ebi_mc2_cluster_resp:init(),
    {ok, State01} = ebi_mc2_cluster_resp:add_call({CR1, CMD1, FROM1}, State00),
    {ok, State02} = ebi_mc2_cluster_resp:add_call({CR2, CMD2, FROM2}, State01),
    {ok, State03} = ebi_mc2_cluster_resp:add_call({CR3, CMD3, FROM3}, State02),
    {ok, State04} = ebi_mc2_cluster_resp:add_call({CR4, CMD4, FROM4}, State03),
    {ok, State05} = ebi_mc2_cluster_resp:add_call({CR5, CMD5, FROM5}, State04),
    {ok, State06} = ebi_mc2_cluster_resp:add_call({CR6, CMD6, FROM6}, State05),
    {ok, Responses, _State07} = ebi_mc2_cluster_resp:parse_lines([
        <<"#CLUSTER:OUT(0000000000000000000000000000000000000001)==>EXISTING">>,
        <<"#CLUSTER:OUT(0000000000000000000000000000000000000002)==>CLUSTER_STATUS:START">>,
        <<"#DATA:FS:SID0000000000000000000000000000000000002:RUNNING:258">>,
        <<"#CLUSTER:OUT(0000000000000000000000000000000000000002)==>CLUSTER_STATUS:END">>,
        <<"#CLUSTER:OUT(0000000000000000000000000000000000000003)==>SUBMITTED:SID0000000000000000000000000000000000003:556">>,
        <<"#CLUSTER:OUT(0000000000000000000000000000000000000004)==>CANCELED:SID0000000000000000000000000000000000004">>,
        <<"#CLUSTER:OUT(0000000000000000000000000000000000000005)==>DELETED:SID0000000000000000000000000000000000005">>,
        <<"#CLUSTER:OUT(0000000000000000000000000000000000000006)==>RESULT:SID0000000000000000000000000000000000006:SIM_RUNNING">>
    ], State06),

    [
        {response, existing, from_01},
        {response, {cluster_status, [{fs, "SID0000000000000000000000000000000000002", "RUNNING"}]}, from_02},
        {response, ok, from_03},
        {response, ok, from_05},
        {response, {error, running}, from_06}
    ] = Responses,
    ok.

