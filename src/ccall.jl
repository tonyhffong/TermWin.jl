#= Adapter layer: provides ncurses-compatible function signatures
   backed by Notcurses. This allows existing widget code to work
   with minimal changes during migration.
=#

# ===== Window/Plane management =====

# newwin equivalent: create a child plane of rootplane
function newwin( lines::Int, cols::Int, origy::Int, origx::Int )
    global rootplane
    NC.Plane(NC.LibNotcurses.ncplane_create(rootplane.ptr,
        NC.PlaneOptions(y=origy, x=origx, rows=lines, cols=cols)))
end

function delwin( win::NC.Plane )
    global rootplane
    if win != rootplane
        NC.destroy( win )
    end
end

# ===== Output functions =====

function mvwaddch( win::NC.Plane, y::Int, x::Int, c )
    NC.cursor_move_yx( win, y, x )
    if c isa Char
        NC.putstr( win, string(c) )
    elseif c isa Integer
        # Could be a Unicode codepoint or ACS value
        # In the old code, ACS values were special encoded ints.
        # With Notcurses, we just use Unicode chars directly.
        NC.putstr( win, string(Char(c)) )
    else
        NC.putstr( win, string(c) )
    end
end

function mvwaddch( w::TwWindow, y::Int, x::Int, c )
    if objtype( w.parent.value ) == :List && !isa( w.parent.value.window, TwWindow )
        # terminal layer. use its pad
        mvwaddch( w.parent.value.data.pad, y+w.yloc, x+w.xloc, c )
    else
        mvwaddch( w.parent.value.window, y+w.yloc, x+w.xloc, c )
    end
end

function mvwprintw( win::NC.Plane, row::Int, col::Int, fmt::String, str::T ) where {T<:AbstractString}
    NC.putstr_yx( win, row, col, str )
end

# note that it could in turn call another TwWindow...
function mvwprintw( w::TwWindow, y::Int, x::Int, fmt::String, s::T ) where {T<:AbstractString}
    if objtype( w.parent.value ) == :List && !isa( w.parent.value.window, TwWindow )
        # terminal layer. use its pad
        mvwprintw( w.parent.value.data.pad, y+w.yloc, x+w.xloc, fmt, s )
    else
        mvwprintw( w.parent.value.window, y+w.yloc, x+w.xloc, fmt, s )
    end
end

# ===== Cursor =====

function wmove( win::NC.Plane, y::Int, x::Int )
    NC.cursor_move_yx( win, y, x )
end

# ===== Erase / Clear =====

function erase()
    global rootplane
    if rootplane !== nothing
        NC.erase( rootplane )
    end
end

function werase( win::NC.Plane )
    NC.erase( win )
end

function werase( win::TwWindow, y::Int=win.yloc, x::Int=win.xloc, h::Int=win.height, w::Int=win.width )
    parwin = win.parent.value.window
    if isa( parwin, NC.Plane )
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

# ===== Box drawing =====

function box( win::NC.Plane, vchr, hchr )
    # Use Notcurses perimeter_rounded for a standard box
    NC.LibNotcurses.ncplane_perimeter_rounded( win.ptr, UInt16(0), NC.channels(win), UInt32(0) )
end

function box( win::TwWindow, vchr::Integer, hchr::Integer, y::Int=win.yloc, x::Int=win.xloc, h::Int=win.height, w::Int=win.width )
    parwin = win.parent.value.window
    if isa( parwin, NC.Plane )
        if objtype( win.parent.value ) == :List
            tmpw = win.parent.value.data.pad
        else
            tmpw = parwin
        end
        # Draw the box manually using Unicode box-drawing characters
        mvwaddch( tmpw, y,x, '┌' )
        mvwaddch( tmpw, y+h-1,x, '└' )
        mvwaddch( tmpw, y,x+w-1, '┐' )
        mvwaddch( tmpw, y+h-1,x+w-1, '┘' )

        vc = vchr==0 ? '│' : Char(vchr)
        hc = hchr==0 ? '─' : Char(hchr)
        for r = y+1:y+h-2
            mvwaddch( tmpw, r, x, vc )
            mvwaddch( tmpw, r, x+w-1, vc )
        end
        for c = x+1:x+w-2
            mvwaddch( tmpw, y, c, hc )
            mvwaddch( tmpw, y+h-1, c, hc )
        end
    else
        box( parwin, vchr, hchr, parwin.yloc+win.yloc, parwin.xloc+win.xloc, h, w )
    end
end

# ===== Window info =====

function getwinmaxyx( win::NC.Plane )
    d = NC.dim_yx( win )
    ( Int(d[1]), Int(d[2]) )
end

function getwinbegyx( win::NC.Plane )
    pos = NC.yx( win )
    ( Int(pos.y), Int(pos.x) )
end

function mvwin( win::NC.Plane, y::Int, x::Int )
    NC.move_yx( win, y, x )
end

function copywin( s::NC.Plane, d::NC.Plane, sminrow::Int, smincol::Int, dminrow::Int, dmincol::Int, dmaxrow::Int, dmaxcol::Int )
    leny = dmaxrow - dminrow + 1
    lenx = dmaxcol - dmincol + 1
    NC.mergedown( s, d, sminrow, smincol, leny, lenx, dminrow, dmincol )
end

function wresize( win::NC.Plane, lines::Int, cols::Int )
    NC.resize( win, 0, 0, 0, 0, 0, 0, lines, cols )
end

# ===== Color =====

function init_pair( pair, f, b )
    # Build the channel pair and store in the table
    color_channel_table[Int(pair)] = make_channel_pair(Int(f), Int(b))
end

# ===== Attributes =====

function wattroff( win::NC.Plane, attrs )
    if attrs isa TwAttr
        NC.off_styles( win, UInt32(attrs.style) )
        if attrs.channels != 0 || attrs.reverse
            NC.set_fg_default( win )
            NC.set_bg_default( win )
        end
    else
        s, c, r = decompose_attrs(attrs)
        NC.off_styles( win, UInt32(s) )
        if c != 0 || r
            NC.set_fg_default( win )
            NC.set_bg_default( win )
        end
    end
end

function wattroff( win::TwWindow, attrs )
    parwin = win.parent.value.window
    if objtype( win.parent.value ) == :List && isa( parwin, NC.Plane )
        wattroff( win.parent.value.data.pad, attrs )
    else
        wattroff( win.parent.value.window, attrs )
    end
end

function wattron( win::NC.Plane, attrs )
    if attrs isa TwAttr
        NC.on_styles( win, UInt32(attrs.style) )
        if attrs.channels != 0
            NC.set_channels( win, attrs.channels )
        end
        if attrs.reverse
            # Swap fg and bg channels
            ch = NC.channels( win )
            fg = (ch >> 32) & 0xFFFFFFFF
            bg = ch & 0xFFFFFFFF
            NC.set_channels( win, (bg << 32) | fg )
        end
    else
        s, c, r = decompose_attrs(attrs)
        NC.on_styles( win, UInt32(s) )
        if c != 0
            NC.set_channels( win, c )
        end
        if r
            ch = NC.channels( win )
            fg = (ch >> 32) & 0xFFFFFFFF
            bg = ch & 0xFFFFFFFF
            NC.set_channels( win, (bg << 32) | fg )
        end
    end
end

function wattron( win::TwWindow, attrs )
    parwin = win.parent.value.window
    if objtype( win.parent.value ) == :List && isa( parwin, NC.Plane )
        wattron( win.parent.value.data.pad, attrs )
    else
        wattron( win.parent.value.window, attrs )
    end
end

# ===== Mouse =====

# Mouse event cache (populated by readtoken)
const _last_mouse_event = Ref{Any}((:unknown, 0, 0, nothing))

function getmouse()
    return _last_mouse_event[]
end

function screen_to_relative( w::NC.Plane, y::Integer, x::Integer )
    pos = NC.yx( w )
    begy = Int(pos.y)
    begx = Int(pos.x)
    ( y-begy, x-begx )
end

function screen_to_relative( w::TwWindow, y::Integer, x::Integer )
    # figure out the canvas coordinate, ultimate parent
    xloc = w.xloc
    yloc = w.yloc
    par = w.parent.value
    while( !isa( par.window, NC.Plane ) )
        xloc += par.window.xloc
        yloc += par.window.yloc
        par = par.window.parent.value
    end
    (view_rel_y, view_rel_x) = screen_to_relative( par.window, y, x )

    ( par.data.canvaslocy + view_rel_y, par.data.canvaslocx + view_rel_x )
end

# ===== Misc =====

function beep()
    write(stdout, '\a')
end

# ===== Panel library (mapped to plane z-ordering) =====
# In Notcurses, panels are just planes with z-ordering.
# These functions operate on planes directly.

function top_panel( pan::NC.Plane )
    # Move plane to top of z-stack (pass C_NULL as "below" to move to top)
    NC.move_below( pan, C_NULL )
end

function show_panel( panel::NC.Plane )
    global hidden_planes
    # Restore from hidden position if it was hidden
    if haskey( hidden_planes, panel.ptr )
        (oy, ox) = hidden_planes[panel.ptr]
        NC.move_yx( panel, oy, ox )
        delete!( hidden_planes, panel.ptr )
    end
end

function hide_panel( panel::NC.Plane )
    global hidden_planes
    # Save current position and move off-screen
    pos = NC.yx( panel )
    hidden_planes[panel.ptr] = (Int(pos.y), Int(pos.x))
    NC.move_yx( panel, -10000, -10000 )
end

function panel_hidden( panel::NC.Plane )
    global hidden_planes
    haskey( hidden_planes, panel.ptr )
end

# ===== Pad functions =====

function newpad( rows::Int, cols::Int )
    global rootplane
    # Create a large off-screen plane to serve as a pad
    NC.Plane(NC.LibNotcurses.ncplane_create(rootplane.ptr,
        NC.PlaneOptions(y=-10000, x=-10000, rows=rows, cols=cols)))
end

