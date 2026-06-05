# hand-crafted date selector
#
# This widget is the reference conversion for "bindings as data": its keymap is
# declared once in `bindings(o)` below, and the F1 help screen is *generated*
# from that table (see helptext) — there is no hand-maintained help constant.

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

mutable struct TwCalendarData
    showHelp::Bool
    date::Date
    cursorweekofmonth::Int # cached "nth week" in the current month containing date, 1-based
    geometry::Tuple{Int,Int} # rows x cols in months
    ncalStyle::Bool
    holidayCal::Symbol
    TwCalendarData(dt::Date) = new(true, dt, 1, (1, 1), false, :USSettlement)
end

function monthDimension(ncalStyle::Bool)
    ncalStyle ? (8, 3*6-1) : (8, 3*7+1)
end

function bestfitgeometry(ncalStyle, scr::TwScreen, box::Bool)
    (parmaxy, parmaxx) = getwinmaxyx(scr.window)
    leftcols = 0
    monthdim::Tuple{Int,Int} = monthDimension(ncalStyle)
    if ncalStyle
        allowed_geometry = [(3, 4), (2, 3), (1, 3), (1, 1)]
        leftcols = 2
    else
        allowed_geometry = [(4, 3), (2, 3), (1, 3), (1, 1)]
    end

    found = false
    finalg = (0, 0, 0, 0)
    for g in allowed_geometry
        h::Int = 1 + g[1] * monthdim[1] + (box ? 2 : 0) # box borders + contents + year title
        w::Int = leftcols + g[2] * monthdim[2] + (box ? 2 : 0)
        if w <= parmaxx && h <= parmaxy
            found = true
            finalg = (h, w, g[1]::Int, g[2]::Int)
            break
        end
    end

    if !found
        throw("terminal is too small to view even one month")
    end
    return finalg
end

function newTwCalendar(
    scr::TwScreen,
    dt::Date;
    posy::Any = :center,
    posx::Any = :center,
    ncalStyle = true,
    box = true,
    showHelp = true,
    title = "",
    key::Union{Nothing,Symbol} = nothing,
)
    data = TwCalendarData(dt)
    obj = TwObj(data, Val{:Calendar})
    registerTwObj(scr, obj)
    obj.box = box
    obj.title = title
    obj.formkey = key
    obj.borderSizeV = box ? 1 : 0
    obj.borderSizeH = box ? 1 : 0
    obj.data.showHelp = showHelp
    obj.data.date = dt
    h, w, g1, g2 = bestfitgeometry(ncalStyle, scr, box)
    obj.data.geometry = (g1, g2)
    obj.data.ncalStyle = ncalStyle
    alignxy!(obj, h, w, posx, posy)
    configure_newwinpanel!(obj)
    obj.value = dt
    obj
end

function apply_default!(obj::TwObj{TwCalendarData}, value::Date)
    obj.data.date = value
    obj.value = value
end

function draw(o::TwObj{TwCalendarData})
    werase(o.window)
    if o.box
        box(o.window, 0, 0)
    end
    if !isempty(o.title) && o.box
        mvwprintw(o.window, 0, round(Int, (o.width - length(o.title))/2), "%s", o.title)
    end
    starty = o.borderSizeV
    startx = o.borderSizeH
    yearstr = string(year(o.data.date)) * "  [" * string(o.data.holidayCal) * "]"
    yearflags = year(o.data.date) == year(today()) ? A_BOLD | A_UNDERLINE : 0
    wattron(o.window, yearflags)
    mvwprintw(
        o.window,
        starty,
        max(startx, round(Int, (o.width - length(yearstr))/2)),
        "%s",
        yearstr,
    )
    wattroff(o.window, yearflags)
    starty += 1
    # figure out the start month
    nummonths = o.data.geometry[1] * o.data.geometry[2]
    m = month(o.data.date)
    if nummonths >= 12
        startmonth = 1 # jan
    elseif nummonths >= 6
        startmonth = m >= 7 ? 7 : 1
    elseif nummonths >= 3
        startmonth = m - mod1(m, 3) + 1
    else
        startmonth = m
    end

    mth = startmonth
    ncalStyle = o.data.ncalStyle
    monthdim = monthDimension(ncalStyle)
    wkdys = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    for i = 1:o.data.geometry[1]
        if ncalStyle # draw the week column on the left
            for (wdidx, wdstr) in enumerate(wkdys)
                mvwprintw(o.window, starty + wdidx, startx, "%s ", wkdys[wdidx])
            end
            startx += 3
        end
        for j = 1:o.data.geometry[2]
            # print the month header
            mthflags = (mth == month(today()) && year(o.data.date) == year(today())) ? A_BOLD | A_UNDERLINE : 0
            wattron(o.window, mthflags)
            mvwprintw(o.window, starty, startx + 6, "%s", monthabbr(mth))
            wattroff(o.window, mthflags)
            mst = Date(year(o.data.date), mth, 1)
            men = Date(year(o.data.date), mth, daysinmonth(year(o.data.date), mth))
            dt = mst
            wkd = dayofweek(dt)
            if ncalStyle
                wcol = 0
                while dt <= men
                    flags = 0
                    is_cursor = dt == o.data.date
                    if is_cursor
                        flags = theme(o.hasFocus ? :selection_focused : :selection_unfocused)
                        o.data.cursorweekofmonth = wcol + 1
                    elseif !isbday(o.data.holidayCal, dt)
                        flags = COLOR_PAIR(1)  # red for non-business days
                    end
                    if dt == today()
                        flags = flags | A_BOLD | A_UNDERLINE
                    end
                    wattron(o.window, flags)
                    if wcol == 0
                        mvwprintw(o.window, starty + wkd, startx, "%>2s", string(day(dt)))
                    else
                        mvwprintw(
                            o.window,
                            starty + wkd,
                            startx - 1 + wcol * 3,
                            "%>3s",
                            string(day(dt)),
                        )
                    end
                    wattroff(o.window, flags)
                    if wkd == 7
                        wkd = 1
                        wcol += 1
                    else
                        wkd += 1
                    end
                    dt = dt + Day(1)
                end
            else
                wrow = 0
                for (wdidx, wdstr) in enumerate(wkdys)
                    mvwprintw(
                        o.window,
                        starty + 1,
                        startx + (wdidx-1) * 3,
                        "%3s",
                        wkdys[wdidx],
                    )
                end
                while dt <= men
                    flags = 0
                    is_cursor = dt == o.data.date
                    if is_cursor
                        flags = theme(o.hasFocus ? :selection_focused : :selection_unfocused)
                        o.data.cursorweekofmonth = wrow + 1
                    elseif !isbday(o.data.holidayCal, dt)
                        flags = COLOR_PAIR(1)  # red for non-business days
                    end
                    if dt == today()
                        flags = flags | A_BOLD | A_UNDERLINE
                    end
                    wattron(o.window, flags)
                    mvwprintw(
                        o.window,
                        starty + 2 + wrow,
                        startx + (wkd-1) * 3,
                        "%3s",
                        string(day(dt)),
                    )
                    wattroff(o.window, flags)
                    if wkd == 7
                        wkd = 1
                        wrow += 1
                    else
                        wkd += 1
                    end
                    dt = dt + Day(1)
                end
            end
            startx += monthdim[2]
            mth += 1
        end
        starty += monthdim[1]
        startx = o.borderSizeH # reset
    end
end

# returns a range of the dates of that week. n is 1-based
# if n is too large, it'd use the last week of that month
function monthNthWeekRange(y::Int, m::Int, n::Int)
    monthstart = Date(y, m)
    wdaystart = dayofweek(monthstart)
    mdays = daysinmonth(y, m)
    we = 8 - wdaystart + 7 * (n-1)
    ws = we - 6
    while ws > mdays
        n = n-1
        we = 8 - wdaystart + 7 * (n-1)
        ws = we - 6
    end
    return (Date(y, m, max(ws, 1)), Date(y, m, min(we, mdays)))
end

# ── Cursor (arrow-key) navigation, extracted so it is unit-testable without a
#    window. Mutates o.data.date in place; preserves the original ncalStyle and
#    flow-style behaviour exactly.
function calendar_arrow!(o::TwObj{TwCalendarData}, dir::Symbol)
    ncalStyle = o.data.ncalStyle
    if ncalStyle
        if dir == :left
            o.data.date = o.data.date - Day(7)
        elseif dir == :right
            o.data.date = o.data.date + Day(7)
        elseif dir == :up
            if dayofweek(o.data.date) > 1 && day(o.data.date) > 1
                o.data.date = o.data.date - Day(1)
            else
                prevmonth = o.data.date - Month(o.data.geometry[2])
                o.data.date = monthNthWeekRange(
                    year(prevmonth), month(prevmonth), o.data.cursorweekofmonth,
                )[2]
            end
        else # :down
            if dayofweek(o.data.date) < 7 &&
               day(o.data.date) < daysinmonth(year(o.data.date), month(o.data.date))
                o.data.date = o.data.date + Day(1)
            else
                nextmonth = o.data.date + Month(o.data.geometry[2])
                o.data.date = monthNthWeekRange(
                    year(nextmonth), month(nextmonth), o.data.cursorweekofmonth,
                )[1]
            end
        end
    else
        if dir == :up
            d = day(o.data.date)
            if d >= 7
                o.data.date = o.data.date - Day(7)
            else
                currdayofweek = dayofweek(o.data.date)
                prevmonth = o.data.date - Month(o.data.geometry[2])
                (y, m) = (year(prevmonth), month(prevmonth))
                mds = daysinmonth(y, m)
                lstdayofwk = dayofweek(Date(y, m, mds))
                o.data.date = Date(y, m, mds - mod(lstdayofwk-currdayofweek, 7))
            end
        elseif dir == :down
            (y, m, d) = (year(o.data.date), month(o.data.date), day(o.data.date))
            mds = daysinmonth(y, m)
            if d + 7 <= mds
                o.data.date = o.data.date + Day(7)
            else
                currdayofweek = dayofweek(o.data.date)
                nextmonth = o.data.date + Month(o.data.geometry[2])
                (y, m) = (year(nextmonth), month(nextmonth))
                mds = daysinmonth(y, m)
                fstdayofwk = dayofweek(Date(y, m, 1))
                o.data.date = Date(y, m, 1 + mod(currdayofweek-fstdayofwk, 7))
            end
        elseif dir == :left
            if dayofweek(o.data.date) > 1 && day(o.data.date) > 1
                o.data.date = o.data.date - Day(1)
            else
                prevmonth = o.data.date - Month(1)
                o.data.date = monthNthWeekRange(
                    year(prevmonth), month(prevmonth), o.data.cursorweekofmonth,
                )[2]
            end
        else # :right
            if dayofweek(o.data.date) < 7 &&
               day(o.data.date) < daysinmonth(year(o.data.date), month(o.data.date))
                o.data.date = o.data.date + Day(1)
            else
                nextmonth = o.data.date + Month(1)
                o.data.date = monthNthWeekRange(
                    year(nextmonth), month(nextmonth), o.data.cursorweekofmonth,
                )[1]
            end
        end
    end
    return Handled
end

# Alt-C: pick a holiday calendar from a popup (needs the live screen).
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

# The calendar keymap, declared once. Footer, F1 help, and dispatch all derive
# from this table (see bindings.jl).
function bindings(o::TwObj{TwCalendarData})
    Binding[
        Binding([:up],    "up",    action = w -> calendar_arrow!(w, :up)),
        Binding([:down],  "down",  action = w -> calendar_arrow!(w, :down)),
        Binding([:left],  "left",  action = w -> calendar_arrow!(w, :left)),
        Binding([:right], "right", action = w -> calendar_arrow!(w, :right)),
        Binding(["."], "today",
                action = w -> (w.data.date = today(); Handled)),
        Binding(["a"], "month start",
                action = w -> (w.data.date = Date(year(w.data.date), month(w.data.date)); Handled)),
        Binding(["e"], "month end", action = w -> (
                    w.data.date = Date(year(w.data.date), month(w.data.date),
                                       daysinmonth(year(w.data.date), month(w.data.date)));
                    Handled)),
        Binding(["A"], "Jan 1",
                action = w -> (w.data.date = Date(year(w.data.date), 1); Handled)),
        Binding(["E"], "Dec 31",
                action = w -> (w.data.date = Date(year(w.data.date), 12, 31); Handled)),
        Binding(["d"], "+day",     action = w -> (w.data.date = w.data.date + Day(1);   Handled)),
        Binding(["D"], "-day",     action = w -> (w.data.date = w.data.date - Day(1);   Handled)),
        Binding(["w"], "+week",    action = w -> (w.data.date = w.data.date + Day(7);   Handled)),
        Binding(["W"], "-week",    action = w -> (w.data.date = w.data.date - Day(7);   Handled)),
        Binding(["m"], "+month",   action = w -> (w.data.date = w.data.date + Month(1); Handled)),
        Binding(["M"], "-month",   action = w -> (w.data.date = w.data.date - Month(1); Handled)),
        Binding(["q"], "+quarter", action = w -> (w.data.date = w.data.date + Month(3); Handled)),
        Binding(["Q"], "-quarter", action = w -> (w.data.date = w.data.date - Month(3); Handled)),
        Binding(["y", :pagedown], "+year", action = w -> (w.data.date = w.data.date + Year(1); Handled)),
        Binding(["Y", :pageup],   "-year", action = w -> (w.data.date = w.data.date - Year(1); Handled)),
        Binding([:alt_c], "holiday cal (non-business days in red)",
                action = calendar_pick_holiday!),
        Binding([:enter, Symbol("return")], "select",
                action = w -> (w.value = w.data.date; Accept)),
        Binding([:esc], "cancel", action = _ -> Cancel),
    ]
end

function inject(o::TwObj{TwCalendarData}, token)
    r = inject_via_table(o, token)
    # Every handled calendar action repaints; Accept/Cancel exit, Ignored bubbles.
    r === Handled && refresh(o)
    return r
end

function helptext(o::TwObj{TwCalendarData})
    o.data.showHelp ? helptext_from_bindings(o) : ""
end
