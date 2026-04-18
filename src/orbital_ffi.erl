-module(orbital_ffi).

-export([packbeam_create/3, packbeam_list/1, run_executable/3,
    find_executable/1, set_cwd/1]).

packbeam_create(OutputPath, StartModule, Files) ->
    % The packbeam_api call expects its arguments to be Erlang charlists,
    % this is called from Gleam passing in Gleam strings (binaries).
    % So we need to massage those types into something that packbeam will
    % accept.
    CharOutputPath = unicode:characters_to_list(OutputPath),
    CharFiles = [unicode:characters_to_list(File) || File <- Files],
    Options = #{
        % This removes beam files that are not referenced
        prune => true,
        lib => false,
        start_module => binary_to_atom(StartModule),
        include_lines => true
    },
    try packbeam_api:create(CharOutputPath, CharFiles, Options) of
        ok -> {ok, nil};
        {error, eisdir} -> {error, {output_file_is_directory, OutputPath}};
        {error, _} -> {error, {cannot_find_entrypoint_module, StartModule}}
    catch
        _ -> {error, {cannot_find_entrypoint_module, StartModule}}
    end.

-spec packbeam_list(binary()) -> {ok,[binary()]} | {error, nil}.
packbeam_list(InputPath) ->
    ListInputPath = unsafe_characters_to_list(InputPath),
    try packbeam_api:list(ListInputPath) of
        Elements when is_list(Elements) ->
            Names = lists:map(fun(Element) ->
                Name = packbeam_api:get_element_name(Element),
                unsafe_characters_to_binary(Name)
            end, Elements),
            {ok, Names};
        _ -> {error, nil}
    catch
        _ -> {error, nil}
    end.

-spec run_executable(Name :: binary(), Directory :: binary(), Arguments :: list(binary())) -> {ok, integer()} | {error, nil}.
run_executable(Name, Directory, Arguments) ->
    try
        StringName = unsafe_characters_to_list(Name),
        Port = erlang:open_port({spawn_executable, StringName},
            [
                {args, Arguments},
                {cd, Directory},
                hide,
                exit_status,
                stderr_to_stdout,
                use_stdio
            ]
        ),
        ExitStatus = receive {Port, {exit_status, Code}} -> Code end,
        {ok, ExitStatus}
    catch
        error:_ -> {error, nil}
    end.

-spec find_executable(Name :: binary()) -> {ok, binary()} | {error, nil}.
find_executable(Name) ->
    case os:find_executable(unsafe_characters_to_list(Name)) of
        false -> {error, nil};
        Path -> {ok, unsafe_characters_to_binary(Path)}
    end.

-spec unsafe_characters_to_list(Name :: binary()) -> string().
unsafe_characters_to_list(Name) ->
    case unicode:characters_to_list(Name) of
        Result when is_list(Result) -> Result;
        Error -> throw({unsafe_characters_to_list, Error})
    end.

-spec unsafe_characters_to_binary(Name :: string()) -> binary().
unsafe_characters_to_binary(Name) ->
    case unicode:characters_to_binary(Name) of
        Result when is_binary(Result) -> Result;
        Error -> throw({unsafe_characters_to_binary, Error})
    end.

-spec set_cwd(Path :: binary()) -> {ok, nil} | {error, nil}.
set_cwd(Path) ->
    try file:set_cwd(Path) of
        ok -> {ok, nil};
        {error, _} -> {error, nil}
    catch
        _:_ -> {error, nil}
    end.
