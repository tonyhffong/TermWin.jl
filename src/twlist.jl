# horizontal or vertical array of widgets
# nestable. But the top-most List handles the canvas navigation

# Every time a nesting layer is added, all the children's windows have to be redone,
# to reflect their locations in the main pad.
# This is bad!

function newTwList(
    scr::TwObj;
    height::SizeSpec = 25,
    width::SizeSpec = 80,
    posy::Any = :center,
    posx::Any = :center,
    canvasheight = 80,
    canvaswidth = 128,
    box = true,
    horizontal = false,
    title = "",
    showLineInfo = true,
    form = false,
    bottomText::String = "",
    keys::AbstractVector = Binding[],
    visible_when::Union{Nothing,Function} = nothing,
)
    obj = TwObj(TwListData(), Val{:List})
    obj.box = box
    obj.title = title
    obj.borderSizeV = box ? 1 : 0
    obj.borderSizeH = box ? 1 : 0
    obj.data.horizontal = horizontal
    obj.data.showLineInfo = showLineInfo
    obj.data.isForm = form
    obj.data.bottomText = bottomText
    obj.data.userbindings = collect(Any, keys)
    obj.data.visible_when = visible_when
    obj.data.canvasheight = canvasheight
    obj.data.canvaswidth = canvaswidth

    link_parent_child(scr, obj, height, width, posy, posx)
    if objtype(scr) == :Screen
        obj.data.pad = newpad(obj.data.canvasheight, obj.data.canvaswidth)
    end
    obj
end

# move a fully formed widget into this list. need more bookkeeping
function push_widget!(o::TwObj{TwListData}, w::TwObj)
    global rootplane
    # change the widget's window to reflect its location on the canvas
    begx = 0
    begy = 0
    if o.data.horizontal
        for sw in o.data.widgets
            begx += sw.width
        end
    else
        for sw in o.data.widgets
            begy += sw.height
        end
    end

    # This widget must have been previously registered to screen
    unregisterTwObj(o.screen.value, w)
    if isa(w.window, NC.Plane) && w.window != rootplane
        delwin(w.window) # so we don't leak memory
    end

    # by the time a list is being added, its contents must be fully populated
    if objtype(w) == :List
        if isa(w.data.pad, NC.Plane) && w.data.pad != o.data.pad # the list has its own pad, get rid of it.
            delwin(w.data.pad)
        end
        update_list_canvas(w)
        w.height = w.data.canvasheight
        w.width = w.data.canvaswidth
        w.data.pad = nothing
    end

    # Invariant: children inside a TwList render edge-to-edge on the canvas.
    # Any box/border configured on the child widget is suppressed so that the
    # enclosing TwList's own frame (if any) provides the single visual boundary.
    old_bsv = w.borderSizeV
    old_bsh = w.borderSizeH
    w.box = false
    w.borderSizeV = 0
    w.borderSizeH = 0
    w.height -= 2 * old_bsv
    w.width -= 2 * old_bsh
    w.window = TwWindow(WeakRef(o), begy, begx, w.height, w.width)
    push!(o.data.widgets, w)
    w.hasFocus = false
end

function update_list_canvas(o::TwObj{TwListData})
    ws = o.data.widgets
    if isempty(ws)
        # Use the list's own viewport size as the baseline canvas so that
        # fractional heights/widths on child widgets resolve correctly.
        o.data.canvasheight = o.height > 0 ? o.height : 80
        o.data.canvaswidth = o.width > 0 ? o.width : 128
    else
        for w in o.data.widgets
            if objtype(w) == :List
                update_list_canvas(w)
            end
        end
        wsz(x, dim) = objtype(x) == :List ?
            (dim === :h ? x.data.canvasheight : x.data.canvaswidth) :
            (dim === :h ? x.height : x.width)
        # A leaf widget whose CROSS-axis size was given as a fraction (e.g. a
        # separator: width=1.0 inside a vstack, height=1.0 inside an hstack) means
        # "fill the list's cross axis". Its fraction is resolved at link time
        # against the ultimate ancestor's *default* canvas (a nested list is linked
        # while still empty), so it carries a bogus oversized cross dimension here.
        # Such children must ADAPT to the cross-axis size, not DRIVE it: exclude
        # them from the cross-axis maximum, then resolve them below. (Nested lists
        # shrink-wrap and are always included via their own canvas size.)
        is_fill(x, frac) = objtype(x) != :List && cross_fill_factor(frac) !== nothing
        # Hidden children occupy no space: exclude them from the main-axis sum and
        # the cross-axis maximum so the canvas collapses around what's shown.
        if o.data.horizontal
            real_h = [wsz(x, :h) for x in ws if x.isVisible && !is_fill(x, x.desiredHeight)]
            computed_h = isempty(real_h) ? 1 : maximum(real_h)
            computed_w = sum((wsz(x, :w) for x in ws if x.isVisible); init = 0)
        else
            real_w = [wsz(x, :w) for x in ws if x.isVisible && !is_fill(x, x.desiredWidth)]
            computed_w = isempty(real_w) ? 1 : maximum(real_w)
            computed_h = sum((wsz(x, :h) for x in ws if x.isVisible); init = 0)
        end
        if isa(o.window, NC.Plane)
            # Root-level list: canvas floor is the content area (viewport minus
            # borders), not the outer widget size. Children with fractional
            # width/height resolve against canvaswidth/canvasheight as parmaxx,
            # so using the outer width would make them 2 cols/rows too wide and
            # cause ensure_visible_on_canvas to shift canvaslocx/y by 2.
            o.data.canvasheight = max(computed_h, o.height - 2 * o.borderSizeV)
            o.data.canvaswidth  = max(computed_w, o.width  - 2 * o.borderSizeH)
        else
            # Nested list (TwWindow or not yet attached): canvas = content size,
            # and the list's own height/width grows to match.
            o.data.canvasheight = computed_h
            o.data.canvaswidth = computed_w
            o.height = o.data.canvasheight + (o.box ? 2 : 0)
            o.width = o.data.canvaswidth + (o.box ? 2 : 0)
        end
        # Now that the cross-axis size is final, resize the fill leaves to match it
        # (a separator spanning the full height of an hstack / width of a vstack).
        # A fractional cross-axis size keeps its fraction; :fill / Flex span fully.
        crosssize = o.data.horizontal ? o.data.canvasheight : o.data.canvaswidth
        for x in ws
            objtype(x) == :List && continue
            if o.data.horizontal
                f = cross_fill_factor(x.desiredHeight)
                if f !== nothing
                    x.height = max(1, round(Int, crosssize * f))
                    isa(x.window, TwWindow) && (x.window.height = x.height)
                end
            else
                f = cross_fill_factor(x.desiredWidth)
                if f !== nothing
                    x.width = max(1, round(Int, crosssize * f))
                    isa(x.window, TwWindow) && (x.window.width = x.width)
                end
            end
        end
    end
    if o.data.pad !== nothing
        delwin(o.data.pad)
        o.data.pad = newpad(o.data.canvasheight, o.data.canvaswidth)
    end
end

# Re-place a list's children edge-to-edge by cumulative offset, using their
# *current* sizes. Children are positioned at link time, but a nested list is
# linked while still empty — it carries the default full-size canvas, so its
# offset (and the alignxy-clamped offset of any sibling added after it) is wrong
# until it shrinks to its content. The vstack/hstack builders call this once the
# list is fully populated so nested columns/rows actually sit side by side /
# stacked, instead of all collapsing to (0,0). Leaf children are already in the
# right place, so re-deriving their offsets here is a no-op for them.
function reflow_children!(o::TwObj{TwListData})
    begx = 0
    begy = 0
    for c in o.data.widgets
        if isa(c.window, TwWindow)
            c.window.yloc   = begy
            c.window.xloc   = begx
            c.window.height = c.height
            c.window.width  = c.width
        end
        c.ypos = begy
        c.xpos = begx
        # A hidden child is parked at the current offset but consumes no space, so
        # the next visible sibling collapses into its place.
        c.isVisible || continue
        if o.data.horizontal
            begx += c.width
        else
            begy += c.height
        end
    end
    return o
end

# Main-axis distribution pass — the top-down "allocate" half of the two-pass
# layout (the bottom-up "measure" half is update_list_canvas, which shrink-wraps
# every list to a natural size). Sizes `:content` children to their natural
# extent, splits the leftover main-axis space among `:fill`/`Flex` children by
# weight, then **recurses** into any participating nested list so flex works at
# any nesting depth. See design/layout-design.md.
#
# Budget: the main-axis space available to distribute. A top-level list (window is
# an NC.Plane) derives it from its own viewport; a nested list is handed one by its
# parent via the `budget` kwarg. A nested list reached without a budget (its own
# builder's call, before its parent has sized it) gets 0 → no distribution, so its
# flex/content leaves fall back to natural size until the parent re-solves it.
#
# Participation (opt-in): a nested list joins its parent's distribution only when
# its main-axis spec is `:fill`/`Flex`/`:content`. allocate_main treats any
# numeric/fraction spec as fixed, so a default-sized (1.0) nested list keeps
# shrink-wrapping exactly as before — no regression.
function resolve_flex!(o::TwObj{TwListData}; budget::Union{Nothing,Int} = nothing)
    ws = o.data.widgets
    isempty(ws) && return o
    horizontal = o.data.horizontal

    mainspec(c) = horizontal ? c.desiredWidth : c.desiredHeight
    mainsize(c) = horizontal ? c.width : c.height
    natof(c)    = horizontal ? natural_width(c) : natural_height(c)
    setmain!(c, v) = horizontal ? (c.width = v) : (c.height = v)
    setcross!(c, v) = horizontal ? (c.height = v) : (c.width = v)
    participates(c) = objtype(c) == :List && (is_flex(mainspec(c)) || is_content(mainspec(c)))

    b = budget !== nothing ? budget :
        isa(o.window, NC.Plane) ?
            (horizontal ? o.width - 2 * o.borderSizeH : o.height - 2 * o.borderSizeV) : 0

    # Hidden children take no space: present them to allocate_main as fixed-0 so
    # they neither claim flex budget nor subtract from the budget available to
    # visible siblings. Their real sizes are left untouched (recomputed by
    # relayout_list_children! from desiredHeight/Width when they reappear).
    specs    = [c.isVisible ? mainspec(c) : 0 for c in ws]
    presizes = [c.isVisible ? mainsize(c) : 0 for c in ws]
    naturals = [c.isVisible ? natof(c) : 0 for c in ws]
    sizes    = allocate_main(specs, presizes, naturals, b)

    # Parent's cross extent — a participating nested list spans it (so a column
    # fills the row's height, and vice-versa).
    crosssize = horizontal ? o.data.canvasheight : o.data.canvaswidth

    for (c, v) in zip(ws, sizes)
        c.isVisible || continue
        setmain!(c, v)
        if objtype(c) == :List
            if b > 0 && participates(c)
                setcross!(c, crosssize)
                if isa(c.window, TwWindow)
                    c.window.height = c.height
                    c.window.width  = c.width
                end
                # The nested list's canvas must match its newly allocated box so
                # its own children fit and its scroll/line-info read correctly.
                c.data.canvasheight = c.height
                c.data.canvaswidth  = c.width
                # Recurse: distribute along the child's *own* main axis in its box.
                childbudget = c.data.horizontal ? c.width : c.height
                resolve_flex!(c; budget = childbudget)
            end
        else
            # Leaf cross-fill: a fill spec spans the cross axis, a fraction takes
            # its share. Re-applied here (not just in update_list_canvas) so leaves
            # inside a nested list that *grew* via allocation re-span the new size.
            cf = cross_fill_factor(horizontal ? c.desiredHeight : c.desiredWidth)
            if cf !== nothing
                setcross!(c, max(1, round(Int, crosssize * cf)))
                isa(c.window, TwWindow) &&
                    (horizontal ? (c.window.height = c.height) : (c.window.width = c.width))
            end
        end
    end

    reflow_children!(o)               # re-place + sync TwWindow records
    for c in ws                       # keep each child's scroll valid after resize
        clamp_scroll!(c)
    end
    return o
end

function clamp_scroll!(o::TwObj{TwListData})
    contentwidth = o.width - (o.box ? 2 : 0)
    contentheight = o.height - (o.box ? 2 : 0)
    if contentwidth < 1 || contentheight < 1
        return
    end
    if o.data.canvaslocx < 0
        o.data.canvaslocx = 0
    elseif o.data.canvaslocx > max(0, o.data.canvaswidth - contentwidth)
        o.data.canvaslocx = max(0, o.data.canvaswidth - contentwidth)
    end
    if o.data.canvaslocy < 0
        o.data.canvaslocy = 0
    elseif o.data.canvaslocy > max(0, o.data.canvasheight - contentheight)
        o.data.canvaslocy = max(0, o.data.canvasheight - contentheight)
    end
end

function draw(o::TwObj{TwListData})
    werase(o.window) # this is important, or attributes on the pad may be lost

    if isa(o.window, NC.Plane)
        set_default_focus(o)
    end

    for w in o.data.widgets
        # TODO: no need to draw widget outside visible range? or just draw everything?
        if w.isVisible
            draw(w)
        end
    end

    # Push the pad to the visible window if this is the root list.
    # ncplane_mergedown operates on absolute screen-position overlap, so we
    # temporarily move the pad to align its (canvaslocy, canvaslocx) origin
    # with the window's content area before merging, then move it back.
    if isa(o.window, NC.Plane)
        borderSizeH = o.box ? 1 : 0
        borderSizeV = o.box ? 1 : 0
        winpos = NC.yx(o.window)
        NC.move_yx(
            o.data.pad,
            Int(winpos.y) + borderSizeV - o.data.canvaslocy,
            Int(winpos.x) + borderSizeH - o.data.canvaslocx,
        )
        NC.mergedown_simple(o.data.pad, o.window)
        NC.move_yx(o.data.pad, -10000, -10000)

        # Draw box and info AFTER the merge so border cells are never
        # overwritten by pad content (pad may overlap border rows when scrolled).
        viewContentHeight = o.height - 2*o.borderSizeV
        viewContentWidth = o.width - 2*o.borderSizeH
        if o.box
            if o.data.navigationmode
                wattron(o.window, COLOR_PAIR(12))
            end

            box(o.window, 0, 0)

            if o.data.showLineInfo
                if o.data.canvasheight <= viewContentHeight
                    vscale = "v:all"
                else
                    vscale = @sprintf("v:%d/%d", o.data.canvaslocy, o.data.canvasheight)
                end

                if o.data.canvaswidth <= viewContentWidth
                    hscale = "h:all"
                else
                    hscale = @sprintf("h:%d/%d", o.data.canvaslocx, o.data.canvaswidth)
                end

                msg = vscale * " " * hscale
                mvwprintw(o.window, 0, o.width - length(msg) - 3, "%s", msg)
            end

            if o.title != ""
                mvwprintw(o.window, 0, 2, "%s", o.title )
            end

            if o.data.bottomText != ""
                mvwprintw(o.window, o.height-1, 2, "%s", o.data.bottomText)
            end

            if o.data.navigationmode
                mvwprintw(o.window, 0, 2, "%s", "Navigation mode")
                wattroff(o.window, COLOR_PAIR(12))
            end
        end
    end
end

function lowest_widget(o::TwObj{TwListData})
    if o.data.focus == 0
        error("cannot locate focused widget")
    end
    w = o.data.widgets[o.data.focus]
    if objtype(w) == :List
        return lowest_widget(w)
    else
        return w
    end
end

function lowest_widget_location_area(o::TwObj{TwListData}, y::Int = 0, x::Int = 0)
    if o.data.focus == 0
        error("cannot locate focused widget")
    end
    w = o.data.widgets[o.data.focus]
    if objtype(w) == :List
        return lowest_widget_location_area(w, y+w.window.yloc, x+w.window.xloc)
    else
        return (w, y+w.window.yloc, x+w.window.xloc, w.window.height, w.window.width)
    end
end

function ensure_visible_on_canvas(o::TwObj)
    h = o.height
    w = o.width
    y = o.window.yloc
    x = o.window.xloc
    log(@sprintf("ensure %s is visible", string(o)))
    log(@sprintf("  init local y,x: %d %d", y, x))
    win = o.window
    par = win.parent.value
    while (!isa(win.parent.value.window, NC.Plane))
        y += win.parent.value.window.yloc
        x += win.parent.value.window.xloc
        par = win.parent.value
        win = win.parent.value.window
    end
    par = win.parent.value
    log(@sprintf("  actual coord y,x: %d %d", y, x))
    @assert objtype(par) == :List
    contentwidth = par.width - (par.box ? 2 : 0)
    contentheight = par.height - (par.box ? 2 : 0)
    log(@sprintf("  canvas size     : %d %d", par.data.canvasheight, par.data.canvaswidth))
    log(@sprintf("  window geom     : %d %d", contentheight, contentwidth))
    log(@sprintf("  canvas wind.orig: %d %d", par.data.canvaslocy, par.data.canvaslocx))

    if par.data.canvaslocx > x
        par.data.canvaslocx = x
    end
    if par.data.canvaslocy > y
        par.data.canvaslocy = y
    end
    if x + w - par.data.canvaslocx > contentwidth
        par.data.canvaslocx = max(0, x + w - contentwidth)
    end
    if y + h - par.data.canvaslocy > contentheight
        par.data.canvaslocy = max(0, y + h - contentheight)
    end
    if par.data.canvaslocx > par.data.canvaswidth - contentwidth
        par.data.canvaslocx = max(0, par.data.canvaswidth - contentwidth)
    end
    if par.data.canvaslocy > par.data.canvasheight - contentheight
        par.data.canvaslocy = max(0, par.data.canvasheight - contentheight)
    end
    log(@sprintf("  canvas  new orig: %d %d", par.data.canvaslocy, par.data.canvaslocx))
end

"""
    on_key(keys, label, callback; when=_->true, scope=:global) -> Binding

Build a custom key [`Binding`](@ref) for a layout container (`@twlayout`,
`vstack`, `hstack`) — pass a vector of these via the `keys=` keyword.

`keys` is a single token or a vector of tokens (`:F5`, `"d"`, `[:ctrl_s, :F2]`).
`callback` is invoked with the current **data snapshot** — the
`Dict{Symbol,Any}` produced by [`collect_form_values`](@ref), i.e. every keyed
widget's current value (the same dict F10-submit returns).

The callback's return value sets the outcome:
- an [`InjectResult`](@ref) (`Handled`/`Accept`/`Cancel`/`Ignored`) is used as-is;
  returning `Accept` stores the snapshot into the container's value, so
  `activateTwObj` returns it (an early-submit key).
- anything else (e.g. `nothing`) is treated as `Handled` — the key is consumed,
  the view redraws, and the layout stays open.

# Example
```julia
@twlayout (form=true, keys=[
    on_key(:F5,     "Preview", snap -> show_preview(snap)),         # stays open
    on_key(:ctrl_s, "Save",    snap -> (save_draft(snap); Accept)), # exits, returns snap
]) begin
    entry(String; key=:title, title="Title")
end
```
"""
function on_key(keys, label::AbstractString, callback;
                when::Function = _ -> true, scope::Symbol = :global)
    Binding(keys, label; scope = scope, when = when,
        action = o -> begin
            snap = collect_form_values(o)
            r = callback(snap)
            r === Accept && (o.value = snap)
            r isa InjectResult ? r : Handled
        end)
end

function collect_form_values(o::TwObj{TwListData})::Dict{Symbol,Any}
    result = Dict{Symbol,Any}()
    for w in o.data.widgets
        if objtype(w) == :List
            merge!(result, collect_form_values(w))
        elseif w.formkey !== nothing
            result[w.formkey] = w.value
        end
    end
    result
end

# ── Reactive section visibility (visible_when) ──────────────────────────────
# A container list may carry a `visible_when` predicate (see newTwList). After
# each keystroke the root list re-evaluates every predicate against the live form
# snapshot, flips `isVisible`, and reflows so hidden sections collapse and shown
# ones reclaim their space. collect_form_values is deliberately visibility-blind,
# so predicates always see every key regardless of what is currently shown.

# Is `w` actually on screen — itself visible AND every ancestor list visible?
function _is_effectively_visible(w::TwObj)
    w.isVisible || return false
    win = w.window
    while isa(win, TwWindow)
        p = win.parent.value
        p === nothing && break
        p.isVisible || return false
        win = p.window
    end
    return true
end

# Evaluate visible_when on every descendant list; return whether any flag flipped.
function _apply_visibility_walk!(o::TwObj{TwListData}, snap::Dict{Symbol,Any})
    changed = false
    for w in o.data.widgets
        objtype(w) == :List || continue
        if w.data.visible_when !== nothing
            newvis = w.data.visible_when(snap)::Bool
            if newvis != w.isVisible
                w.isVisible = newvis
                changed = true
            end
        end
        # Recurse regardless: a nested predicate is evaluated independently of its
        # ancestor's visibility (a hidden ancestor simply isn't drawn/sized).
        changed |= _apply_visibility_walk!(w, snap)
    end
    return changed
end

# If the currently focused leaf is now hidden (itself or via a hidden ancestor),
# move focus to the first visible focusable widget.
function _refocus_if_hidden!(root::TwObj{TwListData})
    root.data.focus == 0 && return
    cur = lowest_widget(root)
    _is_effectively_visible(cur) && return
    deep_unfocus(cur)
    set_default_focus(root)
end

# Re-evaluate all visible_when predicates against the current form snapshot. On
# any change, keep focus off hidden widgets and reflow (relayout! rebuilds the
# pad and re-runs the now visibility-aware sizing passes). Returns whether
# anything changed. Call on the ROOT list only.
function apply_visibility!(root::TwObj{TwListData})
    snap = collect_form_values(root)
    changed = _apply_visibility_walk!(root, snap)
    if changed
        _refocus_if_hidden!(root)
        relayout!(root)
    end
    return changed
end

function apply_defaults!(o::TwObj{TwListData}, defaults::Dict{Symbol,Any})
    for w in o.data.widgets
        if objtype(w) == :List
            apply_defaults!(w, defaults)
        elseif w.formkey !== nothing && haskey(defaults, w.formkey)
            apply_default!(w, defaults[w.formkey])
        end
    end
end

function _list_check_accept_focus(w::TwObj, stepsign::Int)
    if w.isVisible && w.acceptsFocus
        if objtype(w) == :List
            r = 1:length(w.data.widgets)
            if stepsign == -1
                r = reverse(r)
            end
            for i in r
                if _list_check_accept_focus(w.data.widgets[i], stepsign)
                    return true
                end
            end
            return false
        else
            return true
        end
    end
    return false
end

function _list_refocus_after_nav!(o::TwObj{TwListData})
    (w, yloc, xloc, height, width) = lowest_widget_location_area(o)
    canvaslocx  = o.data.canvaslocx
    canvaslocy  = o.data.canvaslocy
    canvaslocx2 = o.data.canvaslocx + o.width - o.borderSizeH * 2
    canvaslocy2 = o.data.canvaslocy + o.height - o.borderSizeV * 2
    distfunc = function (to::Tuple{Int,Int,Int,Int})
        a       = to[3] * to[4]
        aOverlap =
            max(0, min(to[2] + to[4], canvaslocx2) - max(to[2], canvaslocx)) *
            max(0, min(to[1] + to[3], canvaslocy2) - max(to[1], canvaslocy))
        d = point_from_area(yloc + height >> 1, xloc + width >> 1, to)
        aOverlap == 0 ? d + 1000 : d + a / aOverlap
    end
    wdists = Any[]
    geometric_filter(o, distfunc, 0, 0, wdists, false, 2000)
    candidate = nothing
    mindist   = 999999
    for (cw, dist) in wdists
        if dist < mindist
            candidate = cw
            mindist   = dist
        end
    end
    if candidate !== nothing
        w = lowest_widget(o)
        deep_unfocus(w)
        deep_focus(candidate)
    end
end

function bindings(o::TwObj{TwListData})
    isroot() = isa(o.window, NC.Plane)
    builtins = [
        Binding(:enter, "next field",
            when   = _-> isroot() && o.data.isForm,
            action = _-> Ignored),            # display-only: actual advance is in inject
        Binding(:F10, "submit form",
            when   = _-> isroot() && o.data.isForm,
            action = _-> begin
                focus = o.data.focus
                focus != 0 && inject(lowest_widget(o), :focus_off)
                o.value = collect_form_values(o)
                refresh(o)
                Accept
            end),
        Binding(:ctrl_F4, "toggle navigation",
            when   = _-> isroot(),
            action = _-> begin
                o.data.navigationmode = !o.data.navigationmode
                !o.data.navigationmode && _list_refocus_after_nav!(o)
                refresh(o)
                Handled
            end),
        Binding(:F1, "help",
            when   = _-> isroot(),
            action = _-> begin
                helper = newTwViewer(
                    o.screen.value,
                    helptext(o),
                    posy        = :center,
                    posx        = :center,
                    showHelp    = false,
                    showLineInfo = false,
                    bottomText  = "Esc to continue",
                )
                raiseTwObject(helper)
                Handled
            end),
    ]
    # Caller-supplied custom bindings come after the built-ins, so they cannot
    # accidentally shadow Tab/F1/F10. They still dispatch (inject_via_table),
    # show up in F1 help, and contribute to the footer.
    isempty(o.data.userbindings) ? builtins :
        vcat(builtins, collect(Binding, o.data.userbindings))
end

function inject(o::TwObj{TwListData}, token::Any)
    retcode = Ignored
    dorefresh = false
    isrootlist = isa(o.window, NC.Plane)
    focus = o.data.focus
    if focus == 0
        return Ignored
    end

    if token == :esc
        return Cancel
    end

    if !o.data.navigationmode
        result = inject(o.data.widgets[focus], token)
        if result == Cancel
            refresh(o)
            return Cancel
        elseif result == Accept && isrootlist && o.data.isForm
            # Form mode: Enter advances focus to the next field instead of exiting.
            prevw = o.data.widgets[focus]
            i = mod1(focus + 1, length(o.data.widgets))
            while i != focus
                w = o.data.widgets[i]
                if _list_check_accept_focus(w, 1)
                    deep_unfocus(prevw)
                    deep_focus(w, false)
                    break
                end
                i = mod1(i + 1, length(o.data.widgets))
            end
            dorefresh = true
            retcode = Handled
        elseif result != Ignored
            # A field handled the key (typically a value change), and this path
            # returns early — so re-evaluate section visibility here too, not just
            # at the fall-through exit below. Root list only; no-op unless a flag
            # actually flips.
            isrootlist && apply_visibility!(o)
            refresh(o)
            return result
        end
    end

    # TODO: what's the behavior of :esc
    # TODO: what's the behavior of Accept
    if !o.data.navigationmode && token in [:tab, :shift_tab]
        prevw = o.data.widgets[focus]
        # note that if the widget is a list and can take a tab/shift tab as, we
        # wouldn't be here in the first place
        dorefresh = true
        if token == :tab
            stp = 1
        else
            stp = -1
        end
        if isrootlist # wrap around
            i = mod1(focus + stp, length(o.data.widgets))
            while (i != focus)
                w = o.data.widgets[i]
                if _list_check_accept_focus(w, stp)
                    deep_unfocus(prevw)
                    deep_focus(w, stp == -1) # 2nd arg is reverse
                    retcode = Handled
                    break
                end
                i = mod1(i + stp, length(o.data.widgets))
            end
            # Fallback: no other sibling accepted focus (single-child root list, or
            # all siblings are non-focusable). Re-enter the current widget from the
            # opposite end so Tab wraps within the view rather than leaking to the screen.
            if retcode == Ignored && _list_check_accept_focus(prevw, stp)
                deep_unfocus(prevw)
                deep_focus(prevw, stp == -1) # stp==1 (Tab) → forward; stp==-1 → reverse
                retcode = Handled
            end
        else
            i = focus + stp
            if stp == 1
                r = (focus+stp):length(o.data.widgets)
            else
                r = (focus+stp):-1:1
            end
            for i in r
                w = o.data.widgets[i]
                if _list_check_accept_focus(w, stp)
                    deep_unfocus(prevw)
                    deep_focus(w, stp == -1) # 2nd arg is reverse
                    retcode = Handled
                    break
                end
            end
        end
    elseif !o.data.navigationmode &&
           token in
           [:left, :right, :up, :down, :ctrl_left, :ctrl_right, :ctrl_up, :ctrl_down] &&
           isrootlist
        # find the location of the current focus
        (w, yloc, xloc, height, width) = lowest_widget_location_area(o)
        if token in [:up, :ctrl_up]
            distfunc = function (to::Tuple{Int,Int,Int,Int})
                updown_arrow_distance(to, (yloc, xloc, height, width), 1)
            end
        elseif token in [:down, :ctrl_down]
            distfunc = function (to::Tuple{Int,Int,Int,Int})
                updown_arrow_distance(to, (yloc, xloc, height, width), -1)
            end
        elseif token in [:left, :ctrl_left]
            distfunc = function (to::Tuple{Int,Int,Int,Int})
                leftright_arrow_distance(to, (yloc, xloc, height, width), 1)
            end
        else
            distfunc = function (to::Tuple{Int,Int,Int,Int})
                leftright_arrow_distance(to, (yloc, xloc, height, width), -1)
            end
        end
        wdists = Any[]
        geometric_filter(o, distfunc, 0, 0, wdists, true, 40)
        candidate = nothing
        mindist = 999999
        for (cw, dist) in wdists
            if dist < mindist
                candidate = cw
                mindist = dist
            end
        end
        if candidate !== nothing
            deep_unfocus(w)
            deep_focus(candidate)
            dorefresh = true
            retcode = Handled
        end
    elseif o.data.navigationmode && token in [:left, :right]
        if token == :left
            xstep = -1
        elseif token == :right
            xstep = 1
        end
        newlocx = o.data.canvaslocx + xstep
        if newlocx < 0
            o.data.canvaslocx = 0
        elseif newlocx + o.width - o.borderSizeH*2 >= o.data.canvaswidth
            o.data.canvaslocx = max(0, o.data.canvaswidth - o.width + o.borderSizeH*2)
        else
            o.data.canvaslocx = newlocx
        end
        dorefresh = true
    elseif o.data.navigationmode && token in [:up, :down, :pageup, :pagedown]
        # the canvas location can move by one screen-size in either direction
        # but it's kept in by the maximum canvas sizes
        # also, focus would change to the new one closest to the current focused widget
        if token == :up
            ystep = -1
        elseif token == :down
            ystep = 1
        elseif token == :pageup
            ystep = -(o.height - o.borderSizeV*2)
        elseif token == :pagedown
            ystep = (o.height - o.borderSizeV*2)
        end
        newlocy = o.data.canvaslocy + ystep
        if newlocy < 0
            o.data.canvaslocy = 0
        elseif newlocy + o.height - o.borderSizeV*2 >= o.data.canvasheight
            o.data.canvaslocy = max(0, o.data.canvasheight - o.height+o.borderSizeV*2)
        else
            o.data.canvaslocy = newlocy
        end
        dorefresh = true
    elseif token == :KEY_MOUSE && isrootlist
        (mstate, x, y, bs) = getmouse()
        if mstate == :button1_pressed
            (rely, relx) = screen_to_relative(o.window, y, x)
            if 0<=relx<o.width && 0<=rely<o.height
                # Convert the window-relative click to CANVAS coordinates: strip
                # the border, then add the scroll offset. geometric_filter compares
                # against child rects in canvas space (w.window.yloc/xloc), and draw
                # maps canvas (canvaslocy,canvaslocx) to the window content origin —
                # so without adding canvasloc a scrolled layout (e.g. a large
                # embedded table pushing the canvas past the viewport) routes clicks
                # to the wrong widget.
                rely += o.data.canvaslocy - o.borderSizeV
                relx += o.data.canvaslocx - o.borderSizeH
                # find the closest widget
                distfunc = function (to::Tuple{Int,Int,Int,Int})
                    point_from_area(rely, relx, to)
                end
                wdists = Any[]
                geometric_filter(o, distfunc, 0, 0, wdists, false, 40)
                candidate = nothing
                mindist = 999999
                for (cw, dist) in wdists
                    if dist < mindist
                        candidate = cw
                        mindist = dist
                    end
                end
                if candidate !== nothing
                    w = lowest_widget(o)
                    deep_unfocus(w)
                    deep_focus(candidate)
                    if o.data.focus != 0
                        inject(lowest_widget(o), :KEY_MOUSE)
                    end
                    dorefresh = true
                    retcode = Handled
                    o.data.navigationmode = false
                end
            else
                retcode = Ignored
            end
        elseif mstate in (:scroll_up, :scroll_down)
            if o.data.focus != 0
                focused = lowest_widget(o)
                inject(focused, mstate == :scroll_up ? :up : :down)
                dorefresh = true
                retcode = Handled
            end
        end
    else
        r = inject_via_table(o, token)
        if r !== Ignored
            retcode = r
        end
    end

    # Reactive section visibility: after the token has been processed (a field may
    # have changed), re-evaluate visible_when predicates against the live snapshot.
    # Root list only; relayout runs (inside apply_visibility!) solely when a flag
    # actually flips.
    if isrootlist && apply_visibility!(o)
        dorefresh = true
    end

    if dorefresh
        refresh(o)
    end
    return retcode
end

function deep_unfocus(w::TwObj)
    tmpw = w
    while isa(tmpw, TwObj{TwListData})
        focus = tmpw.data.focus
        tmpw2 = tmpw.data.widgets[focus]
        tmpw.data.focus = 0
        tmpw2.hasFocus = false
        tmpw = tmpw2
    end

    local par::TwObj{TwListData}
    w.hasFocus = false
    inject(w, :focus_off)
    if tmpw != w
        inject(tmpw, :focus_off)
    end
    tmpw = w
    # do-while: execute once, then continue while condition holds
    while true
        par = tmpw.window.parent.value
        par.data.focus = 0
        par.hasFocus = false
        tmpw = par
        if isa(tmpw.window, NC.Plane)
            break
        end
    end
end

function set_default_focus(w::TwObj{TwListData}, rev = false)
    if w.data.focus == 0 && !isempty(w.data.widgets)
        r = rev ? (length(w.data.widgets):-1:1) : (1:length(w.data.widgets))
        for i in r
            child = w.data.widgets[i]
            if _list_check_accept_focus(child, rev ? -1 : 1)
                w.data.focus = i
                child.hasFocus = true
                if isa(child, TwObj{TwListData})
                    set_default_focus(child, rev)
                else
                    ensure_visible_on_canvas(child)
                end
                break
            end
        end
    end
end

function deep_focus(w::TwObj, rev = false)
    local par::TwObj{TwListData}
    w.hasFocus = true
    if objtype(w) == :List
        set_default_focus(w, rev)
    else
        ensure_visible_on_canvas(w)
    end
    tmpw = w
    # do-while: execute once, then continue while condition holds
    while true
        par = tmpw.window.parent.value
        for (i, c) in enumerate(par.data.widgets)
            if c == tmpw
                par.data.focus = i
                par.hasFocus = true
                tmpw = par
                break
            end
        end
        @assert par.data.focus != 0
        @assert par.hasFocus
        if isa(tmpw.window, NC.Plane)
            break
        end
    end
end

function geometric_filter(
    o::TwObj{TwListData},
    distfunc::Function,
    y::Int,
    x::Int,
    list::Array,
    excludezero::Bool = false,
    cutoff::Int = 100,
)
    for w in o.data.widgets
        if objtype(w) == :List
            geometric_filter(
                w,
                distfunc,
                y+w.window.yloc,
                x+w.window.xloc,
                list,
                excludezero,
                cutoff,
            )
        elseif w.isVisible && w.acceptsFocus
            to = (y+w.window.yloc, x+w.window.xloc, w.window.height, w.window.width)
            dist = distfunc(to)
            if dist > cutoff || dist == 0 && excludezero
                continue
            end
            push!(list, (w, dist))
        end
    end
end

function updown_arrow_distance(
    to::Tuple{Int,Int,Int,Int},
    from::Tuple{Int,Int,Int,Int},
    sgn::Int,
)
    tocentx = to[2] + to[4] >> 1
    tocenty = to[1] + to[3] >> 1

    fromcentx = from[2] + from[4] >> 1
    fromcenty = from[1] + from[3] >> 1

    if sgn*tocenty >= sgn*fromcenty
        return 99999
    end

    ret = (fromcenty - tocenty)*sgn

    if from[2] > tocentx
        ret += (from[2] - tocentx) * 5
    elseif tocentx >= from[2]+from[4]
        ret += (tocentx - (from[2]+from[4])+1) * 5
    end
    return ret
end

function leftright_arrow_distance(
    to::Tuple{Int,Int,Int,Int},
    from::Tuple{Int,Int,Int,Int},
    sgn::Int,
)
    tocentx = to[2] + to[4] >> 1
    tocenty = to[1] + to[3] >> 1

    fromcentx = from[2] + from[4] >> 1
    fromcenty = from[1] + from[3] >> 1

    if sgn*tocentx >= sgn*fromcentx
        return 99999
    end

    ret = (fromcentx - tocentx)*sgn

    if from[1] > tocenty
        ret += (from[1] - tocenty) * 5
    elseif tocenty >= from[1]+from[3]
        ret += (tocenty - (from[1]+from[3])+1) * 5
    end
    return ret
end

# used for mouse click
# inside the area it returns zero, otherwise it's manhattan distance to the boundary
function point_from_area(y::Int, x::Int, from::Tuple{Int,Int,Int,Int})
    xdist = 0
    if x < from[2]
        xdist += from[2]-x
    elseif x >= from[2]+from[4]
        xdist += x - (from[2]+from[4]-1)
    end

    ydist = 0
    if y < from[1]
        ydist += from[1]-y
    elseif y >= from[1]+from[3]
        ydist += y - (from[1]+from[3]-1)
    end

    return xdist + ydist
end

function helptext(o::TwObj{TwListData})
    focus = o.data.focus
    focus == 0 && return ""
    child_help = helptext(o.data.widgets[focus])
    isa(o.window, NC.Plane) || return child_help
    nav_help = """
mouse-click    : activate nearest widget
ctrl-arrows    : directional focus movement
  (normal arrows work too if not consumed by the current widget)
tab/shift-tab  : cycle through all widgets
"""
    own_help = helptext_from_bindings(o)
    sep = child_help == "" ? "" : "\n" * ("—"^7) * " canvas navigation " * ("—"^7) * "\n"
    return child_help * sep * nav_help * own_help
end
