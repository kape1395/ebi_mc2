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
%%  @doc Supervisor governing all the cluster partitions (connectors to them).
%%  @see bio_ers_queue_mifcl2
%%
-module(bio_ers_queue_mifcl2_part_supersup).
-behaviour(supervisor).
-export([start_link/2]). % API
-export([init/1]). % Callbacks
-include("bio_ers_queue_mifcl2.hrl").


%% =============================================================================
%%  API functions.
%% =============================================================================

%%
%%
%%
-spec start_link([#part_cfg{}], pid()) -> {ok, Supervisor :: pid()}.
start_link(PartCfgs, Queue) ->
    supervisor:start_link(?MODULE, {PartCfgs, Queue}).



%% =============================================================================
%%  Callbacks.
%% =============================================================================

%%
%%  @doc Configure the supervisor.
%%
init({PartCfgs, Queue}) ->
    Mod = bio_ers_queue_mifcl2_part_sup,
    Spec = fun (PartCfg) ->
        #part_cfg{name = Name} = PartCfg,
        {{part_sup, Name},
            {Mod, start_link, [PartCfg, Queue]},
            permanent, brutal_kill, supervisor, [Mod]
        }
    end, 
    {ok, {
        {one_for_one, 120, 60},
        [ Spec(PartCfg) || PartCfg <- PartCfgs ]
    }}.

