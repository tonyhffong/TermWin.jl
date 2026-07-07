# TermWin.jl — Package Development Guide

This document is for Julia package developers who want to use TermWin to compose terminal widgets
to present their data structures, and to compose widgets to interact with users.

This document covers extending TermWin: building data-entry forms, authoring custom
widgets, and hooking into `tshow` dispatch. For general usage and content display,
see [README.md](README.md).

## When to use `tshow_` dispatch vs. layout/widget development

The two extension points serve different needs:

**`tshow_` dispatch** (see [Extending TermWin: custom `tshow_` dispatch](#extending-termwin-custom-tshow_-dispatch)) is the right choice when:
- you want `tshow(your_object)` to render your type in a meaningful way without changing calling code.
- the view is a straightforward composition of existing widgets (`dftable`, `viewer`, `entry`, etc.) using `@twlayout` or `vstack`/`hstack`.
- you own the type being displayed and can add a method to your own package.

This covers the majority of real-world use cases. `@twlayout` is expressive enough to arrange multi-panel views, mixed viewer/form layouts, and labelled sections — no new widget code required.

**Full layout and widget development** (composable layouts + authoring custom widgets) is needed when:
- the visual behaviour of a cell, row, or control cannot be expressed by combining existing widgets — e.g. a custom gauge, a sparkline column, a colour swatch, or any widget with bespoke key handling.
- you are building a reusable widget for distribution in your own package, and want it to appear as a first-class short name inside `@twlayout` (via `register_twlayout_widget!`).
- you need the `tick` callback for background-driven refresh (progress bars, live monitors).

In short: reach for `tshow_` first. Only drop down to custom widget authoring when the existing widget palette cannot express what you need.

---

## Composable layouts

Arrange multiple widgets side-by-side or stacked without writing sizing logic by hand.
Children have their borders automatically stripped and rendered edge-to-edge inside
the layout canvas.

### `@twlayout` macro

```julia
@twlayout (title="Results") begin
    viewer(summary_text;  height=0.3, title="Summary")
    dftable(results_df;   height=0.7, title="Data")
end
```

Short names available inside `@twlayout`:

| Short name    | Constructor          |
|:--------------|:---------------------|
| `viewer`      | `newTwViewer`        |
| `dftable`     | `newTwDfTable`       |
| `edittable`   | `newTwEditTable`     |
| `entry`       | `newTwEntry`         |
| `popup`       | `newTwPopup`         |
| `multiselect` | `newTwMultiSelect`   |
| `tree`        | `newTwTree`          |
| `calendar`    | `newTwCalendar`      |
| `filebrowser` | `newTwFileBrowser`   |
| `spacer`      | `newTwSpacer`        |
| `label`       | `newTwLabel`         |
| `separator`   | `newTwSeparator`     |

`vstack` and `hstack` can be **nested inside `@twlayout`** using a `begin...end`
block as their first positional argument — the macro auto-generates a gensym parent
and links the inner container to the outer list correctly. Any other expression
passes through unchanged to the caller's scope.

### `vstack` / `hstack`

Equivalent function-based builders for nesting:

```julia
vstack(; title="Dashboard") do outer
    newTwViewer(outer, header_text; height=4, title="Info")
    hstack(outer; height=0.9) do inner
        newTwDfTable(inner, left_df;  width=0.5, title="Left")
        newTwDfTable(inner, right_df; width=0.5, title="Right")
    end
end
```

`height` and `width` accept either an integer (rows/columns) or a float in `(0,1]`
(fraction of the parent's size).

### Flexible sizing hints

Beyond literal sizes, `height`/`width` accept **hints** so variable-content
widgets (trees, tables, the viewer) take exactly the space they need — or claim
whatever space is left over — instead of being pinned to a magic number:

| Value | Meaning (main axis = height in a `vstack`, width in an `hstack`) |
|-------|------------------------------------------------------------------|
| `:content` | size to the widget's natural content extent, capped at the container |
| `:fill` | grow to consume the leftover main-axis space (weight 1) |
| `Flex(w)` | like `:fill`, but split the leftover space by relative weight `w` |

```julia
# A header, a table sized to its rows, and a tree that soaks up the rest:
vstack(; height=40, width=80) do s
    newTwLabel(s, "Header"; style=:header)   # fixed: height=1
    newTwDfTable(s, df; height=:content)     # shrinks to its row count
    newTwTree(s, tree;  height=:fill)        # takes all remaining height
end

# Two columns splitting the width 2:1:
hstack(; height=40, width=80) do s
    newTwTree(s, left;  width=Flex(2))
    newTwTree(s, right; width=Flex(1))
end
```

`Flex` is exported. `:fill` is `Flex(1)`; two siblings with `Flex(2)`/`Flex(1)`
divide the leftover space 2:1. On terminal resize, `:fill`/`Flex` children
re-expand automatically.

**Nesting works at any depth.** Flex is honored inside nested `vstack`/`hstack`,
including perpendicular nesting — `hstack` columns sized `Flex(2)`/`Flex(1)` split
the width *and* a `:fill` tree inside a column fills the column's full height:

```julia
hstack(; height=40, width=90) do s
    vstack(s; width=Flex(2)) do col       # column takes 2/3 of the width
        newTwLabel(col, "left"; style=:header)   # :content header
        newTwTree(col, a; height=:fill)          # fills the column's height
    end
    vstack(s; width=Flex(1)) do col       # column takes 1/3
        newTwLabel(col, "right"; style=:header)
        newTwTree(col, b; height=:fill)
    end
end
```

A nested `vstack`/`hstack` opts into this **only** when you give it an explicit
`:fill`/`Flex`/`:content` size; a nested list with a numeric or default size still
shrink-wraps to its content (unchanged). See `design/layout-design.md` for the
two-pass (measure → allocate) design and `test/flex_layout.jl` (Demo 4) for a
runnable version.

### Layout labels and spacers

Inside any layout container or `@twlayout` block:

```julia
@twlayout begin
    label("Section header"; style=:header)        # bold yellow, acts as a title
    label("──────────────"; style=:divider)        # ruled divider line
    label("Plain note";     style=:plain)          # default unstyled text
    spacer(; height=1)                             # blank row
    dftable(df; height=0.8)
end
```

`style` values: `:plain` (default), `:header` (bold yellow), `:divider` (white/dark-gray
with embedded `── text ────` rule).

---

## Data-entry forms

Add `form=true` to any layout to collect a `Dict{Symbol,Any}` from the user.

```julia
using TermWin

TermWin.initsession()

form = @twlayout (form=true, title="Settings", height=0.6, width=0.5) begin
    entry(String; key=:host,    title="Host",    width=35)
    entry(Int;    key=:port,    title="Port",    width=10)
    popup(["dev","staging","prod"]; key=:env, title="Environment")
end

activateTwObj(rootTwScreen)
TermWin.endsession()

config = form.value   # Dict(:host=>..., :port=>..., :env=>...) or nothing
```

A more complete example with mixed widget types:

```julia
TermWin.initsession()

result = @twlayout (form=true, title="New User") begin
    entry(String; key=:username, title="Username", width=28)
    entry(Int;    key=:age,      title="Age",      width=10)
    popup(["Engineering","Sales","HR"]; key=:dept, title="Department")
    multiselect(["read","write","exec"]; key=:perms, title="Permissions")
end

activateTwObj(rootTwScreen)
TermWin.endsession()

# result.value is a Dict{Symbol,Any} on submit, or nothing on Esc
if result.value !== nothing
    for (k, v) in result.value
        println("  :$k => $v")
    end
end
```

Widgets without `key=` render normally and receive focus but are excluded from the dict.

`vstack` and `hstack` accept `form=true` the same way. Keyed widgets inside nested
`hstack`/`vstack` blocks are collected automatically.

**Form key bindings:**

| Key | Action |
|:----|:-------|
| Enter | Validate current field and advance focus to next |
| Tab / Shift-Tab | Move focus forward / backward |
| F10 | Submit — returns `Dict{Symbol,Any}` |
| Esc | Cancel — returns `nothing` |
| F1 | In-widget help |

Arrow keys also move focus *geometrically*: ↑/↓ jump to the nearest widget above/below,
←/→ to the nearest on the left/right — but only when the focused widget doesn't consume
the key. A text field walks its cursor first and hands off ←/→ once the cursor is at the
field edge, so left/right can cross to a neighbouring column.

### Reactive section visibility — `visible_when`

Any layout container takes a `visible_when = snap -> Bool` predicate that is
re-evaluated against the live form snapshot after **every keystroke**. When it flips,
the section collapses (reclaiming its rows/columns) or reappears — so a form shows only
what's currently relevant.

```julia
@twlayout (form=true, title="New Job") begin
    popup(["Basic","Advanced"]; key=:mode, title="Mode")
    entry(String; key=:name, title="Job name")
    vstack(begin
        entry(Int;    key=:threads, title="Threads")
        entry(String; key=:host,    title="Host")
    end; visible_when = s -> get(s, :mode, "Basic") == "Advanced")   # shown only in Advanced
end
```

Use `get(snap, :k, default)` — a field's key is absent until it has a value. Hidden
fields still contribute their value to the F10 submit result (visibility only affects
layout and focus, not collection).

### Custom layout key bindings — `on_key`

Attach application-specific keys to any container with `keys=[on_key(...)]`. The callback
receives the same live `Dict{Symbol,Any}` snapshot F10 returns.

```julia
@twlayout (form=true, keys=[
    on_key(:F5,     "preview", snap -> show_preview(snap)),         # stays open
    on_key(:ctrl_s, "save",    snap -> (save_draft(snap); Accept)), # exits, returns snap
]) begin
    entry(String; key=:title, title="Title")
end
```

The callback's return value is the outcome: return an `InjectResult` (`Accept` to submit
with the snapshot, `Handled`/`Cancel` as usual) or return anything else (e.g. `nothing`)
to consume the key, redraw, and stay open. Custom keys appear in the F1 help and footer
automatically, and can't shadow the built-in Tab/F1/F10.

> **Tip:** wrap direct (non-`tshow`) sessions in `withsession(f)` instead of a bare
> `initsession()` / `endsession()` pair — it runs the teardown in a `finally`, so the
> terminal is always restored even if your builder throws (the backtrace then prints on a
> clean terminal). `tshow`/`trun` are built on it.

---

## Authoring custom widgets

TermWin is an extensible TUI framework: your own package can define a widget and
plug it into the `@twlayout` / `vstack` / `hstack` DSL under a short name, using
only TermWin's public API. A widget is a data struct plus a `draw` method (and,
optionally, key handling declared as data).

```julia
using TermWin
import TermWin: draw, inject, bindings

mutable struct GaugeData; value::Int; max::Int; end

function newGauge(parent::TwObj; key=nothing, max=100, value=0,
                  height=1, width=1.0, posy=:top, posx=:left)
    o = TwObj(GaugeData(value, max), Val{:Gauge})
    o.acceptsFocus = true; o.box = false; o.borderSizeV = 0; o.borderSizeH = 0
    o.value = value; o.formkey = key
    link_parent_child(parent, o, height, width, posy, posx)
    o
end

function draw(o::TwObj{GaugeData})
    werase(o.window)
    n = round(Int, o.width * o.data.value / o.data.max)
    o.hasFocus && wattron(o.window, theme(:selection_focused))
    mvwprintw(o.window, 0, 0, "%s", repeat("█", n) * repeat("░", o.width - n))
    o.hasFocus && wattroff(o.window, theme(:selection_focused))
end

function bindings(o::TwObj{GaugeData})
    Binding[
        Binding([:left, "h"],  "−", action = o -> (o.value = max(0, o.value-1); Handled)),
        Binding([:right, "l"], "+", action = o -> (o.value = min(o.data.max, o.value+1); Handled)),
        Binding(:enter, "ok", action = o -> Accept),
    ]
end
inject(o::TwObj{GaugeData}, token) = inject_via_table(o, token)

register_twlayout_widget!(:gauge, newGauge)   # short name → constructor
```

After registering, the short name behaves like a built-in — the container is
injected as the constructor's first argument, and a `key=` makes it participate in
form collection:

```julia
@twlayout (title = "Status") begin
    label("Disk usage"; style = :header)
    gauge(; key = :disk, max = 100, value = 72)
end
```

Registration is resolved at runtime, so register at package load and the name is
immediately usable. `twlayout_widgets()` lists every registered short name.

### Making a custom widget hint-aware

Your widget already accepts the sizing hints for free: `link_parent_child`
forwards whatever `height`/`width` it is given (`:content`, `:fill`, `Flex(w)`,
or a literal) and `alignxy!` resolves it. A fixed-height widget like the gauge
above needs nothing more.

If your widget has **variable content** and should support `:content` (or be a
sensible `:fill` fallback), define `natural_height`/`natural_width` — the layout
engine queries them for the widget's preferred extent. Both default to the
widget's current size; override the relevant axis:

```julia
import TermWin: natural_height, natural_width

# e.g. a list widget that wants one row per item plus its border
natural_height(o::TwObj{MyListData}) = length(o.data.items) + 2 * o.borderSizeV
```

Both are exported. With them defined, `height=:content` sizes your widget to its
content, and inside a nested (shrink-wrapped) container a `:fill` child falls back
to this natural size — see "Flexible sizing hints" above.

See **`design/termwin-widget-authoring-guide.md`** for the full contract (the
`draw`/`inject`/`helptext`/`tick`/`clamp_scroll!` dispatch points, theme tokens,
the bindings/scroll/rows helpers, and forms) and `test/custom_widget_demo.jl` for
a complete interactive example.

---

## Extending TermWin: custom `tshow_` dispatch

Define `TermWin.tshow_` for your own types so users can call `tshow(your_object)`:

```julia
using TermWin, DataFrames

struct ModelResult
    name::String
    summary::String
    data::DataFrame
end

function TermWin.tshow_(r::ModelResult; kwargs...)
    @twlayout (title=r.name) begin
        viewer(r.summary;  height=5,   title="Summary", showLineInfo=false)
        dftable(r.data;    height=0.8, title="Data")
    end
end

# End users just call:
tshow(ModelResult("OLS", "R²=0.87", df))
```

`tshow_` must return the widget (the TwList returned by `@twlayout`/`vstack`/`hstack`)
or a single widget created with a `newTwXxx` constructor.

For forms, return the form container and the caller accesses `.value` after `tshow` returns:

```julia
function TermWin.tshow_(::UserConfig; kwargs...)
    @twlayout (form=true, title="Configure") begin
        entry(String; key=:host, title="Host")
        entry(Int;    key=:port, title="Port")
    end
end

widget = tshow(UserConfig())
config = widget.value   # Dict or nothing
```
