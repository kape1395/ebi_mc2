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
%%  @doc Supervisor governing the fragile part of the queue: ssh channel
%%  and associated simulation processes (supervisor of them).
%%  @see bio_ers_queue_mifcl2
%%
-module(bio_ers_queue_mifcl2_part_sup).
-behaviour(supervisor).
-export([start_link/2, create_sim_sup/3]). % API
-export([init/1]). % Callbacks
-include("bio_ers_queue_mifcl2.hrl").


%% =============================================================================
%%  API functions.
%% =============================================================================

%%
%%  @doc Initialize this supervisor.
%%
-spec start_link(#part_cfg{}, pid()) -> {ok, Supervisor :: pid()}.
start_link(PartCfg, Queue) ->
    supervisor:start_link(?MODULE, {PartCfg, Queue}).


%%
%%  @doc Create simulations supervisor.
%%
-spec create_sim_sup(pid(), pid(), pid()) -> {ok, pid()}.
create_sim_sup(Supervisor, Queue, SshChan) ->
    Mod = bio_ers_queue_mifcl2_sim_sup,
    Spec = {sim_sup, {Mod, start_link, [Queue, SshChan]}, permanent, brutal_kill, supervisor, [Mod]},
    supervisor:start_child(Supervisor, Spec).



%% =============================================================================
%%  Callbacks.
%% =============================================================================

%%
%%  @doc Configure the supervisor.
%%
init({PartCfg, Queue}) ->
    Mod = bio_ers_queue_mifcl2_ssh_channel,
    Spec = {ssh_chan, {Mod, start_link, [self(), PartCfg, Queue]}, permanent, brutal_kill, worker, [Mod]}, 
    {ok, {{one_for_all, 120, 60}, [Spec]}}.

