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
-export([start_link_spec/1, start_link/1, add_cluster_sup/2, add_simulation_sup/1]). % API
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
start_link(Config) ->
    supervisor:start_link(?MODULE, {Config}).


%%
%%  @doc Add a cluster (ssh channel) supervisor.
%%
-spec add_cluster_sup(pid(), [#config_cluster{}]) ->
        {ok, pid()} |
        term().
add_cluster_sup(Supervisor, Clusters) ->
    Mod = ebi_mc2_cluster_sup,
    Spec = {Mod,
        {Mod, start_link, [Clusters]},
        permanent, brutal_kill, supervisor, [Mod]
    }, 
    supervisor:start_child(Supervisor, Spec).


%%
%%  @doc Add a supervisor for the simulations.
%%
-spec add_simulation_sup(pid()) ->
        {ok, pid()} |
        term().
add_simulation_sup(Supervisor) ->
    Mod = ebi_mc2_simulation_sup,
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
    Mod = ebi_mc2_queue,
    Spec = {Mod,
        {Mod, start_link, [Config, self()]},
        permanent, brutal_kill, worker, [Mod]
    }, 
    {ok, {{one_for_all, 100, 60}, [Spec]}}.

