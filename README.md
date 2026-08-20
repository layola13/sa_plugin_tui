# SA TUI Plugin

The `tui` plugin exposes a small, versioned C/SAI ABI for terminal ownership, dimensions, output, mode changes, and byte-oriented input events.

Platform behavior:

- Windows uses console handles, screen-buffer dimensions, and ConsoleMode raw-mode restoration.
- Unix-like targets query dimensions through `ioctl(TIOCGWINSZ)` and use `termios` for raw mode.
- Input reads support a bounded timeout and return status `3` when no byte is available.
- PTY supervision, escape-sequence decoding, resize events, and frame-buffer diffing remain future ABI work.

## Build and test

```text
zig build test
zig build
```

The default artifact names are `libtui.so` on Linux and `tui.dll` on Windows.
