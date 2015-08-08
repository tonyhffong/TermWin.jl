# bookkeeping data for a screen

# Screen is unique also in that its instantiation requires a window. It's because often we'd simply
# supply the rootwin that has already been created.
function newTwScreen( win::Ptr{Void} )
    obj = TwObj( TwScreenData(), Val{ :Screen } )
    begy, begx = getwinbegyx( win )
    maxy, maxx = getwinmaxyx( win )

    obj.window = win
    obj.height = maxy
    obj.width = maxx
    obj.xpos = begx
    obj.ypos = begy

    obj.hasFocus = true
    obj.acceptsFocus = true
    obj.isVisible = true
    #wbkgdset( win, COLOR_PAIR( 15 ) | @compat UInt( '.'))
    obj
end

function registerTwObj( scr::TwObj{TwScreenData}, o::TwObj )
    if o.screen.value != nothing
        if o.screen.value == scr
            return
        end
        unregisterTwObj( o.screen.value, o )
    end
    push!( scr.data.objects, o )
    o.screenIndex = length(scr.data.objects)
    o.screen = WeakRef( scr )
end

function unregisterTwObj( scr::TwObj{TwScreenData}, o::TwObj )
    if o.screen.value != scr
        throw( "unregister obj that doesn't belong to the screen")
    end
    idx = o.screenIndex
    deleteat!( scr.data.objects, idx )
    if o.panel != nothing
        hide_panel( o.panel )
    end
    for i in idx:length( scr.data.objects )
        scr.data.objects[i].screenIndex = i
    end
    if scr.data.focus >= idx
        scr.data.focus -= 1
    end
    if scr.data.focus == idx
        setTwFocusNext( scr )
    end
    o.screen = WeakRef()
end

function setTwFocusNext( scr::TwObj{TwScreenData})
    n = scr.data.focus
    fst = n
    result = nothing
    while true
        n +=1
        if n > length(scr.data.objects)
            n = 1
        end
        o = scr.data.objects[ n ]
        if o.acceptsFocus
            result = o
            break
        end
        if n == fst
            break
        end
    end
    if result != nothing
        scr.data.focus = n
    else
        scr.data.focus = 0
    end
    return result
end

function setTwFocusPrevious( scr::TwObj{TwScreenData} )
    n = scr.data.focus
    fst = n
    result = nothing
    while true
        n -=1
        if n <= 0
            n = length( scr.data.objects )
        end
        o = scr.data.objects[ n ]
        if o.acceptsFocus
            result = o
            break
        end
        if n == fst
            break
        end
    end
    if result != nothing
        scr.data.focus = n
    else
        scr.data.focus = 0
    end
    return result
end

function swapTwObjIndices( scr::TwObj{TwScreenData}, n1::Int, n2::Int )
    if n1!=n2 && 1 <= n1 <= length(scr.data.objects) && 1 <= n2 <= length( scr.data.objects )
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

function raiseTwObject( o::TwObj )
    log( "Raise: " * string( o ) )
    scr = o.screen.value
    if scr != nothing
        si = o.screenIndex
        deleteat!( scr.data.objects, si )
        push!( scr.data.objects, o )
        for i in si:length( scr.data.objects )
            scr.data.objects[i].screenIndex = i
            scr.data.objects[i].hasFocus = false
        end
        o.hasFocus = true
        scr.data.focus = length( scr.data.objects )
        refresh( o )
        top_panel( o.panel )
    end
end

function lowerTwObject( o::TwObj )
    log( "Lower: " * string( o ) )
    scr = o.screen.value
    if scr != nothing
        si = o.screenIndex
        deleteat!( scr.data.objects, si )
        unshift!( scr.data.objects, o )
        for i in 1:length( scr.data.objects )
            scr.data.objects[i].screenIndex = i
            scr.data.objects[i].hasFocus = false
        end
        scr.data.objects[end].hasFocus = true
        scr.data.focus = length( scr.data.objects )
        refresh( o )
        bottom_panel( o.panel )
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
function activateTwObj( scr::TwObj{TwScreenData}, tokens::Any=nothing )
    # consume one token, this also makes sure the readtoken function is jitted
    #=
    if tokens == nothing
        readtoken( scr.window )
    end
    =#
    refresh(scr) # clear any potential wait message
    focusObj = nothing
    focusIdx = scr.data.focus
    retvalue = nothing

    if focusIdx > 0 && focusIdx <= length( scr.data.objects )
        focusObj = scr.data.objects[ focusIdx ]
    end

    handleStatus = (st, tok)->begin
        focusIdx = scr.data.focus
        if focusIdx > 0 && focusIdx <= length( scr.data.objects )
            focusObj = scr.data.objects[ focusIdx ]
        else
            focusObj = nothing
        end
        if st== :exit_ok || st== :exit_nothing
            if st== :exit_ok
                retvalue = scr.value
            end
            if focusObj != nothing
                unregisterTwObj( scr, focusObj )
                # find the next focusObj, if not found, just return
                # otherwise, make it the new focus and continue
                focusObj = nothing
                for i in length( scr.data.objects ) :-1: 1
                    o = scr.data.objects[i]
                    if o.isVisible && o.acceptsFocus
                        focusObj = o
                        o.hasFocus = true
                        scr.data.focus = i
                        refresh( o )
                        break
                    end
                end
            end
            if focusObj == nothing
                return :really_exit
            end
        elseif st == :pass
            if focusObj != nothing
                i = length( scr.data.objects )
                while( st == :pass && i >= 1 )
                    o = scr.data.objects[i]
                    if o!=focusObj && o.isVisible && o.grabUnusedKey
                        st = inject( o, tok )
                    end
                    i -= 1
                end
                if st == :exit_ok || st == :exit_nothing
                    return :really_exit
                end
            end
        end
    end

    if tokens == nothing
        while true
            update_panels()
            doupdate()
            token = readtoken( scr.window )
            status = inject( scr, token )

            for o in scr.data.objects
                global twGlobProgressData
                if objtype(o) == :Progress && isready( twGlobProgressData.statusChannel )
                    inject( o, :progressupdate )
                end
            end

            if handleStatus( status, token ) == :really_exit
                return retvalue
            end
            sleep(0.01) # this is important or @async task won't run
        end
    else
        for token in tokens
            update_panels()
            doupdate()
            token = readtoken( scr.window )
            status = inject( scr, token )
            if handleStatus( status, token ) == :really_exit
                return retvalue
            end
        end
        # exhausted all the tokens, no obvious response
        return nothing
    end
end

function inject( scr::TwObj{TwScreenData}, token )
    global rootTwScreen
    result = :pass
    if token == :KEY_MOUSE
        (mstate, x,y,bs ) = getmouse()
    end
    if scr.data.focus != 0
        result = inject( scr.data.objects[ scr.data.focus], token )
        if result != :pass
            return result
        end
        if token == :F1
            h = helptext( scr.data.objects[ scr.data.focus ] )
            if h != ""
                helper = newTwViewer( rootTwScreen, h, posy= :center, posx=:center, showHelp=false, showLineInfo=false, bottomText = "Esc to continue" )
                activateTwObj( helper )
                unregisterTwObj( rootTwScreen, helper )
                return :got_it
            end
        elseif token == :tab
            lowerTwObject(scr.data.objects[ scr.data.focus ])
        elseif token == :shift_tab
            raiseTwObject(scr.data.objects[1])
        end
    end

    for i in length( scr.data.objects ) : -1 : 1
        o = scr.data.objects[i]
        o.hasFocus = (i==scr.data.focus)
        if token == :KEY_MOUSE && o.isVisible
            rely,relx = screen_to_relative( o.window, y, x )
            log( @sprintf( "Screen: Test mouse click on %s (r%d,c%d)", string( o ), y, x ) )
            if 0<=relx<o.width && 0<=rely<o.height
                log( "  raising it" )
                raiseTwObject( o )
                result = :got_it
                break
            end
        elseif o.isVisible && !o.hasFocus && o.grabUnusedKey
            result = inject( scr.data.objects[i], token )
            if result != :pass
                break
            end
        end
    end
    return result
end

function draw( scr::TwObj{TwScreenData} )
    focused = 0
    i = length( scr.data.objects )
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
    for (i,o) in enumerate( scr.data.objects )
        o.hasFocus = (i == focused)
        if o.isVisible
            if panel_hidden( o.panel )
                show_panel( o.panel )
            end
            top_panel( o.panel )
            draw( o )
        else
            if !panel_hidden( o.panel )
                hide_panel( o.panel )
            end
        end
    end
end

function refresh( scr::TwObj{TwScreenData} )
    focused = 0
    i = length( scr.data.objects )
    while i>=1
        o = scr.data.objects[i]
        if o.isVisible
            if o.hasFocus && focused < 1
                focused = i
            end
        else
            erase( o )
        end
        i -= 1
    end
    werase( scr.window )
    scr.data.focus = focused
    for (i,o) in enumerate( scr.data.objects )
        o.hasFocus = (i == focused)
        if o.panel == nothing
            throw( string( o ) * " has unset panel. Check its constructor." )
        end
        if o.isVisible
            if panel_hidden( o.panel )
                show_panel( o.panel )
            end
            top_panel( o.panel )
            draw( o )
        else
            if !panel_hidden( o.panel )
                hide_panel( o.panel )
            end
        end
    end
end

function erase( scr::TwObj{TwScreenData} )
    werase( scr.window )
    for o in scr.data.objects
        erase( o )
    end
end
