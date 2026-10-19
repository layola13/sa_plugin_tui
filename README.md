# SA TUI Plugin

> **Build requirement: Zig 0.17** — this plugin targets and is verified against **Zig 0.17.0**. Build and test with Zig 0.17; older toolchains such as 0.14.x are not supported.
> 本插件需使用 **Zig 0.17** 编译与测试。


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

## fx compatibility assessment

`fx` separates terminal ownership, input decoding, resize handling, rendering, and
product state across `src/ui/terminal`, `src/ui/input`, `src/ui/render_engine`,
and the event loop. The `tui` plugin is compatible as a low-level host adapter,
but it is not a replacement for the complete `fx` UI stack.

Current coverage:

- terminal handle ownership, dimensions, UTF-8 output, flushing, raw/cooked mode,
  alternate-screen and mouse-tracking toggles;
- bounded byte input reads with explicit timeout status;
- Linux/Unix `ioctl` and `termios` paths plus Windows console dimensions and
  `ConsoleMode` restoration;
- manifest skills split into `tui.terminal`, `tui.input`, and `tui.ansi`.

Required before an `fx`-style application can depend on this plugin directly:

1. decode escape sequences into typed keyboard, mouse, paste, and focus events;
2. emit resize events and expose a stable event queue rather than raw bytes;
3. add cell/frame surfaces, cursor control, diff commits, and inline-screen ownership;
4. add PTY/ConPTY supervision and lifecycle-safe alternate-screen handoff;
5. define a host callback ABI for event-loop polling and output backpressure.

The existing `http-*`, `node`, `deno`, `db`, `bc2sa`, `react`, `mui`, `vm`, `wgpu`,
`sax`, and `sla` plugins remain complementary. A future `tui` revision should
stay focused on terminal primitives; `fx` rendering and product state should not
be duplicated inside the plugin.

