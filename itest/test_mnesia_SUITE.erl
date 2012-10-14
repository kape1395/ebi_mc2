-module(test_mnesia_SUITE).
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([test_mnesia_rw/1]).
-include_lib("common_test/include/ct.hrl").
-include("ebi_mc2.hrl").


all() ->
    [test_mnesia_rw].


init_per_suite(Config) ->
    Priv = ?config(priv_dir, Config),
    application:set_env(mnesia, dir, Priv),
    ebi_mc2_app:install([node()]),
    application:start(mnesia),
    Config.
 

end_per_suite(_Config) ->
    application:stop(mnesia),
    ok.


test_mnesia_rw(_Config) ->
    S = #ebi_mc2_sim{simulation_id = "id1", simulation = {[{},{}]}, state = running},
    W = fun () -> mnesia:write(S) end,
    R = fun () -> mnesia:read(ebi_mc2_sim, S#ebi_mc2_sim.simulation_id) end,
    mnesia:activity(transaction, W),
    [S] = mnesia:activity(transaction, R).

