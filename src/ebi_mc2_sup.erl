%
% Copyright 2012 Karolis Petrauskas
%
% Licensed under the Apache License, Version 2.0 (the "License");
% you may not use this file except in compliance with the License.
% You may obtain a copy of the License at
%
%     http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS,
% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
% See the License for the specific language governing permissions and
% limitations under the License.
%

%%
%%  @private
%%  @doc Main Supervisor for the {@link ebi_mc2} queue and related modules.
%%  @see ebi_mc2
%%
-module(ebi_mc2_sup).
-behaviour(supervisor).
-export([start_link_spec/1, start_link/1, add_cluster_setsup/3, add_simulation_setsup/1]). % API
-export([init/1]). % Callbacks
-include("ebi_mc2.hrl").


%% =============================================================================
%%  API functions.
%% =============================================================================


%%
%%
%%
start_link_spec(Config = #config{name = Name}) ->
    {Name,
        {?MODULE, start_link, [Config]},
        permanent, brutal_kill, supervisor, [?MODULE]
    }.


%%
%%  @doc Start and link this supervisor.
%%  `Name' is used to register the queue process and
%%  `Args' is used as a configuration for it (see {@link ebi_mc2_queue}).
%%
-spec start_link(term() | embedded) -> {ok, pid()} | term().
start_link(Config) ->
    supervisor:start_link(?MODULE, {Config}).


%%
%%  @doc Add a cluster (ssh channel) supervisor.
%%
-spec add_cluster_setsup(pid(), [#config_cluster{}], pid()) ->
        {ok, pid()} |
        term().
add_cluster_setsup(Supervisor, Clusters, Queue) ->
    Mod = ebi_mc2_cluster_setsup,
    Spec = {Mod,
        {Mod, start_link, [Clusters, Queue]},
        permanent, brutal_kill, supervisor, [Mod]
    }, 
    supervisor:start_child(Supervisor, Spec).


%%
%%  @doc Add a supervisor for the simulations.
%%
-spec add_simulation_setsup(pid()) ->
        {ok, pid()} |
        term().
add_simulation_setsup(Supervisor) ->
    Mod = ebi_mc2_simulation_setsup,
    Spec = {Mod,
        {Mod, start_link, []},
        permanent, brutal_kill, supervisor, [Mod]
    }, 
    supervisor:start_child(Supervisor, Spec).



%% =============================================================================
%%  Callbacks for supervisor.
%% =============================================================================

%%
%%  @doc Configures this supervisor.
%%
init({Config}) ->
    case Config of
        embedded ->
            {ok, {{one_for_all, 100, 60}, []}};
        #config{} ->
            Mod = ebi_mc2_queue,
            Spec = {Mod,
                {Mod, start_link, [Config, self()]},
                permanent, brutal_kill, worker, [Mod]
            }, 
            {ok, {{one_for_all, 100, 60}, [Spec]}}
    end.

