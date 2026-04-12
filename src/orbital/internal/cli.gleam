import glam/doc.{type Document}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam_community/ansi
import hoist.{type ValidatedFlagSpecs}

pub const orbital_version = "v1.1.0"

pub type Command {
  Version
  Usage
  Help
  Flash(
    platform: Platform,
    port: String,
    baud: Option(Int),
    dry_run: Bool,
    help: Bool,
  )
  Build(output_file: Option(String), help: Bool)
  List(input_file: Option(String), help: Bool)
}

pub type ParsingState {
  ParsingBase
  ParsingFlash
  ParsingHelp
  ParsingBuild
  ParsingList
}

pub type CustomError {
  UnknownCommand(command: String)
}

pub type Platform {
  Esp32
}

pub type Error {
  HoistError(state: ParsingState, error: hoist.ParseError(CustomError))
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
  let #(parsing_state, result) = parse_args(args)
  case result {
    Ok(hoist.Args(arguments: [], flags:)) ->
      case toggled(flags, "version") {
        // If there's no argument at all we just show the "usage" page.
        False -> Ok(Usage)
        // If the version flag was toggled we show the version.
        True -> Ok(Version)
      }

    // "help" is pretty straightforward, the parsing done by hoist
    // is plenty enough.
    Ok(hoist.Args(arguments: ["help"], flags: _)) -> Ok(Help)

    // "build" too since it only needs the help flag!
    Ok(hoist.Args(arguments: ["build"], flags:)) ->
      Ok(Build(
        output_file: option.from_result(find_flag_value(flags, "output-file")),
        help: toggled(flags, "help"),
      ))

    // "list" too since it only needs the help flag!
    Ok(hoist.Args(arguments: ["list"], flags:)) ->
      Ok(List(
        input_file: option.from_result(find_flag_value(flags, "input-file")),
        help: toggled(flags, "help"),
      ))

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
              UnknownCommand(unknown)
              |> hoist.CustomError
              |> HoistError(state: parsing_state)
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
      UnknownCommand(command)
      |> hoist.CustomError
      |> HoistError(state: parsing_state)
      |> Error
    }

    Error(error) -> Error(HoistError(parsing_state, error))
  }
}

fn parse_args(
  args: List(String),
) -> #(ParsingState, Result(hoist.Args, hoist.ParseError(CustomError))) {
  let flags = base_flags()
  hoist.parse_with_hook(args, flags, ParsingBase, fn(state, command, _, flags) {
    case command, state {
      // The base cli only accepts "help", or "flash" as commands.
      "build", ParsingBase -> Ok(#(ParsingBuild, build_flags()))
      "flash", ParsingBase -> Ok(#(ParsingFlash, flash_flags()))
      "list", ParsingBase -> Ok(#(ParsingList, list_flags()))
      "help", ParsingBase -> Ok(#(ParsingHelp, help_flags()))
      _, ParsingBase -> Error(UnknownCommand(command:))

      // The "help" command accepts no subcommands
      _, ParsingHelp -> Error(UnknownCommand(command:))

      // The "build" command accepts no subcommands
      _, ParsingBuild -> Error(UnknownCommand(command:))

      // The "list" command accepts no subcommands
      _, ParsingList -> Error(UnknownCommand(command:))

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
      hoist.new_flag("version")
        |> hoist.with_short_alias("v")
        |> hoist.as_toggle,
    ])
  base_flags
}

fn help_flags() -> ValidatedFlagSpecs {
  let assert Ok(help_flags) = hoist.validate_flag_specs([])
  help_flags
}

fn build_flags() -> ValidatedFlagSpecs {
  let assert Ok(build_flags) =
    hoist.validate_flag_specs([
      hoist.new_flag("help")
        |> hoist.with_short_alias("h")
        |> hoist.as_toggle,
      hoist.new_flag("output-file")
        |> hoist.with_short_alias("o"),
    ])
  build_flags
}

fn list_flags() -> ValidatedFlagSpecs {
  let assert Ok(list_avm_flags) =
    hoist.validate_flag_specs([
      hoist.new_flag("help")
        |> hoist.with_short_alias("h")
        |> hoist.as_toggle,
      hoist.new_flag("file")
        |> hoist.with_short_alias("f"),
    ])
  list_avm_flags
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

pub fn usage_text() -> Document {
  [
    doc.from_string(ansi.magenta("⚛️  orbital - " <> orbital_version)),
    doc.lines(2),
    doc.from_string(
      ansi.magenta("Usage: ")
      <> ansi.green("gleam run -m orbital ")
      <> "[COMMAND]",
    ),
    doc.lines(2),
    doc.from_string(ansi.magenta("Commands:")),
    doc.line,
    command_line("  build  ", "build your code into an 'avm' file"),
    doc.line,
    command_line("  flash  ", "build and flash your code to a device"),
    doc.line,
    command_line("  list   ", "list the contents of an 'avm' file"),
    doc.line,
    command_line("  help   ", "show this help text"),
    doc.lines(2),
    doc.from_string(ansi.magenta("Flags:")),
    doc.line,
    command_line("  -v, --version  ", "print orbital's version"),
  ]
  |> doc.concat
  |> doc.group
}

pub fn flash_help_text(description: Bool) -> Document {
  [
    case description {
      False -> doc.empty
      True ->
        "Build your project into an 'avm' file and flash it to the given device."
        |> flex_text
        |> doc.append(doc.lines(2))
    },
    doc.from_string(
      ansi.magenta("Usage: ")
      <> ansi.green("gleam run -m orbital ")
      <> "flash [PLATFORM] <FLAGS>",
    ),
    doc.lines(2),
    doc.from_string(ansi.magenta("Platforms:")),
    doc.line,
    command_line("  esp32  ", "this will require `esptool` installed"),
    doc.lines(2),
    doc.from_string(ansi.magenta("Flags:")),
    doc.line,
    command_line(
      "  -p, --port     <STRING>  ",
      "the path where to find the device",
    ),
    doc.line,
    command_line_with_default(
      "  -b, --baud     <INT>     ",
      "the baud used when flashing the device",
      "921_600",
    ),
    doc.line,
    command_line(
      "  -d, --dry-run            ",
      "only show the command used to flash the device",
    ),
    doc.line,
    command_line("  -h, --help               ", "show this help text"),
  ]
  |> doc.concat
  |> doc.group
}

pub fn build_help_text(description: Bool) -> Document {
  [
    case description {
      False -> doc.empty
      True ->
        [
          flex_text("Build your project into an 'avm' file."),
          doc.line,
          flex_text(
            "This is handy if you need to interact with the 'avm' file with "
            <> "additional tooling, otherwise you can use the `flash` command "
            <> "directly.",
          ),
        ]
        |> doc.concat
        |> doc.append(doc.lines(2))
    },
    doc.from_string(
      ansi.magenta("Usage: ")
      <> ansi.green("gleam run -m orbital ")
      <> "build <FLAGS>",
    ),
    doc.lines(2),
    doc.from_string(ansi.magenta("Flags:")),
    doc.line,
    command_line_with_default(
      "  -o, --output-file  <PATH>  ",
      "the path to write the 'avm' file to",
      "\"name_of_your_project.avm\"",
    ),
    doc.line,
    command_line("  -h, --help                 ", "show this help text"),
  ]
  |> doc.concat
}

pub fn list_help_text(description: Bool) -> Document {
  [
    case description {
      False -> doc.empty
      True ->
        [flex_text("List the contents of an 'avm' file.")]
        |> doc.concat
        |> doc.append(doc.lines(2))
    },
    doc.from_string(
      ansi.magenta("Usage: ")
      <> ansi.green("gleam run -m orbital ")
      <> "list <FLAGS>",
    ),
    doc.lines(2),
    doc.from_string(ansi.magenta("Flags:")),
    doc.line,
    command_line_with_default(
      "  -f, --file  <PATH>  ",
      "the path to the 'avm' file",
      "\"name_of_your_project.avm\"",
    ),
    doc.line,
    command_line("  -h, --help          ", "show this help text"),
  ]
  |> doc.concat
}

pub fn help_text_for_state(state: ParsingState) -> Document {
  case state {
    ParsingBase -> usage_text()
    ParsingFlash -> flash_help_text(False)
    ParsingHelp -> usage_text()
    ParsingBuild -> build_help_text(False)
    ParsingList -> list_help_text(False)
  }
}

fn command_line(name: String, description: String) -> Document {
  doc.concat([
    doc.from_string(name),
    flex_text(description)
      |> doc.nest(by: string.length(name)),
  ])
}

fn command_line_with_default(
  name: String,
  description: String,
  default: String,
) -> Document {
  [
    doc.from_string(name),
    [
      flex_text(description),
      doc.space,
      flex_text("(default: " <> default <> ")"),
    ]
      |> doc.concat
      |> doc.group
      |> doc.nest(by: string.length(name)),
  ]
  |> doc.concat
}

fn flex_text(text: String) -> Document {
  string.split(text, on: " ")
  |> list.map(doc.from_string)
  |> doc.join(doc.flex_space)
  |> doc.group
}

fn error_heading(title: String) -> Document {
  doc.from_string(ansi.bold(ansi.red("Error: ") <> title))
}

pub fn error_to_document(error: Error) -> Document {
  case error {
    MissingRequiredPositionalArgument(state:, argument:) ->
      doc.concat([
        error_heading("missing argument " <> argument),
        doc.lines(2),
        help_text_for_state(state),
      ])

    MissingRequiredFlag(state:, flag:) ->
      doc.concat([
        error_heading("missing flag --" <> flag),
        doc.lines(2),
        help_text_for_state(state),
      ])

    InvalidFlagValue(state:, flag:, value:, expected:) ->
      doc.concat([
        error_heading("invalid --" <> flag <> " value"),
        doc.line,
        flex_text(
          "The flag --"
          <> flag
          <> " expects "
          <> expected
          <> " but it was given the value '"
          <> value
          <> "'",
        ),
        doc.lines(2),
        help_text_for_state(state),
      ])

    InvalidFlashPlatform(platform:) ->
      doc.concat([
        error_heading("invalid platform"),
        flex_text("'" <> platform <> "' is not a supported platform."),
        doc.line,
        flex_text("The only supported platform at the moment is 'esp32'."),
        doc.lines(2),
        help_text_for_state(ParsingFlash),
      ])

    HoistError(state:, error: hoist.UnknownFlag(flag)) ->
      doc.concat([
        error_heading("unknown flag '" <> flag <> "'"),
        doc.lines(2),
        help_text_for_state(state),
      ])

    HoistError(state:, error: hoist.ValueNotProvided(flag:)) ->
      doc.concat([
        error_heading("missing value for flag '" <> flag <> "'"),
        doc.line,
        flex_text(
          "The flag '"
          <> flag
          <> "' must have a value, but no value was passed to it",
        ),
        doc.lines(2),
        help_text_for_state(state),
      ])

    HoistError(state:, error: hoist.ValueNotSupported(flag:, given:)) ->
      doc.concat([
        error_heading("invalid " <> flag <> " value"),
        doc.line,
        flex_text(
          "The flag --"
          <> flag
          <> " is used as a toggle and expects no value,"
          <> " but it was given the value '"
          <> given
          <> "'",
        ),
        doc.lines(2),
        help_text_for_state(state),
      ])

    HoistError(
      state:,
      error: hoist.CustomError(value: UnknownCommand(command:)),
    ) ->
      doc.concat([
        error_heading("unknown command '" <> command <> "'"),
        doc.lines(2),
        help_text_for_state(state),
      ])
  }
}
