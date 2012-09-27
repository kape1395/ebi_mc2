-module(basic_SUITE).
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([test_mnesia_rw/1]).
-include_lib("common_test/include/ct.hrl").
-include("bio_ers_queue_mifcl2.hrl").

all() ->
    [test_mnesia_rw].

init_per_suite(Config) ->
    Priv = ?config(priv_dir, Config),
    application:set_env(mnesia, dir, Priv),
    ebi_app:install([node()]),
    application:start(mnesia),
    application:start(ebi),
    Config.
 
end_per_suite(_Config) ->
    application:stop(mnesia),
    ok.

test_mnesia_rw(_Config) ->
    S = #ebi_mifcl2_sim{id = "id1", definition = {[{},{}]}, state = running},
    W = fun () -> mnesia:write(S) end,
    R = fun () -> mnesia:read(ebi_mifcl2_sim, S#ebi_mifcl2_sim.id) end,
    mnesia:activity(transaction, W),
    [S] = mnesia:activity(transaction, R).

