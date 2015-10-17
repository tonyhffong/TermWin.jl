# horizontal or vertical array of widgets
# nestable. But the top-most List handles the canvas navigation

# Every time a nesting layer is added, all the children's windows have to be redone,
# to reflect their locations in the main pad.
# This is bad!

using Lazy

function newTwList( scr::TwObj;
        height::Real = 25, width::Real = 80,
        posy::Any = :center, posx::Any = :center,
        canvasheight = 80,
        canvaswidth = 128,
        box=true,
        horizontal=false,
        title=utf8(""),
        showLineInfo=true)
    obj = TwObj( TwListData(), Val{:List } )
    obj.box = box
    obj.title = title
    obj.borderSizeV= box ? 1 : 0
    obj.borderSizeH= box ? 1 : 0
    obj.data.horizontal = horizontal
    obj.data.showLineInfo = showLineInfo
    obj.data.canvasheight = canvasheight
    obj.data.canvaswidth = canvaswidth

    link_parent_child( scr, obj, height,width,posy,posx )
    if objtype( scr ) == :Screen
        obj.data.pad = newpad( obj.data.canvasheight, obj.data.canvaswidth )
    end
    obj
end

# move a fully formed widget into this list. need more bookkeeping
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
        # TODO: is this necessary?
        for w in o.data.widgets
            if objtype( w ) == :List
                update_list_canvas(w)
            end
        end
        if o.data.horizontal
            o.data.canvasheight = maximum( map( _->objtype(_)==:List? _.data.canvasheight : _.height, ws ) )
            o.data.canvaswidth = sum( map( _->objtype(_)==:List? _.data.canvaswidth : _.width, ws ) )
        else
            o.data.canvasheight = sum( map( _->objtype(_)==:List? _.data.canvasheight: _.height, ws ) )
            o.data.canvaswidth = maximum( map( _->objtype(_)==:List? _.data.canvaswidth : _.width, ws ) )
        end
        if !(typeof( o.window ) <: Ptr)
            o.height = o.data.canvasheight + (o.box?2:0)
            o.width = o.data.canvaswidth + (o.box?2:0)
        end
    end
    if o.data.pad != nothing
        delwin( o.data.pad )
        o.data.pad = newpad( o.data.canvasheight, o.data.canvaswidth )
    end
end

function draw( o::TwObj{TwListData} )
    werase( o.window ) # this is important, or attributes on the pad may be lost

    if typeof( o.window ) <: Ptr
        set_default_focus( o )
        viewContentHeight = o.height - 2*o.borderSizeV
        viewContentWidth  = o.width - 2*o.borderSizeH
        if o.box
            if o.data.navigationmode
                wattron( o.window, COLOR_PAIR( 12 ) )
            end

            box( o.window, 0, 0 )

            if o.data.showLineInfo
                if o.data.canvasheight <= viewContentHeight
                    vscale = "v:all"
                else
                    vscale = @sprintf( "v:%d/%d", o.data.canvaslocy, o.data.canvasheight )
                end

                if o.data.canvaswidth <= viewContentWidth
                    hscale = "h:all"
                else
                    hscale = @sprintf( "h:%d/%d", o.data.canvaslocx, o.data.canvaswidth )
                end

                msg = vscale * " " * hscale
                mvwprintw( o.window, 0, o.width - length( msg ) - 3, "%s", msg )
            end

            if o.data.bottomText != ""
                mvwprintw( o.window, o.height-1, 2, "%s", o.data.bottomText )
            end

            if o.data.navigationmode
                mvwprintw( o.window, 0, 2, "%s", "Navigation mode" )
                wattroff( o.window, COLOR_PAIR( 12 ) )
            end
        end
    end

    for w in o.data.widgets
        # TODO: no need to draw widget outside visible range? or just draw everything?
        if w.isVisible
            draw( w )
        end
    end
    # handle pushing the canvas to the screen if it is the root list
    if typeof( o.window ) <: Ptr
        #TODO: how much of the canvas are we showing?
        borderSizeH = o.box ? 1 : 0
        borderSizeV = o.box ? 1 : 0
        contentheight = o.height - borderSizeV*2
        contentwidth  = o.width  - borderSizeH*2
        canvasheight = o.data.canvasheight
        canvaswidth  = o.data.canvaswidth
        copywin( o.data.pad, o.window, o.data.canvaslocy, o.data.canvaslocx,
            borderSizeV, borderSizeH,
            min( contentheight, canvasheight - o.data.canvaslocy),
            min( contentwidth , canvaswidth  - o.data.canvaslocx) )
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
    log( @sprintf( "ensure %s is visible", string( o ) ) )
    log( @sprintf( "  init local y,x: %d %d", y, x ) )
    win = o.window
    par = win.parent.value
    while( !(typeof( win.parent.value.window) <: Ptr) )
        y += win.parent.value.window.yloc
        x += win.parent.value.window.xloc
        par = win.parent.value
        win = win.parent.value.window
    end
    par = win.parent.value
    log( @sprintf( "  actual coord y,x: %d %d", y, x ) )
    @assert objtype( par ) == :List
    contentwidth = par.width - (par.box?2:0)
    contentheight = par.height - (par.box?2:0)
    log( @sprintf( "  canvas size     : %d %d", par.data.canvasheight, par.data.canvaswidth ) )
    log( @sprintf( "  window geom     : %d %d", contentheight, contentwidth ) )
    log( @sprintf( "  canvas wind.orig: %d %d", par.data.canvaslocy, par.data.canvaslocx) )

    if par.data.canvaslocx > x
        par.data.canvaslocx = x
    end
    if par.data.canvaslocy > y
        par.data.canvaslocy = y
    end
    if x + w - par.data.canvaslocx > contentwidth
        par.data.canvaslocx = max( 0, x + w - contentwidth )
    end
    if y + h - par.data.canvaslocy > contentheight
        par.data.canvaslocy = max( 0, y + h - contentheight )
    end
    if par.data.canvaslocx > par.data.canvaswidth - contentwidth
        par.data.canvaslocx = max(0,par.data.canvaswidth - contentwidth)
    end
    if par.data.canvaslocy > par.data.canvasheight - contentheight
        par.data.canvaslocy = max(0,par.data.canvasheight- contentheight)
    end
    log( @sprintf( "  canvas  new orig: %d %d", par.data.canvaslocy, par.data.canvaslocx) )
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

    if !o.data.navigationmode
        result = inject( o.data.widgets[ focus], token )
        if result != :pass
            refresh(o)
            return result
        end
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
                return true
            end
        end
        return false
    end

    # TODO: what's the behavior of :esc
    # TODO: what's the behavior of :exit_ok
    if !o.data.navigationmode && token in [ :tab, :shift_tab ]
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
    elseif !o.data.navigationmode && token in [ :left, :right, :up, :down,
        :ctrl_left, :ctrl_right, :ctrl_up, :ctrl_down ] && isrootlist
        # find the location of the current focus
        (w, yloc,xloc, height, width) = lowest_widget_location_area( o )
        if token in [ :up, :ctrl_up ]
            distfunc = function( to::Tuple{Int,Int,Int,Int} )
                updown_arrow_distance( to, (yloc,xloc,height,width), 1 )
            end
        elseif token in [ :down, :ctrl_down ]
            distfunc = function( to::Tuple{Int,Int,Int,Int} )
                updown_arrow_distance( to, (yloc,xloc,height,width), -1 )
            end
        elseif token in [ :left, :ctrl_left ]
            distfunc = function( to::Tuple{Int,Int,Int,Int} )
                leftright_arrow_distance( to, (yloc,xloc,height,width), 1 )
            end
        else
            distfunc = function( to::Tuple{Int,Int,Int,Int} )
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
    elseif o.data.navigationmode && token in [ :left, :right]
        if token == :left
            xstep = -1
        elseif token == :right
            xstep = 1
        end
        newlocx = o.data.canvaslocx + xstep
        if newlocx < 0
            o.data.canvaslocx = 0
        elseif newlocx + o.width - o.borderSizeH*2 >= o.data.canvaswidth
            o.data.canvaslocx = max(0, o.data.canvaswidth - o.width + o.borderSizeH*2 )
        else
            o.data.canvaslocx = newlocx
        end
        dorefresh = true
    elseif o.data.navigationmode && token in [ :up, :down, :pageup, :pagedown ]
        # the canvas location can move by one screen-size in either direction
        # but it's kept in by the maximum canvas sizes
        # also, focus would change to the new one closest to the current focused widget
        if token == :up
            ystep = -1
        elseif token == :down
            ystep = 1
        elseif token == :pageup
            ystep = -( o.height - o.borderSizeV*2 )
        elseif token == :pagedown
            ystep = ( o.height - o.borderSizeV*2 )
        end
        newlocy = o.data.canvaslocy + ystep
        if newlocy < 0
            o.data.canvaslocy = 0
        elseif newlocy + o.height - o.borderSizeV*2 >= o.data.canvasheight
            o.data.canvaslocy = max(0, o.data.canvasheight - o.height+ o.borderSizeV*2 )
        else
            o.data.canvaslocy = newlocy
        end
        dorefresh = true
    elseif token == :KEY_MOUSE && isrootlist
        (mstate, x, y, bs ) = getmouse()
        if mstate == :button1_pressed
            (rely, relx) = screen_to_relative( o.window, y, x )
            if 0<=relx<o.width && 0<=rely<o.height
                rely -= o.borderSizeV
                relx -= o.borderSizeH
                # find the closest widget
                distfunc = function( to::Tuple{Int,Int,Int,Int} )
                    point_from_area( rely, relx, to )
                end
                wdists = Any[]
                geometric_filter( o, distfunc, 0, 0, wdists, false, 40 )
                candidate = nothing
                mindist = 999999
                for (cw,dist) in wdists
                    if dist < mindist
                        candidate = cw
                        mindist = dist
                    end
                end
                if candidate != nothing
                    w = lowest_widget( o )
                    deep_unfocus( w )
                    deep_focus( candidate )
                    dorefresh = true
                    retcode = :got_it
                    o.data.navigationmode = false
                end
            else
                retcode = :pass
            end
        end
    elseif token == :ctrl_F4 && isrootlist
        o.data.navigationmode = !o.data.navigationmode
        # if no longer in navigationmode
        # switch focus to the closest visible widget (% overlap with visible window makes a big difference)
        # partially visible widgets suffer a substantial penalty
        if !o.data.navigationmode
            (w, yloc,xloc, height, width) = lowest_widget_location_area( o )
            canvaslocx = o.data.canvaslocx
            canvaslocy = o.data.canvaslocy
            canvaslocx2 = o.data.canvaslocx + o.width - o.borderSizeH*2
            canvaslocy2 = o.data.canvaslocy + o.height - o.borderSizeV*2
            distfunc = function( to::Tuple{Int,Int,Int,Int} )
                # a = area of the candidate box
                # aOverlap = area overlap between candidate box and the canvas window
                # d = distance between the candidate box and the current box's center
                # final distance = D * A / (AOverlap + epsilon)
                a = to[3]*to[4]
                aOverlap = max( 0, min( to[2] + to[4], canvaslocx2 )-max( to[2], canvaslocx ) ) *
                    max( 0, min( to[1] + to[3], canvaslocy2 )-max( to[1], canvaslocy ) )
                d = point_from_area( yloc + height >> 1, xloc + width >> 1, to )
                if aOverlap == 0 # this this the best way to do effective distance?
                    return d + 1000
                else
                    return d + a / aOverlap
                end
            end
            wdists = Any[]
            geometric_filter( o, distfunc, 0, 0, wdists, false, 2000 )
            candidate = nothing
            mindist = 999999
            for (cw,dist) in wdists
                if dist < mindist
                    candidate = cw
                    mindist = dist
                end
            end
            if candidate != nothing
                w = lowest_widget( o )
                deep_unfocus( w )
                deep_focus( candidate )
            end
        end
        dorefresh = true
        retcode = :got_it
    elseif token == :F1 && isrootlist
        helper = newTwViewer( o.screen.value, helptext( o ), posy=:center, posx=:center, showHelp=false, showLineInfo=false, bottomText = "Esc to continue" )
        activateTwObj( helper )
        unregisterTwObj( o.screen.value, helper )
        dorefresh = true
        retcode = :got_it
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

    local par::TwObj{TwListData}
    w.hasFocus = false
    inject(w, :focus_off)
    if tmpw != w
        inject( tmpw, :focus_off )
    end
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
        else
            ensure_visible_on_canvas( subw )
        end
    end
end

function deep_focus( w::TwObj, rev=false )
    local par::TwObj{TwListData}
    w.hasFocus = true
    if objtype(w) == :List
        set_default_focus( w, rev )
    else
        ensure_visible_on_canvas( w )
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

function updown_arrow_distance( to::(@compat Tuple{Int,Int,Int,Int}), from::(@compat Tuple{Int,Int,Int,Int}), sgn::Int )
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

function leftright_arrow_distance( to::(@compat Tuple{Int,Int,Int,Int}), from::(@compat Tuple{Int,Int,Int,Int}),sgn::Int )
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
function point_from_area( y::Int, x::Int, from::(@compat Tuple{Int,Int,Int,Int}) )
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

function helptext( o::TwObj{TwListData} )
    focus = o.data.focus
    isrootlist = typeof( o.window ) <: Ptr
    if focus == 0
        return utf8("")
    end
    s = helptext( o.data.widgets[ focus ] )
    if isrootlist
h = utf8("""
ctrl-F4 : toggle navigation mode
mouse-click: activate nearest widget
ctrl-arrows: directional focus movements
  (normal arrows work too if not consumed by the current widget)
tab/shift-tab: cycle through all widgets
""")
        if s == "" # just the navigation text
            s = h
        else # merge the help text into a single window
            s *= "\n"* ("—"^7) * " canvas navigation " * ("—"^7) * "\n"* h
        end
    end
    s
end
