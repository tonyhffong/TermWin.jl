# twedittable.jl — editable table widget backed by a DataFrame

defaultEditTableBottomText = "F1:Help  Ctrl-N:New_row  Ctrl-D:Del_Row  Ctrl-Y:Copy  Ctrl-P:Paste  F10:Submit"

struct TwEditTableCol
    name::Symbol                               # DataFrame column name
    title::String                              # Header display text
    width::Int                                 # Display width in chars
    editable::Bool                             # Whether user may edit
    valuetype::DataType                        # String, Int, Float64, Date, ...
    enumvalues::Union{Nothing,Vector{String}}  # Non-nothing → popup picker
end

mutable struct TwEditTableData
    df::DataFrame
    colspecs::Vector{TwEditTableCol}
    currentRow::Int        # 1-based row index into df
    currentCol::Int        # 1-based index into colspecs
    currentTop::Int        # first visible row (vertical scroll)
    currentLeft::Int       # first visible column (horizontal scroll)
    editbuffer::String     # working value for the active cell
    cursorPos::Int         # 1-based width position (next char goes here)
    fieldLeftPos::Int      # 1-based width position of leftmost visible char
    overwriteMode::Bool
    incomplete::Bool       # editbuffer failed validation
    editDirty::Bool        # editbuffer differs from stored df value
    bottomText::String
end

function newTwEditTable(
    scr::TwObj,
    df::DataFrame,
    colspecs::Vector{TwEditTableCol};
    height::Real = 0.8,
    width::Real = 0.8,
    posy::Any = :center,
    posx::Any = :center,
    title::String = "",
    box::Bool = true,
    key::Union{Nothing,Symbol} = nothing,
    bottomText::String = defaultEditTableBottomText,
)
    data = TwEditTableData(
        df,
        colspecs,
        1, 1, 1, 1,
        "", 1, 1,
        false, false, false,
        bottomText,
    )
    obj = TwObj(data, Val{:EditTable})
    obj.box = box
    obj.title = title
    obj.formkey = key
    obj.borderSizeV = box ? 1 : 0
    obj.borderSizeH = box ? 1 : 0

    link_parent_child(scr, obj, height, width, posy, posx)

    if nrow(df) > 0 && !isempty(colspecs)
        _et_load_cell!(data)
    end
    obj.value = df
    obj
end

# ─── Helpers ──────────────────────────────────────────────────────────────────

function _et_cell_to_buf(val, col::TwEditTableCol)::String
    val === missing && return ""
    if col.enumvalues !== nothing || col.valuetype <: AbstractString
        return string(val)
    elseif col.valuetype <: Date
        return Dates.format(Date(val), "yyyy-mm-dd")
    elseif col.valuetype <: Number
        ed = TwEntryData(col.valuetype)
        return myNumFormat(val, ed, col.width)
    else
        return string(val)
    end
end

function _et_load_cell!(data::TwEditTableData)
    col = data.colspecs[data.currentCol]
    val = data.df[data.currentRow, col.name]
    data.editbuffer = _et_cell_to_buf(val, col)
    data.cursorPos = length(data.editbuffer) + 1
    data.fieldLeftPos = 1
    data.incomplete = false
    data.editDirty = false
end

function _et_commit_cell!(data::TwEditTableData)::Bool
    col = data.colspecs[data.currentCol]
    !col.editable && return true
    col.enumvalues !== nothing && return true  # enum written directly on selection

    if col.valuetype <: AbstractString
        data.df[data.currentRow, col.name] = data.editbuffer
        data.incomplete = false
        data.editDirty = false
        return true
    else
        ed = TwEntryData(col.valuetype)
        (v, s) = evalNFormat(ed, data.editbuffer, col.width)
        if v !== nothing
            data.df[data.currentRow, col.name] = v
            data.editbuffer = s
            data.incomplete = false
            data.editDirty = false
            return true
        else
            data.incomplete = true
            return false
        end
    end
end

function _et_checkcursor!(data::TwEditTableData)
    col = data.colspecs[data.currentCol]
    if data.editbuffer == ""
        data.cursorPos = 1
    else
        data.cursorPos = max(1, min(length(data.editbuffer) + 1, data.cursorPos))
    end
    if col.valuetype <: AbstractString || col.enumvalues !== nothing
        fieldcount = col.width
        remainspacecount = fieldcount - textwidth(data.editbuffer)
        if remainspacecount <= 0
            if data.cursorPos - data.fieldLeftPos > fieldcount - 1
                data.fieldLeftPos = data.cursorPos - fieldcount + 1
            elseif data.fieldLeftPos > data.cursorPos
                data.fieldLeftPos = data.cursorPos
            end
        else
            data.fieldLeftPos = 1
        end
    end
end

function _et_checkTop!(o::TwObj{TwEditTableData})
    data = o.data
    dataH = o.height - 2 * o.borderSizeV - 1
    dataH <= 0 && return
    if data.currentRow < data.currentTop
        data.currentTop = data.currentRow
    elseif data.currentRow >= data.currentTop + dataH
        data.currentTop = data.currentRow - dataH + 1
    end
end

function _et_checkLeft!(o::TwObj{TwEditTableData})
    data = o.data
    ncols = length(data.colspecs)
    viewW = o.width - 2 * o.borderSizeH

    if data.currentLeft > data.currentCol
        data.currentLeft = data.currentCol
        return
    end

    # Advance currentLeft until currentCol is fully visible
    while true
        colx = 0
        last_visible = data.currentLeft - 1
        for c in data.currentLeft:ncols
            col = data.colspecs[c]
            colx + col.width > viewW && break
            last_visible = c
            colx += col.width
            colx < viewW && (colx += 1)
        end
        last_visible >= data.currentCol && break
        data.currentLeft += 1
        data.currentLeft > data.currentCol && (data.currentLeft = data.currentCol; break)
    end
end

# Compute visible column indices and their starting x offsets (within content area)
function _et_visible_cols(o::TwObj{TwEditTableData})
    data = o.data
    viewW = o.width - 2 * o.borderSizeH
    cols = Int[]
    starts = Int[]
    colx = 0
    for c in data.currentLeft:length(data.colspecs)
        col = data.colspecs[c]
        colx + col.width > viewW && break
        push!(cols, c)
        push!(starts, colx)
        colx += col.width
        colx < viewW && (colx += 1)
    end
    cols, starts
end

function _et_default_value(col::TwEditTableCol)
    col.enumvalues !== nothing    && return col.enumvalues[1]
    col.valuetype <: AbstractString && return ""
    col.valuetype <: AbstractFloat   && return zero(col.valuetype)
    col.valuetype <: Integer         && return zero(col.valuetype)
    col.valuetype <: Date            && return today()
    col.valuetype == Bool            && return false
    return missing
end

function _et_insert_row_after!(data::TwEditTableData, after_row::Int)
    col_syms = Tuple(Symbol.(names(data.df)))
    colspec_map = Dict(col.name => col for col in data.colspecs)
    vals = Tuple(
        haskey(colspec_map, sym) ? _et_default_value(colspec_map[sym]) : missing
        for sym in col_syms
    )
    new_row = NamedTuple{col_syms}(vals)
    insert!(data.df, after_row + 1, new_row)
end

function _et_format_cell(val, col::TwEditTableCol)::String
    val === missing && return repeat(" ", col.width)
    s = _et_cell_to_buf(val, col)
    if col.valuetype <: Number && col.enumvalues === nothing
        # right-justify: lpad to width, truncate with # if overflow
        sw = textwidth(s)
        sw > col.width ? repeat("#", col.width) : lpad(s, col.width)
    else
        ensure_length(s, col.width)
    end
end

function _et_draw_active_cell!(
    o::TwObj{TwEditTableData},
    y::Int,
    startx::Int,
    col::TwEditTableCol,
)
    data = o.data
    fieldcount = col.width
    editbuffer = data.editbuffer
    cursorPos = data.cursorPos
    fieldLeftPos = data.fieldLeftPos
    remainspacecount = fieldcount - textwidth(editbuffer)

    # Build outstr and rcursPos (display cursor column, 1-based within field)
    local outstr::String
    local rcursPos::Int
    if col.valuetype <: Number && col.valuetype != Bool && col.enumvalues === nothing
        if remainspacecount <= 0
            rcursPos = max(1, min(fieldcount, cursorPos))
            outstr = repeat("#", fieldcount - 1) * " "
        else
            rcursPos = max(1, min(remainspacecount + cursorPos - 1, fieldcount))
            outstr = repeat(" ", remainspacecount - 1) * editbuffer * " "
        end
    elseif col.valuetype <: Date && col.enumvalues === nothing
        if remainspacecount <= 0
            rcursPos = max(1, min(fieldcount, cursorPos))
            outstr = repeat("#", fieldcount - 1) * " "
        else
            rcursPos = max(1, min(cursorPos, fieldcount))
            outstr = editbuffer * repeat(" ", remainspacecount)
        end
    else  # String or enum
        if remainspacecount <= 0
            rcursPos = min(fieldcount, max(1, cursorPos - fieldLeftPos + 1))
            outstr = substr_by_width(editbuffer, fieldLeftPos - 1, fieldcount)
            strw = textwidth(outstr)
            if strw < fieldcount
                outstr *= repeat(" ", fieldcount - strw)
            end
        else
            outstr = editbuffer * repeat(" ", remainspacecount)
            rcursPos = cursorPos
        end
    end

    if o.hasFocus
        inputflag = COLOR_PAIR(15)
    elseif data.incomplete
        inputflag = COLOR_PAIR(12)
    else
        inputflag = COLOR_PAIR(30)
    end

    wattron(o.window, inputflag)
    mvwprintw(o.window, y, startx, "%s", outstr)

    firstflag = inputflag
    lastflag = inputflag
    if o.hasFocus && col.editable && col.enumvalues === nothing
        c = substr_by_width(outstr, rcursPos - 1, 1)
        flag = data.overwriteMode ? (inputflag | A_REVERSE) : (inputflag | A_UNDERLINE)
        wattron(o.window, flag)
        mvwprintw(o.window, y, startx + rcursPos - 1, "%s", string(c))
        wattroff(o.window, flag)
        rcursPos == 1 && (firstflag = flag)
        rcursPos == fieldcount && (lastflag = flag)
    end

    # Boundary indicators for string/enum cells with overflow
    if col.valuetype <: AbstractString || col.enumvalues !== nothing
        if fieldLeftPos > 1
            c = substr_by_width(outstr, 0, 1)
            wattron(o.window, firstflag | A_BOLD)
            mvwprintw(o.window, y, startx, "%s", string(c))
            wattroff(o.window, firstflag | A_BOLD)
        end
        if fieldLeftPos + fieldcount <= textwidth(editbuffer)
            c = substr_by_width(outstr, fieldcount - 1, 1)
            wattron(o.window, lastflag | A_BOLD)
            mvwprintw(o.window, y, startx + fieldcount - 1, "%s", string(c))
            wattroff(o.window, lastflag | A_BOLD)
        end
    end

    wattroff(o.window, inputflag)
end

function _et_clipboard_write(s::String)
    try
        if Sys.isapple()
            open(`pbcopy`, "w") do io; write(io, s); end
        elseif Sys.iswindows()
            open(`clip`, "w") do io; write(io, s); end
        else
            try
                open(`xclip -selection clipboard`, "w") do io; write(io, s); end
            catch
                open(`xsel --clipboard --input`, "w") do io; write(io, s); end
            end
        end
    catch
        beep()
    end
end

function _et_clipboard_read()::String
    try
        if Sys.isapple()
            return read(`pbpaste`, String)
        elseif Sys.iswindows()
            return read(`powershell -command Get-Clipboard`, String)
        else
            try
                return read(`xclip -selection clipboard -o`, String)
            catch
                return read(`xsel --clipboard --output`, String)
            end
        end
    catch
        return ""
    end
end

function _et_tsv_cell(val, col::TwEditTableCol)::String
    val === missing && return ""
    col.valuetype <: Date && return Dates.format(Date(val), "yyyy-mm-dd")
    col.valuetype <: Number && return string(val)
    return string(val)
end

function _et_copy_table!(o::TwObj{TwEditTableData})
    data = o.data
    rows = String[]
    push!(rows, join((col.title for col in data.colspecs), "\t"))
    for r in 1:nrow(data.df)
        push!(rows, join((_et_tsv_cell(data.df[r, col.name], col) for col in data.colspecs), "\t"))
    end
    _et_clipboard_write(join(rows, "\n"))
end

function _et_paste_table!(o::TwObj{TwEditTableData})
    data = o.data
    raw = _et_clipboard_read()
    isempty(raw) && return

    lines = split(raw, r"\r?\n")
    while !isempty(lines) && isempty(strip(lines[end]))
        pop!(lines)
    end
    isempty(lines) && return

    # Detect and skip a header line that matches our column titles from currentCol onward
    paste_cols = data.colspecs[data.currentCol:end]
    first_fields = split(lines[1], "\t")
    is_header = length(first_fields) <= length(paste_cols) &&
                all(i -> strip(first_fields[i]) == paste_cols[i].title,
                    1:length(first_fields))
    data_lines = is_header ? lines[2:end] : lines

    isempty(data_lines) && return
    _et_commit_cell!(data)

    dest_row = data.currentRow
    for line in data_lines
        fields = split(line, "\t")

        # Auto-insert row if needed
        if dest_row > nrow(data.df)
            _et_insert_row_after!(data, nrow(data.df))
        end

        for (fi, field) in enumerate(fields)
            col_idx = data.currentCol + fi - 1
            col_idx > length(data.colspecs) && break
            col = data.colspecs[col_idx]
            !col.editable && continue

            s = strip(field)
            if col.valuetype <: AbstractString || col.enumvalues !== nothing
                data.df[dest_row, col.name] = s
            else
                ed = TwEntryData(col.valuetype)
                (v, _) = evalNFormat(ed, s, col.width)
                v !== nothing && (data.df[dest_row, col.name] = v)
            end
        end

        dest_row += 1
    end

    _et_load_cell!(data)
    _et_checkTop!(o)
end

function _et_open_enum_popup!(o::TwObj{TwEditTableData})
    global rootTwScreen
    data = o.data
    col = data.colspecs[data.currentCol]
    popup = newTwPopup(rootTwScreen, col.enumvalues;
        posy = :center, posx = :center,
        substrsearch = true,
        maxheight = min(length(col.enumvalues) + 2, 12),
        maxwidth = max(col.width + 4, 20),
    )
    result = activateTwObj(popup)
    unregisterTwObj(rootTwScreen, popup)
    if result !== nothing
        data.df[data.currentRow, col.name] = result
        _et_load_cell!(data)
    end
end

# ─── draw ─────────────────────────────────────────────────────────────────────

function draw(o::TwObj{TwEditTableData})
    data = o.data
    nrows = nrow(data.df)
    bv = o.borderSizeV
    bh = o.borderSizeH
    viewW = o.width - 2 * bh
    viewH = o.height - 2 * bv   # total drawable rows including header
    dataH = viewH - 1            # rows available for data

    werase(o.window)
    if o.box
        box(o.window, 0, 0)
    end
    if !isempty(o.title) && o.box
        mvwprintw(o.window, 0, max(1, div(o.width - length(o.title), 2)), "%s", o.title)
    end

    viewH < 2 && return

    visibleCols, colxStarts = _et_visible_cols(o)

    # Header row
    wattron(o.window, COLOR_PAIR(3) | A_UNDERLINE)
    mvwprintw(o.window, bv, bh, "%s", repeat(" ", viewW))
    for (vi, c) in enumerate(visibleCols)
        col = data.colspecs[c]
        cx = bh + colxStarts[vi]
        hdr = if col.valuetype <: Number && col.enumvalues === nothing
            lpad(col.title, col.width)
        else
            ensure_length(col.title, col.width)
        end
        mvwprintw(o.window, bv, cx, "%s", hdr)
        if vi < length(visibleCols)
            mvwprintw(o.window, bv, cx + col.width, "%s", "│")
        end
    end
    wattroff(o.window, COLOR_PAIR(3) | A_UNDERLINE)

    # Data rows
    for ri in 1:dataH
        r = data.currentTop + ri - 1
        r > nrows && break
        y = bv + ri

        is_current = (r == data.currentRow)
        row_flag = is_current ? (o.hasFocus ? COLOR_PAIR(30) : COLOR_PAIR(13)) :
                                (isodd(r)   ? COLOR_PAIR(7)  : COLOR_PAIR(13))

        # Paint the full row background
        wattron(o.window, row_flag)
        mvwprintw(o.window, y, bh, "%s", repeat(" ", viewW))
        wattroff(o.window, row_flag)

        for (vi, c) in enumerate(visibleCols)
            col = data.colspecs[c]
            cx = bh + colxStarts[vi]
            is_active = is_current && (c == data.currentCol)

            if is_active
                _et_draw_active_cell!(o, y, cx, col)
            else
                cellstr = _et_format_cell(data.df[r, col.name], col)
                wattron(o.window, row_flag)
                mvwprintw(o.window, y, cx, "%s", cellstr)
                wattroff(o.window, row_flag)
            end

            if vi < length(visibleCols)
                wattron(o.window, row_flag)
                mvwprintw(o.window, y, cx + col.width, "%s", "│")
                wattroff(o.window, row_flag)
            end
        end
    end

    if !isempty(data.bottomText)
        mvwprintw(o.window, o.height - 1, 3, "%s", data.bottomText)
    end
end

# ─── inject ───────────────────────────────────────────────────────────────────

function inject(o::TwObj{TwEditTableData}, token)
    data = o.data
    nrows = nrow(data.df)
    ncols = length(data.colspecs)
    dorefresh = false
    retcode = :got_it

    col = data.colspecs[data.currentCol]
    is_editable = col.editable
    is_enum = col.enumvalues !== nothing

    insertchar = (c) -> begin
        data.editbuffer = insertstring(data.editbuffer, c, data.cursorPos, data.overwriteMode)
        data.cursorPos += textwidth(c)
        data.editDirty = true
    end

    function move_next_editable()
        c = data.currentCol; r = data.currentRow
        start_c, start_r = c, r
        while true
            c += 1
            if c > ncols; c = 1; r += 1; r > nrows && (r = start_r; c = start_c; return); end
            (c == start_c && r == start_r) && return
            data.colspecs[c].editable && (data.currentCol = c; data.currentRow = r; return)
        end
    end

    function move_prev_editable()
        c = data.currentCol; r = data.currentRow
        start_c, start_r = c, r
        while true
            c -= 1
            if c < 1; c = ncols; r -= 1; r < 1 && (r = start_r; c = start_c; return); end
            (c == start_c && r == start_r) && return
            data.colspecs[c].editable && (data.currentCol = c; data.currentRow = r; return)
        end
    end

    if token == :F10
        if _et_commit_cell!(data)
            o.value = data.df
            retcode = :exit_ok
        else
            beep()
        end
    elseif token == :esc
        if data.editDirty
            _et_load_cell!(data)
            dorefresh = true
        else
            retcode = :exit_nothing
        end
    elseif token == :up
        if _et_commit_cell!(data)
            if data.currentRow > 1
                data.currentRow -= 1
            else
                beep()
            end
            _et_load_cell!(data)
            _et_checkTop!(o)
            dorefresh = true
        else
            beep()
        end
    elseif token == :down
        if _et_commit_cell!(data)
            if data.currentRow < nrows
                data.currentRow += 1
            else
                beep()
            end
            _et_load_cell!(data)
            _et_checkTop!(o)
            dorefresh = true
        else
            beep()
        end
    elseif (token == :enter || token == Symbol("return")) && !(is_editable && is_enum)
        # Enter on non-enum cells moves down a row (like a spreadsheet)
        if _et_commit_cell!(data)
            if data.currentRow < nrows
                data.currentRow += 1
            else
                beep()
            end
            _et_load_cell!(data)
            _et_checkTop!(o)
            dorefresh = true
        else
            beep()
        end
    elseif token == :pageup
        if _et_commit_cell!(data)
            pageSize = max(1, o.height - 2 * o.borderSizeV - 1)
            data.currentRow = max(1, data.currentRow - pageSize)
            _et_load_cell!(data)
            _et_checkTop!(o)
            dorefresh = true
        else
            beep()
        end
    elseif token == :pagedown
        if _et_commit_cell!(data)
            pageSize = max(1, o.height - 2 * o.borderSizeV - 1)
            data.currentRow = min(nrows, data.currentRow + pageSize)
            _et_load_cell!(data)
            _et_checkTop!(o)
            dorefresh = true
        else
            beep()
        end
    elseif token == :left
        if !is_editable || is_enum || data.cursorPos <= 1
            # Move to previous column
            if _et_commit_cell!(data)
                if data.currentCol > 1
                    data.currentCol -= 1
                else
                    beep()
                end
                _et_load_cell!(data)
                _et_checkLeft!(o)
                dorefresh = true
            else
                beep()
            end
        else
            data.cursorPos -= 1
            _et_checkcursor!(data)
            dorefresh = true
        end
    elseif token == :right
        if !is_editable || is_enum || data.cursorPos > length(data.editbuffer)
            # Move to next column
            if _et_commit_cell!(data)
                if data.currentCol < ncols
                    data.currentCol += 1
                else
                    beep()
                end
                _et_load_cell!(data)
                _et_checkLeft!(o)
                dorefresh = true
            else
                beep()
            end
        else
            data.cursorPos += 1
            _et_checkcursor!(data)
            dorefresh = true
        end
    elseif token == :home || token == :ctrl_a
        if data.cursorPos > 1
            data.cursorPos = 1
            _et_checkcursor!(data)
            dorefresh = true
        end
    elseif token == :end || token == :ctrl_e
        newpos = length(data.editbuffer) + 1
        if data.cursorPos < newpos
            data.cursorPos = newpos
            _et_checkcursor!(data)
            dorefresh = true
        end
    elseif token == :ctrl_k && is_editable && !is_enum
        data.editbuffer = ""
        data.cursorPos = 1
        data.fieldLeftPos = 1
        data.editDirty = true
        dorefresh = true
    elseif (token == :ctrl_r || token == :insert)
        data.overwriteMode = !data.overwriteMode
        dorefresh = true
    elseif token == :delete && is_editable && !is_enum
        utfs = delete_char_at(data.editbuffer, data.cursorPos)
        if utfs != data.editbuffer
            data.editbuffer = utfs
            _et_checkcursor!(data)
            data.editDirty = true
            dorefresh = true
        else
            beep()
        end
    elseif token == :backspace && is_editable && !is_enum
        utfs, newpos = delete_char_before(data.editbuffer, data.cursorPos)
        if utfs != data.editbuffer
            data.editbuffer = utfs
            data.cursorPos = newpos
            _et_checkcursor!(data)
            data.editDirty = true
            dorefresh = true
        else
            beep()
        end
    elseif is_editable && is_enum &&
           (typeof(token) <: AbstractString || token == :enter || token == Symbol("return"))
        _et_open_enum_popup!(o)
        dorefresh = true
    elseif typeof(token) <: AbstractString && is_editable && !is_enum
        if col.valuetype <: AbstractString
            insertchar(token)
            _et_checkcursor!(data)
            dorefresh = true
        elseif col.valuetype <: Date && !in(token, ["?", ","])
            insertchar(token)
            dorefresh = true
        elseif col.valuetype <: Number && col.valuetype != Bool
            allowed =
                isdigit(token[1]) ||
                token == "," ||
                (col.valuetype <: AbstractFloat && in(token, [".", "e", "+", "-"])) ||
                (col.valuetype <: Signed && in(token, ["+", "-"]))
            if allowed
                if token == "e"
                    if occursin("e", data.editbuffer)
                        beep()
                    else
                        insertchar(token)
                        dorefresh = true
                    end
                elseif token == "."
                    dpos = findfirst(isequal('.'), data.editbuffer)
                    if dpos !== nothing
                        data.cursorPos = dpos + 1
                        dorefresh = true
                    else
                        insertchar(token)
                        dorefresh = true
                    end
                elseif token == "," # format with commas
                    ed = TwEntryData(col.valuetype)
                    (v, s) = evalNFormat(ed, data.editbuffer, col.width)
                    if v !== nothing
                        data.editbuffer = s
                        _et_checkcursor!(data)
                        data.incomplete = false
                        dorefresh = true
                    else
                        data.incomplete = true
                        beep()
                    end
                elseif token == "-" || token == "+"
                    epos = findfirst(isequal('e'), data.editbuffer)
                    at_start = data.cursorPos == 1 &&
                               (startswith(data.editbuffer, "-") ||
                                startswith(data.editbuffer, "+"))
                    after_e = data.cursorPos != 1 &&
                              (epos === nothing || data.cursorPos != epos + 1)
                    if at_start || after_e
                        beep()
                    else
                        insertchar(token)
                        dorefresh = true
                    end
                else
                    insertchar(token)
                    dorefresh = true
                end
            else
                beep()
            end
        end
    elseif token == :ctrl_n
        if _et_commit_cell!(data)
            _et_insert_row_after!(data, data.currentRow)
            data.currentRow += 1
            # Move to first editable column on the new row
            first_ed = findfirst(c -> c.editable, data.colspecs)
            data.currentCol = first_ed !== nothing ? first_ed : 1
            _et_load_cell!(data)
            _et_checkTop!(o)
            _et_checkLeft!(o)
            dorefresh = true
        else
            beep()
        end
    elseif token == :ctrl_d
        if nrows <= 1
            beep()
        else
            delete!(data.df, data.currentRow)
            data.currentRow = min(data.currentRow, nrow(data.df))
            _et_load_cell!(data)
            _et_checkTop!(o)
            dorefresh = true
        end
    elseif token == :ctrl_i
        if _et_commit_cell!(data)
            move_next_editable()
            _et_load_cell!(data)
            _et_checkTop!(o)
            _et_checkLeft!(o)
            dorefresh = true
        else
            beep()
        end
    elseif token == :ctrlshift_i
        if _et_commit_cell!(data)
            move_prev_editable()
            _et_load_cell!(data)
            _et_checkTop!(o)
            _et_checkLeft!(o)
            dorefresh = true
        else
            beep()
        end
    elseif token == :ctrl_y
        _et_copy_table!(o)
    elseif token == :ctrl_p
        _et_paste_table!(o)
        dorefresh = true
    elseif token == :KEY_MOUSE
        (mstate, x, y, bs) = getmouse()
        bv = o.borderSizeV
        bh = o.borderSizeH
        if mstate == :scroll_up
            if _et_commit_cell!(data)
                data.currentRow = max(1, data.currentRow - 3)
                _et_load_cell!(data)
                _et_checkTop!(o)
                dorefresh = true
            end
        elseif mstate == :scroll_down
            if _et_commit_cell!(data)
                data.currentRow = min(nrows, data.currentRow + 3)
                _et_load_cell!(data)
                _et_checkTop!(o)
                dorefresh = true
            end
        elseif mstate == :button1_pressed
            rely, relx = screen_to_relative(o.window, y, x)
            # screen_to_relative returns canvas coords for TwWindow; normalise to widget-local.
            if isa(o.window, TwWindow)
                rely -= o.window.yloc
                relx -= o.window.xloc
            end
            # Check click is inside the data area (not border, not header row)
            in_content = bh <= relx < o.width - bh && bv + 1 <= rely < o.height - bv
            if in_content
                clicked_row = data.currentTop + (rely - bv - 1)
                clicked_row = clamp(clicked_row, 1, nrows)
                # Determine clicked column from x offset within content area
                visibleCols, colxStarts = _et_visible_cols(o)
                clicked_col = data.currentCol  # default: stay
                for (vi, c) in enumerate(visibleCols)
                    col_start = bh + colxStarts[vi]
                    col_end   = col_start + data.colspecs[c].width - 1
                    if col_start <= relx <= col_end
                        clicked_col = c
                        break
                    end
                end
                if clicked_row != data.currentRow || clicked_col != data.currentCol
                    if _et_commit_cell!(data)
                        data.currentRow = clicked_row
                        data.currentCol = clicked_col
                        _et_load_cell!(data)
                        _et_checkTop!(o)
                        _et_checkLeft!(o)
                        dorefresh = true
                    else
                        beep()
                    end
                else
                    dorefresh = true  # refresh to show focus
                end
            else
                retcode = :pass
            end
        end
    elseif token == :focus_off
        _et_commit_cell!(data)
        retcode = :exit_ok
    else
        retcode = :pass
    end

    if dorefresh
        refresh(o)
    end
    retcode
end

function helptext(o::TwObj{TwEditTableData})
    """
←/→      : move cursor (at edge: switch column)
↑/↓      : move row (commits current cell)
Enter    : move down
Home/End : cursor to start/end of cell
Ctrl-K   : clear cell contents
Ctrl-R   : toggle insert/overwrite mode
Del/BS   : delete character
Ctrl-N   : insert new row after current row
Ctrl-D   : delete current row
Ctrl-Tab : advance to next editable field (wraps rows)
C-Sh-Tab : retreat to previous editable field (wraps rows)
Ctrl-Y   : copy whole table to clipboard (TSV with header)
Ctrl-P   : paste TSV from clipboard starting at cursor position
Esc      : revert cell (if changed) / exit
F10      : commit and exit
"""
end
