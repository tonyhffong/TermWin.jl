# TermWin.jl

## Introduction
TermWin is a Julia based terminal UI toolkit optimized for
* data exploration - a capable tree/table viewer to help users quickly gain an understanding on
  complex tree structures (a package, a file directory, a julia expression AST, a heavily nested dictionary, etc.) 
  and dataframes.
* a modal interface. Show a widget, collect user input, return a value, continue in REPL or interact further with another widget.
  Use TermWin to efficiently identify what the user needs, and then get out of the way.
* Composing multi-panel layouts to suit your own data structure human interface needs.
* niceties on displaying julia code (pretty-print when viewing julia code) and shortcut to edit the underlying file in vim

TermWin is built on [Notcurses](https://github.com/dankamongmen/notcurses). It requires a 256-colour 
terminal. `xterm-256color` or iTerm2 on macOS are recommended.

TermWin is not a framework for standalone TUI app. For that, Tachikoma.jl is a better choice. Tachikoma is basically a
view-controller-model UI framework, and it handles continuous animation/refresh natively.

---

## Requirements

* NotCurses.jl
* 256-color terminal (e.g. iTerm2)

### NotCurses
Install the Julia package. It should install the notcurses. If it doesn't work you may install directly the native Notcurses library.

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

### Terminal Notes
**MacOS iTerm2 note**: Disable *Preferences → Profiles → Terminal → Modern parser for CSI codes*.
Map F1–F4 in *Preferences → Profiles → Keys → Key Bindings* to hex sequences
`0x1b 0x4f 0x50` through `0x1b 0x4f 0x53` so they are not swallowed by the terminal emulator.

---

## Quick start

### 1 — Explore anything with `tshow` (Read-only)

`tshow` accepts almost any Julia value and renders an interactive viewer:

```julia
using TermWin

tshow(42)                          # value viewer
tshow(:( f(x) = x^2 + 1 ) )        # expression tree — useful for understanding Julia's AST
tshow(TermWin)                     # module browser
tshow(sort!)                       # method table
tshow(DataFrame(a=1:3, b=["x","y","z"]))   # DataFrame table
tshow(DataFrame(a=1:3, b=["x","y","z"]), colspecs)   # editable table; colspecs::Vector{TwEditTableCol} (2nd arg matters)
tshow("./","path")                 # file browser (2nd argument "path" required)
tshow( code_snippet,"julia")       # show julia code with syntax coloring (2nd argument "julia" required, or coloring won't happen)
tshow( code_snippet,"julia:pathname.jl")  # show julia code with syntax coloring, and a shortcut to launch to vim
```

Press **F1** inside any viewer for a full keyboard reference. Press **Esc** to exit.

Note: later on, you will find that tshow is indispensable when compositing a UI. Read-only widgets can be readily shown by just tshow()'ing 
the thing.

### 2 — Collect a value from the user

```julia
using TermWin

TermWin.initsession()
w = newTwEntry(rootTwScreen, Float64; title="Enter a number: ", width=25)
activateTwObj(rootTwScreen)
TermWin.endsession()

println("You entered: ", w.value)
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

### Text, Date and numeric entry — `newTwEntry`

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

More options:
- `enumvalues=["A","B",…]` — turns the field into a popup picker (type or press `?`).
- `allow_calendar=true` — press `?` to open the calendar even in a `String` field; the
  picked date is written in as text, so the field can hold a real date **or** free text
  (a relative date like `T+2`, or an empty/"null" date). `Date`-typed fields always
  support `?`.
- `choices=["…"]` — press `?` for a preset popup that still lets you type your own value.
- `hintfn = buffer -> String` — a dimmed live hint line under the field, recomputed as
  you type (e.g. echoing how your text parses).

In-field editing: `←/→` move the cursor, `Ctrl-A`/`Ctrl-E` jump to start/end,
`Ctrl-K` clears, `Ctrl-R` toggles insert/overwrite.

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

The calendar highlights today's date (bold + underline) and the current year and month
header (bold + underline).  Non-business days are shown in red using
[BusinessDays.jl](https://github.com/felipenoris/BusinessDays.jl).
Press **Alt-C** to pick a different holiday calendar (e.g. `USSettlement`, `TARGET`,
`UKSettlement`); the selected calendar is shown in the header.

**Calendar key bindings:**

| Key | Action |
|:----|:-------|
| Arrow keys | Move cursor (ncal-style: ←/→ = week, ↑/↓ = day) |
| `.` | Jump to today |
| `a` / `e` | Start / end of current month |
| `A` / `E` | Jan 1 / Dec 31 |
| `d` / `D` | +1 / −1 day |
| `w` / `W` | +1 / −1 week |
| `m` / `M` | +1 / −1 month |
| `q` / `Q` | +1 / −1 quarter |
| `y` / PgDn | +1 year |
| `Y` / PgUp | −1 year |
| Alt-C | Change holiday calendar |
| Enter | Confirm selection |
| Esc | Cancel |

Pass `optional=true` to make the calendar **clearable**: `Ctrl-K` then accepts a
result of `missing` — an explicit "no date", distinct from `Enter` (a `Date`) and
`Esc` (`nothing`). Useful for a form field that may legitimately be left blank.

### Scrollable text viewer — `newTwViewer`

```julia
TermWin.initsession()
lines = ["Line $i: " * repeat("x", i) for i in 1:200]
newTwViewer(rootTwScreen, lines; title="Log output", height=0.8, width=0.9)
activateTwObj(rootTwScreen)
TermWin.endsession()
```

### File browser — `newTwFileBrowser`

Browse a directory tree with a four-column left pane (name, type, size, modified time)
and a live preview pane for text files on the right.

```julia
TermWin.initsession()
w = newTwFileBrowser(rootTwScreen, "/path/to/dir"; title="Browse")
activateTwObj(rootTwScreen)
TermWin.endsession()
println(w.value)   # selected file path, or nothing
```

Or trigger from `tshow` by passing `"path"` as the second argument:

```julia
tshow("./src", "path")
```

Preview is shown automatically for `.jl`, `.txt`, `.md`, `.log`, `.toml`, `.csv`,
`.json`, `.yaml`, `.yml`, `.xml`, `.cfg`, `.ini`, `.conf`, `.sh`, `.py`, `.c`, `.h`,
`.rs`, `.go`, and any file named `README`.

**File browser key bindings:**

| Key | Action |
|:----|:-------|
| Arrow keys / PgUp / PgDn | Navigate |
| Space / Enter | Toggle expand (directory) / select (file) |
| Ctrl-Left | Jump to parent directory |
| Ctrl-Up / Ctrl-Down | Jump to previous / next sibling |
| Ctrl-PgUp / Ctrl-PgDn | Scroll preview pane up / down a page |
| `+` / `-` | Expand / collapse one level |
| `_` | Collapse all |
| `.` | Toggle hidden files |
| `s` | Cycle sort order (name → size → mtime) |
| `/` | Search |
| `n` / `p` | Next / previous search match |
| F6 | Open file in popup viewer |
| Shift-F6 | Show file stat details |
| F1 | Full key reference |
| Esc | Exit |

Key constructor options: `showHidden` (default `false`), `previewSplit` (fraction of
width for the tree pane, default `0.5`).

---

> **For developers** — to compose multi-panel layouts, build data-entry forms, or author
> custom widgets that plug into the `@twlayout` / `vstack` / `hstack` DSL, see
> [README_PKG_DEV.md](README_PKG_DEV.md).

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
tshow(methods(AbstractArray))
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
its previous state (pivot selections, column order, etc.) preserved. For a
DataFrame table, `table_config(widget)` extracts that layout as a serializable
value you can store and later replay with `tshow(df; config=cfg)` — see
[Saving and restoring a layout](#saving-and-restoring-a-layout).

---

## Tree viewer keyboard reference

The tree viewer (`tshow` on any non-DataFrame value) supports the following navigation:

| Key | Action |
|:----|:-------|
| Arrow keys / PgUp / PgDn | Standard navigation |
| Space / Enter | Toggle node expansion |
| Ctrl-Left | Jump to parent node |
| Ctrl-Up / Ctrl-Down | Jump to previous / next sibling at the same level |
| Ctrl-Right | Jump to end of line |
| Home / End | Jump to first / last row |
| `+` / `-` | Expand / collapse one level |
| `_` | Collapse all |
| `/` | Search dialog |
| `n` / `p` | Next / previous search match |
| F5 | Show `string(value)` in popup viewer (Julia syntax-highlighted for `Expr`) |
| F6 | Open value in popup viewer |
| Shift-F6 | Open type in popup viewer |
| F7 | Save current node's value to a `Main` global variable (prompts for name) |
| `m` | (Module only) toggle exported vs all names |

### Saving a node value to a Julia variable

Press **F7** on any node to capture its value into a `Main` global variable at runtime.
A small entry popup appears pre-filled with the node's key name; edit it if needed and
press Enter.  The value is assigned immediately, so it is available in the REPL as soon
as the tree viewer returns:

```julia
tshow(my_model)           # navigate to an interesting sub-value and press F7
# → popup: "Store as global: weights"
# → press Enter

my_model                  # still intact; only the captured value was copied
weights                   # now available in Main
```

**F7 works in both the read-only tree viewer (`tshow`) and the editable dict tree
(`newTwDictTree`).**  The value saved is always the *current* value at the node's path
(reflecting any edits made in dict-tree mode before pressing F7).

---

## DataFrame viewer reference

### Pivot and grouping options

| Option | Type | Description |
|:-------|:-----|:------------|
| `pivots` | `Array{Symbol}` | Columns to group by; determines the tree hierarchy |
| `initdepth` | `Int` | Number of pivot levels open at start (default 1) |
| `calcpivots` | `Dict{Symbol,Any}` | Dynamic computed pivot columns (see below) |

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

`aggrHints` accepts a `Dict{Any,Any}` keyed by column name (`Symbol`) or type. A
value is an `Expr` (or `Symbol`/`Function`) where `:_` stands for the column being
aggregated. `Expr` specs are *trusted* — they may call module-qualified functions
that resolve against your loaded packages:

```julia
using StatsBase   # for the weighted mean below
aggrHints = Dict{Any,Any}(
    :score  => :( mean(:_) ),                                        # mean (Statistics)
    :count  => :( sum(:_) ),
    :salary => :( StatsBase.mean(:_, StatsBase.Weights(:headcount)) ),  # weighted mean
    String  => :( uniqvalue(:_) ),                                   # fallback for all String cols
)
```

Built-in aggregation helpers: `uniqvalue` (value if all identical, else missing),
`unionall` (union of array-typed cells).

You can also override a column's aggregation **interactively** inside the viewer
with the **a** key, which opens a spec entry (type-aware templates, live parse
checking, Tab completion). There `_` is the column and sibling columns are named
directly, e.g. `sum(_ * wt) / sum(wt)`. A blank spec reverts to the default.

### Calculated pivots

`calcpivots` adds derived grouping columns computed at runtime. It is a
`Dict{Symbol,Any}` mapping a name to a dimension spec: a `dimspec(...)` (wrapping a
trusted `Expr`, optionally with `by=`/`kind=`), a bare `Expr`, an untrusted
`dim"..."` string, or a `Function`. (`dimspec`, `discretize`, `topnames`, and
`@dim_str` are re-exported by `TermWin`.)

```julia
calcpivots = Dict{Symbol,Any}(
    # per-group buckets: aggregate :score per :region, then classify the groups → a pivot
    :score_band  => dimspec(:( discretize(:score, [60,70,80,90], rank=true) ); by=:region, kind=:pivot),
    # row-level quantile buckets (no `by`) → a window dimension
    :score_qtile => dimspec(:( discretize(:score, ngroups=4) )),
    # topnames is a classifier verb — the name column is auto-inferred as the group key
    :top5        => dimspec(:( topnames(:name, :score, 5) )),
)
```

`discretize(col, breaks; rank, compact, reverse, label, ngroups, ...)` — bucket a
numeric column. `topnames(name_col, measure_col, n; ...)` — top-N names by measure.

Trusted `Expr` specs use `:col` symbols and may call module-qualified functions;
untrusted `dim"..."` strings use bare-identifier columns and are eval-free (safe to
accept from end users).

You can also **define** calculated dimensions interactively with the **P** key,
which opens a small editor table of them — the `name` and the `spec` (edited in a
popup with type-aware templates and live parse-checking). `Ctrl-N` adds a
dimension, `Ctrl-D` deletes one, and `F10` applies. Dimensions created here go
through the untrusted safe grammar; ones defined as trusted `Expr`/`Function` at
construction are shown **read-only** (tinted, and the spec popup won't open for
them). `P` only *defines* dimensions — to apply and order them as grouping levels,
use the **p** pivot popup (which lists calculated dimensions alongside real
columns).

### Multiple views

```julia
views = [
    Dict{Symbol,Any}(:name => "By Score",  :pivots => [:score_band, :region]),
    Dict{Symbol,Any}(:name => "Top 5",     :pivots => [:top5]),
]
```

Switch views inside the DataFrame viewer with the **v** key.

### Saving and restoring a layout

While viewing a table you can build up a layout interactively — reorder pivots
(**p**), define a new calculated dimension (**P**), and override the current
column's aggregation (**a**). `table_config` captures that layout as a
serializable value, and the `config=` keyword replays it into a fresh table:

```julia
w   = tshow(df)                            # explore: pivot, define dims (P), override aggrs (a), then Esc
cfg = table_config(w; name = "by-region")  # capture the layout (tshow returns the widget)

d   = Dict(cfg)                            # → Dict{String,Any}; persist however you like (TOML / JSON / DB)
# ... next session ...
tshow(df2; config = TableConfig(d))        # replay the layout onto another DataFrame
```

`TableConfig` records the applied pivots, visible columns and their order, column
widths, user-defined calculated dimensions, and per-column aggregation overrides.
It is backend-neutral: `Dict(cfg)` gives a plain `Dict` any serializer can write,
and `TableConfig(dict)` reconstructs it. TermWin ships no file/database layer —
where and how you store the `Dict` is your choice.

Two properties make a stored config safe to share or hand-edit:

- **Schema-resilient** — a config applied to a DataFrame that is missing some of
  its columns just drops the absent references instead of erroring, so one layout
  works across related frames.
- **No code execution** — calculated-dimension and aggregation specs are stored
  as their source text and re-parsed on load through the *untrusted* safe grammar
  (no `eval`). A config can declare aggregations and dimensions but can never run
  arbitrary code.

---

## Universal keyboard reference

### All widgets

| Key | Action |
|:----|:-------|
| F1 | Show widget help |
| Esc | Exit / cancel |
| Tab / Shift-Tab | Cycle focus between widgets |

### Mouse

| Action | Effect |
|:-------|:-------|
| Click inside a widget | Focus that widget; tables, trees and lists also move the cursor to the clicked row |
| Scroll wheel | Scroll the focused widget up / down |
| **Drag a popup's top border** | **Reposition a floating window** — press and hold the left button on the title-bar row (the box's top edge) of a popup / overlay (e.g. the F1 help viewer, `newTwPopup`, `newTwViewer`), then drag and release |
| **Drag a popup's lower corner** | **Resize a floating window** — press and hold the left button near the bottom-left or bottom-right corner, then drag and release. The opposite edges (top, and the far side for that corner) stay fixed |

Window dragging applies to free-floating overlays — any widget shown directly on
the screen with its own border (`box=true`). The drag grab zone is **only the top
border row**; clicking elsewhere in the body selects content as usual. Full-screen
layout panels (the children of a `@twlayout` / `vstack` / `hstack`) are tiled rather
than floating and are not draggable — resize them with the layout's sizing hints
(`:content` / `:fill` / `Flex`) instead.

Window resizing uses the same `box=true` floating-overlay grab as the title-bar
drag, but at the two **lower** corners instead of the top edge. The grab zone has
some tolerance so you don't have to hit the exact corner cell: **2 characters
horizontally and 1 character vertically**. Dragging the bottom-right corner grows
or shrinks height/width with the top-left corner fixed; dragging the bottom-left
corner does the same while keeping the top-right corner fixed (so the window's
right edge stays put as its left edge and width track the cursor). A window can't
be resized smaller than **3 rows tall** or **15 columns wide**.

> Mouse reporting must reach the application. TermWin enables all mouse events at
> session start, but some terminals or multiplexers (e.g. tmux, or a host terminal
> that claims drag for its own text selection) intercept the drag first — pass mouse
> reporting through, or hold the terminal's "bypass" modifier, if a drag does not move
> the window.

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
| Enter / Space | Expand / collapse pivot group |
| `+` / `-` | Expand / collapse all |
| p | Edit pivot column order |
| P | Define calculated dimensions (add / edit spec / delete); apply them via p |
| a | Override the current column's aggregation (spec entry) |
| c | Choose visible columns and their order |
| `[` / `]` | Narrow / widen the current column |
| v | Switch between saved views |
| / | Search |
| Ctrl-Y | Export to CSV / Excel |
| F1 | Full keyboard reference |

---

## Running the example scripts

The `test/` directory contains standalone demo scripts:

```
julia --project=. test/entry_num_tick.jl        # numeric entry with shift-up/down to modify by tick
julia --project=. test/entrystring.jl           # string entry
julia --project=. test/entrydate.jl             # date entry
julia --project=. test/popup_simpleselect.jl    # single-select popup
julia --project=. test/popup_fuzzy.jl           # popup with substring search filter
julia --project=. test/popup_quickselect.jl     # popup with quick-jump by letter
julia --project=. test/popup_allownew.jl        # popup with free-text entry
julia --project=. test/multiselect.jl           # multi-select list
julia --project=. test/caltest.jl               # date picker with holiday calendar
julia --project=. test/textviewertest.jl        # scrollable text viewer
julia --project=. test/filebrowser.jl           # file browser (tshow "path" 2nd arg)
julia --project=. test/formlayout_test.jl       # composable data-entry form
julia --project=. test/formlayout_test2.jl      # form with divider labels
julia --project=. test/buildertest.jl           # @twlayout with DataFrame + viewer
julia --project=. test/dataframe.jl             # DataFrame pivot viewer
julia --project=. test/spec_entry.jl            # dim/aggr spec entry: live parse, templates, Tab completion
julia --project=. test/entry_listofthings.jl    # manual layout with newTwList
julia --project=. test/keystrokes.jl            # interactive key/mouse/unicode tester
```
