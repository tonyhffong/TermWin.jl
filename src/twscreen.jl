typealias TwScreen TwObj

# bookkeeping data for a screen
type TwScreenData
    objects::Array{TwObj, 1 }
    focus::Int
    TwScreenData() = new( TwObj[], 0 )
end

# Screen is unique also in that its instantiation requires a window. It's because often we'd simply
# supply the rootwin that has already been created.
function newTwScreen( win::Ptr{Void} )
    obj = TwObj( twFuncFactory( :Screen ) )
    begy, begx = getwinbegyx( win )
    maxy, maxx = getwinmaxyx( win )

    obj.window = win
    obj.height = maxy
    obj.width = maxx
    obj.xpos = begx
    obj.ypos = begy

    obj.data = TwScreenData()
    obj.hasFocus = true
    obj.acceptsFocus = true
    obj.isVisible = true
    #wbkgdset( win, COLOR_PAIR( 15 ) | uint( '.'))
    obj
end

function registerTwObj( scr::TwScreen, o::TwObj )
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

function unregisterTwObj( scr::TwScreen, o::TwObj )
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

function setTwFocusNext( scr::TwScreen )
    n = scr.data.focus
    first = n
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
        if n == first
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

function setTwFocusPrevious( scr::TwScreen )
    n = scr.data.focus
    first = n
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
        if n == first
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

function swapTwObjIndices( scr::TwScreen, n1::Int, n2::Int )
    if n1!=n2 && 1 <= n1 <= length(scr.data.objects) && 1 <= n2 <= length( scr.data.objects )
        o1 = scr.data.objects[n1]
        o2 = scr.data.objects[n2]
        scr.data.objects[n1] = o2
        scr.data.objects[n2] = o1
        o1.screenIndex = n2
        o2.screenIndex = n1
        if scr.data.focus == n1
            scr.data.focus = n2
        elseif scr.data.focus == n2
            scr.data.focus = n1
        end
    end
end

function raiseTwObject( o::TwObj )
    scr = o.screen.value
    if scr != nothing
        swapTwObjIndices( scr, o.screenIndex, length(scr.data.objects) )
        if o.acceptsFocus
            o.hasFocus = true
            scr.data.focus = length( scr.data.objects )
        end
        top_panel( o.panel )
    end
end

function lowerTwObject( o::TwObj )
    scr = o.screen.value
    if scr != nothing
        swapTwObjIndices( scr, o.screenIndex, 1 )
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
function activateTwScreen( scr::TwScreen, tokens::Any=nothing )
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
            if focusObj == nothing
                token = readtoken( scr.window )
                status = inject( scr, token )
            else
                token = readtoken( focusObj.window )
                status = inject( focusObj, token )
            end
            if handleStatus( status, token ) == :really_exit
                return retvalue
            end
        end
    else
        for token in tokens
            update_panels()
            doupdate()
            if focusObj == nothing
                token = readtoken( scr.window )
                status = inject( scr, token )
            else
                token = readtoken( focusObj.window )
                status = inject( focusObj, token )
            end
            if handleStatus( status, token ) == :really_exit
                return retvalue
            end
        end
        # exhausted all the tokens, no obvious response
        return nothing
    end
end

function injectTwScreen( scr::TwScreen )
    result = :pass
    if scr.data.focus != 0
        result = inject( scr.data.objects[ scr.data.focus] )
        if result != :pass
            return result
        end
    end

    for i in length( scr.data.objects ) : -1 : 1
        o = scr.data.objects[i]
        o.hasFocus = (i==scr.data.focus)
        if o.isVisible && !o.hasFocus && o.grabUnusedKey
            result = inject( scr.data.objects[i] )
            if result != :pass
                break
            end
        end
    end
    return result
end

function drawTwScreen( scr::TwScreen )
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

function refreshTwScreen( scr::TwScreen )
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

function eraseTwScreen( scr::TwScreen )
    werase( scr.window )
    for o in scr.data.objects
        erase( o )
    end
end
