if VERSION < v"0.4-"
    if Pkg.installed( "Dates" ) == nothing
        Pkg.add( "Dates" )
    end
end

module TermWin

using Compat
using Formatting

if VERSION < v"0.4-"
    using Dates
else
    using Base.Dates
end

using DataArrays
using DataFrames

macro lintpragma( s )
end

include( "consts.jl")
include( "ccall.jl" )
include( "twtypes.jl")
include( "strutils.jl")
include( "twobj.jl")
include( "twscreen.jl")
include( "twprogress.jl")
include( "twviewer.jl")
include( "twentry.jl")
include( "readtoken.jl" )
include( "twtree.jl" )
include( "twfunc.jl" )
include( "twpopup.jl" )
include( "twmultiselect.jl")
include( "twcalendar.jl")
include( "twdftable.jl" )

export tshow, newTwViewer, newTwScreen, activateTwObj, unregisterTwObj
export trun
export TwObj, TwScreen
export newTwEntry, newTwTree, rootTwScreen, newTwFunc
export newTwCalendar
export newTwPopup, newTwMultiSelect
export newTwDfTable, DataFrameAggr, uniqvalue, unionall
export twFuncFactory, registerTwObj
export COLOR_PAIR


rootwin = nothing
rootTwScreen = nothing
callcount = 0
acs_map_arr = Uint8[]
COLORS = 8
COLOR_PAIRS = 16

function initsession()
    global rootwin, libncurses, acs_map_arr, COLORS, COLOR_PAIRS
    global rootTwScreen
    global widgetStaggerPosx
    global widgetStaggerPosy

    widgetStaggerPosx = 0
    widgetStaggerPosy = 0
    if rootwin == nothing || rootwin == C_NULL
        ENV["ESCDELAY"] = "25"
        rootwin = initscr()
        if rootwin == C_NULL
            println( "cannot create root win in ncurses")
            return
        end
        if !has_colors()
            ccall( dlsym( libncurses, :endwin), Void, () )
            throw( "terminal doesn't support colors")
        end
        mousemask( BUTTON1_PRESSED | REPORT_MOUSE_POSITION )
        acs_map_ptr = cglobal( (:acs_map, :libncurses ), Uint32 )
        acs_map_arr = pointer_to_array( acs_map_ptr, 128)

        start_color()
        # figure out how many colors are supported
        colorsptr = cglobal( (:COLORS, :libncurses ), Int16 )
        colorsarr = pointer_to_array( colorsptr, 1 )
        COLORS = colorsarr[1]

        colorsptr = cglobal( (:COLOR_PAIRS, :libncurses ), Int16 )
        colorsarr = pointer_to_array( colorsptr, 1 )
        COLOR_PAIRS = colorsarr[1]

        init_pair( 1, COLOR_RED,    COLOR_BLACK )
        init_pair( 2, COLOR_GREEN,  COLOR_BLACK )
        init_pair( 3, COLOR_YELLOW, COLOR_BLACK )
        init_pair( 4, COLOR_BLUE,   COLOR_BLACK )
        init_pair( 5, COLOR_MAGENTA, COLOR_BLACK )
        init_pair( 6, COLOR_CYAN,   COLOR_BLACK )
        init_pair( 7, COLOR_WHITE,  COLOR_BLACK )
        if COLOR_PAIRS >= 16 && COLORS >= 256 # dark blue background
            init_pair( 8, COLOR_BLACK,  21 ) # black on BRIGHT blue
            init_pair( 9, COLOR_RED,    17 ) # red on dark blue
            init_pair( 10, COLOR_GREEN,  17 ) # green on dark blue
            init_pair( 11, COLOR_YELLOW, 17 ) # yellow on dark blue
            init_pair( 12, COLOR_WHITE,   52 ) # white on dark RED
            init_pair( 13, COLOR_WHITE,  235 ) # white on dark gray
            init_pair( 14, COLOR_CYAN,   17 ) # cyan on dark blue
            init_pair( 15, COLOR_WHITE,  17 ) # white on dark blue
        end
        if COLOR_PAIRS >= 24 && COLORS >= 256 # dark red background
            init_pair( 16, COLOR_BLACK,  52 )
            init_pair( 17, COLOR_RED,    52 )
            init_pair( 18, COLOR_GREEN,  52 )
            init_pair( 19, COLOR_YELLOW, 52 )
            init_pair( 20, COLOR_BLUE,   52 )
            init_pair( 21, COLOR_MAGENTA, 52)
            init_pair( 22, COLOR_CYAN,   52 )
            init_pair( 23, COLOR_WHITE,  52 )
        end
        if COLOR_PAIRS >= 32 && COLORS >= 256 # dark red background
            init_pair( 24, 56,  COLOR_BLACK ) # light purple on black
            init_pair( 25, 56,  17 ) # light purple on dark blue
            init_pair( 26, COLOR_GREEN,  17 ) # purple on dark blue
            init_pair( 27, COLOR_YELLOW,  17 ) # yellow on dark blue
            init_pair( 28, 8,  17 ) # gray on dark blue
            init_pair( 29, COLOR_RED, 235 ) # red on dark gray
        end
        keypad( rootwin, true )
        mouseinterval( 0 )
        nodelay( rootwin, true )
        notimeout( rootwin, false )
        wtimeout( rootwin, 100 )
        curs_set( 0 )
        rootTwScreen = newTwScreen( rootwin )
        msg = string( char( 0xb83) ) * " TermWin: Please wait ..."
        mvwprintw( rootwin, int( rootTwScreen.height / 2),
            int( ( rootTwScreen.width - length(msg))/2), "%s", msg)
        wrefresh( rootwin )
    else
        # in case the terminal has been resized
        maxy, maxx = getwinmaxyx( rootwin )
        if maxy != rootTwScreen.height || maxx != rootTwScreen.width
            wresize( rootwin, maxy, maxx )
        end
        wrefresh( rootwin )
    end
end

function get_acs_val( c::Char )
    #= This is what you should use

        ACS_ULCORNER = get_acs_val('l') /* upper left corner */
        ACS_LLCORNER = get_acs_val('m') /* lower left corner */
        ACS_URCORNER = get_acs_val('k') /* upper right corner */
        ACS_LRCORNER = get_acs_val('j') /* lower right corner */
        ACS_LTEE = get_acs_val('t') /* tee pointing right */
        ACS_RTEE = get_acs_val('u') /* tee pointing left */
        ACS_BTEE = get_acs_val('v') /* tee pointing up */
        ACS_TTEE = get_acs_val('w') /* tee pointing down */
        ACS_HLINE = get_acs_val('q') /* horizontal line */
        ACS_VLINE = get_acs_val('x') /* vertical line */
        ACS_PLUS = get_acs_val('n') /* large plus or crossover */
        ACS_S1  = get_acs_val('o') /* scan line 1 */
        ACS_S9  = get_acs_val('s') /* scan line 9 */
        ACS_DIAMOND = get_acs_val('`') /* diamond */
        ACS_CKBOARD = get_acs_val('a') /* checker board (stipple) */
        ACS_DEGREE = get_acs_val('f') /* degree symbol */
        ACS_PLMINUS = get_acs_val('g') /* plus/minus */
        ACS_BULLET = get_acs_val('~') /* bullet */
        ACS_LARROW = get_acs_val(',') /* arrow pointing left */
        ACS_RARROW = get_acs_val('+') /* arrow pointing right */
        ACS_DARROW = get_acs_val('.') /* arrow pointing down */
        ACS_UARROW = get_acs_val('-') /* arrow pointing up */
        ACS_BOARD = get_acs_val('h') /* board of squares */
        ACS_LANTERN = get_acs_val('i') /* lantern symbol */
        ACS_BLOCK = get_acs_val('0') /* solid square block */
    =#
    acs_map_arr[ int( uint8( c ) ) + 1 ]
end

function endsession()
    endwin()
end

function tshow_( x::Number; title = string(typeof( x )) )
    typx = typeof( x )
    if typx <: Integer && typx <: Unsigned
        s = @sprintf( "0x%x", x )
    else
        s = string( x )
    end
    tshow_( s, title=title )
end

tshow_( x::Symbol; title="Symbol" ) = tshow_( ":"*string(x), title=title )
tshow_( x::Ptr; title="Ptr" ) = tshow_( string(x), title=title )
function tshow_( x::WeakRef; title="WeakRef", kwargs... )
    if x.value == nothing
        tshow_( "WeakRef: nothing", title=title )
    else
        tshow_( x.value; title=title, kwargs... )
    end
end
function tshow_( x; title = string( typeof( x ) ), kwargs... )
    newTwTree( rootTwScreen, x, 25, 80, :staggered, :staggered; bottomText = "F1: Help  Esc: Exit", title=title, kwargs... )
end

function tshow_( x::String; title = string(typeof( x )), kwargs... )
    pos = :center
    if length(x) > 100
        pos = :staggered
    end
    newTwViewer( rootTwScreen, x, pos, pos; bottomText = "F1: Help  Esc: Exit", title=title, kwargs... )
end

function tshow_( f::Function; title="Function", kwargs... )
    funloc = "(anonymous)"
    try
        funloc = string( functionloc( f ) )
    end
    if funloc == "(anonymous)"
        return tshow_( string(f) * ":" * funloc, title=title )
    else
        return newTwFunc( rootTwScreen, f, 25, 80, :staggered, :staggered;
            title=title, bottomText = "F1: Help  F6: Explore  F8: Edit", kwargs... )
    end
end

function tshow_( mt::MethodTable; title="MethodTable", kwargs... )
    newTwFunc( rootTwScreen, mt, 25, 80, :staggered, :staggered; title=title, kwargs... )
end

function tshow_( ms::Array{Method,1}; title="Methods", kwargs... )
    newTwFunc( rootTwScreen, ms, 25, 80, :staggered, :staggered; title=title, kwargs... )
end

function tshow_( df::DataFrame; title="DataFrame", kwargs... )
    newTwDfTable( rootTwScreen, df, 1.0, 1.0, :center,:center; title=title, kwargs... )
end

function winnewcenter( ysize, xsize, locy=0.5, locx=0.5 )
    global rootwin
    (maxy, maxx) = getwinmaxyx( rootwin )
    local cols, lines, origx, origy
    if isa( ysize, Int )
        lines = ysize
    elseif isa( ysize, Float64 ) && 0.0 < ysize <= 1.0
        lines = int( maxy * ysize )
        if lines == 0
            throw( "lines are too small")
        end
    else
        throw( "illegal ysize " * string( ysize ) )
    end

    if isa( xsize, Int )
        cols = xsize
    elseif isa( xsize, Float64 ) && 0.0 < xsize <= 1.0
        cols = int( maxx * xsize )
        if cols == 0
            throw( "cols are too small")
        end
    else
        throw( "illegal xsize " * string( ysize ) )
    end

    if isa( locy, Int )
        origy = max( 0, min( locy, maxy-lines-1 ) )
    elseif isa( locy, Float64 ) && 0.0 <= locy <= 1.0
        origy = int( floor( locy * ( maxy - lines ) ) )
    else
        throw( "illegal locy " * string( locy) )
    end

    if isa( locx, Int )
        origx = max( 0, min( locx, maxx-cols-1 ) )
    elseif isa( locx, Float64 ) && 0.0 <= locx <= 1.0
        origx = int( floor( locx * ( maxx - cols ) ) )
    else
        throw( "illegal locx " * string( locx) )
    end
    win = newwin( lines, cols, origy, origx )
    cbreak()
    noecho()
    keypad( win, true )
    nodelay( win, true )
    notimeout( win, false )
    wtimeout( win, 100 )
    win
end

function titleof( x::Any )
    typx = typeof( x )
    if typx == Module || typx == Function
        return string( x )
    else
        return string( typx )
    end
end

function tshow( x::Any; title=titleof( x ), kwargs... )
    global callcount, rootwin, rootTwScreen
    if callcount == 0
        initsession()
        callcount += 1
        werase( rootwin )
        try
            widget = tshow_( x; title=title, kwargs... )
            if widget != nothing
                activateTwObj( rootTwScreen )
            end
        catch err
            callcount -= 1
            endsession()
            rethrow( err )
        end
        callcount -= 1
        endsession()
    else
        found = false
        for o in rootTwScreen.data.objects
            if !in( objtype( o ), [ :Entry, :Viewer, :Calendar ] ) && isequal( o.value, x )
                raiseTwObject( o )
                found = true
                break
            end
        end
        if !found
            widget = nothing
            try
                widget = tshow_(x, title=title )
            catch err
                bt = catch_backtrace()
                msg = string(err) * "\n" * string( bt )
                widget = tshow_( msg, title="Error" )
            end
            if widget != nothing
                if widget.acceptsFocus
                    widget.hasFocus = true
                    rootTwScreen.data.focus = length( rootTwScreen.data.objects )
                    refresh( rootTwScreen )
                else
                    widget.hasFocus = false
                    lowerTwObject( widget )
                end
            end
        end
    end
    nothing
end

# f is a no-arg function
function trun( f::Function; title="" )
    # async start the function
    # start the progress bar window and listen to it
    global callcount, rootwin, rootTwScreen
    @async begin
        problem = false
        updateProgressChannel( :init, nothing )
        try
            val = f()
            updateProgressChannel( :done, val )
        catch er
            updateProgressChannel( :error, er )
        end
    end

    ret = nothing

    if callcount == 0
        initsession()
        callcount += 1
        werase( rootwin )
        try
            o = newTwProgress( rootTwScreen, 5, 50, :center, :center, title=title )
            if o != nothing
                activateTwObj( rootTwScreen )
                ret = o.value
            end
        catch er
            callcount -= 1
            endsession()
            rethrow( er )
        end
        callcount -= 1
        endsession()
        return ret
    else
        found = false
        for o in rootTwScreen.data.objects
            if objtype( o ) == :Progress
                raiseTwObject( o )
                o.title = title
                o.isvisible = true
                found = true
                break
            end
        end
        if !found
            o = newTwProgress( rootTwScreen, 5, 50, :center, :center, title=title )
            o.hasFocus = true
            rootTwScreen.data.focus = length( rootTwScreen.data.objects )
            refresh( rootTwScreen )
        end
        return nothing
    end
end

function testkeydialog()
    width = 42
    initsession()
    win = winnewcenter( 4, width )
    panel = new_panel( win )
    box( win, 0, 0 )
    title = "Test Key/Mouse/Unicode"
    keyhint = "[Esc to continue]"

    mvwprintw( win, 0, int( (width-length(title))/2), "%s", title )
    mvwprintw( win, 3, int( (width-length(keyhint))/2), "%s", keyhint )
    update_panels()
    doupdate()
    local token
    while( (token = readtoken( win )) != :esc )
        if token == :nochar
            continue
        end
        k = ""
        if isa( token, String )
            for c in token
                if isprint( c ) && isascii( c )
                    k *= string(c)
                else
                    k *= @sprintf( "{%x}", uint(c))
                end
            end
            k = k * repeat( " ", 21-length(k) )
            mvwprintw( win, 1, 2, "%s", k)
            if 1 <= uint64(token[1]) <= 127
                mvwprintw( win, 2, 2, "%s", "acs_val:        " )
                mvwaddch( win, 2,11, get_acs_val( token[1] ) )
            else
                mvwprintw( win, 2, 2, "%s        ", "print  :" * string(token[1]) )
            end
        elseif token == :KEY_MOUSE
            ( state, x, y, bs ) = getmouse()
            mvwprintw( win, 1,2, "%s", @sprintf( "x:%d y:%d   ", x,y ))
            mvwprintw( win, 2,2, ":%s      ", string(state))
            #=
            for j = 1:2
                k = ""
                for i = 1:16
                    k *= @sprintf( "%02x", bs[i+(j-1)*16] )
                end
                mvwprintw( win, j, 2, "%s", k )
            end
            =#
        elseif isa( token, Symbol )
            k = ":" * string(token)
            mvwprintw( win, 2, 2, "%s", "                " )
            k = k * repeat( " ", 21-length(k) )
            mvwprintw( win, 1, 2, "%s", k)
        end
        update_panels()
        doupdate()
    end
    del_panel(panel)
    delwin( win )
    endsession()
end

# precompile a bunch of code for better responsiveness
precompile( initsession, (Ptr{Void}, ) )
precompile( readtoken, (Ptr{Void}, ) )
precompile( registerTwObj, (TwObj, TwObj ) )
precompile( twFuncFactory, (Symbol,) )
precompile( injectTwTree, (TwObj, Any ) )
precompile( injectTwEntry, (TwObj, Any ) )
precompile( injectTwViewer, (TwObj, Any ) )

end

