-module(orbital_ffi).

-export([packbeam_create/3, run_executable/3, find_executable/1]).

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

run_executable(Name, Directory, Arguments) ->
    try
        Port = erlang:open_port(
            {spawn_executable, unicode:characters_to_list(Name)},
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

find_executable(Name) ->
    case os:find_executable(unicode:characters_to_list(Name)) of
        false -> {error, nil};
        Path -> {ok, unicode:characters_to_binary(Path)}
    end.
