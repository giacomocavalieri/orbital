"""Serial console used by `gleam run -m orbital monitor`.

The reset order matches ExAtomVM's monitor: both control lines stay asserted
while the port opens, RTS is released before DTR, and a later RTS pulse resets
the board so the boot log is captured. A native-USB board disappears during
that reset and is waited for until the timeout.
"""

import argparse
import codecs
import sys
import time

import serial
import serial.tools.list_ports


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, required=True)
    parser.add_argument("--timeout", type=int, required=True)
    parser.add_argument("--no-reset", action="store_true")
    args = parser.parse_args()

    try:
        port = resolve_port(args.port)
    except LookupError as error:
        print(error, file=sys.stderr)
        return 1

    print(f"Serial port {port}", file=sys.stderr)
    return read_console(
        port,
        args.baud,
        reset=not args.no_reset,
        timeout=None if args.timeout == 0 else args.timeout,
    )


def resolve_port(port: str) -> str:
    if port != "auto":
        return port

    found = usb_ports()
    if len(found) == 1:
        return found[0]
    if not found:
        raise LookupError(
            "No serial port found.\n"
            "Hold BOOT, tap RESET, release BOOT, and try again."
        )
    lines = "\n".join(f"  {device}" for device in found)
    raise LookupError(f"Several serial ports found:\n{lines}\nPass one with --port.")


def usb_ports() -> list[str]:
    devices = []
    for info in serial.tools.list_ports.comports():
        device = info.device
        # macOS publishes every adapter twice. The cu node does not wait for
        # carrier, which is the one a monitor can open.
        if sys.platform == "darwin" and device.startswith("/dev/tty."):
            continue
        description = " ".join(
            part
            for part in (device, info.description or "", info.manufacturer or "", info.hwid or "")
            if part
        ).lower()
        if any(
            token in description
            for token in ("usb", "acm", "slab", "wch", "espressif", "cp210", "ch340", "ftdi")
        ):
            devices.append(device)
    return devices


def read_console(port: str, baud: int, reset: bool, timeout: int | None) -> int:
    deadline = None if timeout is None else time.monotonic() + timeout
    decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")
    at_line_start = True

    def expired() -> bool:
        return deadline is not None and time.monotonic() >= deadline

    def write(text: str) -> None:
        nonlocal at_line_start
        if text:
            sys.stdout.write(text)
            sys.stdout.flush()
            at_line_start = text.endswith("\n")

    def newline() -> None:
        if not at_line_start:
            write("\n")

    def set_line(name: str, value: bool) -> None:
        try:
            setattr(ser, name, value)
            if name == "rts":
                # Windows' usbser.sys sends the lines only when DTR is written.
                ser.dtr = ser.dtr
        except OSError:
            pass

    def open_port() -> None:
        ser.rts = True
        ser.dtr = True
        ser.open()
        set_line("rts", False)
        set_line("dtr", False)

    ser = serial.serial_for_url(
        port, baudrate=baud, timeout=0.1, exclusive=True, do_not_open=True
    )

    try:
        open_port()
    except (serial.SerialException, OSError) as error:
        print(error, file=sys.stderr)
        return 1

    try:
        if reset:
            set_line("rts", True)
            time.sleep(0.1)
            set_line("rts", False)

        while not expired():
            try:
                data = ser.read(ser.in_waiting or 1)
            except (serial.SerialException, OSError):
                newline()
                write("Waiting for the board to reconnect")
                try:
                    ser.close()
                except OSError:
                    pass
                while not expired():
                    time.sleep(0.5)
                    try:
                        open_port()
                        break
                    except (serial.SerialException, OSError):
                        write(".")
                write("\n")
                decoder.reset()
                continue
            write(decoder.decode(data))
    finally:
        newline()
        try:
            ser.close()
        except OSError:
            pass
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ModuleNotFoundError:
        print(
            "pyserial is not installed for this Python.\n"
            "Install esptool, or install pyserial for python3.",
            file=sys.stderr,
        )
        raise SystemExit(1)
