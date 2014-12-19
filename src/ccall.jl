#= PLEASE NOTE THAT ALL NCURSES FUNCS ARE ZERO-BASED
=#
libncurses = dlopen("libncurses")
libpanel = dlopen("libpanel")

function initscr()
    ccall( dlsym( libncurses, :initscr), Ptr{Void}, () )
end

function endwin()
    ccall( dlsym( libncurses, :endwin), Int, () )
end

function isendwin()
    ccall( dlsym( libncurses, :isendwin), Bool, () )
end

function newwin( lines::Int, cols::Int, origy::Int, origx::Int )
    ccall( dlsym( libncurses, :newwin ), Ptr{Void}, ( Int, Int, Int, Int ),
        lines, cols, origy, origx )
end

function subwin( win::Ptr{Void}, lines::Int, cols::Int, origy::Int, origx::Int )
    ccall( dlsym( libncurses, :subwin ), Ptr{Void}, ( Ptr{Void}, Int, Int, Int, Int ),
        win, lines, cols, origy, origx )
end

function derwin( win, lines::Int, cols::Int, origy::Int, origx::Int )
    ccall( dlsym( libncurses, :derwin ), Ptr{Void}, ( Ptr{Void}, Int, Int, Int, Int ),
        win, lines, cols, origy, origx )
end

function delwin( win::Ptr{Void} )
    ccall( dlsym( libncurses, :delwin ), Void, ( Ptr{Void}, ), win )
end

function mvwaddch( win, y::Int, x::Int, c )
    ccall( dlsym( libncurses, :mvwaddch), Void,
        ( Ptr{Void}, Int, Int, Int ), win, y, x, c )
end

function mvwprintw( win::Ptr{Void}, row::Int, height::Int, fmt::String, str::String )
    ccall( dlsym( libncurses, :mvwprintw), Void,
        ( Ptr{Void}, Int, Int, Ptr{Uint8}, Ptr{Uint8}),
        win, row, height, fmt, str )
end

function wmove( win, y::Int, x::Int )
    ccall( dlsym( libncurses, :wmove), Int, ( Ptr{Void}, Int, Int ), win, y, x )
end

function wrefresh( win::Ptr{Void} )
    ccall( dlsym( libncurses, :wrefresh ), Void, ( Ptr{Void}, ), win )
end

function touchwin( win::Ptr{Void} )
    ccall( dlsym( libncurses, :touchwin ), Void, ( Ptr{Void}, ), win )
end

function refresh()
    ccall( dlsym( libncurses, :refresh ), Void, ( ) )
end

function erase()
    ccall( dlsym( libncurses, :erase ), Void, () )
end

function werase( win::Ptr{Void} )
    ccall( dlsym( libncurses, :werase ), Void, (Ptr{Void},), win )
end

function wclear( win::Ptr{Void} )
    ccall( dlsym( libncurses, :wclear ), Void, (Ptr{Void},), win )
end

function box( win, vchr, hchr )
    ccall( dlsym( libncurses, :box ), Void, (Ptr{Void}, Char, Char), win, vchr, hchr )
end

function wgetch( win::Ptr{Void } )
    ccall( dlsym( libncurses, :wgetch ), Uint32, (Ptr{Void},), win )
end

function keypad( win, bf )
    ccall( dlsym( libncurses, :keypad ), Int, (Ptr{Void}, Bool), win, bf )
end

function cbreak()
    ccall( dlsym( libncurses, :cbreak), Void, ( ) )
end

function nocbreak()
    ccall( dlsym( libncurses, :nocbreak), Void, ( ) )
end

function echo()
    ccall( dlsym( libncurses, :echo), Void, ( ) )
end

function noecho()
    ccall( dlsym( libncurses, :noecho), Void, ( ) )
end

function nodelay( win, bf )
    ccall( dlsym( libncurses, :nodelay ), Int, (Ptr{Void}, Bool), win, bf )
end

function raw()
    ccall( dlsym( libncurses, :raw ), Int, () )
end

function noraw()
    ccall( dlsym( libncurses, :noraw ), Int, () )
end

function notimeout( win, bf )
    ccall( dlsym( libncurses, :notimeout ), Int, (Ptr{Void}, Bool), win, bf )
end

function timeout( delay::Int )
    ccall( dlsym( libncurses, :timeout ), Void, (Int,), delay )
end

function wtimeout( win, delay::Int )
    ccall( dlsym( libncurses, :wtimeout ), Void, (Ptr{Void}, Int), win, delay )
end

# not standard but convenient
function getwinmaxyx( win )
    maxy = ccall( dlsym(libncurses, :getmaxy), Int, ( Ptr{Void}, ), win )
    maxx = ccall( dlsym(libncurses, :getmaxx), Int, ( Ptr{Void}, ), win )
    ( maxy, maxx )
end

function getwinbegyx( win )
    maxy = ccall( dlsym(libncurses, :getbegy), Int, ( Ptr{Void}, ), win )
    maxx = ccall( dlsym(libncurses, :getbegx), Int, ( Ptr{Void}, ), win )
    ( maxy, maxx )
end

function mvwin( win, y::Int, x::Int )
    ccall( dlsym( libncurses, :mvwin), Int, ( Ptr{Void}, Int, Int ), win, y, x )
end

function beep()
    ccall( dlsym( libncurses, :beep ), Void, () )
end

function flash()
    ccall( dlsym( libncurses, :flash), Void, () )
end

function is_term_resized( lines::Int, cols::Int )
    ccall( dlsym( libncurses, :is_term_resized ), Bool, (Int, Int), lines, cols )
end

function wresize( win, lines::Int, cols::Int )
    ccall( dlsym( libncurses, :wresize), Int, (Ptr{Void}, Int, Int), win, lines, cols )
end

function getcuryx( win )
    cury = ccall( dlsym(libncurses, :getcury), Cint, ( Ptr{Void}, ), win )
    curx = ccall( dlsym(libncurses, :getcurx), Cint, ( Ptr{Void}, ), win )
    ( cury, curx )
end

function start_color()
    ccall( dlsym( libncurses, :start_color), Void, () )
end

function init_pair( pair, f, b )
    ccall( dlsym( libncurses, :init_pair ), Int, ( Int16, Int16, Int16 ), pair, f, b )
end

function init_color( color, r,g,b )
    ccall( dlsym( libncurses, :init_color ), Int, ( Int16, Int16, Int16, Int16 ),
        color, r,g,b )
end

function has_colors()
    ccall( dlsym( libncurses, :has_colors), Bool, () )
end

function wattroff( win, attrs )
    ccall( dlsym(libncurses, :wattroff), Int, ( Ptr{Void}, Uint32 ), win, attrs )
end

function wattron( win, attrs )
    ccall( dlsym(libncurses, :wattron), Int, ( Ptr{Void}, Uint32 ), win, attrs )
end

function wattrset( win, attrs )
    ccall( dlsym(libncurses, :wattrset), Int, ( Ptr{Void}, Uint32 ), win, attrs )
end

function wbkgdset( win, ch )
    ccall( dlsym(libncurses, :wbkgdset ), Void, ( Ptr{Void}, Uint32 ), win, ch )
end

function wbkgd( win, ch )
    ccall( dlsym(libncurses, :wbkgd ), Void, ( Ptr{Void}, Uint32 ), win, ch )
end

function curs_set( vis )
    ccall( dlsym(libncurses, :curs_set), Int, ( Int, ), vis )
end

function has_mouse()
    ccall( dlsym(libncurses, :has_mouse), Bool, () )
end

function mousemask( mask )
    oldmm = Array( Uint64, 1 )
    resultmm = ccall( dlsym( libncurses, :mousemask), Uint64, (Uint64, Ptr{Uint64}), mask, oldmm )
    ( resultmm, oldmm[1])
end

function mouseinterval( n::Int )
    ccall( dlsym(libncurses, :mouseinterval), Int, (Int, ) , n)
end

#hack!
const mouseByteString = bytestring( Array( Uint8, 64 ) )
function getmouse()
    #=
    type Mouse_Event_t
        id::Int8 # short
        x::Int32 # int
        y::Int32 # int
        z::Int32 # int
        bstate::Uint64 # unsigned long
    end
    =#
    # the 5th byte is x, 9th byte is y
    # 19th byte is x08 if scroll up, 20th byte is x08 if scroll down
    # 17th byte is x02 if button 1 pressed
    # 17th byte is x01 if button 1 released
    # 17-18th is 0xfffd if mousewheel is pressed down
    ccall( dlsym( libncurses, :getmouse), Int, (Ptr{Uint8}, ), mouseByteString )
    bs = mouseByteString
    x = uint8(bs[5])
    y = uint8(bs[9])
    state=:unknown
    if bs[17] & 0x02 != 0
        state = :button1_pressed
    elseif bs[19] & 0x08 != 0
        state = :scroll_up
    elseif bs[20] & 0x08 != 0
        state = :scroll_down
    end
    ( state, x, y, bs )
end

function baudrate()
    ccall( dlsym( libncurses, :baudrate), Int, () )
end

function clearok( win, bf )
    ccall( dlsym( libncurses, :clearok), Int, ( Ptr{Void}, Bool ), win, bf )
end

function immedok( win, bf )
    ccall( dlsym( libncurses, :immedok), Int, ( Ptr{Void}, Bool ), win, bf )
end

function napms( ms::Int )
    ccall( dlsym( libncurses, :napms), Int, (Int, ), ms )
end

#===== PANEL library ====#

function update_panels()
    ccall( dlsym( libpanel, :update_panels), Void, () )
end

function doupdate()
    ccall( dlsym( libpanel, :doupdate ), Void, () )
end

function new_panel( win::Ptr{Void} )
    ccall( dlsym( libpanel, :new_panel ), Ptr{Void}, ( Ptr{Void}, ), win )
end

function top_panel( pan::Ptr{Void} )
    ccall( dlsym( libpanel, :top_panel ), Int, ( Ptr{Void}, ), pan )
end

function bottom_panel( pan::Ptr{Void} )
    ccall( dlsym( libpanel, :bottom_panel ), Int, ( Ptr{Void}, ), pan )
end

function move_panel( pan::Ptr{Void}, starty::Int, startx::Int )
    ccall( dlsym( libpanel, :move_panel ), Ptr{Void}, ( Ptr{Void}, Int, Int ), pan, starty, startx )
end

function del_panel( panel::Ptr{Void} )
    ccall(dlsym( libpanel, :del_panel ), Void, (Ptr{Void}, ), panel )
end

function show_panel( panel::Ptr{Void} )
    ccall(dlsym( libpanel, :show_panel ), Int, (Ptr{Void}, ), panel )
end

function hide_panel( panel::Ptr{Void} )
    ccall(dlsym( libpanel, :hide_panel ), Int, (Ptr{Void}, ), panel )
end

function panel_hidden( panel::Ptr{Void } )
    ccall(dlsym( libpanel, :panel_hidden ), Int, (Ptr{Void}, ), panel ) != 0
end

function replace_panel( panel::Ptr{Void}, window::Ptr{Void} )
    ccall(dlsym( libpanel, :replace_panel ), Void, (Ptr{Void}, Ptr{Void} ), panel, window )
end

function set_panel_userptr( p1::Ptr{Void}, p2::Ptr{Void} )
    ccall(dlsym( libpanel, :set_panel_userptr), Void, (Ptr{Void}, Ptr{Void}), p1, p2 )
end
