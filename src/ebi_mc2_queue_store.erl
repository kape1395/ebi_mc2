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
%%  Provides a persistent store for the queue.
%%
-module(ebi_mc2_queue_store).
-export([
    init/0, add/2, delete/2, get/2, get_running/1,
    get_next_pending/1, set_status/3, set_target/3, add_command/3
]).
-include("ebi.hrl").
-include("ebi_mc2.hrl").

init() ->
    ets:new(ebi_mc2_queue_store, [private]).

%%
%%  Add new simulation to the store.
%%
add(Table, Simulation) ->
    #simulation{id = SimulationId} = Simulation,
    true = ets:insert(Table, {
        SimulationId,                       % Simulation ID.
        Simulation,                         % Simulation definition.
        {pending, undefined, undefined},    % Simulation state: {Global, Local, IsTerminal}        
        [],                                 % Commands sent to this simulation.
        {undefined, undefined}              % Target: {ClusterName, PartitionName}.
    }),
    ok.


%%
%%  Delete simulation from the store.
%%
delete(Table, SimulationId) ->
    true = ets:delete(Table, SimulationId),
    ok.


%%
%%  Get a simulation by ID.
%%
get(Table, SimulationId) ->
    case ets:lookup(Table, SimulationId) of
        [{SID, Sim, State, Commands, Target}] ->
            {ok, #ebi_mc2_sim{
                simulation_id = SID,
                simulation = Sim,
                state = State,
                commands = Commands,
                target = Target
            }};
        [] ->
            {error, not_found}
    end.


%%
%%  Returns a list of SimulationIds, for simulations that should be running now.
%%
get_running(Table) ->
    Normalize = fun
        ([SID, Target]) -> {SID, Target}
    end,
    lists:map(Normalize, ets:match(Table, {'$1', '_', {running, '_', '_'}, '_', '$2'})).


%%
%%  Get next pending simulation.
%%
get_next_pending(Table) ->
    Match = ets:match(Table, {'$1', '_', {pending, '_', '_'}, '_', '_'}, 1),
    case Match of
        '$end_of_table' ->
            {error, empty};
        {[[SimulationId]], _Cont} ->
            {ok, SimulationId}
    end.


%%
%%  Update simulation status by ID.
%%
set_status(Table, SimulationId, Status) ->
    true = ets:update_element(Table, SimulationId, {3, Status}),
    ok.


%%
%%  Update simulation target by id.
%%  The assigned target cluster and the corresponding partition are used
%%  on restart of the queue. The same simulations should be assigned to
%%  the same clusters to avoid duplicated simulations. 
%%
set_target(Table, SimulationId, Target = {_Cluster, _Partition}) ->
    true = ets:update_element(Table, SimulationId, [{3, {running, assigned, false}}, {5, Target}]),
    ok.


add_command(Table, SimulationId, Command) ->
    Tuple = ets:lookup(Table, SimulationId),
    Commands = [Command | Tuple#ebi_mc2_sim.commands],
    true = ets:update_element(Table, SimulationId, {4, Commands}),
    ok.

