
defaultFileBrowserBottomText = "F1:help <spc><rtn>:toggle F6:view /:search .:hidden s:sort"

const PREVIEW_EXTENSIONS = Set([".txt", ".md", ".jl", ".log", ".toml", ".csv", ".json", ".yaml", ".yml", ".xml", ".cfg", ".ini", ".conf", ".sh", ".py", ".c", ".h", ".rs", ".go"])

const IMAGE_EXTENSIONS = Set([".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".tiff", ".tif"])

fileTypeMaxWidth = 6
fileMtimeWidth = 6

mutable struct TwFileBrowserData
    rootpath::String
    openstatemap::Dict{String,Bool}
    datalist::Vector{FileRow}    # typed rows (was an anonymous 9-tuple)
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
    searchText::String
    showHidden::Bool
    sortBy::Symbol  # :name, :size, :mtime
    # preview state
    previewSplit::Float64
    previewCache::Dict{String,Vector{String}}
    previewSpanCache::Dict{String,Vector{Vector{Tuple{Int,Int,TwAttr}}}}
    previewMtimeCache::Dict{String,Float64}
    previewTop::Int
    previewPath::String
    imagePreviewCache::Dict{String,NC.Visual}
    selection_text::Observable{String}
    function TwFileBrowserData()
        ret = new(
            "",
            Dict{String,Bool}(),
            FileRow[],
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
            "",
            false,
            :name,
            0.5,
            Dict{String,Vector{String}}(),
            Dict{String,Vector{Vector{Tuple{Int,Int,TwAttr}}}}(),
            Dict{String,Float64}(),
            1,
            "",
            Dict{String,NC.Visual}(),
            Observable(""),
        )
        finalizer(ret) do d
            for v in values(d.imagePreviewCache)
                try; NC.destroy(v); catch; end
            end
            empty!(d.imagePreviewCache)
        end
        ret
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

function is_image_preview(path::String)
    isfile(path) || return false
    ext = lowercase(splitext(path)[2])
    return ext in IMAGE_EXTENSIONS
end

# Returns the cached NC.Visual, decoding+caching if needed. Bounded LRU
# (8 entries, evict 4 oldest when full). Returns nothing on decode failure.
function load_image_preview(o::TwObj{TwFileBrowserData}, path::String)
    if haskey(o.data.imagePreviewCache, path)
        return o.data.imagePreviewCache[path]
    end
    if length(o.data.imagePreviewCache) >= 8
        ks = collect(keys(o.data.imagePreviewCache))
        for k in ks[1:4]
            v = o.data.imagePreviewCache[k]
            try; NC.destroy(v); catch; end
            delete!(o.data.imagePreviewCache, k)
        end
    end
    visual = nothing
    try
        ptr = NC.LibNotcurses.ncvisual_from_file(path)
        if ptr != C_NULL
            visual = NC.Visual(ptr)
        end
    catch er
        log("file browser: ncvisual_from_file failed: " * sprint(showerror, er))
    end
    if visual !== nothing
        o.data.imagePreviewCache[path] = visual
    end
    return visual
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
    list::Vector{FileRow},
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
            push!(list, FileRow("../", "<dir>", "", "", Any[], :single, Int[], parentpath, true))
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
            push!(list, FileRow(s, typestr, sizestr, mtimestr, newstack, expandhint, newskip, fullpath, is_dir))
        else
            push!(list, FileRow(s, typestr, sizestr, mtimestr, newstack, expandhint, skiplines, fullpath, is_dir))
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
        maximum(map(r -> length(r.name) + 1 + 2 * length(r.stack), o.data.datalist))
    o.data.datatypewidth =
        min(fileTypeMaxWidth, max(4, maximum(map(r -> length(r.typestr), o.data.datalist))))
    o.data.datasizewidth =
        max(6, maximum(map(r -> length(r.sizestr), o.data.datalist)))
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

# ─── nav + data helpers ───────────────────────────────────────────────────────

function _fb_update_data!(o::TwObj{TwFileBrowserData})
    o.data.datalist = FileRow[]
    file_tree_data(o.data.rootpath, o.data.datalist, o.data.openstatemap,
                   Any[], Int[], o.data.showHidden, o.data.sortBy)
    updateFileBrowserDimensions(o)
end

function _fb_checkTop!(o::TwObj{TwFileBrowserData})
    vh = o.height - 2 * o.borderSizeV
    if o.data.currentTop < 1; o.data.currentTop = 1; end
    if o.data.currentTop > o.data.datalistlen - vh + 1
        o.data.currentTop = max(1, o.data.datalistlen - vh + 1)
    end
    if o.data.currentTop > o.data.currentLine
        o.data.currentTop = o.data.currentLine
    elseif o.data.currentLine - o.data.currentTop > vh - 1
        o.data.currentTop = o.data.currentLine - vh + 1
    end
end

function _fb_moveby!(o::TwObj{TwFileBrowserData}, n::Int)
    o.data.datalistlen == 0 && (beep(); return false)
    old = o.data.currentLine
    o.data.currentLine = max(1, min(o.data.datalistlen, o.data.currentLine + n))
    if old != o.data.currentLine
        _fb_checkTop!(o)
        return true
    else
        beep()
        return false
    end
end

function _fb_search_next!(o::TwObj{TwFileBrowserData}, step::Int, trivialstop::Bool)
    vh = o.height - 2 * o.borderSizeV
    o.data.datalistlen == 0 && (beep(); return 0)
    st = o.data.currentLine
    o.data.searchText = lowercase(o.data.searchText)
    i = trivialstop ? st : (mod(st - 1 + step, o.data.datalistlen) + 1)
    while true
        if occursin(o.data.searchText, lowercase(o.data.datalist[i].name))
            o.data.currentLine = i
            abs(i - st) > vh && (o.data.currentTop = o.data.currentLine - (vh >> 1))
            _fb_checkTop!(o)
            return i
        end
        i = mod(i - 1 + step, o.data.datalistlen) + 1
        i == st && (beep(); return 0)
    end
end

function _fb_navigate_up!(o::TwObj{TwFileBrowserData})
    parentpath = dirname(o.data.rootpath)
    parentpath == o.data.rootpath && (beep(); return false)
    o.data.rootpath = parentpath
    o.title = parentpath
    o.data.openstatemap = Dict{String,Bool}()
    o.data.openstatemap[o.data.rootpath] = true
    o.data.datalist = FileRow[]
    file_tree_data(o.data.rootpath, o.data.datalist, o.data.openstatemap,
                   Any[], Int[], o.data.showHidden, o.data.sortBy)
    updateFileBrowserDimensions(o)
    o.data.currentLine = 1; o.data.currentTop = 1; o.data.currentLeft = 1
    o.data.previewPath = ""; o.data.previewTop = 1
    return true
end

function _fb_expand_all!(o::TwObj{TwFileBrowserData})
    o.data.datalistlen == 0 && (beep(); return false)
    vh = o.height - 2 * o.borderSizeV
    currentstack = o.data.datalist[o.data.currentLine].stack
    somethingchanged = false
    for i = 1:o.data.datalistlen
        if o.data.datalist[i].expandhint == :close
            o.data.openstatemap[o.data.datalist[i].abspath] = true
            somethingchanged = true
        end
    end
    if somethingchanged
        prevline = o.data.currentLine
        _fb_update_data!(o)
        for i = o.data.currentLine:o.data.datalistlen
            if currentstack == o.data.datalist[i].stack
                o.data.currentLine = i
                abs(i - prevline) > vh && (o.data.currentTop = i - round(Int, vh / 2))
                break
            end
        end
        _fb_checkTop!(o)
        return true
    else
        beep()
        return false
    end
end

function _fb_collapse_deepest!(o::TwObj{TwFileBrowserData})
    o.data.datalistlen == 0 && (beep(); return)
    vh = o.height - 2 * o.borderSizeV
    currentstack = copy(o.data.datalist[o.data.currentLine].stack)
    maxdepth = maximum(map(r -> length(r.stack), o.data.datalist))
    maxdepth <= 1 && (beep(); return)
    somethingchanged = false
    for i = 1:o.data.datalistlen
        stck = o.data.datalist[i].stack
        if o.data.datalist[i].expandhint != :single && length(stck) == maxdepth - 1
            fullpath = o.data.datalist[i].abspath
            if get(o.data.openstatemap, fullpath, false)
                o.data.openstatemap[fullpath] = false
                somethingchanged = true
            end
        end
    end
    if somethingchanged
        _fb_update_data!(o)
        length(currentstack) == maxdepth && pop!(currentstack)
        prevline = o.data.currentLine; o.data.currentLine = 1
        for i = 1:min(prevline, o.data.datalistlen)
            if currentstack == o.data.datalist[i].stack
                o.data.currentLine = i
                abs(i - prevline) > vh && (o.data.currentTop = i - round(Int, vh / 2))
                break
            end
        end
        _fb_checkTop!(o)
    else
        beep()
    end
end

function _fb_collapse_all!(o::TwObj{TwFileBrowserData})
    o.data.datalistlen == 0 && (beep(); return)
    vh = o.height - 2 * o.borderSizeV
    currentstack = copy(o.data.datalist[o.data.currentLine].stack)
    length(currentstack) > 1 && (currentstack = Any[currentstack[1]])
    o.data.openstatemap = Dict{String,Bool}()
    o.data.openstatemap[o.data.rootpath] = true
    _fb_update_data!(o)
    prevline = o.data.currentLine; o.data.currentLine = 1
    for i = 1:min(prevline, o.data.datalistlen)
        if currentstack == o.data.datalist[i].stack
            o.data.currentLine = i
            abs(i - prevline) > vh && (o.data.currentTop = o.data.currentLine - round(Int, vh / 2))
            break
        end
    end
    _fb_checkTop!(o)
end

function _fb_toggle_hidden!(o::TwObj{TwFileBrowserData})
    o.data.showHidden = !o.data.showHidden
    prevstack = o.data.datalistlen > 0 ? copy(o.data.datalist[o.data.currentLine].stack) : Any[]
    _fb_update_data!(o)
    o.data.currentLine = 1
    for i = 1:o.data.datalistlen
        o.data.datalist[i].stack == prevstack && (o.data.currentLine = i; break)
    end
    _fb_checkTop!(o)
end

function _fb_cycle_sort!(o::TwObj{TwFileBrowserData})
    o.data.sortBy = o.data.sortBy == :name ? :size : o.data.sortBy == :size ? :mtime : :name
    prevstack = o.data.datalistlen > 0 ? copy(o.data.datalist[o.data.currentLine].stack) : Any[]
    _fb_update_data!(o)
    o.data.currentLine = 1
    for i = 1:o.data.datalistlen
        o.data.datalist[i].stack == prevstack && (o.data.currentLine = i; break)
    end
    _fb_checkTop!(o)
end

# ─── bindings ─────────────────────────────────────────────────────────────────

function bindings(o::TwObj{TwFileBrowserData})
    vh = () -> o.height - 2 * o.borderSizeV
    [
        Binding(:esc, "cancel", action = _->Cancel),
        Binding(" ", "toggle dir",
                action = _->begin
                    o.data.datalistlen == 0 && (beep(); return Handled)
                    fullpath = o.data.datalist[o.data.currentLine].abspath
                    is_dir   = o.data.datalist[o.data.currentLine].isdir
                    if fullpath == dirname(o.data.rootpath) &&
                            o.data.datalist[o.data.currentLine].name == "../"
                        _fb_navigate_up!(o)
                    elseif is_dir
                        o.data.datalist[o.data.currentLine].expandhint == :single ?
                            beep() :
                            (o.data.openstatemap[fullpath] = !get(o.data.openstatemap, fullpath, false);
                             _fb_update_data!(o))
                    else
                        beep()
                    end
                    Handled
                end),
        Binding([:enter, Symbol("return")], "select / toggle",
                action = _->begin
                    o.data.datalistlen == 0 && (beep(); return Handled)
                    fullpath = o.data.datalist[o.data.currentLine].abspath
                    is_dir   = o.data.datalist[o.data.currentLine].isdir
                    if fullpath == dirname(o.data.rootpath) &&
                            o.data.datalist[o.data.currentLine].name == "../"
                        _fb_navigate_up!(o)
                        return Handled
                    elseif is_dir
                        o.data.datalist[o.data.currentLine].expandhint == :single ?
                            beep() :
                            (o.data.openstatemap[fullpath] = !get(o.data.openstatemap, fullpath, false);
                             _fb_update_data!(o))
                        return Handled
                    else
                        o.value = fullpath
                        return Accept
                    end
                end),
        Binding("+", "expand all",     action = _->(_fb_expand_all!(o); Handled)),
        Binding("-", "collapse level", action = _->(_fb_collapse_deepest!(o); Handled)),
        Binding("_", "collapse all",   action = _->(_fb_collapse_all!(o); Handled)),
        Binding(".", "toggle hidden",  action = _->(_fb_toggle_hidden!(o); Handled)),
        Binding("s", "cycle sort",     action = _->(_fb_cycle_sort!(o); Handled)),
        Binding(:F6, "popup viewer",
                action = _->begin
                    o.data.datalistlen == 0 && (beep(); return Handled)
                    fullpath = o.data.datalist[o.data.currentLine].abspath
                    is_dir   = o.data.datalist[o.data.currentLine].isdir
                    if !is_dir && isfile(fullpath)
                        ext = o.data.datalist[o.data.currentLine].typestr
                        sz = filesize(fullpath)
                        if sz == 0
                            text = "(empty file)"
                        else
                            bytes = read(fullpath, min(sz, 256_000))
                            text = any(==(0x00), bytes) ?
                                "(binary file, " * human_readable_size(Int64(sz)) * ")" :
                                String(bytes)
                        end
                        ext == ".jl" ? tshow(text, "julia:" * fullpath; title = basename(fullpath)) :
                                       tshow(text, title = basename(fullpath))
                    else
                        beep()
                    end
                    Handled
                end),
        Binding(:shift_F6, "file stat",
                action = _->begin
                    o.data.datalistlen == 0 && (beep(); return Handled)
                    fullpath = o.data.datalist[o.data.currentLine].abspath
                    local info
                    try
                        st = stat(fullpath)
                        info = "Path: " * fullpath * "\n"
                        info *= "Size: " * human_readable_size(Int64(st.size)) *
                                " (" * string(st.size) * " bytes)\n"
                        info *= "Modified: " * string(unix2datetime(st.mtime)) * "\n"
                        info *= "Mode: " * string(st.mode, base = 8) * "\n"
                        islink(fullpath) && (info *= "Link target: " * readlink(fullpath) * "\n")
                        info *= isdir(fullpath) ? "Type: directory\n" :
                                isfile(fullpath) ? "Type: file\n" : ""
                    catch err
                        info = "Error reading stat: " * string(err)
                    end
                    tshow(info, title = "stat: " * basename(fullpath))
                    Handled
                end),
        Binding(:ctrl_up, "prev sibling",
                action = _->begin
                    (target, moved) = tree_nav(o.data.datalist, o.data.currentLine, :prev_sibling)
                    moved ? (o.data.currentLine = target; _fb_checkTop!(o)) : beep()
                    Handled
                end),
        Binding(:ctrl_down, "next sibling",
                action = _->begin
                    (target, moved) = tree_nav(o.data.datalist, o.data.currentLine, :next_sibling)
                    moved ? (o.data.currentLine = target; _fb_checkTop!(o)) : beep()
                    Handled
                end),
        Binding(:ctrl_pageup, "preview page up",
                action = _->begin
                    o.data.previewTop > 1 ?
                        (o.data.previewTop = max(1, o.data.previewTop - vh())) : beep()
                    Handled
                end),
        Binding(:ctrl_pagedown, "preview page down",
                action = _->begin
                    curpath = o.data.datalistlen > 0 ?
                        o.data.datalist[o.data.currentLine].abspath : ""
                    if curpath != "" && haskey(o.data.previewCache, curpath)
                        maxTop = max(1, length(o.data.previewCache[curpath]) - vh() + 1)
                        o.data.previewTop < maxTop ?
                            (o.data.previewTop = min(maxTop, o.data.previewTop + vh())) : beep()
                    else
                        beep()
                    end
                    Handled
                end),
        Binding(:up,       "up",        action = _->(_fb_moveby!(o, -1); Handled)),
        Binding(:down,     "down",      action = _->(_fb_moveby!(o,  1); Handled)),
        Binding(:pageup,   "page up",   action = _->(_fb_moveby!(o, -vh()); Handled)),
        Binding(:pagedown, "page down", action = _->(_fb_moveby!(o,  vh()); Handled)),
        Binding(:home, "go to start",
                action = _->begin
                    if o.data.currentTop != 1 || o.data.currentLeft != 1 || o.data.currentLine != 1
                        o.data.currentTop = 1; o.data.currentLeft = 1; o.data.currentLine = 1
                    else
                        beep()
                    end
                    Handled
                end),
        Binding(Symbol("end"), "go to end",
                action = _->begin
                    if o.data.datalistlen > 0 && o.data.currentLine != o.data.datalistlen
                        o.data.currentTop = max(1, o.data.datalistlen - vh() + 1)
                        o.data.currentLine = o.data.datalistlen
                    else
                        beep()
                    end
                    Handled
                end),
        Binding("/", "search",
                action = _->begin
                    helper = newTwEntry(o.screen.value, String;
                                       width = 30, posy = :center, posx = :center,
                                       title = "Search: ")
                    helper.data.inputText = o.data.searchText
                    s = activateTwObj(helper)
                    unregisterTwObj(o.screen.value, helper)
                    if s !== nothing && s != "" && o.data.searchText != s
                        o.data.searchText = s
                        _fb_search_next!(o, 1, true)
                    end
                    Handled
                end),
        Binding(["n", :ctrl_n], "next match",
                action = _->(o.data.searchText != "" && _fb_search_next!(o,  1, false); Handled)),
        Binding(["p", "N", :ctrl_p], "prev match",
                action = _->(o.data.searchText != "" && _fb_search_next!(o, -1, false); Handled)),
        Binding("L", "mid → end",
                action = _->begin
                    o.data.datalistlen == 0 && (beep(); return Handled)
                    target = min(round(Int, ceil((o.data.currentLine + o.data.datalistlen) / 2)),
                                 o.data.datalistlen)
                    target != o.data.currentLine ?
                        (o.data.currentLine = target; _fb_checkTop!(o)) : beep()
                    Handled
                end),
        Binding("l", "mid → start",
                action = _->begin
                    o.data.datalistlen == 0 && (beep(); return Handled)
                    target = max(round(Int, floor(o.data.currentLine / 2)), 1)
                    target != o.data.currentLine ?
                        (o.data.currentLine = target; _fb_checkTop!(o)) : beep()
                    Handled
                end),
    ]
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
        stacklen = length(o.data.datalist[r].stack)
        is_dir = o.data.datalist[r].isdir

        s = ensure_length(
            repeat(" ", 2 * stacklen + 1) * o.data.datalist[r].name,
            treeW,
        )
        t = ensure_length(o.data.datalist[r].typestr, typeW)
        sz = ensure_length(o.data.datalist[r].sizestr, sizeW, false)
        # right-align size: pad with spaces on the left
        szpad = sizeW - length(sz)
        if szpad > 0
            sz = repeat(" ", szpad) * sz
        end
        mt = ensure_length(o.data.datalist[r].mtimestr, mtimeW, false)
        mtpad = mtimeW - length(mt)
        if mtpad > 0
            mt = repeat(" ", mtpad) * mt
        end

        if r == o.data.currentLine
            wattron(o.window, A_BOLD | theme(o.hasFocus ? :selection_focused : :selection_unfocused))
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
            if !in(i, o.data.datalist[r].skiplines)  # skiplines
                mvwaddch(o.window, row, 2 * i, get_acs_val('x'))
            end
        end
        if stacklen != 0
            contchar = get_acs_val('t')  # tee pointing right ├
            if r == o.data.datalistlen ||
               length(o.data.datalist[r+1].stack) < stacklen ||
               (
                   length(o.data.datalist[r+1].stack) > stacklen &&
                   in(stacklen, o.data.datalist[r+1].skiplines)
               )
                contchar = get_acs_val('m')  # LL corner └
            end
            mvwaddch(o.window, row, 2 * stacklen, contchar)
            mvwaddch(o.window, row, 2 * stacklen + 1, get_acs_val('q'))  # horizontal ─
        end

        # expand/collapse indicator
        if o.data.datalist[r].expandhint == :close
            mvwprintw(o.window, row, 2 * stacklen + 2, "%s", string(Char(0x25b8)))
        elseif o.data.datalist[r].expandhint == :open
            mvwprintw(o.window, row, 2 * stacklen + 2, "%s", string(Char(0x25be)))
        end

        if r == o.data.currentLine
            wattroff(o.window, A_BOLD | theme(o.hasFocus ? :selection_focused : :selection_unfocused))
        end
    end

    # ── RIGHT ZONE: file preview ──
    if rightW > 0
        previewX = dividerX + 1

        # update preview for current selection
        if o.data.datalistlen > 0
            curpath = o.data.datalist[o.data.currentLine].abspath
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

        # Check whether the current selection is an image. If so, blit the
        # cached visual onto the preview pane and skip the text-preview path.
        is_image_path = o.data.previewPath != "" &&
                        !(o.data.datalistlen > 0 &&
                          o.data.datalist[o.data.currentLine].isdir) &&
                        is_image_preview(o.data.previewPath)

        if is_image_path
            # Clear preview area first to wipe any prior text
            for i in 1:viewContentHeight
                mvwprintw(o.window, i, previewX, "%s", repeat(" ", rightW))
            end
            visual = load_image_preview(o, o.data.previewPath)
            if visual === nothing
                mvwprintw(o.window, 1, previewX, "%s",
                          ensure_length("(failed to decode image)", rightW, false))
            else
                blitter = NC.Blitter.DEFAULT
                if o.window isa NC.Plane
                    try
                        blitter = _resolve_image_blitter(nc_context, NC.Scale.SCALE)
                    catch
                        blitter = NC.Blitter.DEFAULT
                    end
                    opts = NC.VisualOptions(;
                        plane   = o.window,
                        scaling = NC.Scale.SCALE,
                        y       = 1,           # below the title border
                        x       = previewX,
                        leny    = UInt(0),
                        lenx    = UInt(0),
                        blitter = blitter,
                    )
                    try
                        NC.blit(nc_context, visual, opts)
                    catch er
                        log("file browser image blit failed: " *
                            sprint(showerror, er))
                        mvwprintw(o.window, 1, previewX, "%s",
                                  ensure_length("(blit failed)", rightW, false))
                    end
                else
                    mvwprintw(o.window, 1, previewX, "%s",
                              ensure_length("(image preview unavailable)", rightW, false))
                end
            end
        else
            # get preview lines
            local lines::Vector{String}
            if o.data.previewPath == ""
                lines = String[]
            elseif o.data.datalistlen > 0 && o.data.datalist[o.data.currentLine].isdir
                lines = ["(directory)"]
            else
                current_mtime = try; Float64(stat(o.data.previewPath).mtime); catch; 0.0; end
                if haskey(o.data.previewCache, o.data.previewPath) &&
                        get(o.data.previewMtimeCache, o.data.previewPath, -1.0) != current_mtime
                    delete!(o.data.previewCache, o.data.previewPath)
                    delete!(o.data.previewSpanCache, o.data.previewPath)
                    delete!(o.data.previewMtimeCache, o.data.previewPath)
                end
                if !haskey(o.data.previewCache, o.data.previewPath)
                    # evict old entries if cache is full
                    if length(o.data.previewCache) > 20
                        ks = collect(keys(o.data.previewCache))
                        for k in ks[1:min(10, length(ks))]
                            delete!(o.data.previewCache, k)
                            delete!(o.data.previewSpanCache, k)
                            delete!(o.data.previewMtimeCache, k)
                        end
                    end
                    plines = load_preview(o.data.previewPath)
                    o.data.previewCache[o.data.previewPath] = plines
                    o.data.previewMtimeCache[o.data.previewPath] = current_mtime
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

function _fb_sel_text(o::TwObj{TwFileBrowserData})
    isempty(o.data.datalist) && return ""
    row = o.data.datalist[clamp(o.data.currentLine, 1, length(o.data.datalist))]
    row.abspath
end

function inject(o::TwObj{TwFileBrowserData}, token)
    r = inject_via_table(o, token)
    if r === Handled
        set!(o.data.selection_text, _fb_sel_text(o))
        refresh(o)
        return r
    end
    r !== Ignored && return r

    # h-scroll, ctrl_left (parent dir), ctrl_right, mouse
    vh = o.height - 2 * o.borderSizeV
    if token == :left
        o.data.currentLeft > 1 ? (o.data.currentLeft -= 1; refresh(o)) : beep()
        return Handled
    elseif token == :right
        o.data.currentLeft += 1; refresh(o)
        return Handled
    elseif token == :ctrl_right
        o.data.currentLeft += 10; refresh(o)
        return Handled
    elseif token == :ctrl_left
        (target, moved) = tree_nav(o.data.datalist, o.data.currentLine, :parent)
        if moved
            o.data.currentLine = target; _fb_checkTop!(o)
            set!(o.data.selection_text, _fb_sel_text(o)); refresh(o)
        else
            beep()
        end
        return Handled
    elseif token == :KEY_MOUSE
        (mstate, x, y, bs) = getmouse()
        if mstate == :scroll_up
            _fb_moveby!(o, -(round(Int, vh / 5))); refresh(o)
        elseif mstate == :scroll_down
            _fb_moveby!(o,  round(Int, vh / 5));  refresh(o)
        elseif mstate == :ctrl_scroll_up
            if o.data.previewTop > 1
                o.data.previewTop = max(1, o.data.previewTop - 5); refresh(o)
            else
                beep()
            end
        elseif mstate == :ctrl_scroll_down
            curpath = o.data.datalistlen > 0 ? o.data.datalist[o.data.currentLine].abspath : ""
            if curpath != "" && haskey(o.data.previewCache, curpath)
                maxTop = max(1, length(o.data.previewCache[curpath]) - vh + 1)
                o.data.previewTop < maxTop ?
                    (o.data.previewTop = min(maxTop, o.data.previewTop + 5); refresh(o)) : beep()
            else
                beep()
            end
        elseif mstate == :button1_pressed
            # screen_to_relative handles both an NC.Plane window and a TwWindow
            # (embedded in a list/livewidget).
            rely, relx = screen_to_relative(o.window, y, x)
            if 0 <= relx < o.width && 0 <= rely < o.height
                newline = o.data.currentTop + rely - o.borderSizeV
                if newline >= 1 && newline <= o.data.datalistlen
                    o.data.currentLine = newline; _fb_checkTop!(o)
                    set!(o.data.selection_text, _fb_sel_text(o)); refresh(o)
                end
            else
                return Ignored
            end
        end
        return Handled
    end

    return Ignored
end

helptext(o::TwObj{TwFileBrowserData}) = o.data.showHelp ? helptext_from_bindings(o) : ""

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
