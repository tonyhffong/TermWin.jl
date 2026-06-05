# ===== ScrollState: one viewport-clamp helper for all scrolling widgets =====
#
# Today ~9 widgets each re-derive "keep the cursor visible inside the viewport"
# by hand (twpopup.jl's checkTop/moveby and siblings). This is that math, once.
# See design/termwin-widget-authoring-rearchitecture.md, Part C.
#
# Widgets hold a ScrollState in their data struct and implement
#   clamp_scroll!(o) = clamp_view!(o.data.scroll, content_len(o), viewport(o))
# so the framework's resize path (twobj.jl relayout!) keeps them in range for
# free.

mutable struct ScrollState
    top::Int        # first visible row (1-based)
    left::Int       # first visible column (1-based)
    cursor::Int     # selected row (1-based)
end
ScrollState() = ScrollState(1, 1, 1)
ScrollState(cursor::Integer) = ScrollState(1, 1, Int(cursor))

"""
    clamp_view!(s, n, viewport) -> s

Clamp `s.cursor` into `1:n` and `s.top` so the cursor stays within a
`viewport`-row window, with no trailing blank rows when content overflows.
Invariant on return (for `n ≥ 1`): `1 ≤ s.top ≤ s.cursor ≤ s.top+viewport-1`.
"""
function clamp_view!(s::ScrollState, n::Integer, viewport::Integer)
    n = max(0, Int(n))
    vp = max(1, Int(viewport))
    s.cursor = clamp(s.cursor, 1, max(1, n))
    # keep cursor inside [top, top+vp-1]
    s.top = clamp(s.top, max(1, s.cursor - vp + 1), s.cursor)
    # avoid scrolling past the end (no trailing blank rows)
    s.top = clamp(s.top, 1, max(1, n - vp + 1))
    return s
end

"Move the cursor by `delta` rows and re-clamp the viewport."
function move_cursor!(s::ScrollState, delta::Integer, n::Integer, viewport::Integer)
    s.cursor += Int(delta)
    clamp_view!(s, n, viewport)
end

"Page the cursor by one viewport in direction `dir` (-1 up, +1 down)."
page!(s::ScrollState, dir::Integer, n::Integer, viewport::Integer) =
    move_cursor!(s, Int(dir) * max(1, Int(viewport)), n, viewport)

"Scroll horizontally, clamping `s.left` into `1:maxleft`."
function scroll_left!(s::ScrollState, delta::Integer, maxleft::Integer)
    s.left = clamp(s.left + Int(delta), 1, max(1, Int(maxleft)))
    return s
end

"True iff row index `r` is currently within the visible window of height `viewport`."
visible(s::ScrollState, r::Integer, viewport::Integer) =
    s.top <= r <= s.top + max(1, Int(viewport)) - 1
