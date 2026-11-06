import gleam/string
import gleeunit
import gleeunit/should
import orbital/internal/partition

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn main_avm_offset_skips_earlier_partitions_test() {
  let table =
    bit_array_append(entry("boot.avm", 0x1f0000), entry("main.avm", 0x2b8000))

  partition.main_avm_offset(table)
  |> should.equal(Ok(0x2b8000))
}

pub fn main_avm_offset_is_missing_when_the_table_has_no_app_slot_test() {
  partition.main_avm_offset(entry("boot.avm", 0x1f0000))
  |> should.equal(Error(Nil))
}

pub fn hex_address_formats_the_badge_slot_test() {
  partition.hex_address(0x2b8000)
  |> should.equal("0x2b8000")
}

fn entry(name: String, offset: Int) -> BitArray {
  let padding = 16 - string.byte_size(name)
  <<
    0xaa,
    0x50,
    0x01,
    0x00,
    offset:size(32)-little,
    0:size(32)-little,
    name:utf8,
    0:size(padding)-unit(8),
    0:size(32)-little,
  >>
}

fn bit_array_append(left: BitArray, right: BitArray) -> BitArray {
  <<left:bits, right:bits>>
}
