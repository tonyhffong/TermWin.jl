# default behavior, dummy behavior, and convenient functions for all widgets

widgetStaggerPosx = 0
widgetStaggerPosy = 0

# only use these inside widget constructor, when their states are
# not yet fully formed.
function link_parent_child(
    p::TwObj{TwScreenData},
    c::TwObj,
    height::SizeSpec,
    width::SizeSpec,
    posy::Any,
    posx::Any,
)
    registerTwObj(p, c)
    c.desiredHeight = height
    c.desiredWidth = width
    c.desiredPosy = posy
    c.desiredPosx = posx
    alignxy!(c, height, width, posx, posy, parent = p)
    configure_newwinpanel!(c)
    log("Screen-" * string(objtype(c)) * ": x=" * string(c.xpos) * " y=" * string(c.ypos))
end

function link_parent_child(
    p::TwObj{TwListData},
    c::TwObj,
    height::SizeSpec,
    width::SizeSpec,
    posy::Any,
    posx::Any,
)
    update_list_canvas(p)
    begx = 0
    begy = 0
    if p.data.horizontal
        for sw in p.data.widgets
            begx += sw.width
        end
    else
        for sw in p.data.widgets
            begy += sw.height
        end
    end

    @assert c.screen.value === nothing
    @assert c.window === nothing

    # Record what the user originally asked for so we can re-resolve on resize.
    # For nested lists the height/width are overridden by the canvas below; we
    # still preserve the *user-supplied* values so the canvas can grow with the
    # parent at relayout time.
    c.desiredHeight = height
    c.desiredWidth = width
    c.desiredPosy = posy
    c.desiredPosx = posx

    # by the time a list is being added, its contents must be fully populated
    if objtype(c) == :List
        @assert c.data.pad === nothing
        update_list_canvas(c)
        height = c.data.canvasheight
        width = c.data.canvaswidth
    end
    push!(p.data.widgets, c)
    update_list_canvas(p)
    alignxy!(c, height, width, begx, begy, parent = p)
    c.hasFocus = false
    # Strip borders so child widgets render edge-to-edge inside the composed layout.
    old_bsv = c.borderSizeV
    old_bsh = c.borderSizeH
    c.box = false
    c.borderSizeV = 0
    c.borderSizeH = 0
    c.height -= 2 * old_bsv
    c.width -= 2 * old_bsh
    # Remember the strip so relayout! reproduces it (see relayout_list_children!).
    c.strippedBorderV = old_bsv
    c.strippedBorderH = old_bsh
    c.window = TwWindow(WeakRef(p), c.ypos, c.xpos, c.height, c.width)
    log("List-" * string(objtype(c)) * ": x=" * string(c.xpos) * " y=" * string(c.ypos))
    log(" orig begxy: x=" * string(begx) * " y=" * string(begy))
    log(" new geom: h=" * string(p.height) * " w=" * string(p.width))
end

function link_parent_child(
    p::TwObj,
    c::TwObj,
    height::SizeSpec,
    width::SizeSpec,
    posy::Any,
    posx::Any,
)
    c.desiredHeight = height
    c.desiredWidth = width
    c.desiredPosy = posy
    c.desiredPosx = posx
    alignxy!(c, height, width, posx, posy, parent = p)
    c.window = TwWindow(WeakRef(p), c.ypos, c.xpos, c.height, c.width)
    log(
        string(objtype(p)) *
        "-" *
        string(objtype(c)) *
        ": x=" *
        string(c.xpos) *
        " y=" *
        string(c.ypos),
    )
end

function subscribe!(f::Function, obs::Observable, owner::TwObj)
    on(f, obs)
    push!(owner.subscriptions, (obs, f))
    return f
end

function configure_newwinpanel!(obj::TwObj)
    global rootplane
    obj.window = NC.Plane(
        NC.LibNotcurses.ncplane_create(
            rootplane.ptr,
            NC.PlaneOptions(
                y = obj.ypos,
                x = obj.xpos,
                rows = obj.height,
                cols = obj.width,
            ),
        ),
    )
    # Set an explicit opaque background on the base cell.
    # A new plane's default base cell has channels=0: alpha=OPAQUE but color="terminal
    # default".  Notcurses emits no color escape for "default", so the terminal's own
    # background shows through any cell werase() resets — visually transparent.
    # Using explicit black (bit-30 RGB flag set, R=G=B=0) forces Notcurses to emit a
    # real color escape, blocking whatever is underneath.
    NC.LibNotcurses.ncplane_set_base(
        obj.window.ptr,
        " ",
        UInt16(0),
        make_channel_pair(COLOR_WHITE, COLOR_BLACK),
    )
    log(
        "configure_newwinpanel!: created plane at y=" *
        string(obj.ypos) *
        " x=" *
        string(obj.xpos) *
        " h=" *
        string(obj.height) *
        " w=" *
        string(obj.width),
    )
end

function alignxy!(
    o::TwObj,
    h::SizeSpec,
    w::SizeSpec,
    x::Any,
    y::Any;
    relative::Bool = false, # if true, o.xpos = parent.x + x
    parent = o.screen.value,
)
    global widgetStaggerPosx, widgetStaggerPosy
    if isa(parent, TwScreen)
        parentwin = parent.window
        if isa(parentwin, NC.Plane)
            pos = NC.yx(parentwin)
            parbegy = Int(pos.y)
            parbegx = Int(pos.x)
            d = NC.dim_yx(parentwin)
            parmaxy = Int(d[1])
            parmaxx = Int(d[2])
        else
            parbegy = 0;
            parbegx = 0
            parmaxy = parent.height
            parmaxx = parent.width
        end
    else
        tmppar = parent
        while (isa(tmppar.window, TwWindow))
            tmppar = tmppar.window.parent.value
        end
        if objtype(tmppar) == :List
            parmaxy = tmppar.data.canvasheight
            parmaxx = tmppar.data.canvaswidth
        else
            parmaxy = tmppar.height
            parmaxx = tmppar.width
        end
        log("parmaxy=" * string(parmaxy) * "parmaxx=" * string(parmaxx))
        parbegx = parbegy = 0
    end
    # Resolve literal sizes and sizing hints (:content/:fill/Flex) on each axis.
    # The parent's stacking direction decides which axis is "main": a fill hint
    # on the main axis gets a provisional size here and is finalized by
    # resolve_flex! once all siblings are known.
    horizontal =
        (parent isa TwObj && objtype(parent) == :List) ? parent.data.horizontal : false
    o.height = resolve_dim(h, parmaxy, natural_height(o); main = !horizontal)
    o.width  = resolve_dim(w, parmaxx, natural_width(o);  main = horizontal)

    if relative
        if typeof(x) <: Integer && typeof(y) <: Integer
            if isa(o.window, NC.Plane)
                pos = NC.yx(o.window)
                begx = Int(pos.x)
                begy = Int(pos.y)
            else
                begx = 0;
                begy = 0
            end
            xpos = x+begx
            ypos = y+begy
        else
            throw("Illegal relative position")
        end
    else
        xpos = x
        ypos = y
    end

    gapx = max(0, parmaxx - o.width)
    gapy = max(0, parmaxy - o.height)
    lastx = parbegx + gapx
    lasty = parbegy + gapy
    if x == :left
        xpos = parbegx
    elseif x == :right
        xpos = parbegx + gapx
    elseif x == :center
        xpos = round(Int, parbegx + gapx / 2)
    elseif x == :random
        xpos = round(Int, parbegx + gapx * rand())
    elseif x == :staggered
        if widgetStaggerPosx > gapx
            widgetStaggerPosx = 0
        end
        xpos = parbegx + widgetStaggerPosx
        widgetStaggerPosx += 4
    elseif typeof(x) <: AbstractFloat && 0.0 <= x <= 1.0
        xpos = round(Int, parbegx + gapx * x)
    end
    xpos = max(min(xpos, lastx), parbegx)

    if y == :top
        ypos = parbegy
    elseif y == :bottom
        ypos = parbegy + gapy
    elseif y == :center
        ypos = round(Int, parbegy + gapy / 2)
    elseif y == :random
        ypos = round(Int, parbegy + gapy * rand())
    elseif y == :staggered
        if widgetStaggerPosy > gapy
            widgetStaggerPosy = 0
        end
        ypos = parbegy + widgetStaggerPosy
        widgetStaggerPosy += 2
    elseif typeof(y) <: AbstractFloat && 0.0 <= y <= 1.0
        ypos = round(Int, parbegy + gapy * y)
    end
    ypos = max(min(ypos, lasty), parbegy)
    o.xpos = xpos
    o.ypos = ypos
end

# a general blocking API to make a widget a dialogue
function activateTwObj(o::TwObj, tokens::Any = nothing)
    global nc_context
    d = NC.dim_yx(o.window)
    maxy = Int(d[1])
    maxx = Int(d[2])
    werase(o.window)
    mvwprintw(o.window, maxy>>1, maxx>>1, "%s", "...")
    NC.render(nc_context)

    draw(o)
    if tokens === nothing #just wait for input
        while true
            NC.render(nc_context)
            token = readtoken(nc_context)
            if token == :nochar
                sleep(0.05)   # avoid 100% CPU spin when no input is ready
                continue
            end
            status = Base.invokelatest(inject, o, token)
            if status == Accept
                return o.value
            elseif status == Cancel # most likely a cancel
                return nothing
            elseif status == Ignored && token == :F1
                h = helptext(o)
                if h != ""
                    helper = newTwViewer(
                        o.screen.value, h;
                        posy = :center, posx = :center,
                        showHelp = false, showLineInfo = false,
                        bottomText = "Esc to continue",
                    )
                    activateTwObj(helper)
                    unregisterTwObj(o.screen.value, helper)
                    refresh(o)
                end
            end # default is to continue
        end
    else
        for token in tokens
            NC.render(nc_context)
            status = Base.invokelatest(inject, o, token)
            if status == Accept
                return o.value
            elseif status == Cancel # most likely a cancel
                return nothing
            end
        end
        # exhausted all the tokens, no obvious response
        unregisterTwObj(o.screen.value, o)
        return nothing
    end
end

function inject(_::TwObj, k::Any)
    if k == :esc
        return Cancel
    else
        return Ignored
    end
end

erase(o::TwObj) = werase(o.window)

function move(o::TwObj, x, y, relative::Bool, refresh::Bool = false)
    if isa(o.window, NC.Plane)
        pos = NC.yx(o.window)
        begx = Int(pos.x)
        begy = Int(pos.y)
    else
        begx = 0;
        begy = 0
    end
    alignxy!(o, o.height, o.width, x, y, relative = relative)

    xdiff = o.xpos - begx
    ydiff = o.ypos - begy

    if xdiff == 0 && ydiff == 0
        return
    end
    NC.move_yx(o.window, o.ypos, o.xpos)
    if isa(o.screen.value, TwScreen) && isa(o.screen.value.window, NC.Plane)
        # touch the screen
    end
    if refresh
        draw(o)
    end
end

function focus(_::TwObj) end

function unfocus(_::TwObj) end

refresh(o::TwObj) = (erase(o); draw(o))

helptext(_::TwObj) = ""

# ===== Resize / re-layout =====
#
# relayout!(o) re-resolves a widget's geometry against its current parent and
# applies the new size and position to the underlying NC.Plane.  It is invoked
# from the screen-level event loop when a :KEY_RESIZE token arrives, after the
# screen's own height/width have been updated to the new terminal dimensions.
#
# Top-level widgets (own a NC.Plane) are moved+resized in place; if a widget is
# itself a TwList container, its child widgets are recursively re-laid out
# against the new canvas via relayout_list_children!.
#
# Widgets that are embedded inside a TwList (their window is a TwWindow record)
# are re-laid out as part of their parent list's pass — calling relayout!
# directly on them is a no-op.

# Default: per-widget scroll clamping is a no-op.  Widgets with scrolling state
# (Viewer, Tree, DfTable, List) override this so cursor/top stay in range when
# the viewport grows or shrinks.
clamp_scroll!(_::TwObj) = nothing

function relayout!(o::TwObj)
    if o.desiredHeight === nothing || o.desiredWidth === nothing
        # Widget was constructed without going through link_parent_child
        # (e.g. the root TwScreen itself). Nothing to do.
        return false
    end

    if isa(o.window, NC.Plane)
        scr = o.screen.value
        if scr === nothing
            return false
        end

        # If we are a top-level list, recurse into our children first so that
        # update_list_canvas sees their new sizes when computing our own canvas.
        if objtype(o) == :List
            # Re-resolve our own outer dimensions against the new screen size,
            # then push that down to children. update_list_canvas will then
            # bring the canvas in line with both.
            alignxy!(
                o,
                o.desiredHeight,
                o.desiredWidth,
                o.desiredPosx,
                o.desiredPosy,
                parent = scr,
            )
            relayout_list_children!(o)
            # Final canvas pass after children settle.
            update_list_canvas(o)
            # Re-distribute leftover space so :fill/:content children re-expand
            # (or shrink) to the new viewport.
            resolve_flex!(o)
        else
            alignxy!(
                o,
                o.desiredHeight,
                o.desiredWidth,
                o.desiredPosx,
                o.desiredPosy,
                parent = scr,
            )
        end

        # Move the plane *before* resizing.  Notcurses will refuse a resize
        # that pushes the plane past its parent's edges, so for a shrink we
        # need the new origin in place first.
        try
            NC.move_yx(o.window, o.ypos, o.xpos)
        catch err
            log("relayout! move_yx failed: " * string(err))
        end
        try
            NC.resize(o.window, 0, 0, 0, 0, 0, 0, o.height, o.width)
        catch err
            log("relayout! resize failed: " * string(err))
        end

        # Resize the list pad to match the new canvas, if any.
        if objtype(o) == :List && o.data.pad !== nothing
            delwin(o.data.pad)
            o.data.pad = newpad(o.data.canvasheight, o.data.canvaswidth)
        end

        clamp_scroll!(o)
        return true
    end

    # Embedded widget: parent list handles us.
    return false
end

# Re-resolve every child widget of a TwList against the list's *new* canvas,
# stacking them in order and updating their TwWindow records.  Mirrors the
# layout math in link_parent_child(::TwListData, ...) but skips the one-time
# border-stripping (already done at construction).
function relayout_list_children!(p::TwObj{TwListData})
    # Reset the canvas to the list's new viewport BEFORE walking children, so
    # that alignxy! (which reads parmaxy = canvasheight when the parent is a
    # list) resolves their fractional sizes against the new size.  The trailing
    # update_list_canvas call grows the canvas back if children need more space.
    if isa(p.window, NC.Plane)
        p.data.canvasheight = p.height
        p.data.canvaswidth = p.width
    end
    begx = 0
    begy = 0
    for c in p.data.widgets
        # Recurse into nested lists first so their canvases are up-to-date.
        if objtype(c) == :List
            relayout_list_children!(c)
            # Nested list dimensions are driven by the canvas, exactly as in
            # link_parent_child.
            h = c.data.canvasheight
            w = c.data.canvaswidth
        else
            h = c.desiredHeight !== nothing ? c.desiredHeight : c.height
            w = c.desiredWidth !== nothing ? c.desiredWidth : c.width
        end

        alignxy!(c, h, w, begx, begy, parent = p)

        # link_parent_child stripped this child's box borders *after* alignxy
        # sized it, shrinking height/width by 2*border. A numeric (Int/fraction)
        # spec re-resolves border-inclusive here, so re-strip to reproduce the
        # link-time size — otherwise every formerly-boxed child grows by 2
        # rows/cols on each resize, inserting blank gaps between stacked widgets.
        # Hint specs (:content/:fill/Flex) resolve from natural size, which is
        # already post-strip, so they must NOT be re-stripped.
        if objtype(c) != :List
            if c.strippedBorderV > 0 && c.desiredHeight isa Real
                c.height = max(1, c.height - 2 * c.strippedBorderV)
            end
            if c.strippedBorderH > 0 && c.desiredWidth isa Real
                c.width = max(1, c.width - 2 * c.strippedBorderH)
            end
        end

        if isa(c.window, TwWindow)
            c.window.yloc = c.ypos
            c.window.xloc = c.xpos
            c.window.height = c.height
            c.window.width = c.width
        end

        # A hidden child is positioned at the current offset but consumes no
        # space, so the next visible sibling collapses into its place (the
        # trailing update_list_canvas likewise excludes it from the canvas).
        if c.isVisible
            if p.data.horizontal
                begx += c.width
            else
                begy += c.height
            end
        end

        clamp_scroll!(c)
    end
    update_list_canvas(p)
end

# ─── Generic tick framework ────────────────────────────────────────────────
# Widgets that need periodic updates (e.g. progress driven by a worker thread)
# override `tick(o)` and register themselves via `register_tickable!`. The
# screen event loop calls `tick` on each registered widget once per loop pass.
tick(o::TwObj) = Ignored

function register_tickable!(scr::TwObj{TwScreenData}, o::TwObj)
    o in scr.data.tickables || push!(scr.data.tickables, o)
    nothing
end

function unregister_tickable!(scr::TwObj{TwScreenData}, o::TwObj)
    idx = findfirst(==(o), scr.data.tickables)
    idx !== nothing && deleteat!(scr.data.tickables, idx)
    nothing
end
