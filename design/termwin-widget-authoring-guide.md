# TermWin Widget Authoring Guide

How an external package defines its own widget and plugs it into TermWin's layout
DSL (`@twlayout` / `vstack` / `hstack`). A complete, runnable example lives in
`test/custom_widget_demo.jl`.

For the design rationale behind the authoring layers used here (contracts, theme,
bindings, scroll, rows), see `design/termwin-widget-authoring-rearchitecture.md`.

---

## The model

Everything on screen is a `TwObj{T}` where `T` is a data struct holding that
widget's state. TermWin dispatches `draw`, `inject`, and `helptext` on `T`, so a
new widget is: **a data struct + a constructor + a `draw` method**, plus optional
key handling. You build it entirely from the exported public API — no TermWin
internals required.

## Minimal recipe

```julia
using TermWin
import TermWin: draw, inject, bindings   # import to extend these unqualified

# 1. State
mutable struct GaugeData
    value::Int
    max::Int
end

# 2. Constructor — first arg is the parent container; end with link_parent_child.
function newGauge(parent::TwObj; key=nothing, max=100, value=0,
                  height=1, width=1.0, posy=:top, posx=:left)
    o = TwObj(GaugeData(value, max), Val{:Gauge})
    o.acceptsFocus = true     # set false for a static/display widget
    o.box = false; o.borderSizeV = 0; o.borderSizeH = 0
    o.value   = value         # the value forms collect (see "Forms")
    o.formkey = key           # set ⇒ participates in form collection
    link_parent_child(parent, o, height, width, posy, posx)
    o
end

# 3. Render into o.window with the exported primitives + theme tokens.
function draw(o::TwObj{GaugeData})
    werase(o.window)
    n = round(Int, o.width * o.data.value / o.data.max)
    o.hasFocus && wattron(o.window, theme(:selection_focused))
    mvwprintw(o.window, 0, 0, "%s", repeat("█", n) * repeat("░", o.width - n))
    o.hasFocus && wattroff(o.window, theme(:selection_focused))
end

# 4. (optional) Key handling — declare it once as data; help/footer are generated.
function bindings(o::TwObj{GaugeData})
    Binding[
        Binding([:left, "h"],  "−", action = o -> (o.value = max(0, o.value-1); Handled)),
        Binding([:right, "l"], "+", action = o -> (o.value = min(o.data.max, o.value+1); Handled)),
        Binding(:enter, "ok", action = o -> Accept),
    ]
end
inject(o::TwObj{GaugeData}, token) = inject_via_table(o, token)

# 5. Register a short name for the DSL.
register_twlayout_widget!(:gauge, newGauge)
```

Now `gauge(...)` works inside any layout body:

```julia
@twlayout (title = "Status") begin
    label("Disk usage"; style = :header)
    gauge(; key = :disk, max = 100, value = 72)
end
```

## The dispatch contract

| Function | Default | When to override |
|----------|---------|------------------|
| `draw(o::TwObj{T})` | errors | **always** — render to `o.window` |
| `inject(o::TwObj{T}, token)` | `:esc → Cancel`, else `Ignored` | to handle keys |
| `helptext(o::TwObj{T})` | `""` | F1 help; usually `helptext_from_bindings(o)` |
| `bindings(o::TwObj{T})` | `Binding[]` | declare the keymap as data |
| `tick(o::TwObj{T})` | `Ignored` | animated/streaming widgets |
| `clamp_scroll!(o::TwObj{T})` | `nothing` | scrollable widgets (keeps cursor visible on resize) |

`inject` returns an `InjectResult`: `Handled` (consumed, keep focus), `Ignored`
(not ours — the host bubbles it up, e.g. Tab/Esc), `Accept` (finish with
`o.value`), `Cancel` (finish, no result). Return `Ignored` for keys you don't own
so containers can act on them.

Extend the generics either by `import TermWin: draw, inject, …` and defining them
unqualified (as above), or by writing `function TermWin.draw(o::TwObj{T}) … end`.

## `o.window` and the drawing primitives

`o.window` is an `NC.Plane` for a top-level widget, or a `TwWindow` when the
widget sits inside a layout container — every primitive is overloaded for both, so
your `draw` code is identical in either case:

`werase` · `mvwprintw(win, row, col, "%s", str)` · `mvwaddch` · `wattron` /
`wattroff` · `box` / `box_colored` · `beep`. Widget size is `o.height` × `o.width`
(borders are stripped inside layouts, so draw edge-to-edge from `(0,0)`).

## Color: theme tokens, not magic numbers

Prefer semantic tokens so your widget follows theme switches
(`set_theme!(:high_contrast)`):

`theme(:selection_focused)` `:selection_unfocused` `:header` `:divider`
`:negative` `:emphasis`.

Compose raw attributes with `COLOR_PAIR(n)`, the `COLOR_*` constants, the `A_*`
style flags, and `make_attr(...)` / `TwAttr` when you need a literal pair. (Never
OR a raw channel `UInt64` with a style flag — start from `COLOR_PAIR(n)`.)

## Optional layers

- **Scroll** — hold a `ScrollState` in your data struct and implement
  `clamp_scroll!(o) = clamp_view!(o.data.scroll, content_len, viewport)`; use
  `move_cursor!` / `page!` / `scroll_left!` / `visible` for navigation. The
  framework re-clamps you on resize.
- **Trees** — reuse `TreeRow` / `FileRow` and `tree_nav(rows, cursor, :parent | :prev_sibling | :next_sibling)` for Ctrl-Left/Up/Down navigation.
- **Result** — `Ok` / `Cancelled` / `Failed` + `unwrap` for a typed modal return.

## Forms

A widget joins form collection by setting `o.formkey = key` and keeping `o.value`
current. `@twlayout (form=true) … end` (or `vstack`/`hstack` with `form=true`)
harvests every keyed widget into a `Dict{Symbol,Any}` on F10. Returning `Accept`
from `inject` (e.g. on Enter) advances to the next field instead of exiting. To be
pre-fillable from a `defaults` dict, also implement
`apply_default!(o::TwObj{T}, v)`.

## The registry

```julia
register_twlayout_widget!(:name, newMyWidget)   # short name → constructor
unregister_twlayout_widget!(:name)
twlayout_widgets()                              # live list of all short names
```

Registration is consulted at **runtime**, so register at package load (top level
or `__init__`) and the short name is immediately usable in any `@twlayout` /
`vstack` / `hstack` body. The container is injected as the constructor's first
argument, so the constructor must be `newMyWidget(parent, args...; kwargs...)`.
Unregistered bare calls in a layout body run as ordinary code (pass-through), and
re-registering a name overrides it (you can shadow a built-in).

## Exported authoring API (quick reference)

- **Registry:** `register_twlayout_widget!`, `unregister_twlayout_widget!`, `twlayout_widgets`
- **Core:** `TwObj`, `link_parent_child`, `newTwList`, `vstack`, `hstack`, `@twlayout`, `activateTwObj`, `objtype`
- **Dispatch:** `draw`, `inject`, `helptext`, `tick`, `clamp_scroll!`
- **Primitives:** `werase`, `mvwprintw`, `mvwaddch`, `wattron`, `wattroff`, `box`, `box_colored`, `beep`
- **Color:** `COLOR_PAIR`, `TwAttr`, `make_attr`, `COLOR_BLACK…COLOR_WHITE`, `A_NORMAL`, `A_BOLD`, `A_UNDERLINE`, `A_REVERSE`, `A_ITALIC`
- **Theme:** `theme`, `set_theme!`, `refresh_theme!`
- **Bindings:** `Binding`, `bindings`, `active_bindings`, `inject_via_table`, `footer`, `helptext_from_bindings`, `keylabel`
- **Scroll:** `ScrollState`, `clamp_view!`, `move_cursor!`, `page!`, `scroll_left!`, `visible`
- **Rows:** `AbstractRow`, `TreeRow`, `FileRow`, `tree_nav`, `depth`, `parent_prefix`, `stack_of`
- **Contracts:** `InjectResult` (`Handled`/`Ignored`/`Accept`/`Cancel`), `Result` (`Ok`/`Cancelled`/`Failed`), `unwrap`, `isok`

> Note: `draw`, `inject`, `Handled`, `Ignored`, etc. are deliberately short,
> generic names. If they collide with another package, extend via the qualified
> `TermWin.draw(...)` form instead of importing them.
