# TermWin.jl

A terminal UI toolkit for Julia built on [Notcurses](https://github.com/dankamongmen/notcurses).
Explore data structures interactively, collect user input, and compose multi-panel layouts — all in the terminal.

Requires a 256-colour terminal. `xterm-256color` or iTerm2 on macOS are recommended.

---

## Installation

Install the Julia package and the native Notcurses library.

**macOS (Homebrew)**
```
brew install notcurses
```

**Linux (apt)**
```
apt install libnotcurses-dev
```

Then in Julia:
```julia
] add TermWin
```

**iTerm2 note**: Disable *Preferences → Profiles → Terminal → Modern parser for CSI codes*.
Map F1–F4 in *Preferences → Profiles → Keys → Key Bindings* to hex sequences
`0x1b 0x4f 0x50` through `0x1b 0x4f 0x53` so they are not swallowed by the terminal emulator.

---

## Quick start

### 1 — Explore anything with `tshow`

`tshow` accepts almost any Julia value and renders an interactive viewer:

```julia
using TermWin

tshow(42)                          # tree viewer
tshow(:( f(x) = x^2 + 1 ))        # expression tree
tshow(TermWin)                     # module browser
tshow(sort!)                       # method table
tshow(DataFrame(a=1:3, b=["x","y","z"]))   # DataFrame table
```

Press **F1** inside any viewer for a full keyboard reference. Press **Esc** to exit.

### 2 — Collect a value from the user

```julia
using TermWin

TermWin.initsession()
w = newTwEntry(rootTwScreen, Float64; title="Enter a number: ", width=25)
activateTwObj(rootTwScreen)
TermWin.endsession()

println("You entered: ", w.value)
```

### 3 — Compose a multi-field data-entry form

```julia
using TermWin

TermWin.initsession()

result = @twlayout :vertical (form=true, title="New User") begin
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

---

## Basic input widgets

All widgets follow the same lifecycle:

```julia
TermWin.initsession()
w = newTwXxx(rootTwScreen, ...; kwargs...)
activateTwObj(rootTwScreen)   # blocks until user presses Enter or Esc
TermWin.endsession()
value = w.value               # nothing if user pressed Esc
```

### Text and numeric entry — `newTwEntry`

Supports any Julia `DataType`: `String`, `Int`, `Float64`, `Rational`, `Date`, `Bool`, etc.
Input is validated and converted to the requested type before being stored in `w.value`.

```julia
TermWin.initsession()
w = newTwEntry(rootTwScreen, String; title="Name: ", width=30)
activateTwObj(rootTwScreen)
TermWin.endsession()
println(w.value)   # String or nothing
```

Key options: `title`, `width`, `precision` (for floats), `titleLeft` (label on left vs top).

### Single selection — `newTwPopup`

```julia
TermWin.initsession()
w = newTwPopup(rootTwScreen, ["Alice","Bob","Carol"]; title="Pick one")
activateTwObj(rootTwScreen)
TermWin.endsession()
println(w.value)   # String or nothing
```

Key options: `title`, `maxheight`, `maxwidth`, `substrsearch` (live filter as you type),
`quickselect` (press a letter to jump), `allownew` (allow free-text entry not in the list).

### Multi-selection — `newTwMultiSelect`

```julia
TermWin.initsession()
w = newTwMultiSelect(rootTwScreen, ["read","write","exec"]; title="Permissions")
activateTwObj(rootTwScreen)
TermWin.endsession()
println(w.value)   # Array{String,1} or nothing
```

Key options: `selected` (pre-selected items), `orderable` (drag to reorder),
`substrsearch` (live filter).

### Date picker — `newTwCalendar`

```julia
using Dates
TermWin.initsession()
w = newTwCalendar(rootTwScreen, today())
activateTwObj(rootTwScreen)
TermWin.endsession()
println(w.value)   # Date or nothing
```

### Scrollable text viewer — `newTwViewer`

```julia
TermWin.initsession()
lines = ["Line $i: " * repeat("x", i) for i in 1:200]
newTwViewer(rootTwScreen, lines; title="Log output", height=0.8, width=0.9)
activateTwObj(rootTwScreen)
TermWin.endsession()
```

---

## Composable layouts

Arrange multiple widgets side-by-side or stacked without writing sizing logic by hand.
Children have their borders automatically stripped and rendered edge-to-edge inside
the layout canvas.

### `@twlayout` macro

```julia
@twlayout :vertical (title="Results") begin
    viewer(summary_text;  height=0.3, title="Summary")
    dftable(results_df;   height=0.7, title="Data")
end
```

Short names available inside `@twlayout`:

| Short name    | Constructor        |
|:--------------|:-------------------|
| `viewer`      | `newTwViewer`      |
| `dftable`     | `newTwDfTable`     |
| `entry`       | `newTwEntry`       |
| `popup`       | `newTwPopup`       |
| `multiselect` | `newTwMultiSelect` |
| `tree`        | `newTwTree`        |
| `calendar`    | `newTwCalendar`    |

Any other expression is passed through unchanged, so you can nest `vstack`/`hstack`
calls inside the block.

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

---

## Data-entry forms

Add `form=true` to any layout to collect a `Dict{Symbol,Any}` from the user.

```julia
TermWin.initsession()

form = @twlayout :vertical (form=true, title="Settings", height=0.6, width=0.5) begin
    entry(String; key=:host,    title="Host",    width=35)
    entry(Int;    key=:port,    title="Port",    width=10)
    popup(["dev","staging","prod"]; key=:env, title="Environment")
end

activateTwObj(rootTwScreen)
TermWin.endsession()

config = form.value   # Dict(:host=>..., :port=>..., :env=>...) or nothing
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

---

## Data exploration with `tshow`

`tshow` is the main entry point for interactive exploration. It wraps `initsession`,
widget construction, and `endsession` automatically and returns the widget, whose
`.value` and internal state you can inspect after the call.

```julia
using TermWin
tshow(any_julia_value)
```

### Expressions and code

```julia
tshow(:( f(x) = x*x + 2x + 1 ))
```

![expression](https://cloud.githubusercontent.com/assets/7191122/5458271/62ae80c0-8583-11e4-8ebb-a996d0d63f5e.png)

### Modules

```julia
tshow(TermWin)        # browse exported names
tshow(Base)
```

### Functions and methods

```julia
tshow(sort!)                     # searchable, sortable methods table
tshow(methods(sort!))            # same
tshow(methodswith(AbstractArray))
```

### DataFrames

```julia
using DataFrames
df = DataFrame(name=["Alice","Bob"], score=[85, 92])
tshow(df)
```

For larger DataFrames, `tshow` supports grouping, aggregation, and dynamic pivots:

```julia
tshow(df;
    colorder  = [:score, :name, "*"],
    pivots    = [:department, :region],
    initdepth = 2,
    sortorder = [(:score, :desc)],
    aggrHints = Dict{Any,Any}(
        :score => :( mean(:_) ),
    ),
)
```

More elaborate example:
![caschool](https://cloud.githubusercontent.com/assets/7191122/5457618/8f136f72-857e-11e4-8a27-5c4666f0386b.png)

**`tshow` keyword arguments** (most widgets):

| Argument | Type | Description |
|:---------|:-----|:------------|
| `title` | `String` | Window title |
| `height` | `Int` or `Float64` | Rows, or fraction `(0,1]` of screen |
| `width` | `Int` or `Float64` | Columns, or fraction `(0,1]` of screen |
| `posx` | `Int` or `Symbol` | Horizontal position: `:center`, `:left`, `:right`, `:staggered`, `:random` |
| `posy` | `Int` or `Symbol` | Vertical position: `:center`, `:top`, `:bottom`, `:staggered`, `:random` |

`tshow` returns the widget object. Call `tshow(widget)` again to re-display it with
its previous state (pivot selections, column order, etc.) preserved.

---

## DataFrame viewer reference

### Pivot and grouping options

| Option | Type | Description |
|:-------|:-----|:------------|
| `pivots` | `Array{Symbol}` | Columns to group by; determines the tree hierarchy |
| `initdepth` | `Int` | Number of pivot levels open at start (default 1) |
| `calcpivots` | `Dict{Symbol,CalcPivot}` | Dynamic computed pivot columns (see below) |

### Column display options

| Option | Type | Description |
|:-------|:-----|:------------|
| `colorder` | `Array` | Symbols, `Regex`, and `"*"` (remaining columns). Controls display order |
| `hidecols` | `Array` | Symbols and `Regex` — matched columns are hidden (overrides `colorder`) |
| `sortorder` | `Array` | `(Symbol, :asc/:desc)` pairs |
| `headerHints` | `Dict{Symbol,String}` | Alternate column header labels |
| `widthHints` | `Dict{Symbol,Int}` | Override default column widths |
| `formatHints` | `Dict{Any,FormatHints}` | Numeric/date display format per column or type |

### Aggregation

`aggrHints` accepts a `Dict{Any,Any}` keyed by column name (`Symbol`) or type.
Values are expressions where `:_` is replaced by the column being aggregated:

```julia
aggrHints = Dict{Any,Any}(
    :score  => :( mean(:_) ),
    :count  => :( sum(:_) ),
    :salary => :( mean(:_, weights(:headcount)) ),   # weighted mean
    String  => :( uniqvalue(:_) ),                   # fallback for all String cols
)
```

Built-in aggregation helpers: `uniqvalue` (value if all identical, else missing),
`unionall` (union of array-typed cells).

### Calculated pivots

`CalcPivot` creates a derived grouping column computed at runtime from the current subtree:

```julia
calcpivots = Dict{Symbol,Any}(
    :score_band => CalcPivot(:(discretize(:score, [60,70,80,90], rank=true)), :region),
    :top5       => CalcPivot(:(topnames(:name, :score, 5))),
)
```

`discretize(col, breaks; rank, compact, reverse, label, ...)` — bucket a numeric column.
`topnames(name_col, measure_col, n; others, dense, ...)` — top-N names by measure.

### Multiple views

```julia
views = [
    Dict{Symbol,Any}(:name => "By Score",  :pivots => [:score_band, :region]),
    Dict{Symbol,Any}(:name => "Top 5",     :pivots => [:top5]),
]
```

Switch views inside the DataFrame viewer with the **v** key.

---

## Keyboard reference

### Universal

| Key | Action |
|:----|:-------|
| F1 | Show widget help |
| Esc | Exit / cancel |
| Tab / Shift-Tab | Cycle focus between widgets |

### Layout canvas (inside `@twlayout` / `vstack` / `hstack`)

| Key | Action |
|:----|:-------|
| Ctrl-F4 | Toggle navigation mode (scroll the canvas) |
| Ctrl-arrows | Move focus in a spatial direction |
| Arrow keys | Focus movement (when not consumed by the focused widget) |
| Mouse click | Focus the nearest widget |

### Form mode

| Key | Action |
|:----|:-------|
| Enter | Validate field and advance to next |
| F10 | Submit form → `Dict{Symbol,Any}` |
| Esc | Cancel form → `nothing` |

### DataFrame viewer

| Key | Action |
|:----|:-------|
| Arrow keys / PgUp / PgDn | Navigate rows and columns |
| Enter | Expand / collapse pivot group |
| p | Edit pivot column order |
| v | Switch between saved views |
| s | Sort by current column |
| / | Search |
| F1 | Full keyboard reference |

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
    @twlayout :vertical (title=r.name) begin
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
    @twlayout :vertical (form=true, title="Configure") begin
        entry(String; key=:host, title="Host")
        entry(Int;    key=:port, title="Port")
    end
end

widget = tshow(UserConfig())
config = widget.value   # Dict or nothing
```

---

## Running the example scripts

The `test/` directory contains standalone demo scripts:

```
julia --project=. test/entrytest.jl       # numeric entry
julia --project=. test/popuptest.jl       # single-select popup
julia --project=. test/multiselect.jl     # multi-select
julia --project=. test/caltest.jl         # date picker
julia --project=. test/viewertest.jl      # text viewer
julia --project=. test/formtest.jl        # composable data-entry form
julia --project=. test/buildertest.jl     # @twlayout with DataFrame + viewer
julia --project=. test/dataframe.jl       # DataFrame pivot viewer
julia --project=. test/list.jl            # manual layout with newTwList
```
