# TermWin Layout & Flexible Sizing — Design Notes

> Scope: how `vstack`/`hstack`/`@twlayout` size their children, the `:content`/
> `:fill`/`Flex` hints, and — importantly — the **design limit** on flex sizing
> inside *nested* (inner) containers. Code: `src/sizing.jl`, `src/twlist.jl`,
> `src/twbuilder.jl`, `src/twobj.jl`.

---

## 1. The sizing model

A child's `height=`/`width=` argument is a `SizeSpec` (`src/sizing.jl`):

| Spec | Meaning |
|------|---------|
| `Int` | fixed rows/cols |
| `Float ∈ (0,1]` | fraction of the container's canvas |
| `:content` / `:auto` | size to the widget's natural content extent |
| `:fill` | grow to consume leftover main-axis space (weight 1) |
| `Flex(w)` | like `:fill`, split leftover space by relative weight `w` |

"**Main axis**" is the stacking direction: **height** in a `vstack`, **width** in
an `hstack`. The other axis is the "**cross axis**". Hints behave differently per
axis — on the cross axis a fill spec just means "span the container" (the role
separators already play); the interesting case is the **main axis**, where fill
children share whatever space the fixed/content children leave behind.

Hints ride the existing `Any`-typed `TwObj.desiredHeight`/`desiredWidth` — no
struct change. `natural_height(o)`/`natural_width(o)` are generics (default: the
widget's current size) overridden by the variable widgets (tree, dicttree,
dftable, edittable, filebrowser, viewer), each derived from that widget's
existing dimensions function (`datalistlen`, summed column widths, `msglen`, …).

---

## 2. Two-phase layout

Sizing happens in two phases because a child is *linked into* its parent before
all siblings exist, but flex distribution needs the whole sibling set.

**Phase A — link time (`alignxy!`, `src/twobj.jl`).** Each child resolves its
spec to a *provisional* size against the parent canvas via `resolve_dim`:
`:content` → its natural extent; a main-axis `:fill`/`Flex` → a provisional `1`
(finalized in Phase B); `Int`/`Float` → their literal/fractional value. The
provisional `1` keeps the canvas math clean (it doesn't inflate the parent).

**Phase B — after the do-block (`resolve_flex!`, `src/twlist.jl`).** Once every
child is present, the builder (`vstack`/`hstack`/`@twlayout`) runs, in order:
`update_list_canvas` → `reflow_children!` → **`resolve_flex!`**. The flex pass:

1. sizes `:content` children to `natural`, clamped to the budget;
2. sums the non-flex children → `used`;
3. splits `remaining = budget − used` among `:fill`/`Flex` children by weight.

The arithmetic is a pure, window-free helper, `allocate_main` (unit-tested in
`test/sizing_unit.jl`). `resolve_flex!` is the **main-axis analogue** of the
cross-axis fill pass already inside `update_list_canvas`. It also re-runs from
`relayout!` on terminal resize, so fill children re-expand when the window grows.
At the root, Phase B **recurses** into nested containers — see §3.

---

## 3. Nested flex: the top-down recursive allocate

`:fill`/`Flex`/`:content` are honored at **any nesting depth**, including
*perpendicular* nesting (a `vstack` column inside a root `hstack` whose tree fills
the column's height). This is a real flexbox-style solve: bottom-up **measure**,
then top-down **allocate**.

### Participation is opt-in

A nested list joins its parent's distribution **only** when its main-axis spec is
`:fill`, `Flex(w)`, or `:content`. `allocate_main` treats any numeric/fraction
spec as fixed (it keeps the child's `presize`), so a default-sized (`1.0`) nested
list — which is *every* list that wasn't given an explicit hint — keeps
shrink-wrapping exactly as before. **No existing layout changes behavior.**

### The recursion

`resolve_flex!` takes an optional `budget` kwarg — the main-axis space the list
may distribute. The root derives it from its `NC.Plane` viewport; a nested list is
*handed* one by its parent. After `allocate_main` sizes its own children, the pass
recurses into each participating nested-list child, pinning it on **both** axes
and re-solving inside:

```julia
for (c, v) in zip(ws, sizes)
    setmain!(c, v)                       # allocated main-of-parent extent
    if b > 0 && participates(c)          # c is a list with a :fill/Flex/:content main spec
        setcross!(c, crosssize)          # span the parent's cross axis …
        c.data.canvasheight = c.height   # … and pin the child's canvas to its box
        c.data.canvaswidth  = c.width
        childbudget = c.data.horizontal ? c.width : c.height
        resolve_flex!(c; budget = childbudget)   # distribute along c's own main axis
    end
end
```

Two things make perpendicular nesting work:

- **Cross-pinning.** A participating child list is stretched to the parent's cross
  extent (`o.data.canvasheight` for an hstack parent, `canvaswidth` for a vstack
  parent). So a `vstack` column inside an `hstack` becomes as tall as the row —
  giving it a real *height* budget to distribute among its own children.
- **`budget` is the child's *own* main extent.** For a `vstack` column that is
  `(c.horizontal ? c.width : c.height) == c.height`, i.e. the height it was just
  pinned to. The recursion then splits that height among the column's `:fill`
  children.

Leaf cross-fill (a `width=1.0`/`:fill` separator-style child spanning the cross
axis) is re-applied in this same pass, so leaves inside a nested list that *grew*
via allocation re-span the new size — not just the shrink-wrapped one they saw
during measure.

A nested list reached **without** a budget — the inner builder's own
`resolve_flex!` call, which runs before its parent has sized it — gets `budget==0`
and skips distribution. The root pass re-solves it top-down afterward, so the
premature call is harmless.

### Example — what now works

```julia
# Columns split width 2:1; inside each, a :content header over a :fill tree that
# fills the column's full height.
hstack(; height=40, width=90) do s
    vstack(s; width=Flex(2)) do col
        newTwLabel(col, "left";  style=:header)   # :content (natural 1 row)
        newTwTree(col, a; height=:fill)           # fills the column height
    end
    vstack(s; width=Flex(1)) do col
        newTwLabel(col, "right"; style=:header)
        newTwTree(col, b; height=:fill)
    end
end
```

See `test/flex_layout.jl` (Demo 4) for a runnable version and
`test/sizing_unit.jl` for the headless recursion tests (the `budget` kwarg lets
the whole top-down solve run without a TTY).

### Why this is safe against re-shrink-wrap

The allocate pass never calls `update_list_canvas`, so the top-down sizes are not
overwritten by a later measure. Only the **root** owns a `pad`; nested lists draw
onto it through the `TwWindow` offset chain, so resizing a nested list is pure
window/position bookkeeping — no pad reallocation.

---

## 4. Remaining edges

- **Overflow.** When fixed + `:content` children already exceed the budget,
  `remaining == 0`: `:fill` children floor at 1 and the recursion budget is small;
  the root canvas grows past the viewport and scrolls, as before.
- **Numeric sizes on inner lists are still ignored.** Honoring an `Int`/`Float`
  size on a nested list (rather than shrink-wrapping it) was intentionally left
  out — only the explicit flex/content hints opt a nested list into sizing. If a
  use case needs "this nested column is exactly 30 cols", that would be a further
  extension to `allocate_main`/`participates`.
