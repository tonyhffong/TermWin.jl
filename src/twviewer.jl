
defaultViewerHelpText = """
PgUp/PgDn,←/→/↑/↓ : standard navigation
l          : move halfway toward the start
L          : move halfway to the end
Home       : jump to the start
End        : jump to the end
"""

mutable struct TwViewerData
    messages::Array
    msglen::Int
    msgwidth::Int
    currentTop::Int
    currentLine::Int
    currentLeft::Int
    showLineInfo::Bool # e.g.1/100 1.0% at top right corner
    bottomText::String
    trackLine::Bool
    showHelp::Bool
    helpText::String
    tabWidth::Int
    colorspans::Union{Nothing, Vector{Vector{Tuple{Int,Int,TwAttr}}}}
    filename::String #if we want to introduce a shortcut to edit the file
    fileloc::Int     #if we want to introduce a shortcut to edit the file
    TwViewerData() =
        new(String[], 0, 0, 1, 1, 1, true, "", false, true, defaultViewerHelpText, 4, nothing, "", 0 )
end

# the ways to use it:
# exact dimensions known: h,w,y,x, content to add later
# exact dimensions unknown, but content known and content drives dimensions
function newTwViewer(
    scr::TwScreen;
    height::Real = 0.5,
    width::Real = 0.8,
    posy::Any = :staggered,
    posx::Any = :staggered,
    box = true,
    showLineInfo = true,
    showHelp = true,
    bottomText = "",
    tabWidth = 4,
    trackLine = false,
    title = "",
    filename = "",
    fileloc = 0
)
    obj = TwObj(TwViewerData(), Val{:Viewer})
    obj.box = box
    obj.title = title
    obj.borderSizeV = box ? 1 : 0
    obj.borderSizeH = box ? 2 : 0
    obj.data.showLineInfo = showLineInfo
    obj.data.showHelp = showHelp
    obj.data.tabWidth = tabWidth
    obj.data.bottomText = bottomText
    obj.data.trackLine = trackLine
    obj.data.filename = filename
    obj.data.fileloc = fileloc
    link_parent_child(scr, obj, height, width, posy, posx)
    obj
end

function newTwViewer(
    scr::TwObj,
    msgs::Array;
    height::Real = 0,
    width::Real = 0,
    posy::Any = :staggered,
    posx::Any = :staggered,
    box = true,
    showLineInfo = true,
    bottomText = "F1:Help",
    showHelp = true,
    tabWidth = 4,
    trackLine = false,
    title = "",
    filename = "",
    fileloc = 0
)
    newmsgs = map(z->escape_string(replace(z, "\t" => repeat(" ", tabWidth))), msgs)
    obj = TwObj(TwViewerData(), Val{:Viewer})
    obj.title = title
    setTwViewerMsgs(obj, newmsgs)
    obj.box = box
    obj.borderSizeV = box ? 1 : 0
    obj.borderSizeH = box ? 2 : 0
    obj.data.showLineInfo = showLineInfo
    obj.data.showHelp = showHelp
    obj.data.tabWidth = tabWidth
    obj.data.bottomText = bottomText
    obj.data.trackLine = trackLine
    obj.data.filename = filename
    obj.data.fileloc = fileloc

    # If caller specified explicit size, honour it; otherwise auto-size from content.
    h =
        height != 0 ? height :
        obj.data.msglen +
        obj.borderSizeV * 2 +
        (!box && !isempty(obj.data.bottomText) ? 1 : 0)
    w =
        width != 0 ? width :
        max(25, obj.data.msgwidth + obj.borderSizeH * 2, length(title)+6)

    link_parent_child(scr, obj, h, w, posy, posx)
    obj
end

function newTwViewer(
    scr::TwObj, msg::T;
    highlight::Bool  = false,
    height::Real     = 0,
    width::Real      = 0,
    posy::Any        = :staggered,
    posx::Any        = :staggered,
    box              = true,
    showLineInfo     = true,
    bottomText       = "",
    showHelp         = true,
    tabWidth         = 4,
    trackLine        = false,
    title            = "",
    filename         = "",
    fileloc          = 0
) where {T<:AbstractString}
    if !highlight
        return newTwViewer(scr, split(String(msg), "\n");
            height=height, width=width, posy=posy, posx=posx, box=box,
            showLineInfo=showLineInfo, bottomText=bottomText, showHelp=showHelp,
            tabWidth=tabWidth, trackLine=trackLine, title=title, filename=filename, fileloc=fileloc)
    end
    # Highlighted path: tab-expand whole source first so span byte offsets align
    src   = replace(String(msg), "\t" => repeat(" ", tabWidth))
    lines = split(src, "\n", keepempty=true)
    obj   = TwObj(TwViewerData(), Val{:Viewer})
    obj.title           = title
    obj.box             = box
    obj.borderSizeV     = box ? 1 : 0
    obj.borderSizeH     = box ? 2 : 0
    obj.data.showLineInfo = showLineInfo
    obj.data.showHelp     = showHelp
    obj.data.tabWidth     = tabWidth
    obj.data.trackLine    = trackLine
    obj.data.filename     = filename
    obj.data.fileloc      = fileloc
    obj.data.bottomText   = "F1:Help"

    if bottomText != "" && filename != ""
        obj.data.bottomText *= "  F11:vim"
    end

    setTwViewerMsgs(obj, lines)
    try
        obj.data.colorspans = _highlight_julia_spans(src)
    catch
    end
    h = height != 0 ? height :
        obj.data.msglen + obj.borderSizeV * 2 +
        (!box && !isempty(obj.data.bottomText) ? 1 : 0)
    w = width != 0 ? width :
        max(25, obj.data.msgwidth + obj.borderSizeH * 2, length(title) + 6)
    link_parent_child(scr, obj, h, w, posy, posx)
    obj
end

# ─── syntax highlighting helpers ─────────────────────────────────────────────

# face symbol → (color_pair_number, bold?)
const _HIGHLIGHT_FACE_PAIR = Dict{Symbol,Tuple{Int,Bool}}(
    :julia_keyword  => (4, true),
    :julia_string   => (2, false),
    :julia_comment  => (6, false),
    :julia_number   => (3, false),
    :julia_type     => (6, true),
    :julia_typedec  => (6, true),
    :julia_macro    => (5, false),
    :julia_symbol   => (4, false),
    :julia_builtin  => (4, true),
    :julia_funcall  => (7, false),
    :julia_operator => (7, false),
)

function _face_to_attr(sym::Symbol)::Union{Nothing,TwAttr}
    if haskey(_HIGHLIGHT_FACE_PAIR, sym)
        (n, bold) = _HIGHLIGHT_FACE_PAIR[sym]
        return bold ? COLOR_PAIR(n) | A_BOLD : COLOR_PAIR(n)
    end
    s = string(sym)
    if startswith(s, "julia_rainbow_paren_")
        n = tryparse(Int, s[length("julia_rainbow_paren_")+1:end])
        n !== nothing && return COLOR_PAIR(mod1(n, 6))
    end
    return nothing
end

function _highlight_julia_spans(src::String)::Vector{Vector{Tuple{Int,Int,TwAttr}}}
    isempty(src) && return [Tuple{Int,Int,TwAttr}[]]
    lines = split(src, '\n', keepempty=true)
    nlines = length(lines)
    # byte start of each line in src (1-based)
    line_starts = Vector{Int}(undef, nlines + 1)
    line_starts[1] = 1
    for i in 1:nlines
        line_starts[i+1] = line_starts[i] + ncodeunits(lines[i]) + 1
    end
    spans = [Tuple{Int,Int,TwAttr}[] for _ in 1:nlines]
    highlighted = JuliaSyntaxHighlighting.highlight(src)
    for (range, label, sym) in Base.annotations(highlighted)
        label === :face || continue
        attr = _face_to_attr(sym)
        attr === nothing && continue
        bstart = first(range); bend = last(range)
        for li in 1:nlines
            ls = line_starts[li]
            le = ls + ncodeunits(lines[li]) - 1
            le < ls && continue                 # empty line
            istart = max(bstart, ls); iend = min(bend, le)
            istart > iend && continue
            push!(spans[li], (istart - ls + 1, iend - ls + 1, attr))
        end
    end
    for li in 1:nlines
        sort!(spans[li], by = first)
    end
    return spans
end

function _draw_highlighted_line!(
    win, y::Int, line::AbstractString, spans::Vector{Tuple{Int,Int,TwAttr}},
    currentLeft::Int, viewW::Int, startx::Int,
)
    llen   = ncodeunits(line)
    vstart = currentLeft
    # Clamp to a valid UTF-8 boundary: s[a:b] requires isvalid(s, b+1) or b==llen.
    # Walk back from the raw end until the next byte is a character start (or string end).
    raw_vend = currentLeft + viewW - 1
    vend = min(raw_vend, llen)
    # s[i:j] in Julia requires isvalid(s,j); walk back until vend is a char start.
    while vend > 0 && !isvalid(line, vend)
        vend -= 1
    end
    prev   = 1
    for (cs, ce, attr) in spans
        cs > llen && break
        ce = min(ce, llen)
        # gap before span
        vs = max(prev, vstart); ve = min(cs - 1, vend, llen)
        vs <= ve && mvwprintw(win, y, startx + vs - vstart, "%s", line[vs:ve])
        # colored span
        vs = max(cs, vstart); ve = min(ce, vend)
        if vs <= ve
            wattron(win, attr)
            mvwprintw(win, y, startx + vs - vstart, "%s", line[vs:ve])
            wattroff(win, attr)
        end
        prev = ce + 1
    end
    # trailing gap
    vs = max(prev, vstart); ve = min(llen, vend)
    vs <= ve && mvwprintw(win, y, startx + vs - vstart, "%s", line[vs:ve])
end

# ─────────────────────────────────────────────────────────────────────────────

function viewContentDimensions(o::TwObj{TwViewerData})
    vh = o.height
    vstart = 0
    if o.box
        vh -= o.borderSizeV * 2
        vstart = 1
    else
        if !isempty(o.title) || o.data.showLineInfo
            vh -= 1
            vstart = 1
        end
        if !isempty(o.data.bottomText)
            vh -= 1
        end
    end
    vw = o.width - (o.box ? o.borderSizeH * 2 : 0)
    (vh, vw, vstart)
end

function draw(o::TwObj{TwViewerData})
    viewContentHeight, viewContentWidth, viewStartRow = viewContentDimensions(o)

    if o.data.colorspans !== nothing
        werase(o.window)
    end
    if o.box
        box(o.window, 0, 0)
    end
    if !isempty(o.title)
        mvwprintw(o.window, 0, round(Int, (o.width - length(o.title))/2), "%s", o.title)
    end
    if o.data.showLineInfo
        if o.data.msglen <= o.height - 2 * o.borderSizeV
            msg = "ALL"
        else
            if o.data.trackLine
                msg = @sprintf(
                    "%d/%d %5.1f%%",
                    o.data.currentLine,
                    o.data.msglen,
                    o.data.currentLine / o.data.msglen * 100
                )
            else
                msg = @sprintf(
                    "%d/%d %5.1f%%",
                    o.data.currentTop,
                    o.data.msglen,
                    o.data.currentTop / (o.data.msglen - o.height + 2 * o.borderSizeV) *
                    100
                )
            end
        end
        mvwprintw(o.window, 0, o.width - length(msg)-3, "%s", msg)
    end
    for r = o.data.currentTop:min(o.data.currentTop+viewContentHeight-1, o.data.msglen)
        row_y = r - o.data.currentTop + viewStartRow
        if o.data.colorspans !== nothing
            line  = o.data.messages[r]
            rspans = r <= length(o.data.colorspans) ? o.data.colorspans[r] : Tuple{Int,Int,TwAttr}[]
            _draw_highlighted_line!(
                o.window, row_y, line, rspans,
                o.data.currentLeft, viewContentWidth, o.borderSizeH,
            )
        else
            s = o.data.messages[r]
            endpos = o.data.currentLeft + viewContentWidth - 1
            if endpos < length(s)
                s = s[o.data.currentLeft:endpos]
            else
                s = s[o.data.currentLeft:end]
            end
            if o.data.trackLine && r == o.data.currentLine
                wattron(o.window, A_BOLD | COLOR_PAIR(o.hasFocus ? 15 : 30))
                s *= repeat(" ", max(0, viewContentWidth - length(s)))
            end
            mvwprintw(o.window, row_y, o.borderSizeH, "%s", s)
            if o.data.trackLine && r == o.data.currentLine
                wattroff(o.window, A_BOLD | COLOR_PAIR(o.hasFocus ? 15 : 30))
            end
        end
    end
    bt = o.data.bottomText
    if bt != ""
        mvwprintw(
            o.window,
            o.height-1,
            round(Int, (o.width - length(bt))/2),
            "%s",
            bt
        )
    end
end

function inject(o::TwObj{TwViewerData}, token)
    dorefresh = false
    retcode = :got_it # default behavior is that we know what to do with it
    viewContentHeight, viewContentWidth, viewStartRow = viewContentDimensions(o)

    checkTop =
        () -> begin
            if o.data.currentTop > o.data.currentLine
                o.data.currentTop = o.data.currentLine
            elseif o.data.currentLine - o.data.currentTop > viewContentHeight - 1
                o.data.currentTop = o.data.currentLine - viewContentHeight + 1
            end
        end
    moveby =
        n -> begin
            if o.data.trackLine
                o.data.currentLine = max(1, min(o.data.msglen, o.data.currentLine + n))
                checkTop()
            else
                o.data.currentTop = max(
                    1,
                    min(o.data.msglen - viewContentHeight, o.data.currentTop + n),
                )
            end
            true
        end

    if token == :esc
        retcode = :exit_nothing
    elseif token == :up
        dorefresh = moveby(-1)
    elseif token == :down
        dorefresh = moveby(1)
    elseif token == :left
        if o.data.currentLeft > 1
            o.data.currentLeft -= 1
            dorefresh = true
        else
            beep()
        end
    elseif token == :right
        if o.data.currentLeft + viewContentWidth < o.data.msgwidth
            o.data.currentLeft += 1
            dorefresh = true
        else
            beep()
        end
    elseif token == :pageup
        dorefresh = moveby(-viewContentHeight)
    elseif token == :pagedown
        dorefresh = moveby(viewContentHeight)
    elseif token == :KEY_MOUSE
        (mstate, x, y, bs) = getmouse()
        if mstate == :scroll_up
            dorefresh = moveby(-(round(Int, viewContentHeight/10)))
        elseif mstate == :scroll_down
            dorefresh = moveby(round(Int, viewContentHeight/10))
        elseif mstate == :button1_pressed && o.data.trackLine
            (rely, relx) = screen_to_relative(o.window, y, x)
            if 0<=relx<o.width && 0<=rely<o.height
                o.data.currentLine = o.data.currentTop + rely - o.borderSizeH + 1
                dorefresh = true
            else
                retcode = :pass
            end
        end
    elseif token == :home
        if o.data.currentTop != 1 || o.data.currentLeft != 1 || o.data.currentLine != 1
            o.data.currentTop = 1
            o.data.currentLeft = 1
            o.data.currentLine = 1
            dorefresh = true
        else
            beep()
        end
    elseif in(token, Any[Symbol("end")])
        if o.data.currentTop + o.height-2 < o.data.msglen
            o.data.currentTop = o.data.msglen - o.height + 2
            dorefresh = true
        else
            beep()
        end
    elseif (token == :enter || token == Symbol("return")) && o.data.trackLine
        if haskey(o.listeners, :select)
            for f in o.listeners[:select]
                retcode = f(:select, o)
            end
        end
        dorefresh = true
    elseif token == :F11 && o.data.filename != ""
        open_in_vim( o.data.filename, o.data.fileloc )
    elseif token == "L" # move half-way toward the end
        if o.data.trackLine
            target =
                min(round(Int, ceil((o.data.currentLine + o.data.msglen)/2)), o.data.msglen)
            if target != o.data.currentLine
                o.data.currentLine = target
                checkTop()
                dorefresh = true
            else
                beep()
            end
        else
            target = min(
                round(Int, ceil((o.data.currentTop + o.data.msglen - o.height+2)/2)),
                o.data.msglen - o.height + 2,
            )
            if target != o.data.currentTop
                o.data.currentTop = target
                dorefresh = true
            else
                beep()
            end
        end
    elseif token == "l" # move half-way toward the beginning
        if o.data.trackLine
            target = max(round(Int, floor(o.data.currentLine / 2)), 1)
            if target != o.data.currentLine
                o.data.currentLine = target
                checkTop()
                dorefresh = true
            else
                beep()
            end
        else
            target = max(round(Int, floor(o.data.currentTop / 2)), 1)
            if target != o.data.currentTop
                o.data.currentTop = target
                dorefresh = true
            else
                beep()
            end
        end
    else
        retcode = :pass # I don't know what to do with it
    end

    if dorefresh
        refresh(o)
    end

    return retcode
end

function helptext(o::TwObj{TwViewerData})
    if o.data.showHelp
        o.data.helpText
    else
        ""
    end
end

function setTwViewerMsgs(o::TwObj{TwViewerData}, msgs::Array)
    o.data.messages = msgs
    o.data.msglen = length(msgs)
    o.data.msgwidth = maximum(map(x->length(x), msgs))
end

function clamp_scroll!(o::TwObj{TwViewerData})
    vh, vw, _ = viewContentDimensions(o)
    if vh < 1 || vw < 1
        return
    end
    # Keep currentTop in [1, max(1, msglen-vh+1)]
    if o.data.msglen <= vh
        o.data.currentTop = 1
    else
        maxTop = o.data.msglen - vh + 1
        if o.data.currentTop > maxTop
            o.data.currentTop = maxTop
        end
        if o.data.currentTop < 1
            o.data.currentTop = 1
        end
    end
    # Track-line cursor must remain visible.
    if o.data.trackLine
        if o.data.currentLine < o.data.currentTop
            o.data.currentLine = o.data.currentTop
        elseif o.data.currentLine > o.data.currentTop + vh - 1
            o.data.currentLine = o.data.currentTop + vh - 1
        end
        if o.data.currentLine > o.data.msglen
            o.data.currentLine = o.data.msglen
        end
    end
    # Keep horizontal scroll in range too.
    if o.data.currentLeft + vw - 1 > o.data.msgwidth
        o.data.currentLeft = max(1, o.data.msgwidth - vw + 1)
    end
    if o.data.currentLeft < 1
        o.data.currentLeft = 1
    end
end

function open_in_vim( file::String, line::Int )
    if haskey(ENV, "TMUX")
        run(`tmux new-window vim +$line $file`; wait=false)
        return true
    end

    if Sys.isapple() && !isempty(Sys.which("mvim"))
        serverlist = strip(readchomp(Cmd(["mvim", "--serverlist"])))
        if !isempty(serverlist)
            # Send to existing server: :tab drop reuses an open buffer or opens a new tab
            cmd = ":tab drop $file | call cursor($line, 0)\r"
            run(Cmd(["mvim", "--remote-send", cmd]); wait=false)
        else
            run(Cmd(["mvim", "+$line", file]); wait=false)
        end
        return true
    end

    if Sys.isapple() && get(ENV, "TERM_PROGRAM", "") == "iTerm.app"
        script = """
tell application "iTerm2"
    set newWin to (create window with default profile)
    tell current session of newWin
        write text "vim +$(line) $(file)"
    end tell
end tell"""
        run(Cmd(["osascript", "-e", script]))
        return true
    end

    if haskey(ENV, "TERMINAL")
        run(Cmd([ENV["TERMINAL"], "-e", "vim", "+$line", file]); wait=false)
        return true
    end

    for (bin, args) in [
        ("gnome-terminal", ["--", "vim", "+$line", file]),
        ("konsole",        ["-e", "vim", "+$line", file]),
        ("xterm",          ["-e", "vim +$line $file"]),
        ("kitty",          ["vim", "+$line", file]),
        ("alacritty",      ["-e", "vim", "+$line", file]),
    ]
        if !isempty(Sys.which(bin))
            run(Cmd([bin; args]); wait=false)
            return true
        end
    end
end
