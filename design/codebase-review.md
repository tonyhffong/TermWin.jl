# TermWin Codebase Review

> ✅ resolved · ⚠️ partial · 🔲 open.

---

## What's Working Well

- **`TwObj{T}` + multiple dispatch** — small, consistent `draw`/`inject`/`helptext` triple; adding a widget means defining a struct + methods, not subclassing.
- **`@twlayout` / `vstack` / `hstack` + `form=true`** — a screen of widgets reads like a screen.
- **`TwAttr` / `COLOR_PAIR` discipline** — correctly separates channel data from style flags; `make_attr` prevents style bits being clobbered.
- **`readtoken` using `eff_text`** — layout-correct characters on any keyboard layout, which most TUI libraries get wrong for years.

---

## Open Design Concerns

- 🔲 **`TwList` does two jobs** — it is the layout container *and* the form coordinator (`isForm`, `collect_form_values`, border zeroing on children). The border-zeroing fix-up in `link_parent_child` is the tell: "chrome belongs to the container" should be a design invariant, not a silent rewrite pass.
- 🔲 **`isForm::Bool` flips Enter's meaning** — modal booleans that change a key's semantics are a recurring confusion source. Either form mode is a different container type (`TwForm`) or Enter's behavior belongs in the binding table (the infrastructure now exists).
- 🔲 **`liftAggrSpecToFunc` evals expression DSL at runtime** — namespace is `Main`, errors surface as `LoadError` from gensym'd functions, DSL not documented centrally. A small interpreter over the `:col` AST would be safer and give better error messages.
- 🔲 **`open_in_vim` platform ladder** belongs in a `platform.jl` helper, not embedded inside `twviewer.jl`.
- 🔲 **Mouse support** — Notcurses exposes it. Click row to focus, scroll wheel, drag dividers in the file browser, click cell in the edit table.
- 🔲 **Resizable splits** — file browser panes are a fixed ratio; drag-to-resize and persist per directory.
- 🔲 **Animation budget** — a 60 ms ease on focus moves, scroll, and selection changes would make the TUI feel premium; Notcurses makes this essentially free.

---

## Partial / In-Progress

- ⚠️ **Full bindings sweep** — `Binding`/`inject_via_table` infrastructure done; only 2 of 16 widgets fully converted. Inject ladders in `twpopup`, `twmultiselect`, `twtree`, `twdicttree`, `twfilebrowser`, `twedittable`, `twdftable` are still hand-written, with footer/help text maintained separately.
- ⚠️ **Reactive cross-widget state** — `Observable{T}` + `subscribe!` infrastructure is in place (`src/observable.jl`, `twobj.jl`); no widget yet publishes selection/cursor observables, so wiring a live status footer requires manual plumbing.
- ⚠️ **Toast / status notifications** — `TwStatusBar` + `Observable` infrastructure is ready; blocking `tshow()` confirmations (F7 pin, export menu) not yet replaced with ephemeral toasts.
- ⚠️ **Accessibility** — theme token system + `high_contrast_theme()` cover the color-swap path; no runtime UI toggle (Ctrl-T picker or session option), no screen-reader linear text dump.

---

## Resolved (summary)

- ✅ **Color pairs → theme tokens** (`src/theme.jl`) — `theme(:selection_focused)`, `:header`, `:divider`, `:negative`, `:emphasis`; 11 widgets swept; `high_contrast_theme()` builder ships.
- ✅ **Command palette (Ctrl-P)** — `_palette_open!` in `src/twscreen.jl`; globally intercepted before focused widget; `newTwPopup(substrsearch=true)` over `active_bindings(focused)`; result propagated back to screen loop.
- ✅ **F7 scratchpad** (`src/scratchpad.jl`) — `pin!` / `unpin!` / `export_to_main!`; F7 in tree widgets pins to scratchpad instead of writing to `Main`; Shift-F2 opens a browseable `TwDictTree` panel; exit prompt when scratchpad is non-empty.
- ✅ **Reactive status bar** (`src/twstatusbar.jl`) — non-focusable widget backed by `Observable{String}` + `subscribe!` in `twobj.jl` with auto-cleanup.
- ✅ **Undo/redo + clipboard history** (`src/history.jl`) — 20-step ring buffer; `twedittable` and `twdicttree` wired; `twedittable` has a 20-item clipboard history stack (Alt-Y picker).
- ✅ **InjectResult enum** (`src/contracts.jl`) — `Handled`/`Ignored`/`Accept`/`Cancel`; all 16 widgets; symbol shim retired.
- ✅ **InlineEditor unification** (`src/editor.jl`) — `twentry`/`twedittable`/`twdicttree` share one implementation; uniform beep-on-invalid, overwrite toggle.
- ✅ **ScrollState** (`src/scroll.jl`) — `clamp_view!`/`move_cursor!`/`page!`; popup/multiselect/edittable/tree wired; resize re-clamp is now free via `clamp_scroll!` hook.
- ✅ **TreeRow/FileRow + tree_nav** (`src/rows.jl`) — typed row structs replace anonymous tuples; all 3 tree widgets share sibling/parent navigation logic.
