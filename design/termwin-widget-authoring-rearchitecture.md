# TermWin — Reducing Friction & Abstraction Leakage for Widget Authors

> A rearchitecture proposal, now substantially implemented. Companion to
> `codebase-review.md`. The goal: make writing a *new* TermWin widget a matter of
> declaring a data struct, a `draw`, and a binding table — with footer, help, key
> dispatch, scroll behavior, and colors all **derived** rather than re-typed by hand.

---

## Context — why this change

`codebase-review.md` states the throughline: *today the unit of composition is the
**widget**; the modern move is to make **bindings**, **themes**, and **state** the units
of composition and let widgets be thin views over them.* This document turns that into a
concrete, staged plan.

The friction was real and measurable (pre-rearchitecture):

| Leak | Evidence in `src/` |
|------|--------------------|
| `inject` is a hand-routed key ladder per widget | **16** `inject` methods, **~276** `elseif token ==` branches (`twdicttree.jl`=39, `twdftable.jl`=29, `twfilebrowser.jl`=26, `twtree.jl`=24, `twedittable.jl`=23) |
| Help/footer text drifts from the ladder | **~18** module-level `default*HelpText` / `default*BottomText` string constants, hand-maintained next to the ladder they describe |
| Viewport math is copy-pasted | `currentTop`/`currentLeft` clamp logic (`checkTop`, `moveby`) reimplemented across **9** files; the framework already exposes a `clamp_scroll!(o)` hook (`twobj.jl:390`) but each widget rolls its own |
| Colors are magic integers | `COLOR_PAIR(15)`=focused, `(30)`=unfocused, `(3)`=header, `(13)`=divider, `(1)`=red — scattered as bare numbers across widgets |
| Row payloads are anonymous tuples | `(name,typestr,valuestr,stack,expandhint,skiplines)` in trees, a 9-tuple in the file browser, `Any[lc, c, i, score]` in popup — `row[2]`/`row[4]` mean different things in different files |
| The `inject` return contract is undocumented | `:got_it`/`:pass`/`:exit_ok`/`:exit_nothing` learned only from one comment in `twobj.jl`; not next to `TwObj` |
| Editing fractured across three widgets | `twentry`/`twedittable`/`twdicttree` each re-implemented the same inline text editor (state, cursor math, insertchar, type rules, render) |

Intended outcome: a new widget = **a data struct + a `draw` + a binding table**, with
everything else derived. Existing widgets keep working throughout (staged migration).

---

## Vision — the four layers

Four thin, opt-in layers under the existing `TwObj{T,S}` dispatch model. Nothing is
removed; each layer has a backward-compatible default so the 16 current widgets compile
unchanged and migrate one at a time.

```
            ┌────────────────────────────────────────────┐
  VIEW      │  draw(o::TwObj{T})    — unchanged dispatch   │  ✅ unchanged
            ├────────────────────────────────────────────┤
  BINDINGS  │  bindings(o) :: Vector{Binding}             │  ✅ infra + calendar/viewer; ⚠️ full sweep pending
            ├────────────────────────────────────────────┤
  STATE     │  ScrollState, Result{T}, Observable{T}      │  ✅ all three; ScrollState in 4 widgets
            ├────────────────────────────────────────────┤
  THEME     │  theme(:selection_focused) → TwAttr         │  ✅ all 11 widgets swept
            └────────────────────────────────────────────┘
```

---

## Implementation Status

| Layer / Feature | Status | Notes |
|-----------------|--------|-------|
| **A1.** `InjectResult` enum | ✅ Complete | Shim fully retired; all 16 widgets return the enum |
| **A2.** `Result{T}` caller contract | ✅ Complete | `src/contracts.jl`; `Ok`/`Cancelled`/`Failed`/`unwrap`/`isok` |
| **A3.** `TreeRow`/`FileRow` + `tree_nav` | ✅ Complete | `src/rows.jl`; all 3 tree widgets migrated |
| **B1.** Theme tokens | ✅ Complete | 11 widgets swept; `src/theme.jl` |
| **B2.** Swappable themes + accessibility | ⚠️ Partial | `high_contrast_theme()` builder exists; no UI entry point yet |
| **C.** `ScrollState` + `clamp_scroll!` | ✅ Complete | `src/scroll.jl`; popup/multiselect/edittable/tree wired |
| **D.** `Binding`/`bindings()` infrastructure | ✅ Complete | `src/bindings.jl`; calendar + viewer fully converted |
| **D.** Full bindings sweep (remaining widgets) | ⚠️ 2/16 done | popup/multiselect/twtree/twdicttree/twfilebrowser/twedittable/twdftable remain |
| **E.** `Observable{T}` | ✅ Infrastructure | `src/observable.jl`; not yet wired into cross-widget reactivity |
| **F.** `InlineEditor` unification (review #9) | ✅ Complete | `src/editor.jl`; entry/edittable/dicttree all use it; shim-free |
| **G.** Command palette (Ctrl-P) | ✅ Complete | `_palette_open!` in `src/twscreen.jl`; fuzzy-searches `active_bindings(focused)`; result propagated back to screen loop |
| **H.** Scratchpad (F7 pin, Shift-F2 browse) | ✅ Complete | `src/scratchpad.jl`; `pin!`/`export_to_main!`; exit prompt when non-empty |
| **I.** Undo/redo + clipboard history | ✅ Complete | `src/history.jl`; 20-step ring; twedittable + twdicttree; Alt-Y clipboard picker |
| **J.** Reactive status bar widget | ✅ Complete | `src/twstatusbar.jl`; backed by `Observable{String}` + `subscribe!` in `twobj.jl` |
| Rebindable keys | 🔲 Not started | Depends on full bindings sweep |
| Ship `:high_contrast` theme interactively | ⚠️ Partial | Builder exists (`high_contrast_theme()`); no runtime UI toggle yet |

---

## Part A — Contracts & typed rows ✅ IMPLEMENTED

### A1. Make the `inject` return contract a type, documented at `TwObj`

**What was built:** `src/contracts.jl` — `@enum InjectResult Handled Ignored Accept Cancel`.
During migration a `Symbol→InjectResult` normalizer shim in `activateTwObj` let converted
and unconverted widgets coexist. The shim is now **fully retired**: all 16 widgets return
the enum directly; `inject_symbol` is deleted from `contracts.jl`.

```julia
"""
Outcome of `inject(o, token)`. The screen/host loop dispatches on this:
- `Handled`  — consumed; redraw if needed, keep focus (was `:got_it`)
- `Ignored`  — not ours; host may route elsewhere / bubble up (was `:pass`)
- `Accept`   — finish with `o.value` as the result          (was `:exit_ok`)
- `Cancel`   — finish with no result                        (was `:exit_nothing`)
"""
@enum InjectResult Handled Ignored Accept Cancel
```

Note: `twviewer.jl`'s `_viewer_select!` listener compares the *listener's* return value
(`:exit_ok`/`:exit_nothing`) — that is an **external listener contract**, not an inject
result. It remains as symbols and is translated to `InjectResult` at the boundary.

### A2. A single return contract for *callers*: `Result{T}`

**What was built:** `src/contracts.jl` — `Ok{T}`, `Cancelled`, `Failed`, `unwrap`, `isok`.

```julia
abstract type Result{T} end
struct Ok{T}    <: Result{T}; value::T end
struct Cancelled <: Result{Nothing} end
struct Failed   <: Result{Nothing}; err::Exception end

unwrap(r::Ok)       = r.value
unwrap(::Cancelled) = nothing             # backward-compatible default
```

`activateTwObj` keeps returning `o.value`/`nothing` by default (no breakage); `Result{T}`
is ready for new code and future callers to opt into.

### A3. Replace anonymous row tuples with named structs

**What was built:** `src/rows.jl` — `AbstractRow`, `TreeRow`, `FileRow`, `parent_prefix`,
`depth`, `tree_nav`.

**Key correction from design:** `skiplines` is `Vector{Int}` (not `Int`) to match the
actual codebase usage (a list of source-line gaps for Expr tree rendering).

```julia
abstract type AbstractRow end

struct TreeRow <: AbstractRow
    name::String
    typestr::String
    valuestr::String
    stack::Vector{Any}            # path from root; depth == length(stack)
    expandhint::Symbol            # :single | :open | :close
    skiplines::Vector{Int}        # source-line gaps (Expr rendering)
end
# FileRow adds typecol/sizestr/mtimestr/abspath/isdir
```

The Ctrl-Left/Up/Down sibling-navigation logic (was duplicated identically in `twtree.jl`,
`twdicttree.jl`, `twfilebrowser.jl`) now lives in `tree_nav(rows, cursor, dir)`. All three
tree widgets share it.

**Bug found during migration:** the initial `tree_nav` had an early-return guard
`isempty(target) && return (Int(cursor), false)` that blocked navigation to depth-0 root
rows. Fixed in `rows.jl` and caught by the headless test.

---

## Part B — Theme tokens ✅ IMPLEMENTED

### B1. A semantic token table over `COLOR_PAIR`

**What was built:** `src/theme.jl` — `Theme`, `theme(:sym)`, `set_theme!`, `refresh_theme!`,
`DEFAULT_THEME`, `high_contrast_theme()`, `current_theme::Ref{Theme}`.

`refresh_theme!()` is called in `initsession()` after `color_channel_table` is populated
(the `TwAttr` values depend on the physical palette being initialized first).

```julia
struct Theme
    tokens::Dict{Symbol,TwAttr}
end

const DEFAULT_THEME = Theme(Dict(
    :selection_focused   => COLOR_PAIR(15),
    :selection_unfocused => COLOR_PAIR(30),
    :header              => COLOR_PAIR(3),
    :divider             => COLOR_PAIR(13),
    :negative            => COLOR_PAIR(1),
    :emphasis            => A_BOLD | A_UNDERLINE,
    :focus_indicator     => '▶',
))

theme(sym::Symbol) = current_theme[].tokens[sym]
```

**Sweep completed:** `COLOR_PAIR(o.hasFocus ? 15 : 30)` → `theme(:selection_focused/:selection_unfocused)` across 11 widgets (twtree/twdicttree/twfilebrowser/twviewer/twcalendar/twcalendar2/twdftable/twpopup/twmultiselect + entry-field in twentry/twedittable). Byte-identical under the default theme; now swappable.

**Intentionally left as raw `COLOR_PAIR`:** `twprogress` fill `COLOR_PAIR(15)`;
`twedittable:~516` row-highlight uses a distinct `30/13` scheme (not 15/30);
`COLOR_PAIR(12)` incomplete-edit color (no token yet).

### B2. Swappable themes + accessibility

`high_contrast_theme()` builder shipped in `src/theme.jl`. The theme infrastructure
(`set_theme!` → `refresh_theme!`) is in place. **Not yet done:** an interactive UI entry
point (e.g. a session option or Ctrl-T picker) to switch at runtime. `:color_blind_safe`
theme not yet defined. Shipping these is a Stage 4 item.

---

## Part C — Scroll / viewport helper ✅ IMPLEMENTED

### C1. One `ScrollState`, parametrized by the numbers that matter

**What was built:** `src/scroll.jl` — `ScrollState`, `clamp_view!`, `move_cursor!`,
`page!`, `scroll_left!`, `visible`.

```julia
mutable struct ScrollState
    top::Int        # first visible row (1-based)
    left::Int       # first visible col
    cursor::Int     # selected row
end

function clamp_view!(s::ScrollState, n::Int, viewport::Int)
    s.cursor = clamp(s.cursor, 1, max(1, n))
    s.top    = clamp(s.top, max(1, s.cursor - viewport + 1), s.cursor)
    s.top    = clamp(s.top, 1, max(1, n - viewport + 1))
    s
end

move_cursor!(s, n, total, viewport) = (s.cursor += n; clamp_view!(s, total, viewport))
page!(s, dir, total, viewport)      = move_cursor!(s, dir*viewport, total, viewport)
```

### C2. Wire it into the existing `clamp_scroll!` hook

**What was built:** `twpopup`, `twmultiselect`, and `twedittable` each implement a
`clamp_scroll!(o::TwObj{T})` override that delegates to `clamp_view!`. They now re-clamp
on resize for free via the `twobj.jl` lifecycle hooks (previously popup/multiselect had no
resize re-clamp at all).

**twviewer exception:** its scroll is dual-mode (cursor-tracking `trackLine` vs. pure
top-scroll). `clamp_view!` is cursor-centric and doesn't model both modes. `twviewer` keeps
its own `currentTop`/`currentLine`/`currentLeft` fields; only its keymap was converted to
the `bindings()` table.

**twdftable note:** already had a complete `clamp_scroll!` at ~line 1604 before the
rearchitecture. Nothing to add there.

---

## Part D — Bindings as data ⚠️ INFRASTRUCTURE DONE — full widget sweep pending

**What was built:** `src/bindings.jl` — `Binding` (with `keys::Vector{Any}` — accepts
`Symbol` or `String` tokens), `bindings(o)` default returning `Binding[]`,
`active_bindings`, `footer`, `helptext_from_bindings`, `inject_via_table`, `keylabel`.

**Key correction from design:** `Binding.keys` is `Vector{Any}` not `Vector{Symbol}`.
Letter-key commands (e.g. `"d"`, `"."` in calendar) arrive as `String` tokens from
`readtoken`; the field must accept both.

**Reference conversions done:**
- `twcalendar.jl` — retired `defaultCalendarHelpText` + `helpText` field; `inject` is now a
  thin `inject_via_table` wrapper + host-specific picker calls; `helptext` → `helptext_from_bindings`.
- `twviewer.jl` — retired `defaultViewerHelpText` + `helpText` field; nav helpers extracted
  to module-level; same thin-wrapper pattern.

**Remaining widgets not yet on bindings:** `twpopup`, `twmultiselect`, `twtree`,
`twdicttree`, `twfilebrowser`, `twedittable`, `twdftable`, `twprogress`, `twentry` (entry
uses `editor_handle` instead; a binding table would be redundant), `twimage`.

The table is the foundation for the **command palette (Ctrl-P)** (now implemented as
**G** above) and future **rebindable keys** (depends on full sweep completion).

```julia
struct Binding
    keys::Vector{Any}          # e.g. [:F7], [:ctrl_n], ["d"]
    label::String              # "Save to Main"  → footer + help
    scope::Symbol              # :global | :tree_leaf | :edittable_cell | :form
    when::Function             # o -> Bool   (context guard; default true)
    action::Function           # o -> InjectResult
end

bindings(::TwObj{T}) where T = Binding[]          # default: none

footer(o)    = join(("$(keylabel(b)):$(b.label)" for b in active_bindings(bindings(o), o)), "  ")
helptext(o)  = helptext_from_bindings(bindings(o), o)
function inject_via_table(o, token)
    for b in bindings(o)
        if token in b.keys && b.when(o)
            return b.action(o)
        end
    end
    return Ignored
end
```

---

## Part F — InlineEditor unification ✅ IMPLEMENTED *(added during rearchitecture)*

This work was identified in `codebase-review.md` item #9 and fully executed.

**What was built:** `src/editor.jl` — `InlineEditor` (window-free struct), plus pure
functions `editor_load!`, `editor_checkcursor!`, `editor_insert!`, `editor_handle`,
`editor_commit`, `editor_set_buffer!`, `editor_render`, `editor_tick!`, and the
window-touching `draw_editor!`.

`evalNFormat`/`myNumFormat` and the date-format regex table moved from `twentry.jl` into
`editor.jl` as the raw-param `_evalNFormat`/`_myNumFormat`; `twentry` retains thin shims so
existing callers at `edittable`/`dicttree` resolve without change.

**`editor_handle` return signals** (not `InjectResult` — the host maps these):
`:handled`, `:rejected`, `:at_left_edge`, `:at_right_edge`, `:open_calendar`, `:open_enum`,
`:ignored`.

**`draw_editor!`** accepts an `incomplete_priority::Bool = false` kwarg — dict tree shows
the incomplete color even while focused (unlike entry/edittable).

**Public API preservation:** `TwEntryData`'s `inputText`/`cursorPos`/`tickSize`/etc. are a
public surface (20+ call sites in popup/multiselect searchboxes and tree helper entries).
These are preserved via `Base.getproperty`/`setproperty!` forwarding on `TwEntryData`
(the `_ENTRY_EDITOR_FIELDS` map), so no callers changed.

**Minor behavior changes (now uniform across all three hosts):**
- Invalid numeric keystrokes (duplicate `e`, misplaced sign, letter in number field) now
  beep+consume everywhere (was silent `:got_it`/`:pass` in entry; beep only in edittable).
- Dict tree `ctrl_r` now toggles overwrite mode (was a no-op).

**Test coverage:** `test/editor_unit.jl` (~110 asserts) — all 6 value types, all
`editor_handle` type rules, all 3 `editor_render` branches, 13-case `evalNFormat` parity
vs. the old `TwEntryData` path, per-host edit→commit flows.

---

## Part E — Reactive state 🔲 INFRASTRUCTURE ONLY

**What was built:** `src/observable.jl` — `Observable{T}`, `set!`, `on`, `off`.

```julia
mutable struct Observable{T}; value::T; subs::Vector{Function}; end
set!(o::Observable, v) = (o.value = v; foreach(f->f(v), o.subs); v)
on(f, o::Observable)   = (push!(o.subs, f); f)
```

`current_theme` in `theme.jl` is a `Ref{Theme}` (not `Observable{Theme}`) — swapping the
theme does not yet automatically redraw subscribers. Wiring `Observable` into cross-widget
reactivity (e.g. a status bar subscribing to `selection`) is a Stage 4 item.

---

## How the layers compose — a "hello widget" after the rearchitecture

The acceptance test: a brand-new scrollable list widget, end to end, with **zero**
hand-written footer, help, color integer, or clamp math.

```julia
mutable struct TwTagsData; rows::Vector{TreeRow}; scroll::ScrollState; end

draw(o::TwObj{TwTagsData}) = draw_rows(o, o.data.rows, o.data.scroll;
        focused = theme(:selection_focused), normal = theme(:divider))

clamp_scroll!(o::TwObj{TwTagsData}) =
        clamp_view!(o.data.scroll, length(o.data.rows), viewport(o))

bindings(o::TwObj{TwTagsData}) = [
    Binding([:up],    "up",     :global, _->true,
            o->(move_cursor!(o.data.scroll,-1,length(o.data.rows),viewport(o)); Handled)),
    Binding([:down],  "down",   :global, _->true,
            o->(move_cursor!(o.data.scroll, 1,length(o.data.rows),viewport(o)); Handled)),
    Binding([:enter], "select", :global, _->true,
            o->(o.value = current(o); Accept)),
]
```

Footer (`up  down  select`), F1 help, and dispatch all derive from those three lines.

---

## Migration path (staged, non-breaking)

1. **Land the primitives** ✅ — `InjectResult`/shim, `Result{T}`, `ScrollState`/`clamp_view!`,
   `Theme`/`theme()`, `AbstractRow`+`TreeRow`/`FileRow`, `Binding`/`bindings`/generated
   footer+help, `Observable`. All additive; all with backward-compatible defaults.
2. **Convert one reference widget of each kind** ✅ — `twpopup.jl` (list + scroll + theme),
   `twtree.jl` (typed rows + shared `tree_nav`), `twcalendar.jl` (bindings table). Kept
   `twentry.jl` separate — it uses `editor_handle` rather than a binding table.
3. **Sweep the remaining widgets** ✅ (mostly) — `twdicttree`/`twfilebrowser`/`twmultiselect`
   (typed rows + scroll + theme); `twviewer` (bindings table); `twedittable`/`twdftable`
   (theme tokens + `clamp_scroll!`); `InlineEditor` unification across entry/edittable/dicttree;
   `Symbol→InjectResult` shim retired across all 16 widgets.
   **Still pending:** bindings table for popup/multiselect/twtree/twdicttree/twfilebrowser/
   twedittable/twdftable (inject ladders still hand-written; footer/help still hand-maintained).
4. **Build on the spine** ⚠️ — command palette (Ctrl-P) ✅, scratchpad ✅, undo/redo ✅,
   reactive status bar ✅ are all delivered. Still open: rebindable keys (depends on full
   bindings sweep); interactive high-contrast theme toggle; wiring `Observable` into
   cross-widget selection/cursor reactivity; full bindings sweep for remaining 14 widgets.

---

## Representative files (where each layer landed)

- `src/contracts.jl` — `InjectResult` enum + `Result{T}` + `unwrap`/`isok`.
- `src/theme.jl` — `Theme`, `DEFAULT_THEME`, `high_contrast_theme()`, `theme()`,
  `set_theme!`, `refresh_theme!`, `current_theme`.
- `src/scroll.jl` — `ScrollState`, `clamp_view!`, `move_cursor!`, `page!`, `scroll_left!`, `visible`.
- `src/rows.jl` — `AbstractRow`, `TreeRow`, `FileRow`, `parent_prefix`, `depth`, `tree_nav`.
- `src/observable.jl` — `Observable{T}`, `set!`, `on`, `off`.
- `src/bindings.jl` — `Binding`, `bindings()` default, `active_bindings`, `footer`,
  `helptext_from_bindings`, `inject_via_table`, `keylabel`.
- `src/editor.jl` — `InlineEditor`, `_evalNFormat`/`_myNumFormat`, `editor_load!`/
  `editor_handle`/`editor_commit`/`editor_render`/`draw_editor!` and friends.
- `src/scratchpad.jl` — `pin!`/`unpin!`/`export_to_main!`/`scratchpad_dict()`; `_scratchpad_open!` in `twscreen.jl` (Shift-F2).
- `src/history.jl` — undo/redo ring buffer; clipboard history stack; wired into twedittable + twdicttree.
- `src/twstatusbar.jl` — `newTwStatusBar`; non-focusable; subscribes to `Observable{String}` via `subscribe!` in `twobj.jl`.
- `src/TermWin.jl` — `include` order: `contracts.jl` → `theme.jl` → `scroll.jl` →
  `rows.jl` → `observable.jl` → `editor.jl` → `bindings.jl` → `scratchpad.jl` → `history.jl`, before the widget files.
  `refresh_theme!()` called at end of `initsession()` after `color_channel_table` populated.
- Converted widgets: `src/twpopup.jl`, `src/twtree.jl`, `src/twdicttree.jl`,
  `src/twfilebrowser.jl`, `src/twmultiselect.jl`, `src/twcalendar.jl`, `src/twviewer.jl`,
  `src/twentry.jl`, `src/twedittable.jl`, `src/twdftable.jl`.

## Verification

- **Build/load:** `julia --project=. -e 'using TermWin'` — primitives compile, no widget regressions.
- **Full suite:** `julia --project=. -e 'using Pkg; Pkg.test("TermWin")'` — green after each stage.
  `test/runtests.jl` includes `primitives_unit.jl` (~110 asserts covering all primitives +
  per-host clamp/scroll/row tests) and `editor_unit.jl` (~110 asserts covering all editor
  type rules, render branches, and commit parity).
- **Targeted demos** (per `CLAUDE.md`): `test/color_pair.jl` (theme tokens render identically
  to the old `COLOR_PAIR(n)`), `test/dicttree_edit.jl` + `test/edit_dataframe.jl` (typed
  rows + scroll + footer/help still correct), `test/progress_unit.jl` (enum assertions green).
- **Widget interaction requires TTY** — `test/entrystring.jl`, `test/entrydate.jl`,
  `test/entry_num_tick.jl` (entry: typing, tick, `?` calendar), `test/edit_dataframe.jl`
  (cells incl. enum/date/missing, commit-on-move), `test/dicttree_edit.jl` (inline leaf
  edit, Bool/Date). Verify cursor, boundary `#`/bold indicators, right-justified numbers,
  and picker round-trips render identically to pre-rearchitecture behavior.
- **Resize:** drive `:KEY_RESIZE` through popup/multiselect/edittable and confirm
  `clamp_scroll!`→`clamp_view!` keeps the cursor visible (these had no resize re-clamp before).
