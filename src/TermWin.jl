module TermWin

include( "consts.jl")
include( "ccall.jl" )
include( "readtoken.jl" )
include( "tree.jl" )
include( "func.jl" )

export tshow

rootwin = nothing
callcount = 0
acs_map_ptr = nothing
acs_map_arr = Uint8[]

function initsession()
    global rootwin, libncurses, acs_map_ptr, acs_map_arr

    if rootwin == nothing || rootwin == C_NULL
        ENV["ESCDELAY"] = "25"
        rootwin = ccall(dlsym(libncurses, :initscr), Ptr{Void}, ()) # rootwin is stdscr
        ccall( dlsym( libncurses, :keypad ), Void, (Ptr{Void}, Bool), rootwin, true );
        if rootwin == C_NULL
            println( "cannot create root win in ncurses")
            return
        end
        if !has_colors()
            ccall( dlsym( libncurses, :endwin), Void, () )
            throw( "terminal doesn't support colors")
        end
        acs_map_ptr = cglobal( (:acs_map, :libncurses ), Uint32 )
        acs_map_arr = pointer_to_array( acs_map_ptr, 128)

        start_color()
        init_pair( 1, COLOR_BLACK, COLOR_WHITE )
        keypad( rootwin, true )
        nodelay( rootwin, true )
        notimeout( rootwin, false )
        curs_set( 0 )
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
    global rootwin, libncurses
    if rootwin != nothing
        ccall( dlsym( libncurses, :endwin), Void, () )
        rootwin = nothing
    end
end

function wordwrap( x::String, width::Int )
    spaceleft = width
    lines = String[]
    currline = ""
    words = split( x, " ", true ) # don't keep empty words
    for w in words
        wlen = length(w)
        if wlen>width && spaceleft == width
            push!( lines, SubString( w, 1, width-3 ) * " .." )
        elseif wlen+1 > spaceleft
            push!( lines, currline )
            currline = w * " "
            spaceleft = width - wlen - 1
        else
            currline = currline * w * " "
            spaceleft = spaceleft - wlen -1
        end
    end
    if currline != ""
        push!(lines, currline )
    end
    return lines
end

function tshow_( x::Number; title = string(typeof( x )) )
    s = string( x )
    len = length(s)
    width = max( 21, len, length(title) ) + 4
    win = winnewcenter( 3, width )
    panel = new_panel( win )
    box( win,  0, 0 )
    keyhint = "[Esc to continue]"

    if title != ""
        mvwprintw( win, 0, int( ( width - length(title) )/2 ), "%s", title )
    end
    mvwprintw( win, 1, width-len-2, "%s", s )
    mvwprintw( win, 2, int( (width-length(keyhint))/2), "%s", keyhint )

    update_panels()
    doupdate()
    while( (readtoken( win )) != :esc ) end
    del_panel( panel )
    delwin( win )
end

tshow_( x::Symbol; title="Symbol" ) = tshow_( ":"*string(x), title=title )
tshow_( x::Ptr; title="Ptr" ) = tshow_( string(x), title=title )

function tshow_( x::String; title = string(typeof( x )), showprogress=true, showkeyhelper=true )
    msgs = map( x->replace(x, "\t", "    "), split( x, "\n" ) )
    needy = length(msgs)
    needx = maximum( map( x->length(x), msgs ) )

    maxy= maxx= height= width= 0
    panel = nothing

    update_dimensions = ()-> begin
        (maxy, maxx) = getwinmaxyx( rootwin )
        height=max( 3, min( maxy-2, needy )+2 ) # including the borders
        width =max( 30, length(title)+2, min( maxx-4, needx )+4 ) # including the borders
    end

    update_dimensions()

    win = winnewcenter( height, width )
    panel = new_panel( win )

    currentTop = 1
    currentLeft = 1

    redrawviewer = ()->begin
        werase( win )
        box( win, 0, 0 )
        height, width = getwinmaxyx( win )
        npushed = 0
        for r in currentTop:min(currentTop+height-3, needy)
            s = string( SubString( msgs[ r ], currentLeft, currentLeft + width - 5 ) )
            mvwprintw( win, 1 + r-currentTop, 2, "%s",s )
            npushed += length(s)
            if npushed > 200
                refresh()
                wrefresh( win )
                #update_panels()
                #doupdate()
                npushed = 0
            end
        end
        if title != ""
            mvwprintw( win, 0, int( ( width - length(title) )/2 ), "%s", title )
        end
        if showprogress
            if needy <= height-2
                mvwprintw( win, 0, width-13, "%10s", "ALL" )
            else
                mvwprintw( win, 0, width-13, "%10s", @sprintf( "%9.2f%%", currentTop / (needy - height +2 ) * 100 ) )
            end
        end
        if showkeyhelper && (needy > height -2 || needx > width - 4)
            s = "F1: Help   Esc: exit"
            mvwprintw( win, height-1, int((width-length(s))/2), "%s", s )
        else
            s = "[Esc to continue]"
            mvwprintw( win, height-1, int((width-length(s))/2), "%s", s )
        end
        update_panels()
        doupdate()
    end

    redrawviewer()
    token = 0
    while( (token = readtoken(win )) != :esc )
        dorefresh = false
        if token == :up
            if currentTop > 1
                currentTop -= 1
                dorefresh = true
            else
                beep()
            end
        elseif token == :down
            if currentTop + height-2 < needy
                currentTop += 1
                dorefresh = true
            else
                beep()
            end
        elseif token == :left
            if currentLeft > 1
                currentLeft -= 1
                dorefresh = true
            else
                beep()
            end
        elseif token == :right
            if currentLeft + width-4 < needx
                currentLeft += 1
                dorefresh = true
            else
                beep()
            end
        elseif token == :pageup
            if currentTop > 1
                currentTop = max( 1, currentTop - (height-2) )
                dorefresh = true
            else
                beep()
            end
        elseif token == :pagedown
            if currentTop + height-2 < needy
                currentTop = min( needy - height + 2, currentTop + height - 2 )
                dorefresh = true
            else
                beep()
            end
        elseif  token == :home
            if currentTop != 1 || currentLeft != 1
                currentTop = 1
                currentLeft = 1
                dorefresh = true
            else
                beep()
            end
        elseif in( token, [ "<", "0", "g" ] )
            if currentTop != 1
                currentTop = 1
                dorefresh = true
            else
                beep()
            end
        elseif in( token, { ">", "G", symbol("end") } )
            if currentTop + height-2 < needy
                currentTop = needy - height+ 2
                dorefresh = true
            else
                beep()
            end
        elseif token == "L" # move half-way toward the end
            target = min( int(ceil((currentTop + needy - height+2)/2)), needy - height + 2 )
            if target != currentTop
                currentTop = target
                dorefresh = true
            else
                beep()
            end
        elseif token == "l" # move half-way toward the beginning
            target = max( int(floor( currentTop /2)), 1)
            if target != currentTop
                currentTop = target
                dorefresh = true
            else
                beep()
            end
        elseif token == :F1 && showkeyhelper
            tshow_(
            """
PgUp/PgDn,
Arrow keys : standard navigation
l          : move halfway toward the start
L          : move halfway to the end
<,0,g      : jump to the start
>, G       : jump to the end
            """, title="Help", showprogress= false, showkeyhelper=false
            )
            dorefresh = true
        elseif token == :KEY_RESIZE || is_term_resized( maxy, maxx )
            update_dimensions()
            wresize( win, height, width )
            dorefresh = true
            #TODO search, jump to line, etc.
        end

        if dorefresh
            redrawviewer()
        end
    end
    del_panel( panel )
    delwin( win )
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
    wtimeout( win, 10 )
    win
end

function tshow( x::Any )
    global callcount
    if callcount == 0
        initsession()
    end
    err = nothing
    callcount += 1
    #try
        tshow_( x )
    #catch er
        #err = er
    #end
    callcount -= 1
    if callcount == 0
        endsession()
    end
    if err != nothing
        println( err )
    end
end

function testkeydialog( remapkeypad::Bool = false )
    width = 25
    initsession()
    win = winnewcenter( 4, width )
    panel = new_panel( win )
    box( win, 0, 0 )
    title = "Key Test"
    keyhint = "[Esc to continue]"

    mvwprintw( win, 0, int( (width-length(title))/2), "%s", title )
    mvwprintw( win, 3, int( (width-length(keyhint))/2), "%s", keyhint )
    update_panels()
    doupdate()
    local token
    #while( (token = readtoken( remapkeypad )) != :esc )
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
            if 1 <= uint8(token[1]) <= 127
                mvwprintw( win, 2, 2, "%s", "acs_val:        " )
                mvwaddch( win, 2,11, get_acs_val( token[1] ) )
            else
                mvwprintw( win, 2, 2, "%s", "acs_val: <none> " )
            end
        elseif isa( token, Symbol )
            k = ":" * string(token)
            mvwprintw( win, 2, 2, "%s", "                " )
        end
        k = k * repeat( " ", 21-length(k) )
        mvwprintw( win, 1, 2, "%s", k)
        update_panels()
        doupdate()
    end
    del_panel(panel)
    delwin( win )
    endsession()
end

end
