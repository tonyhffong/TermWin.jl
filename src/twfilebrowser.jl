defaultFileBrowserHelpText = """
PgUp/PgDn, Up/Dn  : standard navigation
<spc>,<rtn>: toggle dir / select file
..         : go up one directory level
Home       : jump to the start
End        : jump to the end
ctrl_left  : jump to parent directory
ctrl_up    : jump to previous sibling
ctrl_down  : jump to next sibling
ctrl-PgUp/Dn      : pageup/down in preview pane
ctrl-scroll up/dn : scroll up/down in preview pane
+, -       : expand/collapse one level
_          : collapse all
/          : search dialog
F6         : preview file in popup
Shift-F6   : show file stat details
.          : toggle hidden files
s          : cycle sort (name/size/mtime)
n, p       : next/previous search match
"""
defaultFileBrowserBottomText = "F1:help <spc><rtn>:toggle F6:view /:search .:hidden s:sort"

const PREVIEW_EXTENSIONS = Set([".txt", ".md", ".jl", ".log", ".toml", ".csv", ".json", ".yaml", ".yml", ".xml", ".cfg", ".ini", ".conf", ".sh", ".py", ".c", ".h", ".rs", ".go"])

fileTypeMaxWidth = 6
fileMtimeWidth = 6

mutable struct TwFileBrowserData
    rootpath::String
    openstatemap::Dict{String,Bool}
    datalist::Vector{Any}
    # each row: (name, typestr, sizestr, mtimestr, stack, expandhint, skiplines, abspath, isdir)
    datalistlen::Int
    datatreewidth::Int
    datatypewidth::Int
    datasizewidth::Int
    currentTop::Int
    currentLine::Int
    currentLeft::Int
    showLineInfo::Bool
    bottomText::String
    showHelp::Bool
    helpText::String
    searchText::String
    showHidden::Bool
    sortBy::Symbol  # :name, :size, :mtime
    # preview state
    previewSplit::Float64
    previewCache::Dict{String,Vector{String}}
    previewSpanCache::Dict{String,Vector{Vector{Tuple{Int,Int,TwAttr}}}}
    previewTop::Int
    previewPath::String
    function TwFileBrowserData()
        new(
            "",
            Dict{String,Bool}(),
            Any[],
            0,
            0,
            0,
            0,
            1,
            1,
            1,
            true,
            "",
            true,
            defaultFileBrowserHelpText,
            "",
            false,
            :name,
            0.5,
            Dict{String,Vector{String}}(),
            Dict{String,Vector{Vector{Tuple{Int,Int,TwAttr}}}}(),
            1,
            "",
        )
    end
end

function human_readable_size(sz::Integer)
    if sz < 1024
        return string(sz) * " B"
    elseif sz < 1024 * 1024
        return @sprintf("%.1f KiB", sz / 1024)
    elseif sz < 1024 * 1024 * 1024
        return @sprintf("%.1f MiB", sz / (1024 * 1024))
    else
        return @sprintf("%.1f GiB", sz / (1024 * 1024 * 1024))
    end
end

function compact_mtime(mtime::Real)
    dt = unix2datetime(mtime)
    now_dt = now()
    if Date(dt) == Date(now_dt)
        return Dates.format(dt, "HH:MM")
    elseif year(dt) == year(now_dt)
        return Dates.format(dt, "u dd")
    else
        return Dates.format(dt, "u") * "'" * Dates.format(dt, "yy")
    end
end

function is_previewable(path::String)
    isfile(path) || return false
    bn = basename(path)
    base_no_ext = lowercase(splitext(bn)[1])
    base_no_ext == "readme" && return true
    ext = lowercase(splitext(bn)[2])
    return ext in PREVIEW_EXTENSIONS
end

function load_preview(path::String)::Vector{String}
    if !isfile(path)
        return ["(not a file)"]
    end
    if !is_previewable(path)
        return ["(no preview)"]
    end
    sz = filesize(path)
    sz == 0 && return ["(empty file)"]
    bytes = read(path, min(sz, 128_000))
    if any(==(0x00), bytes)
        return ["(binary file)"]
    end
    return split(String(bytes), '\n')
end

function file_sort_entries(entries, sortBy::Symbol)
    # directories first, then files; within each group sort by sortBy
    dirs = filter(e -> e[2], entries)
    files = filter(e -> !e[2], entries)
    if sortBy == :name
        sort!(dirs, by = e -> lowercase(e[1]))
        sort!(files, by = e -> lowercase(e[1]))
    elseif sortBy == :size
        sort!(dirs, by = e -> lowercase(e[1]))
        sort!(files, by = e -> e[3], rev = true)
    elseif sortBy == :mtime
        sort!(dirs, by = e -> e[4], rev = true)
        sort!(files, by = e -> e[4], rev = true)
    end
    return vcat(dirs, files)
end

function file_tree_data(
    rootpath::String,
    list::Vector{Any},
    openstatemap::Dict{String,Bool},
    stack::Vector{Any},
    skiplines::Vector{Int},
    showHidden::Bool,
    sortBy::Symbol,
)
    # Prepend ".." navigation entry at the top level only
    if isempty(stack)
        parentpath = dirname(rootpath)
        if parentpath != rootpath  # not already at filesystem root
            push!(list, ("../", "<dir>", "", "", Any[], :single, Int[], parentpath, true))
        end
    end

    isexp = haskey(openstatemap, rootpath) && openstatemap[rootpath]
    local entries
    try
        entries = readdir(rootpath)
    catch
        return
    end

    # collect (name, isdir, size, mtime) for sorting
    raw = Tuple{String,Bool,Int64,Float64}[]
    for name in entries
        if !showHidden && startswith(name, ".")
            continue
        end
        fullpath = joinpath(rootpath, name)
        local is_dir, sz, mt
        try
            st = stat(fullpath)
            is_dir = isdir(fullpath)
            sz = Int64(st.size)
            mt = Float64(st.mtime)
        catch
            is_dir = false
            sz = Int64(0)
            mt = 0.0
        end
        push!(raw, (name, is_dir, sz, mt))
    end

    sorted = file_sort_entries(raw, sortBy)

    for (idx, entry) in enumerate(sorted)
        name, is_dir, sz, mt = entry
        fullpath = joinpath(rootpath, name)
        islast = idx == length(sorted)

        s = name * (is_dir ? "/" : "")
        if is_dir
            typestr = "<dir>"
            local item_count
            try
                items = readdir(fullpath)
                if !showHidden
                    items = filter(n -> !startswith(n, "."), items)
                end
                item_count = length(items)
            catch
                item_count = 0
            end
            sizestr = string(item_count) * " item" * (item_count == 1 ? "" : "s")
            mtimestr = ""
        else
            ext = splitext(name)[2]
            typestr = isempty(ext) ? "file" : ext
            sizestr = human_readable_size(sz)
            mtimestr = compact_mtime(mt)
        end

        newstack = copy(stack)
        push!(newstack, name)

        if is_dir
            dir_is_exp = haskey(openstatemap, fullpath) && openstatemap[fullpath]
            local item_count_for_hint
            try
                items = readdir(fullpath)
                item_count_for_hint = length(items)
            catch
                item_count_for_hint = 0
            end
            expandhint = item_count_for_hint == 0 ? :single : (dir_is_exp ? :open : :close)
        else
            expandhint = :single
        end

        if islast
            newskip = copy(skiplines)
            push!(newskip, length(stack) + 1)
            push!(list, (s, typestr, sizestr, mtimestr, newstack, expandhint, newskip, fullpath, is_dir))
        else
            push!(list, (s, typestr, sizestr, mtimestr, newstack, expandhint, skiplines, fullpath, is_dir))
        end

        # recurse into expanded directories
        if is_dir && expandhint == :open
            if islast
                newskip2 = copy(skiplines)
                push!(newskip2, length(stack) + 1)
                file_tree_data(fullpath, list, openstatemap, newstack, newskip2, showHidden, sortBy)
            else
                file_tree_data(fullpath, list, openstatemap, newstack, skiplines, showHidden, sortBy)
            end
        end
    end
end

function updateFileBrowserDimensions(o::TwObj)
    if isempty(o.data.datalist)
        o.data.datalistlen = 0
        o.data.datatreewidth = 10
        o.data.datatypewidth = 4
        o.data.datasizewidth = 6
        return
    end
    o.data.datalistlen = length(o.data.datalist)
    o.data.datatreewidth =
        maximum(map(r -> length(r[1]) + 1 + 2 * length(r[5]), o.data.datalist))
    o.data.datatypewidth =
        min(fileTypeMaxWidth, max(4, maximum(map(r -> length(r[2]), o.data.datalist))))
    o.data.datasizewidth =
        max(6, maximum(map(r -> length(r[3]), o.data.datalist)))
    nothing
end

function newTwFileBrowser(
    scr::TwObj,
    rootpath::String = pwd();
    height::Real = 0.93,
    width::Real = 0.93,
    posy::Any = :staggered,
    posx::Any = :staggered,
    title::String = rootpath,
    box::Bool = true,
    showLineInfo::Bool = true,
    showHelp::Bool = true,
    bottomText::String = defaultFileBrowserBottomText,
    showHidden::Bool = false,
    previewSplit::Float64 = 0.5,
)
    obj = TwObj(TwFileBrowserData(), Val{:FileBrowser})
    obj.value = nothing
    obj.title = title
    obj.box = box
    obj.borderSizeV = box ? 1 : 0
    obj.borderSizeH = box ? 2 : 0
    obj.data.rootpath = abspath(rootpath)
    obj.data.showLineInfo = showLineInfo
    obj.data.showHelp = showHelp
    obj.data.bottomText = bottomText
    obj.data.showHidden = showHidden
    obj.data.previewSplit = previewSplit

    obj.data.openstatemap[obj.data.rootpath] = true
    file_tree_data(
        obj.data.rootpath,
        obj.data.datalist,
        obj.data.openstatemap,
        Any[],
        Int[],
        obj.data.showHidden,
        obj.data.sortBy,
    )
    updateFileBrowserDimensions(obj)

    link_parent_child(scr, obj, height, width, posy, posx)
    obj
end

function draw(o::TwObj{TwFileBrowserData})
    updateFileBrowserDimensions(o)
    viewContentHeight = o.height - 2 * o.borderSizeV
    totalContentWidth = o.width - 2 * o.borderSizeH

    # compute zone widths
    leftW = max(30, round(Int, totalContentWidth * o.data.previewSplit))
    rightW = totalContentWidth - leftW - 1  # -1 for divider
    if rightW < 10
        # not enough room for preview — use full width for tree
        leftW = totalContentWidth
        rightW = 0
    end
    dividerX = o.borderSizeH + leftW  # column index for the vertical divider

    if o.box
        box(o.window, 0, 0)
    end

    # title
    if !isempty(o.title) && o.box
        titlestr = o.title
        if o.data.showHidden
            titlestr *= " (all)"
        end
        maxtw = dividerX - 2
        if length(titlestr) > maxtw
            titlestr = ensure_length(titlestr, maxtw, false)
        end
        mvwprintw(o.window, 0, round(Int, (dividerX - length(titlestr))/2), "%s", titlestr)
    end

    # line info
    if o.data.showLineInfo && o.box
        if o.data.datalistlen <= viewContentHeight
            msg = "ALL"
        else
            msg = @sprintf(
                "%d/%d %5.1f%%",
                o.data.currentLine,
                o.data.datalistlen,
                o.data.currentLine / o.data.datalistlen * 100
            )
        end
        pos = dividerX - length(msg) - 1
        if pos > 1
            mvwprintw(o.window, 0, pos, "%s", msg)
        end
    end

    # vertical divider
    if rightW > 0
        for row in 1:viewContentHeight
            mvwaddch(o.window, row, dividerX, get_acs_val('x'))
        end
        if o.box
            mvwaddch(o.window, 0, dividerX, get_acs_val('w'))                      # top tee
            mvwaddch(o.window, o.height - 1, dividerX, get_acs_val('v'))           # bottom tee
        end
    end

    # ── LEFT ZONE: 4-column tree ──
    # Compute column positions within left zone
    # Layout: [tree name] | [type] | [size] | [mtime]
    # mtime is fixed width, size and type adapt

    mtimeW = fileMtimeWidth
    separators = 3  # three │ chars between 4 columns
    treeW = min(o.data.datatreewidth, leftW - o.data.datatypewidth - o.data.datasizewidth - mtimeW - separators)
    if treeW < 8
        treeW = 8
    end
    typeW = o.data.datatypewidth
    # remaining space goes to size column
    sizeW = leftW - treeW - typeW - mtimeW - separators
    if sizeW < 4
        sizeW = 4
    end

    col_tree = o.borderSizeH
    col_sep1 = col_tree + treeW
    col_type = col_sep1 + 1
    col_sep2 = col_type + typeW
    col_size = col_sep2 + 1
    col_sep3 = col_size + sizeW
    col_mtime = col_sep3 + 1

    for r = o.data.currentTop:min(o.data.currentTop + viewContentHeight - 1, o.data.datalistlen)
        row = 1 + r - o.data.currentTop
        stacklen = length(o.data.datalist[r][5])
        is_dir = o.data.datalist[r][9]

        s = ensure_length(
            repeat(" ", 2 * stacklen + 1) * o.data.datalist[r][1],
            treeW,
        )
        t = ensure_length(o.data.datalist[r][2], typeW)
        sz = ensure_length(o.data.datalist[r][3], sizeW, false)
        # right-align size: pad with spaces on the left
        szpad = sizeW - length(sz)
        if szpad > 0
            sz = repeat(" ", szpad) * sz
        end
        mt = ensure_length(o.data.datalist[r][4], mtimeW, false)
        mtpad = mtimeW - length(mt)
        if mtpad > 0
            mt = repeat(" ", mtpad) * mt
        end

        if r == o.data.currentLine
            wattron(o.window, A_BOLD | COLOR_PAIR(o.hasFocus ? 15 : 30))
        end

        mvwprintw(o.window, row, col_tree, "%s", s)
        mvwaddch(o.window, row, col_sep1, get_acs_val('x'))
        mvwprintw(o.window, row, col_type, "%s", t)
        mvwaddch(o.window, row, col_sep2, get_acs_val('x'))
        mvwprintw(o.window, row, col_size, "%s", sz)
        mvwaddch(o.window, row, col_sep3, get_acs_val('x'))
        mvwprintw(o.window, row, col_mtime, "%s", mt)

        # tree lines (absolute positions, matching twtree convention)
        for i = 1:(stacklen - 1)
            if !in(i, o.data.datalist[r][7])  # skiplines
                mvwaddch(o.window, row, 2 * i, get_acs_val('x'))
            end
        end
        if stacklen != 0
            contchar = get_acs_val('t')  # tee pointing right ├
            if r == o.data.datalistlen ||
               length(o.data.datalist[r+1][5]) < stacklen ||
               (
                   length(o.data.datalist[r+1][5]) > stacklen &&
                   in(stacklen, o.data.datalist[r+1][7])
               )
                contchar = get_acs_val('m')  # LL corner └
            end
            mvwaddch(o.window, row, 2 * stacklen, contchar)
            mvwaddch(o.window, row, 2 * stacklen + 1, get_acs_val('q'))  # horizontal ─
        end

        # expand/collapse indicator
        if o.data.datalist[r][6] == :close
            mvwprintw(o.window, row, 2 * stacklen + 2, "%s", string(Char(0x25b8)))
        elseif o.data.datalist[r][6] == :open
            mvwprintw(o.window, row, 2 * stacklen + 2, "%s", string(Char(0x25be)))
        end

        if r == o.data.currentLine
            wattroff(o.window, A_BOLD | COLOR_PAIR(o.hasFocus ? 15 : 30))
        end
    end

    # ── RIGHT ZONE: file preview ──
    if rightW > 0
        previewX = dividerX + 1

        # update preview for current selection
        if o.data.datalistlen > 0
            curpath = o.data.datalist[o.data.currentLine][8]
            if curpath != o.data.previewPath
                o.data.previewPath = curpath
                o.data.previewTop = 1
            end
        end

        # preview title in top border
        if o.box && o.data.previewPath != ""
            ptitle = " " * basename(o.data.previewPath) * " "
            ptitle = ensure_length(ptitle, rightW - 2, false)
            mvwprintw(o.window, 0, previewX + 1, "%s", ptitle)
        end

        # get preview lines
        local lines::Vector{String}
        if o.data.previewPath == ""
            lines = String[]
        elseif o.data.datalistlen > 0 && o.data.datalist[o.data.currentLine][9]
            lines = ["(directory)"]
        else
            if !haskey(o.data.previewCache, o.data.previewPath)
                # evict old entries if cache is full
                if length(o.data.previewCache) > 20
                    ks = collect(keys(o.data.previewCache))
                    for k in ks[1:min(10, length(ks))]
                        delete!(o.data.previewCache, k)
                        delete!(o.data.previewSpanCache, k)
                    end
                end
                plines = load_preview(o.data.previewPath)
                o.data.previewCache[o.data.previewPath] = plines
                if lowercase(splitext(o.data.previewPath)[2]) == ".jl"
                    try
                        src = join(map(l -> replace(l, "\t" => "    "), plines), "\n")
                        o.data.previewSpanCache[o.data.previewPath] = _highlight_julia_spans(src)
                    catch
                    end
                end
            end
            lines = o.data.previewCache[o.data.previewPath]
        end

        pspans = get(o.data.previewSpanCache, o.data.previewPath, nothing)
        for i in 1:viewContentHeight
            lineIdx = o.data.previewTop + i - 1
            # always blank the line first so stale chars don't bleed through
            mvwprintw(o.window, i, previewX, "%s", repeat(" ", rightW))
            if lineIdx <= length(lines)
                rawline = replace(lines[lineIdx], "\t" => "    ")
                if pspans !== nothing
                    linespans = lineIdx <= length(pspans) ?
                        pspans[lineIdx] : Tuple{Int,Int,TwAttr}[]
                    _draw_highlighted_line!(
                        o.window, i, rawline, linespans, 1, rightW, previewX,
                    )
                else
                    txt = ensure_length(rawline, rightW, false)
                    mvwprintw(o.window, i, previewX, "%s", txt)
                end
            end
        end

        # preview line info in top border (right-aligned)
        if o.box && !isempty(lines)
            totalLines = length(lines)
            if totalLines <= viewContentHeight
                pmsg = "ALL"
            else
                pmsg = @sprintf(
                    "%d/%d %5.1f%%",
                    o.data.previewTop,
                    totalLines,
                    o.data.previewTop / totalLines * 100
                )
            end
            ppos = o.width - o.borderSizeH - length(pmsg)
            if ppos > previewX
                mvwprintw(o.window, 0, ppos, "%s", pmsg)
            end
        end
    end

    # bottom text
    if length(o.data.bottomText) != 0 && o.box
        mvwprintw(
            o.window,
            o.height - 1,
            round(Int, (o.width - length(o.data.bottomText)) / 2),
            "%s",
            o.data.bottomText,
        )
    end
end

function inject(o::TwObj{TwFileBrowserData}, token)
    dorefresh = false
    retcode = :got_it
    viewContentHeight = o.height - 2 * o.borderSizeV

    update_file_data =
        () -> begin
            o.data.datalist = Any[]
            file_tree_data(
                o.data.rootpath,
                o.data.datalist,
                o.data.openstatemap,
                Any[],
                Int[],
                o.data.showHidden,
                o.data.sortBy,
            )
            updateFileBrowserDimensions(o)
        end

    navigate_up =
        () -> begin
            parentpath = dirname(o.data.rootpath)
            if parentpath == o.data.rootpath
                beep()
                return false
            end
            o.data.rootpath = parentpath
            o.title = parentpath
            o.data.openstatemap = Dict{String,Bool}()
            o.data.openstatemap[o.data.rootpath] = true
            o.data.datalist = Any[]
            file_tree_data(
                o.data.rootpath,
                o.data.datalist,
                o.data.openstatemap,
                Any[],
                Int[],
                o.data.showHidden,
                o.data.sortBy,
            )
            updateFileBrowserDimensions(o)
            o.data.currentLine = 1
            o.data.currentTop = 1
            o.data.currentLeft = 1
            o.data.previewPath = ""
            o.data.previewTop = 1
            return true
        end

    checkTop =
        () -> begin
            if o.data.currentTop < 1
                o.data.currentTop = 1
            elseif o.data.currentTop > o.data.datalistlen - viewContentHeight + 1
                o.data.currentTop = max(1, o.data.datalistlen - viewContentHeight + 1)
            end
            if o.data.currentTop > o.data.currentLine
                o.data.currentTop = o.data.currentLine
            elseif o.data.currentLine - o.data.currentTop > viewContentHeight - 1
                o.data.currentTop = o.data.currentLine - viewContentHeight + 1
            end
        end

    moveby =
        n -> begin
            if o.data.datalistlen == 0
                beep()
                return false
            end
            oldline = o.data.currentLine
            o.data.currentLine = max(1, min(o.data.datalistlen, o.data.currentLine + n))
            if oldline != o.data.currentLine
                checkTop()
                return true
            else
                beep()
                return false
            end
        end

    searchNext =
        (step, trivialstop) -> begin
            if o.data.datalistlen == 0
                beep()
                return 0
            end
            local st = o.data.currentLine
            o.data.searchText = lowercase(o.data.searchText)
            i = trivialstop ? st : (mod(st - 1 + step, o.data.datalistlen) + 1)
            while true
                if occursin(o.data.searchText, lowercase(o.data.datalist[i][1]))
                    o.data.currentLine = i
                    if abs(i - st) > viewContentHeight
                        o.data.currentTop = o.data.currentLine - (viewContentHeight >> 1)
                    end
                    checkTop()
                    return i
                end
                i = mod(i - 1 + step, o.data.datalistlen) + 1
                if i == st
                    beep()
                    return 0
                end
            end
        end

    if token == :esc
        retcode = :exit_nothing
    elseif token == " " || token == Symbol("return") || token == :enter
        if o.data.datalistlen == 0
            beep()
        else
            expandhint = o.data.datalist[o.data.currentLine][6]
            is_dir = o.data.datalist[o.data.currentLine][9]
            fullpath = o.data.datalist[o.data.currentLine][8]
            if fullpath == dirname(o.data.rootpath) && o.data.datalist[o.data.currentLine][1] == "../"
                # ".." entry — navigate to parent directory
                navigate_up()
                dorefresh = true
            elseif is_dir
                # toggle expand/collapse
                if expandhint == :single
                    beep()
                else
                    if haskey(o.data.openstatemap, fullpath) && o.data.openstatemap[fullpath]
                        o.data.openstatemap[fullpath] = false
                    else
                        o.data.openstatemap[fullpath] = true
                    end
                    update_file_data()
                    dorefresh = true
                end
            else
                # select file
                if token == Symbol("return") || token == :enter
                    o.value = fullpath
                    retcode = :exit_ok
                else
                    # space on a file — just beep or do nothing
                    beep()
                end
            end
        end
    elseif token == "+"
        # expand all currently visible collapsed directories by one level
        if o.data.datalistlen == 0
            beep()
        else
            currentstack = o.data.datalist[o.data.currentLine][5]
            somethingchanged = false
            for i = 1:o.data.datalistlen
                expandhint = o.data.datalist[i][6]
                if expandhint == :close
                    fullpath = o.data.datalist[i][8]
                    o.data.openstatemap[fullpath] = true
                    somethingchanged = true
                end
            end
            if somethingchanged
                prevline = o.data.currentLine
                update_file_data()
                for i = o.data.currentLine:o.data.datalistlen
                    if currentstack == o.data.datalist[i][5]
                        o.data.currentLine = i
                        if abs(i - prevline) > viewContentHeight
                            o.data.currentTop = i - round(Int, viewContentHeight / 2)
                        end
                        break
                    end
                end
                checkTop()
                dorefresh = true
            else
                beep()
            end
        end
    elseif token == "-"
        # collapse deepest expanded level
        if o.data.datalistlen == 0
            beep()
        else
            currentstack = copy(o.data.datalist[o.data.currentLine][5])
            maxstackdepth = maximum(map(r -> length(r[5]), o.data.datalist))
            if maxstackdepth > 1
                somethingchanged = false
                for i = 1:o.data.datalistlen
                    expandhint = o.data.datalist[i][6]
                    stck = o.data.datalist[i][5]
                    if expandhint != :single && length(stck) == maxstackdepth - 1
                        fullpath = o.data.datalist[i][8]
                        if haskey(o.data.openstatemap, fullpath) && o.data.openstatemap[fullpath]
                            o.data.openstatemap[fullpath] = false
                            somethingchanged = true
                        end
                    end
                end
                if somethingchanged
                    update_file_data()
                    if length(currentstack) == maxstackdepth
                        pop!(currentstack)
                    end
                    prevline = o.data.currentLine
                    o.data.currentLine = 1
                    for i = 1:min(prevline, o.data.datalistlen)
                        if currentstack == o.data.datalist[i][5]
                            o.data.currentLine = i
                            if abs(i - prevline) > viewContentHeight
                                o.data.currentTop = i - round(Int, viewContentHeight / 2)
                            end
                            break
                        end
                    end
                    checkTop()
                    dorefresh = true
                else
                    beep()
                end
            else
                beep()
            end
        end
    elseif token == "_"
        # collapse all
        if o.data.datalistlen == 0
            beep()
        else
            currentstack = copy(o.data.datalist[o.data.currentLine][5])
            if length(currentstack) > 1
                currentstack = Any[currentstack[1]]
            end
            o.data.openstatemap = Dict{String,Bool}()
            o.data.openstatemap[o.data.rootpath] = true
            update_file_data()
            prevline = o.data.currentLine
            o.data.currentLine = 1
            for i = 1:min(prevline, o.data.datalistlen)
                if currentstack == o.data.datalist[i][5]
                    o.data.currentLine = i
                    if abs(i - prevline) > viewContentHeight
                        o.data.currentTop =
                            o.data.currentLine - round(Int, viewContentHeight / 2)
                    end
                    break
                end
            end
            checkTop()
            dorefresh = true
        end
    elseif token == "."
        # toggle hidden files
        o.data.showHidden = !o.data.showHidden
        prevstack = o.data.datalistlen > 0 ? copy(o.data.datalist[o.data.currentLine][5]) : Any[]
        update_file_data()
        # try to restore position
        o.data.currentLine = 1
        for i = 1:o.data.datalistlen
            if o.data.datalist[i][5] == prevstack
                o.data.currentLine = i
                break
            end
        end
        checkTop()
        dorefresh = true
    elseif token == "s"
        # cycle sort order
        if o.data.sortBy == :name
            o.data.sortBy = :size
        elseif o.data.sortBy == :size
            o.data.sortBy = :mtime
        else
            o.data.sortBy = :name
        end
        prevstack = o.data.datalistlen > 0 ? copy(o.data.datalist[o.data.currentLine][5]) : Any[]
        update_file_data()
        o.data.currentLine = 1
        for i = 1:o.data.datalistlen
            if o.data.datalist[i][5] == prevstack
                o.data.currentLine = i
                break
            end
        end
        checkTop()
        dorefresh = true
    elseif token == :F6
        if o.data.datalistlen == 0
            beep()
        else
            fullpath = o.data.datalist[o.data.currentLine][8]
            is_dir = o.data.datalist[o.data.currentLine][9]
            if !is_dir && isfile(fullpath)
                ext = o.data.datalist[o.data.currentLine][2]
                sz = filesize(fullpath)
                if sz == 0
                    text = "(empty file)"
                else
                    bytes = read(fullpath, min(sz, 256_000))
                    if any(==(0x00), bytes)
                        text = "(binary file, " * human_readable_size(Int64(sz)) * ")"
                    else
                        text = String(bytes)
                    end
                end
                if ext == ".jl"
                    tshow(text,"julia:" * fullpath; title = basename(fullpath))
                else
                    tshow(text, title = basename(fullpath))
                end
                dorefresh = true
            else
                beep()
            end
        end
    elseif token == :shift_F6
        if o.data.datalistlen == 0
            beep()
        else
            fullpath = o.data.datalist[o.data.currentLine][8]
            local info
            try
                st = stat(fullpath)
                info = "Path: " * fullpath * "\n"
                info *= "Size: " * human_readable_size(Int64(st.size)) * " (" * string(st.size) * " bytes)\n"
                info *= "Modified: " * string(unix2datetime(st.mtime)) * "\n"
                info *= "Mode: " * string(st.mode, base=8) * "\n"
                if islink(fullpath)
                    info *= "Link target: " * readlink(fullpath) * "\n"
                end
                if isdir(fullpath)
                    info *= "Type: directory\n"
                elseif isfile(fullpath)
                    info *= "Type: file\n"
                end
            catch err
                info = "Error reading stat: " * string(err)
            end
            tshow(info, title = "stat: " * basename(fullpath))
            dorefresh = true
        end
    elseif token == :ctrl_up
        # Move to the previous sibling (same depth, same parent directory)
        if o.data.datalistlen == 0
            beep()
        else
            currentstack = o.data.datalist[o.data.currentLine][5]
            depth = length(currentstack)
            if depth == 0
                beep()
            else
                parentstack = currentstack[1:end-1]
                found = false
                for i = o.data.currentLine-1:-1:1
                    rowstack = o.data.datalist[i][5]
                    if length(rowstack) < depth
                        break
                    end
                    if length(rowstack) == depth && rowstack[1:end-1] == parentstack
                        o.data.currentLine = i
                        checkTop()
                        dorefresh = true
                        found = true
                        break
                    end
                end
                if !found
                    beep()
                end
            end
        end
    elseif token == :ctrl_down
        # Move to the next sibling (same depth, same parent directory)
        if o.data.datalistlen == 0
            beep()
        else
            currentstack = o.data.datalist[o.data.currentLine][5]
            depth = length(currentstack)
            if depth == 0
                beep()
            else
                parentstack = currentstack[1:end-1]
                found = false
                for i = o.data.currentLine+1:o.data.datalistlen
                    rowstack = o.data.datalist[i][5]
                    if length(rowstack) < depth
                        break
                    end
                    if length(rowstack) == depth && rowstack[1:end-1] == parentstack
                        o.data.currentLine = i
                        checkTop()
                        dorefresh = true
                        found = true
                        break
                    end
                end
                if !found
                    beep()
                end
            end
        end
    elseif token == :ctrl_pageup
        # page up in preview pane
        if o.data.previewTop > 1
            o.data.previewTop = max(1, o.data.previewTop - viewContentHeight)
            dorefresh = true
        else
            beep()
        end
    elseif token == :ctrl_pagedown
        # page down in preview pane
        curpath = o.data.datalistlen > 0 ? o.data.datalist[o.data.currentLine][8] : ""
        if curpath != "" && haskey(o.data.previewCache, curpath)
            maxTop = max(1, length(o.data.previewCache[curpath]) - viewContentHeight + 1)
            if o.data.previewTop < maxTop
                o.data.previewTop = min(maxTop, o.data.previewTop + viewContentHeight)
                dorefresh = true
            else
                beep()
            end
        else
            beep()
        end
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
    elseif token == :ctrl_left
        # Move to the parent directory node
        if o.data.datalistlen == 0
            beep()
        else
            currentstack = o.data.datalist[o.data.currentLine][5]
            if isempty(currentstack)
                beep()
            else
                parentstack = currentstack[1:end-1]
                found = false
                for i = o.data.currentLine-1:-1:1
                    if o.data.datalist[i][5] == parentstack
                        o.data.currentLine = i
                        checkTop()
                        dorefresh = true
                        found = true
                        break
                    end
                end
                if !found
                    beep()
                end
            end
        end
    elseif token == :right
        o.data.currentLeft += 1
        dorefresh = true
    elseif token == :ctrl_right
        o.data.currentLeft += 10
        dorefresh = true
    elseif token == :pageup
        dorefresh = moveby(-viewContentHeight)
    elseif token == :pagedown
        dorefresh = moveby(viewContentHeight)
    elseif token == :KEY_MOUSE
        (mstate, x, y, bs) = getmouse()
        if mstate == :scroll_up
            dorefresh = moveby(-(round(Int, viewContentHeight / 5)))
        elseif mstate == :scroll_down
            dorefresh = moveby(round(Int, viewContentHeight / 5))
        elseif mstate == :ctrl_scroll_up
            # scroll preview pane up by one line
            if o.data.previewTop > 1
		o.data.previewTop = max( 1, o.data.previewTop - 5 )
                dorefresh = true
            else
                beep()
            end
        elseif mstate == :ctrl_scroll_down
            # scroll preview pane down by one line
            curpath = o.data.datalistlen > 0 ? o.data.datalist[o.data.currentLine][8] : ""
            if curpath != "" && haskey(o.data.previewCache, curpath)
                maxTop = max(1, length(o.data.previewCache[curpath]) - viewContentHeight + 1)
                if o.data.previewTop < maxTop
		    o.data.previewTop = min(maxTop, o.data.previewTop + 5)
                    dorefresh = true
                else
                    beep()
                end
            else
                beep()
            end
        elseif mstate == :button1_pressed
            begy, begx = getwinbegyx(o.window)
            relx = x - begx
            rely = y - begy
            if 0 <= relx < o.width && 0 <= rely < o.height
                newline = o.data.currentTop + rely - o.borderSizeV
                if newline >= 1 && newline <= o.data.datalistlen
                    o.data.currentLine = newline
                    dorefresh = true
                end
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
    elseif token == "/"
        helper = newTwEntry(
            o.screen.value,
            String;
            width = 30,
            posy = :center,
            posx = :center,
            title = "Search: ",
        )
        helper.data.inputText = o.data.searchText
        s = activateTwObj(helper)
        unregisterTwObj(o.screen.value, helper)
        if s !== nothing
            if s != "" && o.data.searchText != s
                o.data.searchText = s
                searchNext(1, true)
            end
        end
        dorefresh = true
    elseif token == "n" ||
           token == "p" ||
           token == "N" ||
           token == :ctrl_n ||
           token == :ctrl_p
        if o.data.searchText != ""
            searchNext(((token == "n" || token == :ctrl_n) ? 1 : -1), false)
        end
        dorefresh = true
    elseif in(token, Any[Symbol("end")])
        if o.data.datalistlen > 0 && o.data.currentLine != o.data.datalistlen
            o.data.currentTop = max(1, o.data.datalistlen - viewContentHeight + 1)
            o.data.currentLine = o.data.datalistlen
            dorefresh = true
        else
            beep()
        end
    elseif token == "L"
        if o.data.datalistlen == 0
            beep()
        else
            target = min(
                round(Int, ceil((o.data.currentLine + o.data.datalistlen) / 2)),
                o.data.datalistlen,
            )
            if target != o.data.currentLine
                o.data.currentLine = target
                checkTop()
                dorefresh = true
            else
                beep()
            end
        end
    elseif token == "l"
        if o.data.datalistlen == 0
            beep()
        else
            target = max(round(Int, floor(o.data.currentLine / 2)), 1)
            if target != o.data.currentLine
                o.data.currentLine = target
                checkTop()
                dorefresh = true
            else
                beep()
            end
        end
    else
        retcode = :pass
    end

    if dorefresh
        refresh(o)
    end

    return retcode
end

function helptext(o::TwObj{TwFileBrowserData})
    if o.data.showHelp
        o.data.helpText
    else
        ""
    end
end

function clamp_scroll!(o::TwObj{TwFileBrowserData})
    updateFileBrowserDimensions(o)
    vh = o.height - 2 * o.borderSizeV
    if vh < 1
        return
    end
    if o.data.currentLine < 1
        o.data.currentLine = 1
    elseif o.data.currentLine > o.data.datalistlen
        o.data.currentLine = max(1, o.data.datalistlen)
    end
    if o.data.currentTop < 1
        o.data.currentTop = 1
    elseif o.data.currentTop > max(1, o.data.datalistlen - vh + 1)
        o.data.currentTop = max(1, o.data.datalistlen - vh + 1)
    end
    if o.data.currentTop > o.data.currentLine
        o.data.currentTop = o.data.currentLine
    elseif o.data.currentLine - o.data.currentTop > vh - 1
        o.data.currentTop = o.data.currentLine - vh + 1
    end
end
