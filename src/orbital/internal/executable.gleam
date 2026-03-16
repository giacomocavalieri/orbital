@external(erlang, "erlang", "binary")
pub type ExecutablePath

/// Spawn an operating system process, returning a reference to it that can be
/// used to receive stdio data as messages.
///
/// There is no `PATH` variable resolution, so you cannot give the name of a
/// program. It must be a path to the executable.
///
/// The process that calls this function is the owner of the BEAM port for the
/// spawned program. When this process exits the port and the program will be
/// shut down.
///
@external(erlang, "orbital_ffi", "run_executable")
pub fn run(
  executable_path path: ExecutablePath,
  working_directory directory: String,
  command_line_arguments arguments: List(String),
) -> Result(Int, Nil)

/// Find the path to a program given it's name.
///
/// Returns an error if no such executable could be found in the `PATH`.
///
@external(erlang, "orbital_ffi", "find_executable")
pub fn find(name: String) -> Result(ExecutablePath, Nil)
