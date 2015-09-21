# hand-crafted date selector

defaultCalendarHelpText = """
Arrows : move cursor
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
"""
type TwCalendarData
    showHelp::Bool
    helpText::UTF8String
    date::Date
    cursorweekofmonth::Int # cached "nth week" in the current month containing date, 1-based
    geometry::@compat Tuple{Int, Int} # rows x cols in months
    ncalStyle::Bool
    TwCalendarData( dt::Date ) = new( true, defaultCalendarHelpText, dt, 1, (1,1), false )
end

function monthDimension( ncalStyle::Bool )
    ncalStyle ? ( 8, 3*6-1 ): (8, 3*7+1 )
end

function bestfitgeometry( ncalStyle, scr::TwScreen, box::Bool )
    ( parmaxy, parmaxx ) = getwinmaxyx( scr.window )
    leftcols = 0
    monthdim::Tuple{Int,Int} = monthDimension( ncalStyle )
    if ncalStyle
        allowed_geometry = [ (3,4), (2, 3), (1,3), (1,1 ) ]
        leftcols = 2
    else
        allowed_geometry = [ (4,3), (2, 3), (1,3), (1,1 ) ]
    end

    found = false
    finalg = (0,0,0,0)
    for g in allowed_geometry
        h::Int = 1+g[1] * monthdim[1] + (box?2:0) # box borders + contents + year title
        w::Int = leftcols + g[2] * monthdim[2] + (box?2:0)
        if w <= parmaxx && h <= parmaxy
            found = true
            finalg = (h,w, g[1]::Int, g[2]::Int )
            break
        end
    end

    if !found
        throw( "terminal is too small to view even one month")
    end
    return finalg
end

function newTwCalendar( scr::TwScreen, dt::Date;
    posy::Any = :center,posx::Any = :center,
    ncalStyle=true, box=true, showHelp=true, title = "" )
    data = TwCalendarData( dt )
    obj = TwObj( data, Val{:Calendar} )
    registerTwObj( scr, obj )
    obj.box = box
    obj.title = title
    obj.borderSizeV= box ? 1 : 0
    obj.borderSizeH= box ? 1 : 0
    obj.data.showHelp = showHelp
    obj.data.date = dt
    h,w,g1,g2 = bestfitgeometry( ncalStyle, scr, box )
    obj.data.geometry = (g1, g2)
    obj.data.ncalStyle = ncalStyle
    alignxy!( obj, h, w, posx, posy)
    configure_newwinpanel!( obj )
    obj
end

function draw( o::TwObj{TwCalendarData} )
    werase( o.window )
    if o.box
        box( o.window, 0,0 )
    end
    if !isempty( o.title ) && o.box
        mvwprintw( o.window, 0, (@compat round( Int, ( o.width - length(o.title) )/2 )), "%s", o.title )
    end
    starty = o.borderSizeV
    startx = o.borderSizeH
    mvwprintw( o.window, starty, (@compat round( Int, ( o.width - 4 )/2 )), "%s", string(year(o.data.date)))
    starty += 1
    # figure out the start month
    nummonths = o.data.geometry[1] * o.data.geometry[2]
    m = month( o.data.date )
    if nummonths >= 12
        startmonth = 1 # jan
    elseif nummonths >= 6
        startmonth = m >= 7 ? 7 : 1
    elseif nummonths >= 3
        startmonth = m - mod1( m, 3 ) + 1
    else
        startmonth = m
    end

    mth = startmonth
    ncalStyle = o.data.ncalStyle
    monthdim = monthDimension( ncalStyle )
    wkdys = [ "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" ]
    for i = 1:o.data.geometry[1]
        if ncalStyle # draw the week column on the left
            for (wdidx,wdstr) in enumerate( wkdys )
                mvwprintw( o.window, starty + wdidx, startx, "%s", wkdys[wdidx] )
            end
            startx += 2
        end
        for j = 1:o.data.geometry[2]
            # print the month header
            mvwprintw( o.window, starty, startx + 6, "%s", monthabbr( mth ) )
            mst = Date( year( o.data.date ), mth, 1 )
            men = Date( year( o.data.date ), mth, daysinmonth( year( o.data.date ), mth ) )
            dt = mst
            wkd = dayofweek( dt )
            if ncalStyle
                wcol = 0
                while dt <= men
                    flags = 0
                    if dt == o.data.date
                        flags = COLOR_PAIR( o.hasFocus ? 15 : 30 )
                        o.data.cursorweekofmonth = wcol + 1
                    end
                    if dt == today()
                        flags = flags | A_BOLD
                    end
                    wattron( o.window, flags )
                    if wcol == 0
                        mvwprintw( o.window, starty + wkd, startx, "%2s", string( day( dt ) ) )
                    else
                        mvwprintw( o.window, starty + wkd, startx - 1 + wcol * 3, "%3s", string( day( dt ) ) )
                    end
                    wattroff( o.window, flags )
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
                for (wdidx,wdstr) in enumerate( wkdys )
                    mvwprintw( o.window, starty + 1, startx + (wdidx-1)* 3, "%3s", wkdys[wdidx] )
                end
                while dt <= men
                    flags = 0
                    if dt == o.data.date
                        flags = COLOR_PAIR( o.hasFocus ? 15 :30 )
                        o.data.cursorweekofmonth = wrow + 1
                    end
                    if dt == today()
                        flags = flags | A_BOLD
                    end
                    wattron( o.window, flags )
                    mvwprintw( o.window, starty + 2 + wrow, startx + (wkd-1) * 3, "%3s", string( day( dt ) ) )
                    wattroff( o.window, flags )
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
function monthNthWeekRange( y::Int, m::Int, n::Int )
    monthstart = Date( y, m )
    wdaystart = dayofweek( monthstart )
    mdays = daysinmonth( y, m )
    we = 8 - wdaystart + 7 * (n-1)
    ws = we - 6
    while ws > mdays
        n = n-1
        we = 8 - wdaystart + 7 * (n-1)
        ws = we - 6
    end
    return (Date( y, m, max(ws, 1) ),Date( y, m, min( we, mdays )))
end

function inject( o::TwObj{TwCalendarData}, token )
    dorefresh = false
    retcode = :got_it # default behavior is that we know what to do with it

    ncalStyle = o.data.ncalStyle
    if token == :esc
        retcode = :exit_nothing
    elseif token == "."
        o.data.date = today()
        dorefresh = true
    elseif in( token, [ :up, :down, :left, :right ] )
        if ncalStyle
            if token == :left
                o.data.date = o.data.date - Day(7)
            elseif token == :right
                o.data.date = o.data.date + Day(7)
            elseif token == :up
                if dayofweek( o.data.date ) > 1 && day( o.data.date ) > 1
                    o.data.date = o.data.date - Day(1)
                else
                    # last weekday of the same nth week of the previous month
                    # if the nth week of the previous month doesn't exist, it'd
                    # be the weekday of the last week of the previous month
                    prevmonth = o.data.date - Month( ncalStyle ? o.data.geometry[2] : o.data.geometry[1] )
                    o.data.date = monthNthWeekRange( year( prevmonth ), month( prevmonth ), o.data.cursorweekofmonth )[2]
                end
            else # :down
                if dayofweek( o.data.date ) < 7 && day( o.data.date ) < daysinmonth( year( o.data.date ), month( o.data.date ) )
                    o.data.date = o.data.date + Day(1)
                else
                    # last weekday of the same nth week of the "next" month
                    nextmonth = o.data.date + Month( ncalStyle ? o.data.geometry[2] : o.data.geometry[1] )
                    o.data.date = monthNthWeekRange( year( nextmonth ), month( nextmonth ), o.data.cursorweekofmonth )[1]
                end
            end
            dorefresh = true
        else
            if token == :up
                d = day( o.data.date )
                if d >= 7
                    o.data.date = o.data.date - Day(7)
                else
                    currdayofweek = dayofweek( o.data.date )
                    prevmonth = o.data.date - Month( o.data.geometry[2] )
                    (y,m) = (year(prevmonth), month(prevmonth))
                    mds = daysinmonth( y,m )
                    lstdayofwk = dayofweek( Date( y,m,mds ) )
                    o.data.date = Date( y,m, mds - mod(lstdayofwk-currdayofweek, 7))
                end
            elseif token == :down
                (y,m,d) = (year(o.data.date ), month( o.data.date), day( o.data.date ))
                mds = daysinmonth( y,m )
                if d + 7 <= mds
                    o.data.date = o.data.date + Day(7)
                else
                    currdayofweek = dayofweek( o.data.date )
                    nextmonth = o.data.date + Month( o.data.geometry[2] )
                    (y,m) = (year(nextmonth), month(nextmonth))
                    mds = daysinmonth( y,m )
                    fstdayofwk = dayofweek( Date( y,m,1 ) )
                    o.data.date = Date( y,m, 1 + mod(currdayofweek-fstdayofwk, 7))
                end
            elseif token == :left
                if dayofweek( o.data.date ) > 1 && day( o.data.date ) > 1
                    o.data.date = o.data.date - Day(1)
                else
                    # last weekday of the same nth week of the previous month
                    # if the nth week of the previous month doesn't exist, it'd
                    # be the weekday of the last week of the previous month
                    prevmonth = o.data.date - Month( 1 )
                    o.data.date = monthNthWeekRange( year( prevmonth ), month( prevmonth ), o.data.cursorweekofmonth )[2]
                end
            else # :right
                if dayofweek( o.data.date ) < 7 && day( o.data.date ) < daysinmonth( year( o.data.date ), month( o.data.date ) )
                    o.data.date = o.data.date + Day(1)
                else
                    # last weekday of the same nth week of the "next" month
                    nextmonth = o.data.date + Month( 1 )
                    o.data.date = monthNthWeekRange( year( nextmonth ), month( nextmonth ), o.data.cursorweekofmonth )[1]
                end
            end
            dorefresh = true
        end
    elseif token == "a"
        o.data.date = Date( year( o.data.date ), month( o.data.date ) )
        dorefresh = true
    elseif token == "e"
        (y,m) = year(o.data.date), month( o.data.date )
        o.data.date = Date( y,m, daysinmonth( y,m ) )
        dorefresh = true
    elseif token == "A"
        o.data.date = Date( year( o.data.date ), 1 )
        dorefresh = true
    elseif token == "E"
        y = year(o.data.date)
        o.data.date = Date( y, 12, 31 )
        dorefresh = true
    elseif token == "w"
        o.data.date = o.data.date + Day(7)
        dorefresh = true
    elseif token == "W"
        o.data.date = o.data.date - Day(7)
        dorefresh = true
    elseif token == "m"
        o.data.date = o.data.date + Month(1)
        dorefresh = true
    elseif token == "M"
        o.data.date = o.data.date - Month(1)
        dorefresh = true
    elseif token == "d"
        o.data.date = o.data.date + Day(1)
        dorefresh = true
    elseif token == "D"
        o.data.date = o.data.date - Day(1)
        dorefresh = true
    elseif token == "y"
        o.data.date = o.data.date + Year(1)
        dorefresh = true
    elseif token == "Y"
        o.data.date = o.data.date - Year(1)
        dorefresh = true
    elseif token == "q"
        o.data.date = o.data.date + Month(3)
        dorefresh = true
    elseif token == "Q"
        o.data.date = o.data.date - Month(3)
        dorefresh = true
    elseif token == :enter || token == Symbol( "return" )
        o.value = o.data.date
        retcode = :exit_ok
    else
        retcode = :pass # I don't know what to do with it
    end

    if dorefresh
        refresh(o)
    end

    return retcode
end

function helptext( o::TwObj{TwCalendarData} )
    if o.data.showHelp
        o.data.helpText
    else
        ""
    end
end
