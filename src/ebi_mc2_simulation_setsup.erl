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
%%  @doc Supervisor governing all the running simulations on the queue.
%%  @see ebi_mc2_queue
%%
-module(ebi_mc2_simulation_setsup).
-behaviour(supervisor).
-export([start_link/0, start_simulation/3]). % API
-export([init/1]). % Callbacks
-include("ebi_mc2.hrl").


%% =============================================================================
%%  API functions.
%% =============================================================================

%%
%%  @doc Start this supervisor.
%%
-spec start_link() -> {ok, pid()} | term().
start_link() ->
    supervisor:start_link(?MODULE, {}).


%%
%%  @doc Add new simulation.
%%  Only the simulation ID and the colaborator process ids should
%%  be passed here. The actual simulation definition will be retrieved
%%  from the queue on simulation startup (or restart).
%%
-spec start_simulation(pid(), string(), pid()) ->
        {ok, pid()} |
        term().
start_simulation(Supervisor, SimulationId, Queue) ->
    supervisor:start_child(Supervisor, [SimulationId, Queue]).



%% =============================================================================
%%  Callbacks.
%% =============================================================================

%%
%%  @doc Configure the supervisor.
%%
init({}) ->
    Mod = ebi_mc2_simulation,
    Spec = {Mod,
        {Mod, start_link, []},
        permanent, brutal_kill, worker, [Mod]
    },
    {ok, {{simple_one_for_one, 120, 60}, [Spec]}}.

