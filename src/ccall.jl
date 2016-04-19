#= PLEASE NOTE THAT ALL NCURSES FUNCS ARE ZERO-BASED
=#
libncurses = false
libpanel = false

function initscr()
    global libncurses, libpanel
    if  libncurses == false
        try
            libncurses = Libdl.dlopen("libncurses")
        catch
            libncurses = Libdl.dlopen("libncursesw")
        end
        try
            libpanel = Libdl.dlopen("libpanel")
        catch
            libpanel = Libdl.dlopen("libpanelw")
        end
    end
    ccall( Libdl.dlsym( libncurses, :initscr), Ptr{Void}, () )
end

function endwin()
    ccall( Libdl.dlsym( libncurses, :endwin), Int, () )
end

function isendwin()
    ccall( Libdl.dlsym( libncurses, :isendwin), Bool, () )
end

function newwin( lines::Int, cols::Int, origy::Int, origx::Int )
    ccall( Libdl.dlsym( libncurses, :newwin ), Ptr{Void}, ( Int, Int, Int, Int ),
        lines, cols, origy, origx )
end

function subwin( win::Ptr{Void}, lines::Int, cols::Int, origy::Int, origx::Int )
    ccall( Libdl.dlsym( libncurses, :subwin ), Ptr{Void}, ( Ptr{Void}, Int, Int, Int, Int ),
        win, lines, cols, origy, origx )
end

function derwin( win, lines::Int, cols::Int, origy::Int, origx::Int )
    ccall( Libdl.dlsym( libncurses, :derwin ), Ptr{Void}, ( Ptr{Void}, Int, Int, Int, Int ),
        win, lines, cols, origy, origx )
end

function delwin( win::Ptr{Void} )
    ccall( Libdl.dlsym( libncurses, :delwin ), Void, ( Ptr{Void}, ), win )
end

function mvwaddch( win::Ptr{Void}, y::Int, x::Int, c )
    ccall( Libdl.dlsym( libncurses, :mvwaddch), Void,
        ( Ptr{Void}, Int, Int, Int ), win, y, x, c )
end

function mvwadd_wch( win::Ptr{Void}, y::Int, x::Int, c )
    ccall( Libdl.dlsym( libncurses, :mvwadd_wch), Void,
        ( Ptr{Void}, Int, Int, Int ), win, y, x, Int64(c) )
end

function mvwaddch( w::TwWindow, y::Int, x::Int, c )
    if objtype( w.parent.value ) == :List && typeof( w.parent.value.window ) != TwWindow
        # terminal layer. use its pad
        mvwaddch( w.parent.value.data.pad, y+w.yloc, x+w.xloc, c )
    else
        mvwaddch( w.parent.value.window, y+w.yloc, x+w.xloc, c )
    end
end

function mvwprintw{T<:AbstractString}( win::Ptr{Void}, row::Int, height::Int, fmt::ASCIIString, str::T )
    ccall( Libdl.dlsym( libncurses, :mvwprintw), Void,
        ( Ptr{Void}, Int, Int, Cstring, Cstring ),
        win, row, height, fmt, str )
end

# note that it could in turn call another TwWindow...
function mvwprintw{T<:AbstractString}( w::TwWindow, y::Int, x::Int, fmt::ASCIIString, s::T )
    if objtype( w.parent.value ) == :List && typeof( w.parent.value.window ) != TwWindow
        # terminal layer. use its pad
        mvwprintw( w.parent.value.data.pad, y+w.yloc, x+w.xloc, fmt, s )
    else
        mvwprintw( w.parent.value.window, y+w.yloc, x+w.xloc, fmt, s )
    end
end

function wmove( win::Ptr{Void}, y::Int, x::Int )
    ccall( Libdl.dlsym( libncurses, :wmove), Int, ( Ptr{Void}, Int, Int ), win, y, x )
end

function wrefresh( win::Ptr{Void} )
    ccall( Libdl.dlsym( libncurses, :wrefresh ), Void, ( Ptr{Void}, ), win )
end

function touchwin( win::Ptr{Void} )
    ccall( Libdl.dlsym( libncurses, :touchwin ), Void, ( Ptr{Void}, ), win )
end

function refresh()
    ccall( Libdl.dlsym( libncurses, :refresh ), Void, ( ) )
end

function erase()
    ccall( Libdl.dlsym( libncurses, :erase ), Void, () )
end

function werase( win::Ptr{Void} )
    ccall( Libdl.dlsym( libncurses, :werase ), Void, (Ptr{Void},), win )
end

function werase( win::TwWindow, y::Int=win.yloc, x::Int=win.xloc, h::Int=win.height, w::Int=win.width )
    parwin = win.parent.value.window
    if typeof( parwin ) <: Ptr
        if objtype( win.parent.value ) == :List
            tmpw = win.parent.value.data.pad
        else
            tmpw = parwin
        end
        for r = y:y+h-1
            for c = x:x+w-1
                mvwaddch( tmpw, r, c, ' ' )
            end
        end
    else
        werase( parwin, parwin.yloc+y, parwin.xloc+x, h, w )
    end
end

function wclear( win::Ptr{Void} )
    ccall( Libdl.dlsym( libncurses, :wclear ), Void, (Ptr{Void},), win )
end

function box( win::Ptr{Void}, vchr, hchr )
    ccall( Libdl.dlsym( libncurses, :box ), Void, (Ptr{Void}, Char, Char), win, vchr, hchr )
end

function box( win::TwWindow, vchr::Integer, hchr::Integer, y::Int=win.yloc, x::Int=win.xloc, h::Int=win.height, w::Int=win.width )
    parwin = win.parent.value.window
    if typeof( parwin ) <: Ptr
        if objtype( win.parent.value ) == :List
            tmpw = win.parent.value.data.pad
        else
            tmpw = parwin
        end
        #draw the box myself
        # 4 corners
        mvwaddch( tmpw, y,x, get_acs_val( 'l' ) )
        mvwaddch( tmpw, y+h-1,x, get_acs_val( 'm' ) )
        mvwaddch( tmpw, y,x+w-1, get_acs_val( 'k' ) )
        mvwaddch( tmpw, y+h-1,x+w-1, get_acs_val( 'j' ) )

        if vchr==0
            vchr=get_acs_val('x')
        end
        if hchr==0
            hchr=get_acs_val('q')
        end
        for r = y+1:y+h-2
            mvwaddch( tmpw, r, x, vchr )
            mvwaddch( tmpw, r, x+w-1, vchr )
        end
        for c = x+1:x+w-2
            mvwaddch( tmpw, y, c, hchr )
            mvwaddch( tmpw, y+h-1, c, hchr )
        end
    else
        box( parwin, vchr, hchr, parwin.yloc+win.yloc, parwin.xloc+win.xloc, h, w )
    end
end

function wgetch( win::Ptr{Void} )
    ccall( Libdl.dlsym( libncurses, :wgetch ), UInt32, (Ptr{Void},), win )
end

function keypad( win::Ptr{Void}, bf )
    ccall( Libdl.dlsym( libncurses, :keypad ), Int, (Ptr{Void}, Bool), win, bf )
end

function cbreak()
    ccall( Libdl.dlsym( libncurses, :cbreak), Void, ( ) )
end

function nocbreak()
    ccall( Libdl.dlsym( libncurses, :nocbreak), Void, ( ) )
end

function echo()
    ccall( Libdl.dlsym( libncurses, :echo), Void, ( ) )
end

function noecho()
    ccall( Libdl.dlsym( libncurses, :noecho), Void, ( ) )
end

function nodelay( win, bf )
    ccall( Libdl.dlsym( libncurses, :nodelay ), Int, (Ptr{Void}, Bool), win, bf )
end

function raw()
    ccall( Libdl.dlsym( libncurses, :raw ), Int, () )
end

function noraw()
    ccall( Libdl.dlsym( libncurses, :noraw ), Int, () )
end

function notimeout( win::Ptr{Void}, bf )
    ccall( Libdl.dlsym( libncurses, :notimeout ), Int, (Ptr{Void}, Bool), win, bf )
end

function timeout( delay::Int )
    ccall( Libdl.dlsym( libncurses, :timeout ), Void, (Int,), delay )
end

function wtimeout( win::Ptr{Void}, delay::Int )
    ccall( Libdl.dlsym( libncurses, :wtimeout ), Void, (Ptr{Void}, Int), win, delay )
end

# not standard but convenient
function getwinmaxyx( win::Ptr{Void} )
    maxy = ccall( Libdl.dlsym(libncurses, :getmaxy), Int, ( Ptr{Void}, ), win )
    maxx = ccall( Libdl.dlsym(libncurses, :getmaxx), Int, ( Ptr{Void}, ), win )
    ( maxy, maxx )
end

function getwinbegyx( win::Ptr{Void} )
    maxy = ccall( Libdl.dlsym(libncurses, :getbegy), Int, ( Ptr{Void}, ), win )
    maxx = ccall( Libdl.dlsym(libncurses, :getbegx), Int, ( Ptr{Void}, ), win )
    ( maxy, maxx )
end

function mvwin( win::Ptr{Void}, y::Int, x::Int )
    ccall( Libdl.dlsym( libncurses, :mvwin), Int, ( Ptr{Void}, Int, Int ), win, y, x )
end

function copywin( s::Ptr{Void}, d::Ptr{Void}, sminrow::Int, smincol::Int, dminrow::Int, dmincol::Int, dmaxrow::Int, dmaxcol::Int )
    ccall( Libdl.dlsym( libncurses, :copywin), Int, ( Ptr{Void}, Ptr{Void}, Int, Int, Int, Int, Int, Int ),
       s, d, sminrow,smincol,dminrow, dmincol,dmaxrow,dmaxcol )
end

function beep()
    ccall( Libdl.dlsym( libncurses, :beep ), Void, () )
end

function flash()
    ccall( Libdl.dlsym( libncurses, :flash), Void, () )
end

function is_term_resized( lines::Int, cols::Int )
    ccall( Libdl.dlsym( libncurses, :is_term_resized ), Bool, (Int, Int), lines, cols )
end

function wresize( win::Ptr{Void}, lines::Int, cols::Int )
    ccall( Libdl.dlsym( libncurses, :wresize), Int, (Ptr{Void}, Int, Int), win, lines, cols )
end

function getcuryx( win::Ptr{Void} )
    cury = ccall( Libdl.dlsym(libncurses, :getcury), Cint, ( Ptr{Void}, ), win )
    curx = ccall( Libdl.dlsym(libncurses, :getcurx), Cint, ( Ptr{Void}, ), win )
    ( cury, curx )
end

function start_color()
    ccall( Libdl.dlsym( libncurses, :start_color), Void, () )
end

function init_pair( pair, f, b )
    ccall( Libdl.dlsym( libncurses, :init_pair ), Int, ( Int16, Int16, Int16 ), pair, f, b )
end

function init_color( color, r,g,b )
    ccall( Libdl.dlsym( libncurses, :init_color ), Int, ( Int16, Int16, Int16, Int16 ),
        color, r,g,b )
end

function has_colors()
    ccall( Libdl.dlsym( libncurses, :has_colors), Bool, () )
end

function wattroff( win::Ptr{Void}, attrs )
    ccall( Libdl.dlsym(libncurses, :wattroff), Int, ( Ptr{Void}, UInt32 ), win, attrs )
end

function wattroff( win::TwWindow, attrs )
    parwin = win.parent.value.window
    if objtype( win.parent.value ) == :List && typeof( parwin ) <: Ptr
        wattroff( win.parent.value.data.pad, attrs )
    else
        wattroff( win.parent.value.window, attrs )
    end
end

function wattron( win::Ptr{Void}, attrs )
    ccall( Libdl.dlsym(libncurses, :wattron), Int, ( Ptr{Void}, UInt32 ), win, attrs )
end

function wattron( win::TwWindow, attrs )
    parwin = win.parent.value.window
    if objtype( win.parent.value ) == :List && typeof( parwin ) <: Ptr
        wattron( win.parent.value.data.pad, attrs )
    else
        wattron( win.parent.value.window, attrs )
    end
end

function wattrset( win::Ptr{Void}, attrs )
    ccall( Libdl.dlsym(libncurses, :wattrset), Int, ( Ptr{Void}, UInt32 ), win, attrs )
end

function wbkgdset( win::Ptr{Void}, ch )
    ccall( Libdl.dlsym(libncurses, :wbkgdset ), Void, ( Ptr{Void}, UInt32 ), win, ch )
end

function wbkgd( win::Ptr{Void}, ch )
    ccall( Libdl.dlsym(libncurses, :wbkgd ), Void, ( Ptr{Void}, UInt32 ), win, ch )
end

function curs_set( vis )
    ccall( Libdl.dlsym(libncurses, :curs_set), Int, ( Int, ), vis )
end

function has_mouse()
    ccall( Libdl.dlsym(libncurses, :has_mouse), Bool, () )
end

function mousemask( mask )
    oldmm = Array( UInt64, 1 )
    resultmm = ccall( Libdl.dlsym( libncurses, :mousemask), UInt64, (UInt64, Ptr{UInt64}), mask, oldmm )
    ( resultmm, oldmm[1])
end

function mouseinterval( n::Int )
    ccall( Libdl.dlsym(libncurses, :mouseinterval), Int, (Int, ) , n)
end

#hack!
const mouseByteString = bytestring( Array( UInt8, 64 ) )
function getmouse()
    #=
    type Mouse_Event_t
        id::Int8 # short
        x::Int32 # int
        y::Int32 # int
        z::Int32 # int
        bstate::UInt64 # unsigned long
    end
    =#
    # the 5th byte is x, 9th byte is y
    # 19th byte is x08 if scroll up, 20th byte is x08 if scroll down
    # 17th byte is x02 if button 1 pressed
    # 17th byte is x01 if button 1 released
    # 17-18th is 0xfffd if mousewheel is pressed down
    ccall( Libdl.dlsym( libncurses, :getmouse), Int, (Ptr{UInt8}, ), mouseByteString )
    bs = mouseByteString
    x = @compat UInt8(bs[5])
    y = @compat UInt8(bs[9])
    state=:unknown
    if (@compat UInt(bs[17])) & 0x02 != 0
        state = :button1_pressed
    elseif (@compat UInt(bs[19])) & 0x08 != 0
        state = :scroll_up
    elseif (@compat UInt(bs[20])) & 0x08 != 0
        state = :scroll_down
    end
    ( state, x, y, bs )
end

function screen_to_relative( w::Ptr, y::Integer, x::Integer )
    begy, begx = getwinbegyx( w )
    ( y-begy, x-begx )
end

function screen_to_relative( w::TwWindow, y::Integer, x::Integer )
    # figure out the canvas coordinate, ultimate parent
    xloc = w.xloc
    yloc = w.yloc
    par = w.parent.value
    while( !( typeof( par.window ) <: Ptr ) )
        xloc += par.window.xloc
        yloc += par.window.yloc
        par = par.window.parent.value
    end
    (view_rel_y, view_rel_x) = screen_to_relative( par.window, y, x )

    ( par.data.canvaslocy + view_rel_y, par.data.canvaslocx + view_rel_x )
end

function baudrate()
    ccall( Libdl.dlsym( libncurses, :baudrate), Int, () )
end

function clearok( win::Ptr{Void}, bf )
    ccall( Libdl.dlsym( libncurses, :clearok), Int, ( Ptr{Void}, Bool ), win, bf )
end

function immedok( win::Ptr{Void}, bf )
    ccall( Libdl.dlsym( libncurses, :immedok), Int, ( Ptr{Void}, Bool ), win, bf )
end

function napms( ms::Int )
    ccall( Libdl.dlsym( libncurses, :napms), Int, (Int, ), ms )
end

#===== PANEL library ====#

function update_panels()
    ccall( Libdl.dlsym( libpanel, :update_panels), Void, () )
end

function doupdate()
    ccall( Libdl.dlsym( libpanel, :doupdate ), Void, () )
end

function new_panel( win::Ptr{Void} )
    ccall( Libdl.dlsym( libpanel, :new_panel ), Ptr{Void}, ( Ptr{Void}, ), win )
end

function top_panel( pan::Ptr{Void} )
    ccall( Libdl.dlsym( libpanel, :top_panel ), Int, ( Ptr{Void}, ), pan )
end

function bottom_panel( pan::Ptr{Void} )
    ccall( Libdl.dlsym( libpanel, :bottom_panel ), Int, ( Ptr{Void}, ), pan )
end

function move_panel( pan::Ptr{Void}, starty::Int, startx::Int )
    ccall( Libdl.dlsym( libpanel, :move_panel ), Ptr{Void}, ( Ptr{Void}, Int, Int ), pan, starty, startx )
end

function del_panel( panel::Ptr{Void} )
    ccall(Libdl.dlsym( libpanel, :del_panel ), Void, (Ptr{Void}, ), panel )
end

function show_panel( panel::Ptr{Void} )
    ccall(Libdl.dlsym( libpanel, :show_panel ), Int, (Ptr{Void}, ), panel )
end

function hide_panel( panel::Ptr{Void} )
    ccall(Libdl.dlsym( libpanel, :hide_panel ), Int, (Ptr{Void}, ), panel )
end

function panel_hidden( panel::Ptr{Void } )
    ccall(Libdl.dlsym( libpanel, :panel_hidden ), Int, (Ptr{Void}, ), panel ) != 0
end

function replace_panel( panel::Ptr{Void}, window::Ptr{Void} )
    ccall(Libdl.dlsym( libpanel, :replace_panel ), Void, (Ptr{Void}, Ptr{Void} ), panel, window )
end

function set_panel_userptr( p1::Ptr{Void}, p2::Ptr{Void} )
    ccall(Libdl.dlsym( libpanel, :set_panel_userptr), Void, (Ptr{Void}, Ptr{Void}), p1, p2 )
end

# ------ pad

function newpad( rows::Int, cols::Int )
    ccall(Libdl.dlsym( libncurses, :newpad ), Ptr{Void}, (Int,Int), rows, cols )
end

function subpad( orig::Ptr{Void}, rows::Int, cols::Int, beg_y::Int, beg_x::Int )
    ccall(Libdl.dlsym( libncurses, :subpad ), Ptr{Void}, (Ptr{Void}, Int,Int,Int,Int), orig, rows, cols, beg_y, beg_x )
end

function pnoutrefresh( pad::Ptr{Void}, pminrow::Int, pmincol::Int, sminrow::Int,smincol::Int,smaxrow::Int,smaxcol::Int )
    ccall(Libdl.dlsym( libncurses, :pnoutrefresh), Void, (Ptr{Void}, Int,Int,Int,Int,Int,Int),
        pad, pminrow,pmincol,sminrow,smincol,smaxrow,smaxcol )
end
