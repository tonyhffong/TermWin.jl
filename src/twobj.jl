# default behavior, dummy behavior, and convenient functions for all widgets

widgetStaggerPosx = 0
widgetStaggerPosy = 0

# only use these inside widget constructor, when their states are
# not yet fully formed.
function link_parent_child( p::TwObj{TwScreenData}, c::TwObj, height::Real, width::Real, posy::Any, posx::Any )
    registerTwObj( p, c )
    alignxy!( c, height,width,posx,posy, parent= p )
    configure_newwinpanel!( c )
    log( "Screen-"*string(objtype(c))*": x=" * string(c.xpos) * " y=" * string(c.ypos) )
end

function link_parent_child( p::TwObj{TwListData}, c::TwObj, height::Real, width::Real, posy::Any, posx::Any )
    @lintpragma( "Ignore unused height")
    @lintpragma( "Ignore unused width")
    @lintpragma( "Ignore unused posy")
    @lintpragma( "Ignore unused posx")
    update_list_canvas( p )
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

    @assert c.screen.value == nothing
    @assert c.window == nothing

    # by the time a list is being added, its contents must be fully populated
    if objtype( c ) == :List
        @assert c.data.pad == nothing
        update_list_canvas( c )
        height = c.data.canvasheight
        width = c.data.canvaswidth
    end
    push!( p.data.widgets, c )
    update_list_canvas(p)
    alignxy!( c, height,width,begx,begy, parent= p )
    c.hasFocus = false
    c.window = TwWindow( WeakRef( p ), c.ypos, c.xpos, c.height, c.width )
    log( "List-"*string(objtype(c))*": x=" * string(c.xpos) * " y=" * string(c.ypos) )
    log( " orig begxy: x="*string(begx) * " y=" * string(begy) )
    log( " new geom: h=" *string(p.height)*" w=" * string(p.width) )
end

function link_parent_child( p::TwObj, c::TwObj, height::Real, width::Real, posy::Any, posx::Any )
    alignxy!( c, height,width,posx,posy, parent= p )
    c.window = TwWindow( WeakRef( p ), c.ypos, c.xpos, c.height, c.width )
    log( string(objtype(p))*"-"*string(objtype(c))*": x=" * string(c.xpos) * " y=" * string(c.ypos) )
end

function configure_newwinpanel!( obj::TwObj )
    obj.window = newwin( obj.height,obj.width,obj.ypos,obj.xpos )
    obj.panel = new_panel( obj.window )
    cbreak()
    noecho()
    keypad( obj.window, true )
    nodelay( obj.window, true )
    wtimeout( obj.window, 100 )
    curs_set( 0 )
end

function alignxy!( o::TwObj, h::Real, w::Real, x::Any, y::Any;
        relative::Bool=false, # if true, o.xpos = parent.x + x
        parent = o.screen.value )
    global widgetStaggerPosx, widgetStaggerPosy
    if typeof( parent ) <: TwScreen
        parentwin = parent.window
        ( parbegy, parbegx ) = getwinbegyx( parentwin )
        ( parmaxy, parmaxx ) = getwinmaxyx( parentwin )
    else
        tmppar = parent
        while( typeof( tmppar.window) <: TwWindow )
            tmppar = tmppar.window.parent.value
        end
        if objtype( tmppar ) == :List
            parmaxy = tmppar.data.canvasheight
            parmaxx = tmppar.data.canvaswidth
        else
            parmaxy = tmppar.height
            parmaxx = tmppar.width
        end
        log( "parmaxy=" * string(parmaxy) * "parmaxx=" * string( parmaxx ) )
        parbegx = parbegy = 0
    end
    if typeof( h ) <: Integer
        o.height = min( h, parmaxy )
    elseif typeof( h ) <: AbstractFloat&& 0.0 < h <= 1.0
        o.height = (@compat round(Int, parmaxy * h ))
        if o.height == 0
            throw( "height is too small")
        end
    else
        throw( "Illegal ysize " * string( h ) )
    end

    if typeof( w ) <: Integer
        o.width = min( w, parmaxx )
    elseif typeof( w ) <: AbstractFloat&& 0.0 < w <= 1.0
        o.width = (@compat round(Int, parmaxx * w ))
        if o.width == 0
            throw( "width is too small")
        end
    else
        throw( "Illegal xsize " * string( w ) )
    end

    if relative
        if typeof( x ) <: Integer && typeof( y ) <: Integer
            (begy, begx) = getwinbegyx( o.window )
            xpos = x+begx
            ypos = y+begy
        else
            throw( "Illegal relative position" )
        end
    else
        xpos = x
        ypos = y
    end

    gapx = max( 0, parmaxx - o.width )
    gapy = max( 0, parmaxy - o.height )
    lastx = parbegx + gapx
    lasty = parbegy + gapy
    if x == :left
        xpos = parbegx
    elseif x == :right
        xpos = parbegx + gapx
    elseif x == :center
        xpos = @compat round(Int, parbegx + gapx / 2 )
    elseif x == :random
        xpos = @compat round(Int, parbegx + gapx * rand() )
    elseif x == :staggered
        if widgetStaggerPosx > gapx
            widgetStaggerPosx = 0
        end
        xpos = parbegx + widgetStaggerPosx
        widgetStaggerPosx += 4
    elseif typeof( x ) <: AbstractFloat&& 0.0 <= x <= 1.0
        xpos = @compat round(Int, parbegx + gapx * x )
    end
    xpos = max( min( xpos, lastx ), parbegx )

    if y == :top
        ypos = parbegy
    elseif y == :bottom
        ypos = parbegy + gapy
    elseif y == :center
        ypos = @compat round(Int, parbegy + gapy / 2 )
    elseif y == :random
        ypos = @compat round(Int, parbegy + gapy * rand() )
    elseif y == :staggered
        if widgetStaggerPosy > gapy
            widgetStaggerPosy = 0
        end
        ypos = parbegy + widgetStaggerPosy
        widgetStaggerPosy += 2
    elseif typeof( y ) <: AbstractFloat&& 0.0 <= y <= 1.0
        ypos = @compat round(Int, parbegy + gapy * y )
    end
    ypos = max( min( ypos, lasty ), parbegy )
    o.xpos = xpos
    o.ypos = ypos
end

#=
function unsetFocus( o::TwObj )
    curs_set( 0 )
    obj.hasfocus = false
    unfocus(obj)
end

function setFocus( o::TwObj )
    obj.hasfocus = true
    focus(obj)
    curs_set(1)
end

function switchFocus( newobj, oldobj )
    if oldobj != newobj
        unsetFocus( oldobj )
        setFocus( newobj )
    end
end
=#

# a general blocking API to make a widget a dialogue
function activateTwObj( o::TwObj, tokens::Any=nothing )
    maxy, maxx = getwinmaxyx( o.window )
    werase( o.window )
    mvwprintw( o.window, maxy>>1, maxx>>1, "%s", "..." )
    wrefresh( o.window )

    draw(o)
    if tokens == nothing #just wait for input
        while true
            update_panels()
            doupdate()
            token = readtoken( o.window )
            status = inject( o, token ) # note that it could be :nochar
            if status == :exit_ok
                return o.value
            elseif status == :exit_nothing # most likely a cancel
                return nothing
            end # default is to continue
        end
    else
        for token in tokens
            update_panels()
            doupdate()
            status = inject( o, token )
            if status == :exit_ok
                return o.value
            elseif status == :exit_nothing # most likely a cancel
                return nothing
            end
        end
        # exhausted all the tokens, no obvious response
        unregisterTwObj( o.screen.value, o )
        return nothing
    end
end

function inject( _::TwObj, k::Any )
    if k == :esc
        return :exit_nothing
    else
        return :pass
    end
end

erase( o::TwObj ) = werase( o.window )

function move( o::TwObj, x, y, relative::Bool, refresh::Bool=false )
    begy, begx = getwinbegyx( o.window )
    alignxy!( o, o.height, o.width, x, y, relative=relative )

    xdiff = o.xpos - begx
    ydiff = o.ypos - begy

    if xdiff == 0 && ydiff == 0
        return
    end
    move_panel( o.panel, o.ypos, o.xpos )
    touchwin( o.screen.value )
    if refresh
        draw(o)
    end
end

function focus( _::TwObj )
end

function unfocus( _::TwObj )
end

refresh( o::TwObj ) = (erase(o);draw(o))

helptext( _::TwObj ) = utf8("")
