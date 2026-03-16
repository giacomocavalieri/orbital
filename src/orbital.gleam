import argv
import filepath
import gleam/dict
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/package_interface
import gleam/result
import gleam/string
import gleam_community/ansi
import hoist
import orbital/internal/cli.{type Platform, Esp32}
import orbital/internal/executable.{type ExecutablePath}
import orbital/internal/project.{
  type Project, CannotParseGleamToml, CannotReadGleamToml, CannotReadProjectName,
}
import simplifile.{Enoent}
import temporary
import tom.{NotFound, WrongType}

const default_baud = 921_600

/// The orbital command line interface entry point.
/// This is intended to be ran as a command line tool by running
/// `gleam run -m orbital`.
///
pub fn main() -> Nil {
  case cli.parse(argv.load().arguments) {
    Error(error) -> {
      case error {
        cli.MissingRequiredPositionalArgument(state:, argument:) -> {
          io.println(error_heading("missing argument " <> argument))
          io.println("")
          io.println(cli.help_text_for_state(state))
        }
        cli.MissingRequiredFlag(state:, flag:) -> {
          io.println(error_heading("missing flag --" <> flag))
          io.println("")
          io.println(cli.help_text_for_state(state))
        }
        cli.InvalidFlagValue(state:, flag:, value:, expected:) -> {
          io.println(error_heading("invalid --" <> flag <> " value"))
          io.println("The flag --" <> flag <> " expects " <> expected)
          io.println("But it was given the value '" <> value <> "'")
          io.println("")
          io.println(cli.help_text_for_state(state))
        }
        cli.InvalidFlashPlatform(platform:) -> {
          io.println(error_heading("invalid platform"))
          io.println("'" <> platform <> "' is not a supported platform.")
          io.println("The only supported platform at the moment is 'esp32'.")
          io.println("")
          io.println(cli.help_text_for_state(cli.ParsingFlash))
        }
        cli.HoistError(hoist.UnknownFlag(flag)) -> {
          io.println(error_heading("unknown flag --" <> flag))
        }
        cli.HoistError(hoist.ValueNotProvided(flag:)) -> {
          io.println(error_heading("missing value for --" <> flag))
          io.println(
            "The flag --"
            <> flag
            <> " must have a value, but no value was passed to it",
          )
        }
        cli.HoistError(hoist.ValueNotSupported(flag:, given:)) -> {
          io.println(error_heading("invalid --" <> flag <> " value"))
          io.println(
            "The flag --"
            <> flag
            <> " is used as a toggle and expects no value,",
          )
          io.println("But it was given the value '" <> given <> "'")
        }
        cli.HoistError(hoist.CustomError(value: cli.UnknownCommand(
          command:,
          state:,
        ))) -> {
          io.println(error_heading("unknown command '" <> command <> "'"))
          io.println("")
          io.println(cli.help_text_for_state(state))
        }
      }
      exit(1)
    }

    Ok(cli.Usage) -> io.println(cli.usage_text())
    Ok(cli.Help) -> io.println(cli.usage_text())
    Ok(cli.Flash(help: True, ..)) -> io.println(cli.flash_help_text())
    Ok(cli.Flash(help: False, dry_run: True, platform:, port:, baud:)) ->
      flash_dry_run(platform, port, baud)
    Ok(cli.Flash(help: False, dry_run: False, platform:, port:, baud:)) ->
      flash(platform, port, baud)
  }
}

fn flash_dry_run(_platform: Platform, port: String, baud: Option(Int)) -> Nil {
  let baud = option.unwrap(baud, default_baud) |> int.to_string
  let command =
    [
      "  esptool --chip auto \\",
      "    --port '" <> port <> "' \\",
      "    --baud " <> baud <> " \\",
      "    --before default-reset --after hard-reset write-flash -u \\",
      "    --flash-mode keep --flash-freq keep --flash-size detect 0x210000 \\",
      "    <AVM_FILE>",
    ]
    |> string.join(with: "\n")

  io.println("To flash the device I would run this command:\n\n" <> command)
}

fn flash(platform: Platform, port: String, baud: Option(Int)) -> Nil {
  case do_flash(platform, port, baud) {
    Ok(_) -> io.println(ansi.magenta("⚛️  done!"))
    Error(error) -> {
      io.println(error_to_string(error))
      exit(1)
    }
  }
}

fn do_flash(
  platform: Platform,
  port: String,
  baud: Option(Int),
) -> Result(Nil, Error) {
  // TODO: For now the platform is not needed, we only support one.
  // This is so I won't forget to update the code once we support more!
  let Esp32 = platform

  // In order to do anything useful we need to make sure Gleam is installed
  // (we'll need to run it to compile the project), and that we're inside a
  // Gleam project.
  use gleam <- result.try(
    executable.find("gleam")
    |> result.replace_error(CannotFindGleamExecutable),
  )
  // In future, if supporting multiple platform we'd only required the specific
  // tool needed for the given platform. For now esp is the only supported one
  // so it's fair to always require `esptool`
  use esptool <- result.try(
    executable.find("esptool")
    |> result.replace_error(CannotFindEsptoolExecutable),
  )
  use project <- result.try(
    project.load()
    |> result.map_error(CannotIdentifyProject),
  )

  // The gleam compiler doesn't recompile the root project when running a module
  // from a dependency (`gleam run -m orbital`).
  // This is quite nice as it allows us to run deps even if our own code is not
  // in a compiling state.
  // However, in our case we actually want to make sure that when "orbital" is
  // running it is using the most recent version of the code: it would be quite
  // confusing to run `gleam run -m orbital` and it flushes an outdated version
  // of the code because we forgot to run `gleam build && gleam run -m orbital`.
  // So we start by compiling the root project:
  use Nil <- try_step("Compiling your Gleam project...", fn() {
    compile(gleam, project)
  })
  use Nil <- try_step("Looking for a suitable entrypoint...", fn() {
    validate_entrypoint(gleam, project)
  })

  // If the root project was compiled successufully we're good to go: we can
  // now pack all the produces `.beam` files into an `.avm` file ready to be
  // flushed into the device.
  let outcome = {
    use directory <- temporary.create(temporary.directory())
    let output_path = filepath.join(directory, "build.avm")
    use Nil <- try_step("Building the `.avm` file...", fn() {
      bundle_beam_files(project, output_path)
    })
    use Nil <- try_step("Flashing the `.avm` file into the device...", fn() {
      esp_flash_to_device(project, esptool, output_path, port, baud)
    })
    Ok(Nil)
  }

  case outcome {
    Ok(result) -> result
    Error(_) -> Error(CannotFlashWithEsptool(-1))
  }
}

@external(erlang, "erlang", "halt")
fn exit(status_code: Int) -> a

type Error {
  CannotFindGleamExecutable
  CannotIdentifyProject(reason: project.Error)
  CannotSpawnGleamCompiler
  CannotSpawnEsptool
  CannotCompileProject
  CannotListBeamFiles(reason: simplifile.FileError)

  CannotReadPackageInterface(reason: simplifile.FileError)
  CannotParsePackageInterface(reason: json.DecodeError)
  CannotFindEntrypointModule(module: String)
  CannotFindEntrypointFunction(module: String)
  EntrypointFunctionHasWrongArity(module: String)
  CannotFindEsptoolExecutable

  CannotFlashWithEsptool(status_code: Int)
  EsptoolCannotOpenPort(port: String)
}

fn error_to_string(error: Error) -> String {
  let title = case error {
    CannotFindEntrypointModule(_) -> "missing entrypoint module"
    CannotFindEntrypointFunction(_) -> "missing entrypoint function"
    EntrypointFunctionHasWrongArity(_) -> "wrong entrypoint function"
    CannotCompileProject -> "invalid Gleam project"
    CannotFindEsptoolExecutable -> "missing 'esptool'"
    CannotFlashWithEsptool(_) | EsptoolCannotOpenPort(_) ->
      "cannot flash device"

    // Unusual errors that should never happen, I'm not fretting over a perfect
    // name here.
    CannotIdentifyProject(CannotParseGleamToml)
    | CannotIdentifyProject(CannotReadProjectName(NotFound(..)))
    | CannotIdentifyProject(CannotReadProjectName(WrongType(..))) ->
      "invalid Gleam project"
    CannotIdentifyProject(CannotReadGleamToml(_)) -> "cannot read `gleam.toml`"
    CannotFindGleamExecutable -> "cannot find gleam exectuable"
    CannotSpawnGleamCompiler -> "cannot check Gleam project"
    CannotSpawnEsptool -> "cannot flash to device"
    CannotListBeamFiles(_)
    | CannotReadPackageInterface(_)
    | CannotParsePackageInterface(_) -> "cannot build `.avm` file"
  }

  let body = case error {
    CannotFindEntrypointModule(module:) ->
      "Make sure to define a `"
      <> module
      <> "` module with a public `start()` function.\n"
      <> "That is the entrypoint used by AtomVM."

    CannotFindEntrypointFunction(module:) ->
      "Make sure the `"
      <> module
      <> "` module defines a public `start()` function.\n"
      <> "That is the entrypoint used by AtomVM."

    EntrypointFunctionHasWrongArity(module:) ->
      "The `start` function in the `"
      <> module
      <> "` module must have no arguments to be a valid entrypoint."

    CannotCompileProject ->
      "It seems like your project has some compilation errors.\n"
      <> "Make sure to fix all errors and run `gleam run -m orbital` again."

    CannotFindEsptoolExecutable ->
      "To flash a device 'esptool' needs to be installed, but I couldn't "
      <> "find it in your PATH.\n"
      <> "Hint: you can find installation instructions at\n"
      <> "https://docs.espressif.com/projects/esptool/en/latest/esp32/installation.html"

    CannotFlashWithEsptool(status_code:) ->
      "The call to 'esptool' failed with status code: "
      <> int.to_string(status_code)
      <> "."

    EsptoolCannotOpenPort(port:) ->
      "The port '"
      <> port
      <> "' is busy or doesn't exist.\n"
      <> "Hint: make sure the port is correct and the device connected."

    // We're modelling these errors, but they should technically never happen
    // (so I'm not fretting over perfect error messages): one woulnd't even be
    // able to run `gleam` if any of these were to take place!
    CannotListBeamFiles(_) ->
      "An unexpected error while trying to figure out the files to include "
      <> "in the `.avm` script."
    CannotFindGleamExecutable -> "Make sure `gleam` is in your path."
    CannotSpawnGleamCompiler ->
      "I couldn't check if your project has any compilation errors.\n"
      <> bug_report_call_to_action()
    CannotSpawnEsptool ->
      "I ran into an unexpected error trying to run 'esptool'.\n"
      <> bug_report_call_to_action()
    CannotIdentifyProject(CannotReadGleamToml(Enoent)) ->
      "It looks like this Gleam project doesn't have a `gleam.toml` file, make "
      <> "sure to create one first."
    CannotIdentifyProject(CannotReadGleamToml(_)) ->
      "An unexpected error happened while trying to read this project's "
      <> "`gleam.toml` file."
    CannotIdentifyProject(CannotParseGleamToml) ->
      "It looks like this project's `gleam.toml` file is invalid."
    CannotIdentifyProject(CannotReadProjectName(NotFound(..))) ->
      "This project's `gleam.toml` file doesn't have the required `name` "
      <> "field, make sure to add one."
    CannotIdentifyProject(CannotReadProjectName(WrongType(..))) ->
      "This project's name in the `gleam.toml` file is not a string."
    CannotReadPackageInterface(_) ->
      "I couldn't analyse your project's modules.\n"
      <> bug_report_call_to_action()
    CannotParsePackageInterface(_) ->
      "The project's package interface seems to be invalid.\n"
      <> bug_report_call_to_action()
  }

  error_heading(title) <> "\n" <> body
}

fn bug_report_call_to_action() -> String {
  "This is most likely a bug, please open a bug report at\n"
  <> "https://github.com/giacomocavalieri/orbital/issues/new"
}

fn error_heading(title: String) -> String {
  ansi.bold(ansi.red("Error: ") <> title)
}

/// Compiles the given project using the provided Gleam executable.
///
fn compile(gleam: ExecutablePath, project: Project) -> Result(Nil, Error) {
  use exit_code <- result.try(
    executable.run(gleam, project.root_directory, ["build"])
    |> result.replace_error(CannotSpawnGleamCompiler),
  )
  case exit_code {
    0 -> Ok(Nil)
    _ -> Error(CannotCompileProject)
  }
}

/// Makes sure that the project has a valid entry point, suitable to be used by
/// AtomVM.
///
fn validate_entrypoint(
  gleam: ExecutablePath,
  project: Project,
) -> Result(Nil, Error) {
  // We need to first build the project's package interface, that has info about
  // all the functions defined by the project.
  // We do that in a temporary directory so it gets cleaned up automatically!
  let outcome = {
    use directory <- temporary.create(temporary.directory())
    let file = filepath.join(directory, "package_interface.json")
    let options = ["export", "package-interface", "--out", file]
    use _ <- result.try(
      executable.run(gleam, project.root_directory, options)
      |> result.replace_error(CannotSpawnGleamCompiler),
    )
    use package_interface <- result.try(
      simplifile.read(file)
      |> result.map_error(CannotReadPackageInterface),
    )
    use package_interface <- result.try(
      json.parse(package_interface, package_interface.decoder())
      |> result.map_error(CannotParsePackageInterface),
    )
    use entrypoint_module <- result.try(
      dict.get(package_interface.modules, project.name)
      |> result.replace_error(CannotFindEntrypointModule(project.name)),
    )
    use entrypoint_function <- result.try(
      dict.get(entrypoint_module.functions, "start")
      |> result.replace_error(CannotFindEntrypointFunction(project.name)),
    )
    case entrypoint_function.parameters {
      [] -> Ok(Nil)
      _ -> Error(EntrypointFunctionHasWrongArity(project.name))
    }
  }

  case outcome {
    Ok(result) -> result
    Error(error) -> Error(CannotReadPackageInterface(error))
  }
}

/// Bundles all the `.beam` files of the project into a single `.avm` file
/// located at the given path.
///
fn bundle_beam_files(
  project: Project,
  output_path: String,
) -> Result(Nil, Error) {
  use beam_files <- result.try(
    list_beam_files(project)
    |> result.map_error(CannotListBeamFiles),
  )
  packbeam_create(output_path:, start_module: project.name, beam_files:)
  |> result.replace_error(CannotFindEntrypointModule(project.name))
}

/// Lists all the `.beam` files under the given project's build directory.
///
fn list_beam_files(
  project: Project,
) -> Result(List(String), simplifile.FileError) {
  let build_directory =
    filepath.join(project.root_directory, "build")
    |> filepath.join("dev")
    |> filepath.join("erlang")

  use files <- result.try(simplifile.get_files(build_directory))
  let beam_files =
    list.filter(files, keeping: fn(file) {
      filepath.extension(file) == Ok("beam")
    })

  Ok(beam_files)
}

@external(erlang, "orbital_ffi", "packbeam_create")
fn packbeam_create(
  output_path output_path: String,
  start_module module: String,
  beam_files files: List(String),
) -> Result(Nil, Nil)

fn esp_flash_to_device(
  project: Project,
  esptool: ExecutablePath,
  output_path: String,
  port: String,
  baud: Option(Int),
) -> Result(Nil, Error) {
  let baud = option.unwrap(baud, default_baud) |> int.to_string
  let outcome =
    executable.run(esptool, project.root_directory, [
      "--chip", "auto", "--port", port, "--baud", baud, "--before",
      "default-reset", "--after", "hard-reset", "write-flash", "-u",
      "--flash-mode", "keep", "--flash-freq", "keep", "--flash-size", "detect",
      "0x210000", output_path,
    ])

  case outcome {
    Ok(0) -> Ok(Nil)
    Ok(2) -> Error(EsptoolCannotOpenPort(port))
    Ok(n) -> Error(CannotFlashWithEsptool(n))
    Error(_) -> Error(CannotSpawnEsptool)
  }
}

// --- CLI PRETTY PRINTING -----------------------------------------------------

fn try_step(
  line: String,
  do: fn() -> Result(a, b),
  then: fn(a) -> Result(c, b),
) -> Result(c, b) {
  io.println(ansi.dim(line))
  let result = do()
  delete_line()
  result.try(result, then)
}

fn delete_line() -> Nil {
  let go_back_to_previous_line = "\u{1b}[1F"
  let delete_entire_line = "\u{1b}[2K"
  io.print(go_back_to_previous_line <> delete_entire_line)
}
