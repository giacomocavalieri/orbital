import gleam/option.{None, Some}
import gleeunit
import orbital/internal/cli.{Esp32, Flash}

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn esp32_flash_defaults_to_reading_the_partition_test() {
  let assert Ok(Flash(platform:, help: False)) =
    cli.parse(["flash", "esp32", "--port", "/dev/ttyACM0"])

  let assert Esp32(port:, baud:, offset:, dry_run:) = platform
  assert port == "/dev/ttyACM0"
  assert baud == None
  assert offset == None
  assert dry_run == False
}

pub fn esp32_flash_offset_can_be_overridden_test() {
  let assert Ok(Flash(platform: Esp32(offset:, ..), help: False)) =
    cli.parse([
      "flash", "esp32", "--port", "/dev/ttyACM0", "--offset", "0x210000",
    ])

  assert offset == Some("0x210000")
}

pub fn esp32_flash_rejects_a_bad_offset_test() {
  let assert Error(_) =
    cli.parse(["flash", "esp32", "--port", "/dev/ttyACM0", "--offset", "main"])
}
