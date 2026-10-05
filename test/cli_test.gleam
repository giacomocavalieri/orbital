import gleam/option.{None, Some}
import gleeunit
import orbital/internal/cli.{Monitor}

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn monitor_defaults_test() {
  let assert Ok(Monitor(port:, baud:, timeout:, reset: True, help: False)) =
    cli.parse(["monitor"])

  assert port == None
  assert baud == None
  assert timeout == None
}

pub fn monitor_flags_test() {
  let assert Ok(Monitor(port:, baud:, timeout:, reset: False, help: False)) =
    cli.parse([
      "monitor",
      "--port",
      "/dev/ttyACM0",
      "--baud",
      "9600",
      "--timeout",
      "0",
      "--no-reset",
    ])

  assert port == Some("/dev/ttyACM0")
  assert baud == Some(9600)
  assert timeout == Some(0)
}
