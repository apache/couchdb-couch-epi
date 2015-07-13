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

-module(couch_epi_functions).

-behaviour(gen_server).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([childspec/4]).
-export([start_link/4, reload/1]).
-export([wait/1, stop/1]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
    provider, service_id, modules, hash, handle,
    initialized = false, pending = []}).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

childspec(Id, App, Key, Module) ->
    {
        Id,
        {?MODULE, start_link, [
            App,
            {epi_key, Key},
            {modules, [Module]},
            []
        ]},
        permanent,
        5000,
        worker,
        [Module]
    }.

start_link(ProviderApp, {epi_key, ServiceId}, {modules, Modules}, Options) ->
    gen_server:start_link(
        ?MODULE, [ProviderApp, ServiceId, Modules, Options], []).

reload(Server) ->
    gen_server:call(Server, reload).

wait(Server) ->
    gen_server:call(Server, wait).

stop(Server) ->
    catch gen_server:call(Server, stop).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init([Provider, ServiceId, Modules, _Options]) ->
    gen_server:cast(self(), init),
    {ok, #state{
        provider = Provider,
        modules = Modules,
        service_id = ServiceId,
        handle = couch_epi_functions_gen:get_handle(ServiceId)}}.

handle_call(wait, _From, #state{initialized = true} = State) ->
    {reply, ok, State};
handle_call(wait, From, #state{pending = Pending} = State) ->
    {noreply, State#state{pending = [From | Pending]}};
handle_call(reload, _From, State) ->
    {Res, NewState} = reload_if_updated(State),
    {reply, Res, NewState};
handle_call(stop, _From, State) ->
    {stop, normal, State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(init, #state{pending = Pending} = State) ->
    {_, NewState} = reload_if_updated(State),
    [gen_server:reply(Client, ok) || Client <- Pending],
    {noreply, NewState#state{initialized = true, pending = []}};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, State) ->
    safe_remove(State),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {_, NewState} = reload_if_updated(State),
    {ok, NewState}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

reload_if_updated(#state{hash = OldHash, modules = Modules} = State) ->
    case couch_epi_functions_gen:hash(Modules) of
        OldHash ->
            {ok, State};
        Hash ->
            safe_add(Hash, State)
    end.

safe_add(Hash, #state{modules = OldModules} = State) ->
    #state{
        handle = Handle,
        provider = Provider,
        modules = Modules,
        service_id = ServiceId} = State,
    try
        ok = couch_epi_functions_gen:add(Handle, Provider, Modules),
        couch_epi_server:notify(
            Provider, ServiceId, {modules, OldModules}, {modules, Modules}),
        {ok, State#state{hash = Hash}}
    catch Class:Reason ->
        {{Class, Reason}, State}
    end.

safe_remove(#state{} = State) ->
    #state{
        handle = Handle,
        provider = Provider,
        modules = Modules,
        service_id = ServiceId} = State,
    try
        ok = couch_epi_functions_gen:remove(Handle, Provider, Modules),
        couch_epi_server:notify(
            Provider, ServiceId, {modules, Modules}, {modules, []}),
        {ok, State#state{modules = []}}
    catch Class:Reason ->
        {{Class, Reason}, State}
    end.
