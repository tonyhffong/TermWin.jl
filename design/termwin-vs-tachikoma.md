# TermWin vs. Tachikoma.jl

> **Question:** what are the differences between TermWin and [Tachikoma.jl](https://github.com/kahliburke/Tachikoma.jl)?

## The headline: they're not the same kind of thing

Both are Julia TUI libraries — but they sit on opposite sides of a paradigm split, and that split matters more than any feature checklist.

**TermWin is a retained, *modal*, dispatch-based widget toolkit.** Its core verb is `activateTwObj(widget)` → runs an event loop → **returns a value**. You summon a widget (`tshow(x)`, a form, a DataFrame viewer), the user interacts, you get a result back, control returns to your code. Rendering and input are `draw(o::TwObj{T})` / `inject(o, token)` dispatched on the widget's type parameter. It's built on **Notcurses** (a mature C library) which does the hard terminal work — pixel/sixel/kitty graphics, layout-correct keyboard input via `eff_text`, panel stacking.

**Tachikoma is a declarative *application* framework.** Its core is the Elm triad — `Model` / `update!(m, event)` / `view(m, frame)` — driven by a single continuous **60fps loop** with double-buffering. You don't summon-and-return; you define an app and run it (`app(MyModel())`) until it quits. It's **pure Julia** (no native dependency), does its own ANSI/sixel/kitty rendering, and is even **juliac-compilable to standalone binaries**.

That difference dictates everything else.

## Where each one wins

| Dimension | TermWin | Tachikoma |
|---|---|---|
| Interaction model | Modal "summon → return a value" | Continuous full-screen app loop |
| Best for | Embedded REPL/ICJ data exploration, dialogs, forms | Standalone dashboards, monitors, games, live UIs |
| Rendering backend | Notcurses (C) — pixel/sixel/kitty + Unicode fallback | Pure-Julia ANSI + braille/quadrant/sixel/kitty |
| Native dependency | Yes — Notcurses must be present/pinned | None (dependency-light) |
| Compile to binary | No (needs Notcurses + Julia) | Yes (juliac target is a stated goal) |
| Data widgets | **Grouped/pivot DataFrame tree (1.6k LOC), editable DataFrame w/ enum/date/missing cells, editable dict/vector tree, file browser w/ preview** | DataTable, paged+filterable table (SQLite ext), treeview |
| Domain niceties | BusinessDays calendar, Julia `Expr` pretty-print + syntax highlight, F11→vim | 24 themes, animations/springs/easing, recording → SVG/GIF |
| Live updates | Bolted-on (threaded progress bar + channel) | Native (the whole model is built for it) |
| Maturity | v0.1.0, ~14k LOC, single maintainer (you) | v2.1.0, 146★, 174 commits, 16 releases, CI/docs/property tests |
| Maintenance burden | All yours | External, active |

## Why you should use TermWin?

TermWin's most valuable, hardest-to-replace code is the **analytical data layer**: 
the grouped/pivot DataFrame tree viewer (`twdftable.jl`, the aggregation/`CalcPivot` machinery in `dfutils.jl`), 
the editable DataFrame table with enum/date/missing cell editors, the editable dict/vector tree, 
and the `Expr`-aware highlighting. These exist because TermWin is a 
*data analyst's interactive toolkit embedded in a REPL/ICJ workflow* 

There's also a **paradigm mismatch with how you use it**. ICJ calls `tshow(model)` and expects a value back. 
That modal "open a browser, return a selection" ergonomics is native to TermWin and 
*awkward* in Tachikoma's run-until-quit app model.


Longer term, TermWin may harvest Tachikoma's strongest ideas — constraint-based layout (Fixed/Fill/Percent/Min/Max/Ratio), 
hot-swappable themes, and the continuous-loop model for *new* live views 

## Sources

- [Tachikoma.jl repository](https://github.com/kahliburke/Tachikoma.jl)
