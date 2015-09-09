% Licensed under the Apache License, Version 2.0 (the "License"); you may not
% use this file except in compliance with the License. You may obtain a copy of
% the License at
%
% http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
% License for the specific language governing permissions and limitations under
% the License.

-module(couch_epi_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).
-define(SUP(I, A),
        {I, {I, start_link, A}, permanent, infinity, supervisor, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    case supervisor:start_link({local, ?MODULE}, ?MODULE, []) of
        {ok, _Pid} = Reply ->
            start_plugins(),
            Reply;
        Else ->
            Else
    end.

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    Children = [
        ?CHILD(couch_epi_server, worker),
        ?SUP(couch_epi_keeper_sup, [])
    ],
    {ok, { {one_for_one, 5, 10}, Children} }.

%% ===================================================================
%% Internal functions definitions
%% ===================================================================

start_plugins() ->
    Plugins = application:get_env(couch_epi, plugins, []),
    io:format(user, "PLUGS: ~p~n", [Plugins]),
    ensure_started(Plugins).

ensure_started(Apps) ->
    start_applications(Apps, []).

start_applications([], _Acc) ->
    ok;
start_applications([couch_epi|Apps], Acc) ->
    start_applications(Apps, Acc);
start_applications([App|Apps], Acc) ->
    case not lists:member(App, Acc) of
        true ->
            case application:start(App) of
            {error, {already_started, _}} ->
                start_applications(Apps, Acc);
            {error, {not_started, Dep}} ->
                start_applications([Dep, App | Apps], Acc);
            {error, {not_running, Dep}} ->
                start_applications([Dep, App | Apps], Acc);
            ok ->
                start_applications(Apps, [App|Acc])
            end;
        false ->
            start_applications(Apps, Acc)
    end.
