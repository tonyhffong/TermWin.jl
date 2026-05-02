module TermWin

using Format
using Dates
using DataFrames
using CategoricalArrays
using Statistics
using Printf
using BusinessDays
import Notcurses as NC

debugloghandle = nothing

function logstart()
    global debugloghandle
    debugloghandle = open(joinpath(pkgdir(@__MODULE__), "debug.log"), "a+")
end

function log(s::String)
    global debugloghandle
    if debugloghandle !== nothing
        write(debugloghandle, string(now()) * " ")
        write(debugloghandle, s)
        write(debugloghandle, "\n")
        flush(debugloghandle)
    end
end

import Base.getindex

# uncomment this to provide logging functionality
# or just call TermWin.logstart() in user's script
# logstart()

include("consts.jl")
include("twtypes.jl")
include("twobj.jl")
include("twscreen.jl")
include("ccall.jl")
include("strutils.jl")
include("format.jl")
include("dfutils.jl")
#include( "twprogress.jl")
include("twviewer.jl")
include("twentry.jl")
include("readtoken.jl")
include("twtree.jl")
include("twfilebrowser.jl")
include("twfunc.jl")
include("twpopup.jl")
include("twmultiselect.jl")
include("twcalendar.jl")
include("twdftable.jl")
include("twlist.jl")
include("twlabel.jl")
include("twedittable.jl")
include("twdicttree.jl")
include("twbuilder.jl")
include("precompile.jl")

export tshow, activateTwObj, registerTwObj, unregisterTwObj
export trun # experimental
export TwObj, TwScreen, rootTwScreen
export newTwScreen
export vstack, hstack, @twlayout
export newTwEntry, newTwTree, newTwFileBrowser, newTwFunc, newTwViewer
export newTwCalendar, newTwPopup, newTwMultiSelect
export newTwDfTable, newTwList
export newTwEditTable, TwEditTableCol
export newTwDictTree
export newTwSpacer, newTwLabel

export uniqvalue, unionall
export CalcPivot, discretize, topnames
export FormatHints
export COLOR_PAIR

# ===== Global state =====
nc_context = nothing   # ::Union{Nothing, NC.NotcursesObject}
rootplane = nothing   # ::Union{Nothing, NC.Plane}
rootTwScreen = nothing
callcount = 0
current_session_id = 0  # incremented each time a new NC session is started

# Hidden plane tracking: maps Plane ptr -> original (y,x) before hiding
const hidden_planes = Dict{Ptr{NC.LibNotcurses.ncplane},Tuple{Int,Int}}()

function extractkwarg!(kwargs, sym::Symbol, def::Any)
    for (i, t) in enumerate(kwargs)
        if t[1] == sym
            return t[2]
        end
    end
    return def
end

function initsession()
    global nc_context, rootplane
    global rootTwScreen
    global widgetStaggerPosx
    global widgetStaggerPosy
    global current_session_id

    widgetStaggerPosx = 0
    widgetStaggerPosy = 0
    if nc_context === nothing
        current_session_id += 1
        nc_context = NC.NotcursesObject(
            opts = NC.Options(flags = UInt(NC.LibNotcurses.NCOPTION_SUPPRESS_BANNERS)),
        )
        rootplane = NC.stdplane(nc_context)
        NC.mice_enable(nc_context)
        NC.cursor_disable(nc_context)

        # Build color_channel_table from the old init_pair definitions
        # pair_number => (fg_color_index, bg_color_index)
        pairs = Dict{Int,Tuple{Int,Int}}(
            1 => (COLOR_RED, COLOR_BLACK),
            2 => (COLOR_GREEN, COLOR_BLACK),
            3 => (COLOR_YELLOW, COLOR_BLACK),
            4 => (COLOR_BLUE, COLOR_BLACK),
            5 => (COLOR_MAGENTA, COLOR_BLACK),
            6 => (COLOR_CYAN, COLOR_BLACK),
            7 => (COLOR_WHITE, COLOR_BLACK),
            8 => (COLOR_BLACK, 21),   # black on bright blue
            9 => (COLOR_RED, 19),   # red on blue
            10 => (COLOR_GREEN, 19),   # green on blue
            11 => (COLOR_YELLOW, 19),   # yellow on blue
            12 => (COLOR_WHITE, 52),   # white on dark red
            13 => (COLOR_WHITE, 234),  # white on dark gray
            14 => (COLOR_CYAN, 19),   # cyan on blue
            15 => (COLOR_WHITE, 19),   # white on blue
            16 => (COLOR_BLACK, 52),
            17 => (COLOR_RED, 52),
            18 => (COLOR_GREEN, 52),
            19 => (COLOR_YELLOW, 52),
            20 => (COLOR_BLUE, 52),
            21 => (COLOR_MAGENTA, 52),
            22 => (COLOR_CYAN, 52),
            23 => (COLOR_WHITE, 52),
            24 => (56, COLOR_BLACK),  # light purple on black
            25 => (56, 19),           # light purple on dark blue
            26 => (COLOR_GREEN, 19),  # green on dark blue
            27 => (COLOR_YELLOW, 19),  # yellow on dark blue
            28 => (8, 19),           # gray on dark blue
            29 => (COLOR_RED, 235),    # red on dark gray
            30 => (COLOR_WHITE, 17),   # white on dark blue
            31 => (COLOR_RED, 17),   # red on dark blue
        )
        for (n, (fg, bg)) in pairs
            color_channel_table[n] = make_channel_pair(fg, bg)
        end

        dims = NC.term_dim_yx(nc_context)
        rootTwScreen = newTwScreen(rootplane, Int(dims.rows), Int(dims.cols))

        msg = string(Char(0xb83)) * " TermWin: Please wait ..."
        NC.putstr_yx(
            rootplane,
            div(rootTwScreen.height, 2),
            div(rootTwScreen.width - length(msg), 2),
            msg,
        )
        NC.render(nc_context)
    else
        # in case the terminal has been resized
        dims = NC.term_dim_yx(nc_context)
        maxy = Int(dims.rows)
        maxx = Int(dims.cols)
        if maxy != rootTwScreen.height || maxx != rootTwScreen.width
            # Terminal was resized - update screen dimensions
            rootTwScreen.height = maxy
            rootTwScreen.width = maxx
        end
        NC.render(nc_context)
    end
end

function get_acs_val(c::Char)
    get(ACS_MAP, c, c)
end

function endsession()
    global nc_context, rootplane, rootTwScreen
    if nc_context !== nothing
        # Capture the live reference, then nil out the globals BEFORE calling
        # NC.stop().  That way any TwObj finalizer that fires (now or later)
        # will see nc_context === nothing and skip ncplane_destroy — avoiding a
        # double-free, because NC.stop() will free every plane itself.
        local_nc = nc_context
        nc_context = nothing
        rootplane = nothing
        NC.mice_disable(local_nc)
        NC.cursor_enable(local_nc, 0, 0)
        NC.stop(local_nc)
        empty!(hidden_planes)   # clear stale plane pointers from this session
        # Belt-and-suspenders: send raw escape sequences to ensure the terminal
        # is fully restored. notcurses_stop should do this, but if it doesn't
        # the terminal is left with mouse tracking on, making every key "escaped".
        print(stdout, "\e[<u")      # pop kitty keyboard protocol stack
        print(stdout, "\e[=0u")     # disable all kitty keyboard protocol flags
        print(stdout, "\e[?1000l")  # disable mouse click tracking
        print(stdout, "\e[?1003l")  # disable all-motion mouse tracking
        print(stdout, "\e[?1006l")  # disable SGR extended mouse mode
        print(stdout, "\e[?25h")    # show cursor
        flush(stdout)
    end
end

function tshow_(x::Number; kwargs...)
    typx = typeof(x)
    if typx <: Integer && typx <: Unsigned
        s = @sprintf("0x%x", x)
    else
        s = string(x)
    end
    tshow_(s; kwargs...)
end

tshow_(x::Symbol; kwargs...) = tshow_(":"*string(x); kwargs...)
tshow_(x::Ptr; kwargs...) = tshow_(string(x); kwargs...)
function tshow_(x::WeakRef; kwargs...)
    if x.value === nothing
        tshow_("WeakRef: nothing"; kwargs...)
    else
        tshow_(x.value; kwargs...)
    end
end

function tshow_(x::String; kwargs...)
    pos = :center
    if length(x) > 100
        pos = :staggered
    end
    posx = get(kwargs, :posx, pos)
    posy = get(kwargs, :posy, pos)
    newTwViewer(rootTwScreen, x; posy = posy, posx = posx, kwargs...)
end

#TODO: support a variety of hint e.g. "url", "json", "xml" ...
function tshow_(x::String, hint::String; kwargs... )
    if hint == "path"
        if length(x)<400 && isdir(x)
            p=abspath(x)
            if basename(p)==""
                p = dirname(p)
            end
            return newTwFileBrowser( rootTwScreen, p, title = p )
        end
        println("Unknown path: " * x )
    else
        tshow_( x; kwargs... )
    end
end

function tshow_(f::Function; kwargs...)
    try
        mt = methods(f)
        return newTwFunc(rootTwScreen, collect(mt); kwargs...)
    catch y
        log("fail to display newTwFunc on function")
        return tshow_(string(f) * ": (anonymous?)\n" * string(y); kwargs...)
    end
end

function tshow_(ms::Vector{Method}; kwargs...)
    newTwFunc(rootTwScreen, ms; kwargs...)
end

function tshow_(df::DataFrame; kwargs...)
    newTwDfTable(rootTwScreen, df; kwargs...)
end

function tshow_(df::DataFrame,cols::Vector{TwEditTableCol}; kwargs...)
    newTwEditTable(rootTwScreen, df, cols; kwargs...)
end

function tshow_(o::TwObj; kwargs...)
    registerTwObj(rootTwScreen, o)
    return o
end

function tshow_(x; kwargs...)
    newTwTree(rootTwScreen, x; kwargs...)
end

function winnewcenter(ysize, xsize, locy = 0.5, locx = 0.5)
    global nc_context, rootplane
    dims = NC.term_dim_yx(nc_context)
    maxy = Int(dims.rows)
    maxx = Int(dims.cols)
    local cols, lines, origx, origy
    if isa(ysize, Int)
        lines = ysize
    elseif isa(ysize, Float64) && 0.0 < ysize <= 1.0
        lines = Int(maxy * ysize)
        if lines == 0
            throw("lines are too small")
        end
    else
        throw("illegal ysize " * string(ysize))
    end

    if isa(xsize, Int)
        cols = xsize
    elseif isa(xsize, Float64) && 0.0 < xsize <= 1.0
        cols = Int(maxx * xsize)
        if cols == 0
            throw("cols are too small")
        end
    else
        throw("illegal xsize " * string(ysize))
    end

    if isa(locy, Int)
        origy = max(0, min(locy, maxy-lines-1))
    elseif isa(locy, Float64) && 0.0 <= locy <= 1.0
        origy = Int(floor(locy * (maxy - lines)))
    else
        throw("illegal locy " * string(locy))
    end

    if isa(locx, Int)
        origx = max(0, min(locx, maxx-cols-1))
    elseif isa(locx, Float64) && 0.0 <= locx <= 1.0
        origx = Int(floor(locx * (maxx - cols)))
    else
        throw("illegal locx " * string(locx))
    end
    plane = NC.Plane(
        NC.LibNotcurses.ncplane_create(
            rootplane.ptr,
            NC.PlaneOptions(y = origy, x = origx, rows = lines, cols = cols),
        ),
    )
    plane
end

function titleof(x::Any)
    typx = typeof(x)
    if typx == Module || typx == Function
        return string(x)
    else
        return string(typx)
    end
end

# it'd return the widget, which can be displayed again.
function tshow(x...; kwargs...)
    global callcount, nc_context, rootTwScreen, rootplane
    title = extractkwarg!(kwargs, :title, titleof(x))
    widget = nothing
    if callcount == 0
        initsession()
        callcount += 1
        werase(rootplane)
        try
            widget = Base.invokelatest(tshow_, x...; title = title, kwargs...)
            if widget !== nothing
                activateTwObj(rootTwScreen)
            end
        catch err
            callcount -= 1
            endsession()
            rethrow(err)
        end
        callcount -= 1
        endsession()
        return widget
    else
        found = false
        for o in rootTwScreen.data.objects
            if !in(objtype(o), [:Entry, :Viewer, :Calendar]) && isequal(o.value, x)
                raiseTwObject(o)
                found = true
                widget = o
                break
            end
        end
        if !found
            widget = nothing
            try
                widget = Base.invokelatest(tshow_, x; title = title, kwargs...)
            catch err
                bt = catch_backtrace()
                msg = wordwrap(string(err) * "\n" * string(bt), 80)
                widget = tshow_(msg; title = "Error")
            end
            if widget !== nothing
                refresh(rootTwScreen)
            end
        end
        return widget
    end
end

# f is a no-arg function
function trun(f::Function; kwargs...)
    # async start the function
    # start the progress bar window and listen to it
    global callcount, nc_context, rootTwScreen
    @async begin
        problem = false
        updateProgressChannel(:init, nothing)
        try
            val = f()
            updateProgressChannel(:done, val)
        catch er
            updateProgressChannel(:error, er)
        end
    end

    ret = nothing

    if callcount == 0
        initsession()
        callcount += 1
        werase(rootplane)
        try
            o = newTwProgress(rootTwScreen; kwargs...)
            if o !== nothing
                activateTwObj(rootTwScreen)
                ret = o.value
            end
        catch er
            callcount -= 1
            endsession()
            rethrow(er)
        end
        callcount -= 1
        endsession()
        return ret
    else
        found = false
        for o in rootTwScreen.data.objects
            if objtype(o) == :Progress
                raiseTwObject(o)
                o.isvisible = true
                found = true
                break
            end
        end
        if !found
            o = newTwProgress(rootTwScreen; kwargs...)
            o.hasFocus = true
            rootTwScreen.data.focus = length(rootTwScreen.data.objects)
            refresh(rootTwScreen)
        end
        return nothing
    end
end

# to use this
# using TermWin
# TermWin.testkeydialog()
function testkeydialog()
    global nc_context, rootplane
    width = 42
    initsession()
    NC.erase(rootplane)
    NC.render(nc_context)
    win = winnewcenter(6, width)
    box(win, 0, 0)
    title = "Test Key/Mouse/Unicode"
    keyhint = "[Esc to continue]"

    mvwprintw(win, 0, Int((width-length(title))>>1), "%s", title)
    mvwprintw(win, 5, Int((width-length(keyhint))>>1), "%s", keyhint)
    NC.render(nc_context)
    local token
    while ((token = readtoken(nc_context)) != :esc)
        if token == :nochar
            continue
        end
        werase(win)
        box(win, 0, 0)
        mvwprintw(win, 0, Int((width-length(title))>>1), "%s", title)
        mvwprintw(win, 5, Int((width-length(keyhint))>>1), "%s", keyhint)
        if isa(token, AbstractString)
            k = ""
            for c in token
                if isprint(c) && isascii(c)
                    k *= string(c)
                else
                    k *= @sprintf("{%x}", UInt(c))
                end
            end
            mvwprintw(win, 1, 2, "%s", k)
            if 1 <= length(token) == 1 && UInt64(token[1]) <= 127
                ch = get_acs_val(token[1])
                mvwprintw(win, 2, 2, "%s", "acs_val:" * string(ch))
            else
                mvwprintw(win, 2, 2, "%s", "print  :" * string(token[1]))
            end
        elseif token == :KEY_MOUSE
            (state, x, y, bs) = getmouse()
            mvwprintw(win, 1, 2, "%s", @sprintf("x:%d y:%d", x, y))
            mvwprintw(win, 2, 2, "%s", ":" * string(state))
        elseif isa(token, Symbol)
            mvwprintw(win, 1, 2, "%s", ":" * string(token))
        end
        NC.render(nc_context)
    end
    NC.destroy(win)
    endsession()
end

end
