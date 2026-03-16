# ⚛️ orbital

<!--[![Package Version](https://img.shields.io/hexpm/v/orbital)](https://hex.pm/packages/orbital)-->
<!--[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/orbital/)-->

Build and flash Gleam projects to devices running [AtomVM](https://atomvm.org).

Add it to your project as a git development dependency by adding the following
line under `[dev_dependencies]`:

```sh
orbital = { git = "https://github.com/giacomocavalieri/orbital", ref = "v1.0.0" }
```

Your project must have a module with a `start` function that takes no arguments:

```gleam
import gleam/io

pub fn start() {
  io.println("Hello, from AtomVM!")
}
```

To build and flash it to a device with the AtomVM firmware installed you can
run:

```sh
gleam run -m orbital flash esp32 --port /dev/some_device
```

And you're good to go! To get an overview of all the available commands and
options you can run:

```sh
gleam run -m orbital help
```

## FAQ

- **What's AtomVM?**

  AtomVM is a lightweight implementation of the BEAM, optimized to run on tiny
  micro-controllers. You can read more about it [here!](https://atomvm.org)

- **How can I install AtomVM?**

  To install AtomVM on a device check the
  [getting started guide.](https://doc.atomvm.org/latest/getting-started-guide.html)

- **Can I run any Gleam program on AtomVM?**

  AtomVM implements a constrained subset of the Erlang's standard library, so if
  your Gleam code or dependencies use some of the functions that are not
  supported you will see a runtime error once running it on the device!

  If you see an `undef` error in your stack trace, that most likely means your
  code used one such function.

- **What can I do to help?**

  AtomVM is a wicked cool project, enabling developers to run Erlang, Elixir and
  Gleam code on tiny embedded devices, as cheap as 2$!
  If you think this project is cool, please
  [consider sponsoring it!](https://github.com/sponsors/atomvm)
