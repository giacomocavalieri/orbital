import filepath
import gleam/dict
import gleam/result
import simplifile
import tom

pub type Error {
  CannotReadGleamToml(reason: simplifile.FileError)
  CannotParseGleamToml
  CannotReadProjectName(reason: tom.GetError)
}

pub type Project {
  Project(name: String, root_directory: String, dependencies: List(String))
}

/// Determines the project where this function is run.
///
/// > This works under the assumption that the command is being run somewhere
/// > inside a Gleam project.
///
pub fn load() -> Result(Project, Error) {
  // We first need to locate the project's root directory.
  // That's where we'll find the `gleam.toml` file where the project name
  // is defined.
  let root_directory = find_root_directory(".")
  // We then read the `gleam.toml` file, parse it, and extract the project name
  // from it.
  use gleam_toml <- result.try(
    filepath.join(root_directory, "gleam.toml")
    |> simplifile.read
    |> result.map_error(CannotReadGleamToml),
  )
  use gleam_toml <- result.try(
    tom.parse(gleam_toml)
    |> result.replace_error(CannotParseGleamToml),
  )
  use name <- result.try(
    tom.get_string(gleam_toml, ["name"])
    |> result.map_error(CannotReadProjectName),
  )
  let dependencies =
    tom.get_table(gleam_toml, ["dependencies"])
    |> result.unwrap(dict.new())
    |> dict.keys()

  Ok(Project(name:, root_directory:, dependencies:))
}

fn find_root_directory(current_path: String) -> _ {
  let gleam_toml = filepath.join(current_path, "gleam.toml")
  case simplifile.is_file(gleam_toml) {
    Ok(True) -> current_path
    Ok(False) | Error(_) -> {
      let path = filepath.join(current_path, "..")
      find_root_directory(path)
    }
  }
}
