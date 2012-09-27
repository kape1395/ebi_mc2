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
%%  @doc Supervisor governing all simulations running on a particular partition.
%%  @see bio_ers_queue_mifcl2
%%
-module(bio_ers_queue_mifcl2_sim_sup).
-behaviour(supervisor).
-export([start_link/2, start_sim/2]). % API
-export([init/1]). % Callbacks
-include("bio_ers_queue_mifcl2.hrl").


%% =============================================================================
%%  API functions.
%% =============================================================================

%%
%%
%%
-spec start_link(pid(), pid()) -> {ok, Supervisor :: pid()}.
start_link(Queue, SshChan) ->
    supervisor:start_link(?MODULE, {Queue, SshChan}).


start_sim(Supervisor, Simulation) ->
    supervisor:start_child(Supervisor, [Simulation]).


%% =============================================================================
%%  Callbacks.
%% =============================================================================

%%
%%  @doc Configure the supervisor.
%%
init({Queue, SshChan}) ->
    Mod = bio_ers_queue_mifcl2_sim,
    Spec = {sim,
        {Mod, start_link, [Queue, SshChan]}, % Other params passed from start_sim/2.
        permanent, brutal_kill, worker, [Mod]
    },
    {ok, {
        {simple_one_for_one, 120, 60},
        [ Spec ]
    }}.

