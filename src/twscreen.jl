# bookkeeping data for a screen

# Screen is unique also in that its instantiation requires a plane. It's because often we'd simply
# supply the rootplane that has already been created.
function newTwScreen(plane::NC.Plane, maxy::Int, maxx::Int)
    obj = TwObj(TwScreenData(), Val{:Screen})
    pos = NC.yx(plane)

    obj.window = plane
    obj.height = maxy
    obj.width = maxx
    obj.xpos = Int(pos.x)
    obj.ypos = Int(pos.y)

    obj.hasFocus = true
    obj.acceptsFocus = true
    obj.isVisible = true
    obj
end

function registerTwObj(scr::TwObj{TwScreenData}, o::TwObj)
    if o.screen.value !== nothing
        if o.screen.value == scr
            return
        end
        unregisterTwObj(o.screen.value, o)
    end
    push!(scr.data.objects, o)
    o.screenIndex = length(scr.data.objects)
    o.screen = WeakRef(scr)
end

function unregisterTwObj(scr::TwObj{TwScreenData}, o::TwObj)
    if o.screen.value != scr
        throw("unregister obj that doesn't belong to the screen")
    end
    for (obs, h) in o.subscriptions
        off(h, obs)
    end
    empty!(o.subscriptions)
    idx = o.screenIndex
    deleteat!(scr.data.objects, idx)
    if isa(o.window, NC.Plane)
        hide_panel(o.window)
    end
    for i = idx:length(scr.data.objects)
        scr.data.objects[i].screenIndex = i
    end
    if scr.data.focus >= idx
        scr.data.focus -= 1
    end
    if scr.data.focus == idx
        setTwFocusNext(scr)
    end
    o.screen = WeakRef()
end

function setTwFocusNext(scr::TwObj{TwScreenData})
    n = scr.data.focus
    fst = n
    result = nothing
    while true
        n += 1
        if n > length(scr.data.objects)
            n = 1
        end
        o = scr.data.objects[n]
        if o.acceptsFocus
            result = o
            break
        end
        if n == fst
            break
        end
    end
    if result !== nothing
        scr.data.focus = n
    else
        scr.data.focus = 0
    end
    return result
end

function setTwFocusPrevious(scr::TwObj{TwScreenData})
    n = scr.data.focus
    fst = n
    result = nothing
    while true
        n -= 1
        if n <= 0
            n = length(scr.data.objects)
        end
        o = scr.data.objects[n]
        if o.acceptsFocus
            result = o
            break
        end
        if n == fst
            break
        end
    end
    if result !== nothing
        scr.data.focus = n
    else
        scr.data.focus = 0
    end
    return result
end

function swapTwObjIndices(scr::TwObj{TwScreenData}, n1::Int, n2::Int)
    if n1!=n2 && 1 <= n1 <= length(scr.data.objects) && 1 <= n2 <= length(scr.data.objects)
        o1 = scr.data.objects[n1]
        o2 = scr.data.objects[n2]
        scr.data.objects[n1] = o2
        scr.data.objects[n2] = o1
        o1.screenIndex = n2
        o2.screenIndex = n1
        if scr.data.focus == n1
            scr.data.focus = n2
            o1.hasFocus = false
            o2.hasFocus = true
        elseif scr.data.focus == n2
            scr.data.focus = n1
            o2.hasFocus = false
            o1.hasFocus = true
        end
    end
end

function raiseTwObject(o::TwObj)
    log("Raise: " * string(o))
    scr = o.screen.value
    if scr !== nothing
        si = o.screenIndex
        deleteat!(scr.data.objects, si)
        push!(scr.data.objects, o)
        for i = si:length(scr.data.objects)
            scr.data.objects[i].screenIndex = i
            scr.data.objects[i].hasFocus = false
        end
        o.hasFocus = true
        scr.data.focus = length(scr.data.objects)
        refresh(o)
        if isa(o.window, NC.Plane)
            # Move to top of z-stack (pass C_NULL means "move to top")
            NC.move_below(o.window, C_NULL)
        end
    end
end

function lowerTwObject(o::TwObj)
    log("Lower: " * string(o))
    scr = o.screen.value
    if scr !== nothing
        si = o.screenIndex
        deleteat!(scr.data.objects, si)
        pushfirst!(scr.data.objects, o)
        for i = 1:length(scr.data.objects)
            scr.data.objects[i].screenIndex = i
            scr.data.objects[i].hasFocus = false
        end
        scr.data.objects[end].hasFocus = true
        scr.data.focus = length(scr.data.objects)
        refresh(o)
        if isa(o.window, NC.Plane)
            # Move to bottom of z-stack (pass C_NULL means "move to bottom")
            NC.move_above(o.window, C_NULL)
        end
    end
end

#=
Blocking call. it doesn't use inject directly, because
    * it needs to wait for populating of widgets
    * once there are widgets, get the topmost focused widget (TFW) and
    * inject tokens into the TFW
    * if TFW returns exit, get the next in line that accepts focus
    * otherwise, exit

This is some UGLY code. To be streamlined...
=#
function activateTwObj(scr::TwObj{TwScreenData}, tokens::Any = nothing)
    global nc_context
    refresh(scr) # clear any potential wait message
    focusObj = nothing
    focusIdx = scr.data.focus
    retvalue = nothing

    if focusIdx > 0 && focusIdx <= length(scr.data.objects)
        focusObj = scr.data.objects[focusIdx]
    end

    handleStatus =
        (st, tok)->begin
            focusIdx = scr.data.focus
            if focusIdx > 0 && focusIdx <= length(scr.data.objects)
                focusObj = scr.data.objects[focusIdx]
            else
                focusObj = nothing
            end
            if st == Accept || st == Cancel
                if st == Accept
                    retvalue = scr.value
                    # Export pinned values if this was the pre-exit multiselect.
                    if focusObj !== nothing && focusObj === scr.data.pre_exit_widget
                        selected = focusObj.value
                        if selected !== nothing
                            for name in selected; export_to_main!(name); end
                        end
                    end
                end
                if focusObj !== nothing
                    unregisterTwObj(scr, focusObj)
                    # find the next focusObj, if not found, just return
                    # otherwise, make it the new focus and continue
                    focusObj = nothing
                    for i = length(scr.data.objects):-1:1
                        o = scr.data.objects[i]
                        if o.isVisible && o.acceptsFocus
                            focusObj = o
                            o.hasFocus = true
                            scr.data.focus = i
                            refresh(o)
                            break
                        end
                    end
                end
                if focusObj === nothing
                    # Before truly exiting, offer to export any pinned scratchpad values.
                    if !scr.data.pre_exit_done && !scratchpad_isempty()
                        _show_pre_exit_dialog!(scr)
                        return nothing
                    end
                    return :really_exit
                end
            elseif st == Ignored
                if focusObj !== nothing
                    i = length(scr.data.objects)
                    while (st == Ignored && i >= 1)
                        o = scr.data.objects[i]
                        if o!=focusObj && o.isVisible && o.grabUnusedKey
                            st = inject(o, tok)
                        end
                        i -= 1
                    end
                    if st == Accept || st == Cancel
                        return :really_exit
                    end
                end
            end
        end

    if tokens === nothing
        while true
            NC.render(nc_context)
            token = readtoken(nc_context)
            if token != :nochar
                status = inject(scr, token)
                if handleStatus(status, token) == :really_exit
                    return retvalue
                end
            end

            # Generic tick: each registered widget gets a chance to update.
            # Iterate over a copy because tick() may unregister.
            for o in copy(scr.data.tickables)
                tickstatus = tick(o)
                if tickstatus == Accept || tickstatus == Cancel
                    if tickstatus == Accept
                        retvalue = o.value
                    end
                    unregister_tickable!(scr, o)
                    unregisterTwObj(scr, o)
                    return retvalue
                end
            end

            sleep(0.05) # ~20Hz UI loop; worker runs on its own thread
        end
    else
        for token in tokens
            NC.render(nc_context)
            token = readtoken(nc_context)
            status = inject(scr, token)
            if handleStatus(status, token) == :really_exit
                return retvalue
            end
        end
        # exhausted all the tokens, no obvious response
        return nothing
    end
end

function handle_resize!(scr::TwObj{TwScreenData})
    global nc_context
    if nc_context === nothing
        return
    end
    dims = NC.term_dim_yx(nc_context)
    maxy = Int(dims.rows)
    maxx = Int(dims.cols)
    if maxy == scr.height && maxx == scr.width
        # No real change — still walk children in case a previous resize was
        # only partially applied, but skip the expensive refresh.
        return
    end
    scr.height = maxy
    scr.width = maxx
    for o in scr.data.objects
        try
            relayout!(o)
        catch err
            log("handle_resize! relayout failed for " * string(o) * ": " * string(err))
        end
    end
    refresh(scr)
end

function _palette_open!(scr::TwObj{TwScreenData})
    scr.data.focus == 0 && return Handled
    focused = scr.data.objects[scr.data.focus]
    bs = active_bindings(focused)
    isempty(bs) && return Handled

    # Build display strings: right-padded key label + description.
    # Users can search by key ("Ctrl-N") or by action label ("new row").
    items = [rpad(binding_keylabel(b), 16) * b.label for b in bs]

    w = min(max(44, maximum(length, items) + 6), scr.width - 4)
    h = min(length(items) + 2, scr.height - 4)

    helper = newTwPopup(
        scr, items;
        substrsearch  = true,
        hideunmatched = true,
        title         = "Command Palette",
        height        = h,
        width         = w,
        posy          = :center,
        posx          = :center,
    )
    chosen = activateTwObj(helper)
    unregisterTwObj(scr, helper)
    refresh(scr)

    chosen === nothing && return Handled
    idx = findfirst(==(chosen), items)
    idx === nothing && return Handled

    r = bs[idx].action(focused)
    r === Handled && refresh(focused)
    return r   # propagate Accept/Cancel so the screen loop closes the widget
end

function _scratchpad_open!(scr::TwObj{TwScreenData})
    panel = scr.data.scratchpad_panel
    if panel !== nothing && any(o -> o === panel, scr.data.objects)
        _dt_update_data!(panel)
        raiseTwObject(panel)
    else
        panel = newTwDictTree(
            scr, scratchpad_dict();
            title  = "Scratchpad",
            height = 30,
            width  = 60,
            posy   = :center,
            posx   = :center,
            box    = true,
        )
        panel.borderAttr = theme(:header)
        panel.data.isScratchpad = true
        scr.data.scratchpad_panel = panel
    end
    return Handled
end

function _show_pre_exit_dialog!(scr::TwObj{TwScreenData})
    panel = scr.data.scratchpad_panel
    if panel !== nothing && any(o -> o === panel, scr.data.objects)
        unregisterTwObj(scr, panel)
    end
    names = sort(collect(keys(scratchpad_dict())))
    isempty(names) && (scr.data.pre_exit_done = true; return)
    sel = newTwMultiSelect(
        scr, names;
        title = "Export to Main before exit?",
        posy  = :center,
        posx  = :center,
    )
    sel.borderAttr = theme(:header)
    sel.data.exit_disabled = true
    scr.data.pre_exit_widget = sel
    scr.data.pre_exit_done = true
    raiseTwObject(sel)
end

function inject(scr::TwObj{TwScreenData}, token)
    global rootTwScreen
    result = Ignored
    if token == :KEY_RESIZE
        handle_resize!(scr)
        return Handled
    end
    # NCOPTION_NO_QUIT_SIGHANDLERS routes Ctrl-C as a key instead of SIGINT.
    # Treat it as a global Cancel so the user can always exit the TUI.
    if token == :ctrl_c
        return Cancel
    end
    if token == :KEY_MOUSE
        (mstate, x, y, bs) = getmouse()
    end
    # Global command palette — intercepts Ctrl-P before the focused widget.
    if token == :ctrl_p && scr.data.focus != 0
        return _palette_open!(scr)
    end
    # Global scratchpad toggle — intercepts shift_F2 before the focused widget.
    if token == :shift_F2
        return _scratchpad_open!(scr)
    end
    if scr.data.focus != 0
        result = Base.invokelatest(inject, scr.data.objects[scr.data.focus], token)
        # Escape from the scratchpad panel: lower if other widgets exist, else pre-exit.
        if result == Cancel &&
           scr.data.scratchpad_panel !== nothing &&
           scr.data.objects[scr.data.focus] === scr.data.scratchpad_panel
            panel = scr.data.scratchpad_panel
            other_focusable = any(
                o -> o !== panel && o.isVisible && o.acceptsFocus,
                scr.data.objects,
            )
            if other_focusable
                lowerTwObject(panel)
            else
                _show_pre_exit_dialog!(scr)
            end
            return Handled
        end
        if result != Ignored
            return result
        end
        if token == :F1
            h = helptext(scr.data.objects[scr.data.focus])
            if h != ""
                helper = newTwViewer(
                    rootTwScreen,
                    h,
                    posy = :center,
                    posx = :center,
                    showHelp = false,
                    showLineInfo = false,
                    bottomText = "Esc to continue",
                )
                raiseTwObject(helper)
                return Handled
            end
        elseif token == :tab
            lowerTwObject(scr.data.objects[scr.data.focus])
        elseif token == :shift_tab
            raiseTwObject(scr.data.objects[1])
        end
    end

    for i = length(scr.data.objects):-1:1
        o = scr.data.objects[i]
        o.hasFocus = (i==scr.data.focus)
        if token == :KEY_MOUSE && o.isVisible
            rely, relx = screen_to_relative(o.window, y, x)
            log(@sprintf("Screen: Test mouse click on %s (r%d,c%d)", string(o), y, x))
            if 0<=relx<o.width && 0<=rely<o.height
                log("  raising it")
                raiseTwObject(o)
                result = Handled
                break
            end
        elseif o.isVisible && !o.hasFocus && o.grabUnusedKey
            result = Base.invokelatest(inject, scr.data.objects[i], token)
            if result != Ignored
                break
            end
        end
    end
    return result
end

function draw(scr::TwObj{TwScreenData})
    focused = 0
    i = length(scr.data.objects)
    while i>=1
        o = scr.data.objects[i]
        if o.isVisible
            if o.hasFocus && focused < 1
                focused = i
            end
        end
        i-=1
    end
    scr.data.focus = focused
    for (i, o) in enumerate(scr.data.objects)
        o.hasFocus = (i == focused)
        if o.isVisible
            if isa(o.window, NC.Plane) && panel_hidden(o.window)
                show_panel(o.window)
            end
            if isa(o.window, NC.Plane)
                top_panel(o.window)
            end
            draw(o)
        else
            if isa(o.window, NC.Plane) && !panel_hidden(o.window)
                hide_panel(o.window)
            end
        end
    end
end

function refresh(scr::TwObj{TwScreenData})
    focused = 0
    i = length(scr.data.objects)
    while i>=1
        o = scr.data.objects[i]
        if o.isVisible
            if o.hasFocus && focused < 1
                focused = i
            end
        else
            erase(o)
        end
        i -= 1
    end
    werase(scr.window)
    scr.data.focus = focused
    for (i, o) in enumerate(scr.data.objects)
        o.hasFocus = (i == focused)
        if o.isVisible
            if isa(o.window, NC.Plane) && panel_hidden(o.window)
                show_panel(o.window)
            end
            if isa(o.window, NC.Plane)
                top_panel(o.window)
            end
            Base.invokelatest(draw, o)
        else
            if isa(o.window, NC.Plane) && !panel_hidden(o.window)
                hide_panel(o.window)
            end
        end
    end
end

function erase(scr::TwObj{TwScreenData})
    werase(scr.window)
    for o in scr.data.objects
        erase(o)
    end
end
