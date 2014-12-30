# horizontal or vertical array of widgets
# nestable. But the top-most List handles the canvas navigation

# Every time a nesting layer is added, all the children's windows have to be redone,
# to reflect their locations in the main pad.
# This is bad!

using Lazy

type TwListData
    horizontal::Bool
    widgets::Array{TwObj,1} # this is static.
    focus::Int # which of the widgets has the focus
    canvasheight::Int
    canvaswidth::Int
    pad::Union( Nothing, Ptr{Void} ) # nothing, or Ptr{Void} to the WINDOW from calling newpad()
    canvaslocx::Int # 0-based, view's location on canvas
    canvaslocy::Int # 0-based
    showLineInfo::Bool
    function TwListData()
        ret = new( false, TwObj[], 0, 0, 0, nothing, 0, 0, false )
        finalizer( ret, y->begin
            if y.pad != nothing
                delwin( y.pad )
            end
        end)
        ret
    end
end

function newTwList( scr::TwScreen,
        h::Real, w::Real,
        y::Any, x::Any;
        canvasheight = 80,
        canvaswidth = 128,
        box=true,
        horizontal=false,
        title="",
        showLineInfo=true)
    obj = TwObj( TwListData(), Val{:List } )
    registerTwObj( scr, obj )
    obj.box = box
    obj.title = title
    obj.borderSizeV= box ? 1 : 0
    obj.borderSizeH= box ? 2 : 0
    obj.data.horizontal = horizontal
    obj.data.showLineInfo = showLineInfo
    obj.data.canvasheight = canvasheight
    obj.data.canvaswidth = canvaswidth

    alignxy!( obj, h, w, x, y )
    configure_newwinpanel!( obj )
    obj.data.pad = newpad( obj.data.canvasheight, obj.data.canvaswidth )
    obj
end

function push_widget!( o::TwObj{TwListData}, w::TwObj )
    global rootwin
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
    unregisterTwObj( o.screen.value, w )
    if typeof( w.window ) <: Ptr && w.window != rootwin
        delwin( w.window ) # so we don't leak memory
    end

    # by the time a list is being added, its contents must be fully populated
    if objtype( w ) == :List
        if typeof( w.data.pad ) <: Ptr && w.data.pad != o.data.pad # the list has its own pad, get rid of it.
            delwin( w.data.pad )
        end
        update_list_canvas( w )
        w.height = w.data.canvasheight
        w.width = w.data.canvaswidth
        w.data.pad = nothing
    end

    w.window = TwWindow( WeakRef( o ), begy, begx, w.height, w.width )
    push!( o.data.widgets, w )
    w.hasFocus = false
end

function update_list_canvas( o::TwObj{TwListData} )
    ws = o.data.widgets
    if isempty( ws )
        # TODO: reconsider this
        o.data.canvasheight = 80
        o.data.canvaswidth = 128
    else
        if o.data.horizontal
            o.data.canvasheight = maximum( map( _->objtype(_)==:List? _.data.canvasheight : _.height, ws ) )
            o.data.canvaswidth = sum( map( _->objtype(_)==:List? _.data.canvaswidth : _.width, ws ) )
        else
            o.data.canvasheight = sum( map( _->objtype(_)==:List? _.data.canvasheight: _.height, ws ) )
            o.data.canvaswidth = maximum( map( _->objtype(_)==:List? _.data.canvaswidth : _.width, ws ) )
        end
    end
end

function draw( o::TwObj{TwListData} )
    if typeof( o.window ) <: Ptr
        set_default_focus( o )
    end

    for w in o.data.widgets
        # TODO: no need to draw widget outside visible range? or just draw everything?
        if w.isVisible
            draw( w )
        end
    end
    # handle pushing the canvas to the screen if it is the root list
    if typeof( o.window ) <: Ptr
        if o.box
            box( o.window, 0, 0 )
        end
        #TODO: how much of the canvas are we showing?
        borderSizeH = o.box ? 1 : 0
        borderSizeV = o.box ? 1 : 0
        contentheight = o.height - borderSizeV*2
        contentwidth  = o.width  - borderSizeH*2
        canvasheight = o.data.canvasheight
        canvaswidth  = o.data.canvaswidth
        copywin( o.data.pad, o.window, o.data.canvaslocy, o.data.canvaslocx,
            borderSizeV, borderSizeH,
            min( contentheight-1, canvasheight - o.data.canvaslocy - 1),
            min( contentwidth -1, canvaswidth  - o.data.canvaslocx - 1) )
    end
end

function lowest_widget( o::TwObj{ TwListData } )
    if o.data.focus == 0
        error( "cannot locate focused widget")
    end
    w = o.data.widgets[ o.data.focus ]
    if objtype( w ) == :List
        return lowest_widget( w )
    else
        return w
    end
end

function lowest_widget_location_area( o::TwObj{ TwListData }, y::Int=0, x::Int=0 )
    if o.data.focus == 0
        error( "cannot locate focused widget")
    end
    w = o.data.widgets[ o.data.focus ]
    if objtype( w ) == :List
        return lowest_widget_location_area( w, y+w.window.yloc, x+w.window.xloc )
    else
        return ( w, y+w.window.yloc, x+w.window.xloc, w.window.height, w.window.width )
    end
end

function ensure_visible_on_canvas( o::TwObj )
    h = o.height
    w = o.width
    y = o.window.yloc
    x = o.window.xloc
    win = o.window
    par = win.parent.value
    while( !(typeof( win.parent.value.window) <: Ptr) )
        y += win.parent.value.window.yloc
        x += win.parent.value.window.xloc
        par = win.parent.value
        win = win.parent.value.window
    end
    @assert objtype( par ) == :List
    contentwidth = par.width - (par.box?2:0)
    contentheight = par.height - (par.box?2:0)

    if par.data.canvaslocx < x
        par.data.canvaslocx = x
    end
    if par.data.canvaslocx + contentwidth > x + w
        par.data.canvaslocx = max(0,x + w - contentwidth)
    end
    if par.data.canvaslocy < y
        par.data.canvaslocy = y
    end
    if par.data.canvaslocy + contentheight > y + h
        par.data.canvaslocy = max(0,y + h - contentheight)
    end
end

function inject( o::TwObj{TwListData}, token::Any )
    retcode = :pass
    dorefresh = false
    isrootlist = typeof( o.window ) <: Ptr
    focus = o.data.focus
    if focus == 0
        return :pass
    end

    if token == :esc
        return :exit_nothing
    end

    result = inject( o.data.widgets[ focus], token )
    if result != :pass
        refresh(o)
        return result
    end

    function check_accept_focus(w::TwObj,stepsign::Int)
        if w.isVisible && w.acceptsFocus
            if objtype(w) == :List
                r = 1:length(w.data.widgets)
                if stepsign == -1
                    r = reverse(r)
                end
                for i in r
                    if check_accept_focus(w.data.widgets[i], stepsign )
                        return true
                    end
                end
                return false
            else
                ensure_visible_on_canvas( w )
                return true
            end
        end
        return false
    end

    # TODO: what's the behavior of :esc
    # TODO: what's the behavior of :exit_ok
    # TODO: arrow keys: manhattan distance
    # TODO: mouse: manhattan distance
    if token in [ :tab, :shift_tab ]
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
            i = mod1(focus + stp,length(o.data.widgets) )
            while (i != focus)
                w = o.data.widgets[i]
                if check_accept_focus(w,stp)
                    deep_unfocus( prevw )
                    deep_focus( w, stp == -1 ) # 2nd arg is reverse
                    retcode = :got_it
                    break
                end
                i = mod1(i+ stp,length(o.data.widgets))
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
                if check_accept_focus(w,stp)
                    deep_unfocus( prevw )
                    deep_focus( w, stp == -1 ) # 2nd arg is reverse
                    retcode = :got_it
                    break
                end
            end
        end
    elseif token in [ :left, :right, :up, :down,
        :ctrl_left, :ctrl_right, :ctrl_up, :ctrl_down ] && isrootlist
        # find the location of the current focus
        (w, yloc,xloc, height, width) = lowest_widget_location_area( o )
        if token in [ :up, :ctrl_up ]
            distfunc = function( to::(Int,Int,Int,Int) )
                updown_arrow_distance( to, (yloc,xloc,height,width), 1 )
            end
        elseif token in [ :down, :ctrl_down ]
            distfunc = function( to::(Int,Int,Int,Int) )
                updown_arrow_distance( to, (yloc,xloc,height,width), -1 )
            end
        elseif token in [ :left, :ctrl_left ]
            distfunc = function( to::(Int,Int,Int,Int) )
                leftright_arrow_distance( to, (yloc,xloc,height,width), 1 )
            end
        else
            distfunc = function( to::(Int,Int,Int,Int) )
                leftright_arrow_distance( to, (yloc,xloc,height,width), -1 )
            end
        end
        wdists = Any[]
        geometric_filter( o, distfunc, 0, 0, wdists, true, 40 )
        candidate = nothing
        mindist = 999999
        for (cw,dist) in wdists
            if dist < mindist
                candidate = cw
                mindist = dist
            end
        end
        if candidate != nothing
            deep_unfocus( w )
            deep_focus( candidate )
            dorefresh = true
            retcode = :got_it
        end
    end

    if dorefresh
        refresh( o )
    end
    return retcode
end

function deep_unfocus( w::TwObj )
    tmpw = w
    while typeof( tmpw ) <: TwObj{ TwListData }
        focus = tmpw.data.focus
        tmpw2 = tmpw.data.widgets[focus]
        tmpw.data.focus = 0
        tmpw2.hasFocus = false
        tmpw = tmpw2
    end

    par::TwObj{TwListData}
    w.hasFocus = false
    tmpw = w
    @oncethen while( !( typeof( tmpw.window ) <: Ptr ) )
        par = tmpw.window.parent.value
        par.data.focus = 0
        par.hasFocus = false
        tmpw = par
    end
end

function set_default_focus( w::TwObj{TwListData}, rev=false )
    if w.data.focus == 0 && !isempty( w.data.widgets )
        if rev
            w.data.focus = length(w.data.widgets)
        else
            w.data.focus = 1
        end

        subw = w.data.widgets[w.data.focus]
        subw.hasFocus = true
        if typeof( subw ) <: TwObj{TwListData}
            set_default_focus( subw, rev )
        end
    end
end

function deep_focus( w::TwObj, rev=false )
    par::TwObj{TwListData}
    w.hasFocus = true
    if objtype(w) == :List
        set_default_focus( w, rev )
    end
    tmpw = w
    @oncethen while( !( typeof( tmpw.window ) <: Ptr ) )
        par = tmpw.window.parent.value
        for (i,c) in enumerate( par.data.widgets )
            if c == tmpw
                par.data.focus = i
                par.hasFocus = true
                tmpw = par
                break
            end
        end
        @assert par.data.focus != 0
        @assert par.hasFocus
    end
end

function geometric_filter( o::TwObj{TwListData}, distfunc::Function,
        y::Int, x::Int, list::Array, excludezero::Bool=false, cutoff::Int=100 )
    for w in o.data.widgets
        if objtype( w ) == :List
            geometric_filter( w, distfunc, y+w.window.yloc, x+w.window.xloc,
                list, excludezero, cutoff )
        elseif w.isVisible && w.acceptsFocus
            to = ( y+w.window.yloc, x+w.window.xloc, w.window.height, w.window.width )
            dist = distfunc( to )
            if dist > cutoff || dist == 0 && excludezero
                continue
            end
            push!( list, (w, dist) )
        end
    end
end

function updown_arrow_distance( to::(Int,Int,Int,Int), from::(Int,Int,Int,Int), sgn::Int )
    tocentx = to[2] + to[4] >> 1
    tocenty = to[1] + to[3] >> 1

    fromcentx = from[2] + from[4] >> 1
    fromcenty = from[1] + from[3] >> 1

    if sgn*tocenty >= sgn*fromcenty
        return 99999
    end

    ret = (fromcenty - tocenty)*sgn

    if from[2] > tocentx
        ret += ( from[2] - tocentx ) * 5
    elseif tocentx >= from[2]+from[4]
        ret += (tocentx - (from[2]+from[4])+1) * 5
    end
    return ret
end

function leftright_arrow_distance( to::(Int,Int,Int,Int), from::(Int,Int,Int,Int),sgn::Int )
    tocentx = to[2] + to[4] >> 1
    tocenty = to[1] + to[3] >> 1

    fromcentx = from[2] + from[4] >> 1
    fromcenty = from[1] + from[3] >> 1

    if sgn*tocentx >= sgn*fromcentx
        return 99999
    end

    ret = (fromcentx - tocentx)*sgn

    if from[1] > tocenty
        ret += ( from[1] - tocenty ) * 5
    elseif tocenty >= from[1]+from[3]
        ret += (tocenty - (from[1]+from[3])+1) * 5
    end
    return ret
end

# used for mouse click
# inside the area it returns zero, otherwise it's manhattan distance to the boundary
function point_from_area( y::Int, x::Int, from::(Int,Int,Int,Int) )
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
