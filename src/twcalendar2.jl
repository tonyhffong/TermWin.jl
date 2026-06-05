# Traditional month calendar — days-of-week go horizontally, one quarter per row block.
# Requires HOLIDAY_CALENDAR_NAMES from twcalendar.jl (included before this file).

defaultCalendar2HelpText = """
Arrows : move cursor (←→=±1 day, ↑↓=±1 week)
.      : jump to today
a      : jump to start of cursor's month
e      : jump to end of cursor's month
A      : jump to Jan 1st
E      : jump to Dec 31st
d,D    : add/subtract a day
w,W    : add/subtract a week
( the following would do end-of-month truncation)
m,M    : add/subtract a month
q,Q    : add/subtract a quarter
y,Y    : add/subtract a year
Alt-C  : change holiday calendar
(non-business days shown in red)
"""

# Layout
# Each month block: 20 cols  ("Mo Tu We Th Fr Sa Su" = 20 chars; day numbers align to same cols)
# Gap between months in the same quarter: 2 cols
# Three months per quarter row: 20 + 2 + 20 + 2 + 20 = 64 cols
# Each quarter block: 8 rows (1 month-name + 1 weekday-header + up to 6 week rows)
const CAL2_MONTH_W   = 20
const CAL2_MONTH_GAP = 2
const CAL2_QUARTER_W = CAL2_MONTH_W * 3 + CAL2_MONTH_GAP * 2   # 64
const CAL2_QUARTER_H = 8

mutable struct TwCalendar2Data
    showHelp::Bool
    helpText::String
    date::Date
    cursorweekofmonth::Int  # 1-based week row within the cursor's month (set during draw)
    numquarters::Int        # how many quarter blocks fit: 1, 2, or 4
    holidayCal::Symbol
    TwCalendar2Data(dt::Date) = new(true, defaultCalendar2HelpText, dt, 1, 4, :USSettlement)
end

function bestfitgeometry2(scr::TwScreen, box::Bool)
    (parmaxy, parmaxx) = getwinmaxyx(scr.window)
    w = CAL2_QUARTER_W + (box ? 2 : 0)
    hbase = 1 + (box ? 2 : 0)   # year-header row + box borders
    for nq in [4, 2, 1]
        h = hbase + nq * CAL2_QUARTER_H
        if h <= parmaxy && w <= parmaxx
            return (h, w, nq)
        end
    end
    throw("terminal is too small to display even one calendar quarter")
end

function newTwCalendar2(
    scr::TwScreen,
    dt::Date;
    posy::Any = :center,
    posx::Any = :center,
    box = true,
    showHelp = true,
    title = "",
    key::Union{Nothing,Symbol} = nothing,
)
    data = TwCalendar2Data(dt)
    obj  = TwObj(data, Val{:Calendar2})
    registerTwObj(scr, obj)
    obj.box          = box
    obj.title        = title
    obj.formkey      = key
    obj.borderSizeV  = box ? 1 : 0
    obj.borderSizeH  = box ? 1 : 0
    obj.data.showHelp = showHelp
    obj.data.date     = dt
    h, w, nq = bestfitgeometry2(scr, box)
    obj.data.numquarters = nq
    alignxy!(obj, h, w, posx, posy)
    configure_newwinpanel!(obj)
    obj.value = dt
    obj
end

function apply_default!(obj::TwObj{TwCalendar2Data}, value::Date)
    obj.data.date  = value
    obj.value      = value
end

function draw(o::TwObj{TwCalendar2Data})
    werase(o.window)
    if o.box
        box(o.window, 0, 0)
    end
    if !isempty(o.title) && o.box
        mvwprintw(o.window, 0, round(Int, (o.width - length(o.title)) / 2), "%s", o.title)
    end

    starty = o.borderSizeV
    startx = o.borderSizeH
    yr     = year(o.data.date)

    # Year + holiday-calendar header
    yearstr   = string(yr) * "  [" * string(o.data.holidayCal) * "]"
    yearflags = yr == year(today()) ? A_BOLD | A_UNDERLINE : 0
    wattron(o.window, yearflags)
    mvwprintw(o.window, starty, startx + max(0, div(CAL2_QUARTER_W - length(yearstr), 2)), "%s", yearstr)
    wattroff(o.window, yearflags)
    starty += 1

    # Determine which quarters to show, always keeping cursor's quarter visible
    curq   = div(month(o.data.date) - 1, 3) + 1   # 1..4
    startq = if o.data.numquarters >= 4
        1
    elseif o.data.numquarters == 2
        min(curq, 3)   # latest valid start: Q3 (so Q3+Q4 still fits)
    else
        curq
    end

    wkdys = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    for qi = 0:(o.data.numquarters - 1)
        q      = startq + qi
        qstarty = starty + qi * CAL2_QUARTER_H

        for mi = 0:2
            mth  = (q - 1) * 3 + 1 + mi
            mcol = startx + mi * (CAL2_MONTH_W + CAL2_MONTH_GAP)

            # Month name, centred in CAL2_MONTH_W
            mthname  = monthabbr(mth)
            mthflags = (mth == month(today()) && yr == year(today())) ? A_BOLD | A_UNDERLINE : 0
            wattron(o.window, mthflags)
            mvwprintw(o.window, qstarty, mcol + div(CAL2_MONTH_W - length(mthname), 2), "%s", mthname)
            wattroff(o.window, mthflags)

            # Weekday-header row: Mo Tu We Th Fr Sa Su
            for (di, dname) in enumerate(wkdys)
                mvwprintw(o.window, qstarty + 1, mcol + (di - 1) * 3, "%2s", dname)
            end

            # Day grid
            dt   = Date(yr, mth, 1)
            mend = Date(yr, mth, daysinmonth(yr, mth))
            wkd  = dayofweek(dt)   # 1=Mon … 7=Sun
            wrow = 0

            while dt <= mend
                flags = 0
                if dt == o.data.date
                    flags = theme(o.hasFocus ? :selection_focused : :selection_unfocused)
                    o.data.cursorweekofmonth = wrow + 1
                elseif !isbday(o.data.holidayCal, dt)
                    flags = COLOR_PAIR(1)
                end
                if dt == today()
                    flags = flags | A_BOLD | A_UNDERLINE
                end
                wattron(o.window, flags)
                mvwprintw(o.window, qstarty + 2 + wrow, mcol + (wkd - 1) * 3, "%2s", string(day(dt)))
                wattroff(o.window, flags)

                if wkd == 7
                    wkd   = 1
                    wrow += 1
                else
                    wkd += 1
                end
                dt += Day(1)
            end
        end
    end
end

function inject(o::TwObj{TwCalendar2Data}, token)
    dorefresh = false
    retcode   = Handled

    if token == :esc
        retcode = Cancel
    elseif token == "."
        o.data.date = today()
        dorefresh = true
    elseif token == :up
        o.data.date -= Day(7)
        dorefresh = true
    elseif token == :down
        o.data.date += Day(7)
        dorefresh = true
    elseif token == :left
        o.data.date -= Day(1)
        dorefresh = true
    elseif token == :right
        o.data.date += Day(1)
        dorefresh = true
    elseif token == "a"
        o.data.date = Date(year(o.data.date), month(o.data.date))
        dorefresh = true
    elseif token == "e"
        y, m = year(o.data.date), month(o.data.date)
        o.data.date = Date(y, m, daysinmonth(y, m))
        dorefresh = true
    elseif token == "A"
        o.data.date = Date(year(o.data.date), 1)
        dorefresh = true
    elseif token == "E"
        o.data.date = Date(year(o.data.date), 12, 31)
        dorefresh = true
    elseif token == "d"
        o.data.date += Day(1)
        dorefresh = true
    elseif token == "D"
        o.data.date -= Day(1)
        dorefresh = true
    elseif token == "w"
        o.data.date += Day(7)
        dorefresh = true
    elseif token == "W"
        o.data.date -= Day(7)
        dorefresh = true
    elseif token == "m"
        o.data.date += Month(1)
        dorefresh = true
    elseif token == "M"
        o.data.date -= Month(1)
        dorefresh = true
    elseif token == "q"
        o.data.date += Month(3)
        dorefresh = true
    elseif token == "Q"
        o.data.date -= Month(3)
        dorefresh = true
    elseif token == "y" || token == :pagedown
        o.data.date += Year(1)
        dorefresh = true
    elseif token == "Y" || token == :pageup
        o.data.date -= Year(1)
        dorefresh = true
    elseif token == :alt_c
        helper = newTwPopup(
            o.screen.value,
            HOLIDAY_CALENDAR_NAMES;
            title        = "Holiday Calendar",
            posy         = :center,
            posx         = :center,
            substrsearch = true,
            hideunmatched = true,
        )
        sel = activateTwObj(helper)
        unregisterTwObj(o.screen.value, helper)
        if sel !== nothing
            o.data.holidayCal = Symbol(sel)
        end
        dorefresh = true
    elseif token == :enter || token == Symbol("return")
        o.value = o.data.date
        retcode = Accept
    else
        retcode = Ignored
    end

    if dorefresh
        refresh(o)
    end
    return retcode
end

function helptext(o::TwObj{TwCalendar2Data})
    o.data.showHelp ? o.data.helpText : ""
end
