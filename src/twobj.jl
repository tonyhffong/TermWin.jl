# default behavior, dummy behavior, and convenient functions for all widgets

#Automatic discovery of widget-specific functions
widgetTwFuncCache = Dict{ Symbol, TwFunc }()
function twFuncFactory( widgetname::Symbol )
    global widgetTwFuncCache
    if haskey( widgetTwFuncCache, widgetname )
        return widgetTwFuncCache[ widgetname ]
    end

    args = {}
    modulenames = names( TermWin, true )
    for ( n, t ) in zip( names( TwFunc ), TwFunc.types )
        if n == :objtype
            push!( args, widgetname )
        elseif t == Function
            sym = symbol( string( n ) * "Tw" * string( widgetname ))
            found = false
            if in( sym, modulenames )
                f = getfield( TermWin, sym )
                if typeof( f ) == Function
                    push!( args, f )
                    found = true
                end
            end
            if !found
                try
                    f = eval( Main, sym )
                    if typeof( f ) == Function
                        push!( args, f )
                        found = true
                    end
                end
            end
            if !found
                if n == :draw
                    throw( string( sym ) * " not found for widget " * string( widgetname ) )
                else
                    defsym = symbol( string( n ) * "TwObj" )
                    push!( args, getfield( TermWin, defsym ) )
                end
            end
        else
            throw( "TwFunc has unsupported field type " * string(t) )
        end
    end
    widgetTwFuncCache[ widgetname ] = apply( TwFunc, args )
end

function configure_newwinpanel!( obj::TwObj )
    obj.window = newwin( obj.height,obj.width,obj.ypos,obj.xpos )
    obj.panel = new_panel( obj.window )
    cbreak()
    noecho()
    keypad( obj.window, true )
    nodelay( obj.window, true )
    wtimeout( obj.window, 10 )
    curs_set( 0 )
end

function alignxy!( o::TwObj, h::Real, w::Real, x::Any, y::Any; 
    relative::Bool=false, # if true, o.xpos = parent.x + x
    derwin::Bool=false, # if true, o.xpos will be set relative to parentwin
    parentwin = o.screen.value.window )

    if derwin
        parbegx = parbegy = 0
    else
        ( parbegy, parbegx ) = getwinbegyx( parentwin )
    end
    ( parmaxy, parmaxx ) = getwinmaxyx( parentwin )
    if typeof( h ) <: Integer
        o.height = min( h, parmaxy )
    elseif typeof( h ) <: FloatingPoint && 0.0 < h <= 1.0
        o.height = int( parmaxy * h )
        if o.height == 0
            throw( "height is too small")
        end
    else
        throw( "Illegal ysize " * string( h ) )
    end

    if typeof( w ) <: Integer
        o.width = min( w, parmaxx )
    elseif typeof( w ) <: FloatingPoint && 0.0 < w <= 1.0
        o.width = int( parmaxx * w )
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
        xpos = int( parbegx + gapx / 2 )
    elseif typeof( x ) <: FloatingPoint && 0.0 <= x <= 1.0
        xpos = int( parbegx + gapx * x )
    end
    xpos = max( min( xpos, lastx ), parbegx )

    if y == :top
        ypos = parbegy
    elseif y == :bottom
        ypos = parbegy + gapy
    elseif y == :center
        ypos = int( parbegy + gapy / 2 )
    elseif typeof( y ) <: FloatingPoint  && 0.0 <= y <= 1.0
        ypos = int( parbegy + gapy * y )
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
    if objtype(o) == :Screen
        return activateTwScreen( o, tokens )
    end

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

function injectTwObj( o::TwObj, k )
    if k== :esc
        return :exit_nothing
    else
        return :pass
    end
end

eraseTwObj( o::TwObj ) = werase( o.window )

function moveTwObj( o::TwObj, x, y, relative::Bool, refresh::Bool=false )
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

focusTwObj( o::TwObj ) = nothing
unfocusTwObj( o::TwObj ) = nothing
refreshTwObj( o::TwObj ) = (erase(o);draw(o))
