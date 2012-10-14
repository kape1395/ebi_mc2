-module(main_SUITE).
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([test_queue/1]).
-include_lib("common_test/include/ct.hrl").

all() ->
    [test_queue].

init_per_suite(Config) ->
    % Priv = ?config(priv_dir, Config),
    % application:set_env(mnesia, dir, Priv),
    % ebi_app:install([node()]),
    % application:start(mnesia),
    % application:start(ebi),
    % crypto, ssh, mnesia, xmerl, ebi, ebi_mc2
    Config.
 
end_per_suite(_Config) ->
    % application:stop(mnesia),
    ok.

test_queue(_Config) ->
    ok.

