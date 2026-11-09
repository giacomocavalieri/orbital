import gleam/bit_array
import gleam/int
import gleam/string

/// Address of the `main.avm` partition in an ESP-IDF partition table.
///
/// Each entry is 32 bytes: magic `0x50AA`, type, subtype, little-endian offset,
/// little-endian size, a 16-byte name, and flags. `0xFFFF…` ends the table.
pub fn main_avm_offset(table: BitArray) -> Result(Int, Nil) {
  find_main(table)
}

pub fn hex_address(value: Int) -> String {
  "0x" <> hex_digits(value)
}

fn find_main(table: BitArray) -> Result(Int, Nil) {
  case table {
    <<
      0xaa,
      0x50,
      _:8,
      _:8,
      offset:size(32)-little,
      _:size(32)-little,
      label:bytes-size(16),
      _:size(32)-little,
      rest:bits,
    >> ->
      case label_name(label) {
        "main.avm" -> Ok(offset)
        _ -> find_main(rest)
      }
    <<0xeb, 0xeb, _:bytes-size(30), rest:bits>> -> find_main(rest)
    _ -> Error(Nil)
  }
}

fn label_name(label: BitArray) -> String {
  case label {
    <<0, _:bits>> -> ""
    <<byte, rest:bits>> -> {
      let char = case bit_array.to_string(<<byte>>) {
        Ok(text) -> text
        Error(_) -> ""
      }
      char <> label_name(rest)
    }
    _ -> ""
  }
}

fn hex_digits(value: Int) -> String {
  let assert Ok(nibble) = int.remainder(value, 16)
  let rest = value / 16
  let digit = string.slice("0123456789abcdef", nibble, 1)
  case rest {
    0 -> digit
    _ -> hex_digits(rest) <> digit
  }
}
