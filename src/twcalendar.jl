# Traditional month calendar — days-of-week go horizontally, one quarter per row block.
# Arrows: ←→ = ±1 day, ↑↓ = ±1 week. Non-business days shown in red.

const HOLIDAY_CALENDAR_NAMES = [
    "AustraliaASX",
    "BRSettlement",
    "BrazilExchange",
    "CanadaSettlement",
    "CanadaTSX",
    "Germany",
    "NullHolidayCalendar",
    "TARGET",
    "UKSettlement",
    "USGovernmentBond",
    "USNYSE",
    "USSettlement",
    "WeekendsOnly",
]

# Layout
# Each month block: 20 cols  ("Mo Tu We Th Fr Sa Su" = 20 chars; day numbers align to same cols)
# Gap between months in the same quarter: 2 cols
# Three months per quarter row: 20 + 2 + 20 + 2 + 20 = 64 cols
# Each quarter block: 8 rows (1 month-name + 1 weekday-header + up to 6 week rows)
const CAL_MONTH_W   = 20
const CAL_MONTH_GAP = 2
const CAL_QUARTER_W = CAL_MONTH_W * 3 + CAL_MONTH_GAP * 2   # 64
const CAL_QUARTER_H = 8

mutable struct TwCalendarData
    showHelp::Bool
    date::Date
    cursorweekofmonth::Int  # 1-based week row within the cursor's month (set during draw)
    numquarters::Int        # how many quarter blocks fit: 1, 2, or 4
    holidayCal::Symbol
    TwCalendarData(dt::Date) = new(true, dt, 1, 4, :USSettlement)
end

function bestfitgeometry(scr::TwScreen, box::Bool)
    (parmaxy, parmaxx) = getwinmaxyx(scr.window)
    w = CAL_QUARTER_W + (box ? 2 : 0)
    hbase = 1 + (box ? 2 : 0)   # year-header row + box borders
    for nq in [4, 2, 1]
        h = hbase + nq * CAL_QUARTER_H
        if h <= parmaxy && w <= parmaxx
            return (h, w, nq)
        end
    end
    throw("terminal is too small to display even one calendar quarter")
end

function newTwCalendar(
    scr::TwScreen,
    dt::Date;
    posy::Any = :center,
    posx::Any = :center,
    box = true,
    showHelp = true,
    title = "",
    key::Union{Nothing,Symbol} = nothing,
)
    data = TwCalendarData(dt)
    obj  = TwObj(data, Val{:Calendar})
    registerTwObj(scr, obj)
    obj.box          = box
    obj.title        = title
    obj.formkey      = key
    obj.borderSizeV  = box ? 1 : 0
    obj.borderSizeH  = box ? 1 : 0
    obj.data.showHelp = showHelp
    obj.data.date     = dt
    h, w, nq = bestfitgeometry(scr, box)
    obj.data.numquarters = nq
    alignxy!(obj, h, w, posx, posy)
    configure_newwinpanel!(obj)
    obj.value = dt
    obj
end

function apply_default!(obj::TwObj{TwCalendarData}, value::Date)
    obj.data.date  = value
    obj.value      = value
end

function draw(o::TwObj{TwCalendarData})
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
    mvwprintw(o.window, starty, startx + max(0, div(CAL_QUARTER_W - length(yearstr), 2)), "%s", yearstr)
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
        q       = startq + qi
        qstarty = starty + qi * CAL_QUARTER_H

        for mi = 0:2
            mth  = (q - 1) * 3 + 1 + mi
            mcol = startx + mi * (CAL_MONTH_W + CAL_MONTH_GAP)

            # Month name, centred in CAL_MONTH_W
            mthname  = monthabbr(mth)
            mthflags = (mth == month(today()) && yr == year(today())) ? A_BOLD | A_UNDERLINE : 0
            wattron(o.window, mthflags)
            mvwprintw(o.window, qstarty, mcol + div(CAL_MONTH_W - length(mthname), 2), "%s", mthname)
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

function calendar_pick_holiday!(o::TwObj{TwCalendarData})
    helper = newTwPopup(
        o.screen.value, HOLIDAY_CALENDAR_NAMES;
        title = "Holiday Calendar", posy = :center, posx = :center,
        substrsearch = true, hideunmatched = true,
    )
    sel = activateTwObj(helper)
    unregisterTwObj(o.screen.value, helper)
    sel !== nothing && (o.data.holidayCal = Symbol(sel))
    return Handled
end

function bindings(o::TwObj{TwCalendarData})
    Binding[
        Binding([:up],    "-week",  action = w -> (w.data.date -= Day(7);   Handled)),
        Binding([:down],  "+week",  action = w -> (w.data.date += Day(7);   Handled)),
        Binding([:left],  "-day",   action = w -> (w.data.date -= Day(1);   Handled)),
        Binding([:right], "+day",   action = w -> (w.data.date += Day(1);   Handled)),
        Binding(["."], "today",
                action = w -> (w.data.date = today(); Handled)),
        Binding(["a"], "month start",
                action = w -> (w.data.date = Date(year(w.data.date), month(w.data.date)); Handled)),
        Binding(["e"], "month end",
                action = w -> (w.data.date = Date(year(w.data.date), month(w.data.date),
                                   daysinmonth(year(w.data.date), month(w.data.date))); Handled)),
        Binding(["A"], "Jan 1",
                action = w -> (w.data.date = Date(year(w.data.date), 1); Handled)),
        Binding(["E"], "Dec 31",
                action = w -> (w.data.date = Date(year(w.data.date), 12, 31); Handled)),
        Binding(["d"], "+day",      action = w -> (w.data.date += Day(1);   Handled)),
        Binding(["D"], "-day",      action = w -> (w.data.date -= Day(1);   Handled)),
        Binding(["w"], "+week",     action = w -> (w.data.date += Day(7);   Handled)),
        Binding(["W"], "-week",     action = w -> (w.data.date -= Day(7);   Handled)),
        Binding(["m"], "+month",    action = w -> (w.data.date += Month(1); Handled)),
        Binding(["M"], "-month",    action = w -> (w.data.date -= Month(1); Handled)),
        Binding(["q"], "+quarter",  action = w -> (w.data.date += Month(3); Handled)),
        Binding(["Q"], "-quarter",  action = w -> (w.data.date -= Month(3); Handled)),
        Binding(["y", :pagedown], "+year", action = w -> (w.data.date += Year(1); Handled)),
        Binding(["Y", :pageup],   "-year", action = w -> (w.data.date -= Year(1); Handled)),
        Binding([:alt_c], "holiday cal (non-business days in red)",
                action = calendar_pick_holiday!),
        Binding([:enter, Symbol("return")], "select",
                action = w -> (w.value = w.data.date; Accept)),
        Binding([:esc], "cancel", action = _ -> Cancel),
    ]
end

function inject(o::TwObj{TwCalendarData}, token)
    r = inject_via_table(o, token)
    r === Handled && refresh(o)
    return r
end

function helptext(o::TwObj{TwCalendarData})
    o.data.showHelp ? helptext_from_bindings(o) : ""
end
