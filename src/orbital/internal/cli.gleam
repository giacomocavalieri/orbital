import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam_community/ansi
import hoist.{type ValidatedFlagSpecs}

pub type Command {
  Usage
  Help
  Flash(
    platform: Platform,
    port: String,
    baud: Option(Int),
    dry_run: Bool,
    help: Bool,
  )
}

pub type ParsingState {
  ParsingBase
  ParsingFlash
  ParsingHelp
}

pub type CustomError {
  UnknownCommand(command: String, state: ParsingState)
}

pub type Platform {
  Esp32
}

pub type Error {
  HoistError(hoist.ParseError(CustomError))
  InvalidFlashPlatform(platform: String)
  MissingRequiredPositionalArgument(state: ParsingState, argument: String)
  MissingRequiredFlag(state: ParsingState, flag: String)
  InvalidFlagValue(
    state: ParsingState,
    flag: String,
    value: String,
    expected: String,
  )
}

pub fn parse(args: List(String)) -> Result(Command, Error) {
  case parse_args(args) {
    // If there's no argument at all we just show the "usage" page.
    Ok(hoist.Args(arguments: [], flags: _)) -> Ok(Usage)

    // "help" is pretty straightforward, the parsing done by hoist
    // is plenty enough.
    Ok(hoist.Args(arguments: ["help"], flags: _)) -> Ok(Help)

    // with "flash" we need a little additional checks: first we need to make
    // sure that the required platform positional argument was provided.
    // Then we have to make sure that the "port" flag exists, that is mandatory.
    // Finally, if "baud" was provided we need to validate that it's an Int.
    Ok(hoist.Args(arguments: ["flash", ..rest], flags:)) ->
      case toggled(flags, "help") {
        True ->
          Ok(Flash(
            platform: Esp32,
            port: "port",
            baud: None,
            dry_run: False,
            help: True,
          ))

        False ->
          case rest {
            [] ->
              Error(MissingRequiredPositionalArgument(
                ParsingFlash,
                "[PLATFORM]",
              ))
            [_, unknown, ..] ->
              UnknownCommand(unknown, ParsingFlash)
              |> hoist.CustomError
              |> HoistError
              |> Error

            ["esp32"] -> {
              use port <- require_flag(flags, ParsingFlash, "port")
              use baud <- optional_int_flag(flags, ParsingFlash, "baud")
              let dry_run = toggled(flags, "dry-run")
              let help = toggled(flags, "help")
              Ok(Flash(platform: Esp32, port:, baud:, dry_run:, help:))
            }
            [platform] -> Error(InvalidFlashPlatform(platform))
          }
      }

    // Any other command is invalid. Hoist should prevent against this, but
    // rather than panicking I just use the same error.
    Ok(hoist.Args(arguments: [command, ..], flags: _)) -> {
      UnknownCommand(command, ParsingBase)
      |> hoist.CustomError
      |> HoistError
      |> Error
    }
    Error(error) -> Error(HoistError(error))
  }
}

fn parse_args(
  args: List(String),
) -> Result(hoist.Args, hoist.ParseError(CustomError)) {
  let flags = base_flags()
  hoist.parse_with_hook(args, flags, ParsingBase, fn(state, command, _, flags) {
    case command, state {
      // The base cli only accepts "help", or "flash" as commands.
      "help", ParsingBase -> Ok(#(ParsingHelp, help_flags()))
      "flash", ParsingBase -> Ok(#(ParsingFlash, flash_flags()))
      _, ParsingBase -> Error(UnknownCommand(state:, command:))

      // The "help" command accepts no subcommands
      _, ParsingHelp -> Error(UnknownCommand(state:, command:))

      // The "flash" command takes positional arguments, but no subcommands, so
      // there's no need to special case any of them as they don't change the
      // accepted flags
      _, ParsingFlash -> Ok(#(ParsingFlash, flags))
    }
  })
}

fn base_flags() -> ValidatedFlagSpecs {
  let assert Ok(base_flags) =
    hoist.validate_flag_specs([
      hoist.new_flag("help")
      |> hoist.with_short_alias("h")
      |> hoist.as_toggle,
    ])
  base_flags
}

fn help_flags() -> ValidatedFlagSpecs {
  let assert Ok(help_flags) = hoist.validate_flag_specs([])
  help_flags
}

fn flash_flags() -> ValidatedFlagSpecs {
  let assert Ok(flash_flags) =
    hoist.validate_flag_specs([
      hoist.new_flag("port")
        |> hoist.with_short_alias("p"),
      hoist.new_flag("baud")
        |> hoist.with_short_alias("b"),
      hoist.new_flag("dry-run")
        |> hoist.with_short_alias("d")
        |> hoist.as_toggle,
      hoist.new_flag("help")
        |> hoist.with_short_alias("h")
        |> hoist.as_toggle,
    ])
  flash_flags
}

// --- HELPERS TO WORK WITH FLAGS ----------------------------------------------

fn find_flag_value(flags: List(hoist.Flag), name: String) {
  list.find_map(flags, fn(flag) {
    case flag {
      hoist.ValueFlag(name: actual, value:) if actual == name -> Ok(value)
      hoist.CountFlag(..) | hoist.ValueFlag(..) | hoist.ToggleFlag(..) ->
        Error(Nil)
    }
  })
}

fn require_flag(
  flags: List(hoist.Flag),
  state: ParsingState,
  name: String,
  continue: fn(String) -> Result(a, Error),
) -> Result(a, Error) {
  case find_flag_value(flags, name) {
    Ok(value) -> continue(value)
    Error(_) -> Error(MissingRequiredFlag(state, name))
  }
}

fn optional_int_flag(
  flags: List(hoist.Flag),
  state: ParsingState,
  flag: String,
  continue: fn(Option(Int)) -> Result(a, Error),
) -> Result(a, Error) {
  case find_flag_value(flags, flag) {
    Error(_) -> continue(None)
    Ok(value) ->
      case int.parse(value) {
        Ok(parsed) -> continue(Some(parsed))
        Error(_) ->
          Error(InvalidFlagValue(
            state:,
            flag: flag,
            value:,
            expected: "an integer",
          ))
      }
  }
}

fn toggled(flags: List(hoist.Flag), name: String) {
  list.contains(flags, hoist.ToggleFlag(name))
}

pub fn usage_text() -> String {
  [
    ansi.magenta("⚛️  orbital - v1.0.0"),
    "",
    ansi.magenta("Usage: ")
      <> ansi.green("gleam run -m orbital ")
      <> "[COMMAND]",
    "",
    ansi.magenta("Commands:"),
    "  flash  build and flash your code to a device",
    "  help   show this help text",
  ]
  |> string.join(with: "\n")
}

pub fn flash_help_text() -> String {
  [
    ansi.magenta("Usage: ")
      <> ansi.green("gleam run -m orbital ")
      <> "flash [PLATFORM] <FLAGS>",
    "",
    ansi.magenta("Platforms: "),
    "  esp32          this will require `esptool` installed",
    "",
    ansi.magenta("Flags:"),
    "  -p, --port     <STRING>  the path where to find the device",
    "  -b, --baud     <INT>     the baud used when flashing the device",
    "  -d, --dry-run            only show the command used to flash the device",
    "  -h, --help               show this help text",
  ]
  |> string.join(with: "\n")
}

pub fn help_text_for_state(state: ParsingState) -> String {
  case state {
    ParsingBase -> usage_text()
    ParsingFlash -> flash_help_text()
    ParsingHelp -> usage_text()
  }
}
