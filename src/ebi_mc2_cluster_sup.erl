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
%%  @doc Supervisor governing processes related to single cluster connection.
%%  They should be considered fragile. The server dicsonnects the connections from
%%  time to time. The ssh_channel sometimes hangs till first call, and then fails after
%%  some timeout.
%%
-module(ebi_mc2_cluster_sup).
-behaviour(supervisor).
-export([start_link/2]). % API
-export([init/1]). % Callbacks
-include("ebi_mc2.hrl").


%% =============================================================================
%%  API functions.
%% =============================================================================

%%
%%  @doc Initialize this supervisor.
%%
-spec start_link(#config_cluster{}, pid()) -> {ok, pid()} | term().
start_link(ClusterConfig, Queue) ->
    supervisor:start_link(?MODULE, {ClusterConfig, Queue}).


%% =============================================================================
%%  Callbacks for supervisor.
%% =============================================================================

%%
%%  @doc Configure the supervisor.
%%
init({ClusterConfig, Queue}) ->
    Module = ebi_mc2_cluster,
    {ok, {{one_for_all, 120, 60}, [
        {Module,
            {Module, start_link, [ClusterConfig, Queue]},
            permanent, brutal_kill, worker, [Module]
        }
    ]}}.

