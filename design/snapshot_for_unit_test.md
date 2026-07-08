# Snapshot-based unit testing in TermWin

## Goal

Run a widget, inject a fixed sequence of keystrokes programmatically, then assert on the rendered plane contents — without a human at the terminal.

## How it works

Notcurses exposes `ncplane_contents` as `NC.contents(plane, begy, begx, leny, lenx)`, which returns a flat `String` of every EGC in a rectangular region of a plane. Passing `0` for `leny`/`lenx` reads to the plane boundary. This lets a test call `draw`, inject tokens, call `draw` again, then snapshot the result.

```julia
using TermWin
import Notcurses as NC

withsession() do
    widget = newTwDfTable(rootTwScreen, df)
    draw(widget)

    inject(widget, :down)
    inject(widget, :down)
    draw(widget)

    plane = widget.window          # must be NC.Plane (top-level widget)
    rows, cols = NC.dim_yx(plane)
    snapshot = NC.contents(plane, 0, 0, rows, cols)
    # snapshot is a flat String of all cell EGCs, concatenated row by row

    @test occursin("expected text", snapshot)
end
```

Token values match what `readtoken` produces: `:up`, `:down`, `:enter`, `:ctrl_n`, `"a"` for printable chars, etc.

## Caveats

- **`widget.window` must be an `NC.Plane`** — top-level widgets only. Widgets embedded inside a `TwList` canvas hold a `TwWindow` (a virtual canvas record), not a real Notcurses plane, so `NC.contents` cannot be called on them directly. Test at the root level or promote the widget to a standalone plane.

- **No row separators** — `contents` returns one long string. To work with individual lines, chunk by `cols`:
  ```julia
  lines = [snapshot[i*cols+1 : (i+1)*cols] for i in 0:rows-1]
  ```
  Alternatively, use `NC.at_yx(plane, y, x, stylemask, channels)` for cell-by-cell access that also returns style and color channel data.

## Existing headless infrastructure

`test/custom_keys_unit.jl` and `test/progress_unit.jl` already call `inject` directly, bypassing the event loop. They test business logic but not rendered output. `NC.contents` fills that gap.
