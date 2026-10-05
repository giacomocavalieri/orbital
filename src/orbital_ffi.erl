-module(orbital_ffi).

-export([packbeam_create/3, packbeam_list/1, run_executable/3, find_executable/1, monitor/4]).

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

%% Shows the ESP32 console. The Python interpreter is taken from esptool's
%% shebang, because that environment has pyserial.
monitor(Port, Baud, Reset, Timeout) ->
    case interpreter() of
        {error, Reason} -> {error, Reason};
        {ok, Python} ->
            case monitor_script() of
                {error, Reason} -> {error, Reason};
                {ok, Script} ->
                    run_monitor(Python, [
                        "-u", Script, "--port", Port,
                        "--baud", integer_to_binary(Baud),
                        "--timeout", integer_to_binary(Timeout)
                        | reset_arg(Reset)
                    ])
            end
    end.

reset_arg(true) -> [];
reset_arg(false) -> ["--no-reset"].

run_monitor(Python, Args) ->
    Port = open_port({spawn_executable, Python}, [
        {args, [to_charlist(Arg) || Arg <- Args]},
        binary,
        exit_status,
        stderr_to_stdout,
        use_stdio
    ]),
    monitor_loop(Port).

monitor_loop(Port) ->
    receive
        {Port, {data, Data}} ->
            io:put_chars(Data),
            monitor_loop(Port);
        {Port, {exit_status, 0}} ->
            {ok, nil};
        {Port, {exit_status, _}} ->
            {error, <<>>}
    end.

to_charlist(Value) when is_binary(Value) -> binary_to_list(Value);
to_charlist(Value) when is_list(Value) -> Value.

interpreter() ->
    case os:find_executable("esptool") of
        false -> python3();
        Esptool ->
            case shebang(Esptool) of
                {ok, Program} -> {ok, Program};
                error -> python3()
            end
    end.

python3() ->
    case os:find_executable("python3") of
        false -> {error, <<"Cannot find esptool or python3.">>};
        Python -> {ok, Python}
    end.

shebang(Path) ->
    case file:open(Path, [read, binary]) of
        {ok, File} ->
            Line = io:get_line(File, ""),
            ok = file:close(File),
            parse_shebang(Line);
        {error, _} -> error
    end.

parse_shebang(<<"#!", Rest/binary>>) ->
    Line = string:trim(first_line(Rest)),
    case string:split(Line, " ", all) of
        [<<"/usr/bin/env">>, Program | _] ->
            case os:find_executable(binary_to_list(Program)) of
                false -> error;
                Found -> {ok, Found}
            end;
        [Program | _] -> {ok, binary_to_list(Program)};
        _ -> error
    end;
parse_shebang(_) -> error.

first_line(Bin) ->
    case binary:split(Bin, <<"\n">>) of
        [Line | _] -> Line;
        _ -> Bin
    end.

%% The script lives in this package. `gleam run` from the orbital repo finds
%% it at the project root; a project that depends on orbital finds the copy
%% gleam downloaded under build/packages.
monitor_script() ->
    case code:which(orbital_ffi) of
        non_existing -> {error, <<"Cannot find priv/monitor.py.">>};
        Beam ->
            %% code:which may return a path relative to the project root.
            Absolute = filename:absname(Beam),
            Build = lists:foldl(
                fun(_, Path) -> filename:dirname(Path) end,
                Absolute,
                lists:seq(1, 5)
            ),
            Root = filename:dirname(Build),
            first_regular([
                filename:join(Root, "priv/monitor.py"),
                filename:join([Build, "packages", "orbital", "priv", "monitor.py"])
            ])
    end.

first_regular([]) -> {error, <<"Cannot find priv/monitor.py.">>};
first_regular([Path | Rest]) ->
    case filelib:is_regular(Path) of
        true -> {ok, Path};
        false -> first_regular(Rest)
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
