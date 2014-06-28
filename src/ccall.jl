#= PLEASE NOTE THAT ALL NCURSES FUNCS ARE ZERO-BASED
=#
libncurses = dlopen("libncurses")
libpanel = dlopen("libpanel")

function newwin( lines, cols, origy, origx )
    ccall( dlsym( libncurses, :newwin ), Ptr{Void}, ( Int, Int, Int, Int ),
        lines, cols, origy, origx )
end

function delwin( win::Ptr{Void} )
    ccall( dlsym( libncurses, :delwin ), Void, ( Ptr{Void}, ), win )
end

function mvwaddch( win, y, x, c )
    ccall( dlsym( libncurses, :mvwaddch), Void,
        ( Ptr{Void}, Int, Int, Int ), win, y, x, c )
end

function mvwprintw( win::Ptr{Void}, row::Int, height::Int, fmt::String, str::String )
    ccall( dlsym( libncurses, :mvwprintw), Void,
        ( Ptr{Void}, Int, Int, Ptr{Uint8}, Ptr{Uint8}),
        win, row, height, fmt, str )
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
    ccall( dlsym( libncurses, :wgetch ), Int, (Ptr{Void},), win )
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

function timeout( delay )
    ccall( dlsym( libncurses, :timeout ), Void, (Int,), delay )
end

function wtimeout( win, delay )
    ccall( dlsym( libncurses, :wtimeout ), Void, (Ptr{Void}, Int), win, delay )
end

# not standard but convenient
function getwinmaxyx( win )
    maxy = ccall( dlsym(libncurses, :getmaxy), Int, ( Ptr{Void}, ), win )
    maxx = ccall( dlsym(libncurses, :getmaxx), Int, ( Ptr{Void}, ), win )
    ( maxy, maxx )
end

function beep()
    ccall( dlsym( libncurses, :beep ), Void, () )
end

function flash()
    ccall( dlsym( libncurses, :flash), Void, () )
end

function is_term_resized( lines, cols )
    ccall( dlsym( libncurses, :is_term_resized ), Bool, (Int, Int), lines, cols )
end

function wresize( win, lines, cols )
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

function curs_set( vis )
    ccall( dlsym(libncurses, :curs_set), Int, ( Int, ), vis )
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

function move_panel( win, starty, startx )
    ccall( dlsym( libpanel, :move_panel ), Ptr{Void}, ( Ptr{Void}, Int, Int ), win, starty, startx )
end

function del_panel( panel::Ptr{Void} )
    ccall(dlsym( libpanel, :del_panel ), Void, (Ptr{Void}, ), panel )
end

function replace_panel( panel::Ptr{Void}, window::Ptr{Void} )
    ccall(dlsym( libpanel, :replace_panel ), Void, (Ptr{Void}, Ptr{Void} ), panel, window )
end

function set_panel_userptr( p1::Ptr{Void}, p2::Ptr{Void} )
    ccall(dlsym( libpanel, :set_panel_userptr), Void, (Ptr{Void}, Ptr{Void}), p1, p2 )
end
