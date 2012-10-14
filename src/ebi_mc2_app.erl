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
%%  @doc The OTP application module for ebi_mc2. 
%%
-module(ebi_mc2_app).
-behaviour(application).
-export([install/1]).
-export([start/2, stop/1]). % Callbacks
-include("ebi_mc2.hrl").


%% =============================================================================
%%  API functions.
%% =============================================================================


%%
%%  Install the MNesia DB.
%%
-spec install([node()]) -> ok.
install(Nodes) ->
    ok = mnesia:create_schema(Nodes),
    rpc:multicall(Nodes, application, start, [mnesia]),
    {atomic, ok} = mnesia:create_table(ebi_mc2_sim, [
        {type, set},
        {attributes, record_info(fields, ebi_mc2_sim)},
        {disc_copies, Nodes}
    ]),
    {_ResList, []} = rpc:multicall(Nodes, application, stop, [mnesia]).



%% =============================================================================
%%  Callbacks for application.
%% =============================================================================


start(_StartType, _StartArgs) ->
    {error, not_implemented}.


stop(_State) ->
    ok.

