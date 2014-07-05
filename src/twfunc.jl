
defaultFuncHelpText = """
PgUp/PgDn  : method list navigation
Up/Dn      : method list navigation
Left/Right : search term cursor control
ctrl-a     : move cursor to start
ctrl-e     : move cursor to end
ctrl-k     : empty search entry
ctrl-r     : toggle insert/overwrite
Home       : jump to the start
End        : jump to the end
Shift-left/right : Navigate method list left and right
Ctrl-Sht-lft/rgt : Jump method list to left and right edge
F6         : explore Method as tree
F8         : edit method
"""

type TwFuncData
    datalist::Array{Any,1}
    datalistlen::Int
    datawidth::Int
    searchbox::Any
    currentTop::Int
    currentLine::Int
    currentLeft::Int
    showLineInfo::Bool # e.g.1/100 1.0% at top right corner
    bottomText::String
    showHelp::Bool
    helpText::String
    TwFuncData() = new( Method[], 0, 0, nothing,
        1, 1, 1, true, "", true, defaultFuncHelpText )
end

# the ways to use it:
# exact dimensions known: h,w,y,x, content to add later
# exact dimensions unknown, but content known and content drives dimensions
function newTwFunc( scr::TwScreen, ms::Array{Method,1},
        h::Real,w::Real,
        y::Any,x::Any ;
        box=true,
        title="",
        showLineInfo=true,
        showHelp=true,
        bottomText = "" )
    obj = TwObj( twFuncFactory( :Func ) )
    registerTwObj( scr, obj )
    obj.box = box
    obj.title = title
    obj.borderSizeV= box ? 1 : 0
    obj.borderSizeH= box ? 2 : 0
    obj.data = TwFuncData()
    for d in ms
        s = string(d.sig)*" : " * string(d)
        push!( obj.data.datalist, { lowercase(s), s, d, 0.0 } )
    end
    obj.data.datalistlen = length( ms )
    obj.data.datawidth = maximum( map( x->length( x[2] ), obj.data.datalist ))
    obj.data.showLineInfo = showLineInfo
    obj.data.showHelp = showHelp
    obj.data.bottomText = bottomText
    alignxy!( obj, h, w, x, y )
    configure_newwinpanel!( obj )
    obj.data.searchbox = newTwEntry( obj.window, String, 30, 0, 5, box=false, showHelp=true )
    obj.data.searchbox.title = "Search: "
    obj.data.searchbox.data.helpText = defaultFuncHelpText
    obj
end

function newTwFunc( scr::TwScreen, mt::MethodTable,
        h::Real, w::Real,
        y::Any,x::Any ;
        box=true,
        title="",
        showLineInfo=true,
        bottomText = "",
        showHelp=true )
    ms = Method[]
    d = start(mt)
    while !is(d,())
        push!( ms, d )
        d = d.next
    end
    newTwFunc( scr, ms, h, w, y, x,
        box=box,
        title=title,
        showLineInfo=showLineInfo,
        bottomText=bottomText,
        showHelp=showHelp )
end

function newTwFunc( scr::TwScreen, f::Function,
        h::Real, w::Real,
        y::Any,x::Any ;
        box=true,
        title="",
        showLineInfo=true,
        bottomText = "",
        showHelp=true )
    newTwFunc( scr, methods(f), h, w, y, x,
        box=box,
        title=title,
        showLineInfo=showLineInfo,
        bottomText=bottomText,
        showHelp=showHelp )
end

function update_score_sort( o::TwObj )
    searchterm = o.data.searchbox.data.inputText
    needx = o.data.datawidth

    l1 = length(searchterm)
    if l1 == 0
        for row in o.data.datalist
            row[4]= 0.0
        end
    else
        for row in o.data.datalist
            ld = levenstein_distance( lowercase( searchterm ), row[1] )
            l2 = length( row[1] )
            minld = abs( l1 - l2 )
            maxld = max( l1, l2 )
            # ld closer to the theoretical minimum should be deemed almost as good as a full match
            normld = ( ld - minld + 1) / (maxld - minld + 1) * (minld + 1 )
            # finding the search term in the later part of a string should have a small penalty
            substrpenalty = needx
            r  = search( row[1], searchterm )
            if length(r) != 0
                substrpenalty = r.start
            end
            row[ 4] = ld + normld * 0.5 + substrpenalty
        end
    end
    sort!( o.data.datalist, lt=(x,y)-> x[4] < y[4] )
end

function drawTwFunc( o::TwObj )
    viewContentHeight = o.height - o.borderSizeV * 2
    viewContentWidth = o.width - o.borderSizeH * 2
    viewStartRow = o.borderSizeV
    if o.box
        box( o.window, 0,0 )
    end
    if o.data.showLineInfo
        if o.data.datalistlen <= o.height - 2 * o.borderSizeV
            info = "ALL"
            mvwprintw( o.window, 0, o.width - 13, "%10s", "ALL" )
        else
            info = @sprintf( "%d/%d %5.1f%%", o.data.currentLine, o.data.datalistlen,
                o.data.currentLine / o.data.datalistlen * 100 )
        end
        mvwprintw( o.window, 0, o.width - length(info)-3, "%s", info )
    end
    for r in o.data.currentTop:min( o.data.currentTop + viewContentHeight - 1, o.data.datalistlen )
        line = o.data.datalist[r][2]
        line = line[ chr2ind( line, o.data.currentLeft ):end ]
        if length( line ) > viewContentWidth
            line = line[ 1: chr2ind( line, viewContentWidth ) ]
        end

        if r == o.data.currentLine
            wattron( o.window, A_BOLD | COLOR_PAIR(15) )
        end
        mvwprintw( o.window, r - o.data.currentTop + viewStartRow, o.borderSizeH, "%s", line )
        if r == o.data.currentLine
            wattroff( o.window, A_BOLD | COLOR_PAIR(15) )
        end
    end
    if length( o.data.bottomText ) != 0
        mvwprintw( o.window, o.height-1, int( (o.width - length(o.data.bottomText))/2 ), "%s", o.data.bottomText )
    end
    draw( o.data.searchbox )
end

function injectTwFunc( o::TwObj, token )
    dorefresh = false
    retcode = :got_it # default behavior is that we know what to do with it
    viewContentHeight = o.height - o.borderSizeV * 2
    viewContentWidth = o.width - o.borderSizeH * 2

    checkTop = () -> begin
        if o.data.currentTop > o.data.currentLine
            o.data.currentTop = o.data.currentLine
        elseif o.data.currentLine - o.data.currentTop > viewContentHeight - 1
            o.data.currentTop = o.data.currentLine - viewContentHeight + 1
        end
    end
    moveby = n -> begin
        oldline = o.data.currentLine
        o.data.currentLine = max(1, min( o.data.datalistlen, o.data.currentLine + n) )
        checkTop()
        if oldline == o.data.currentLine
            beep()
            return false
        else
            return true
        end
    end

    inputText = o.data.searchbox.data.inputText
    result = inject( o.data.searchbox, token )

    if result == :got_it
        if inputText != o.data.searchbox.data.inputText
            update_score_sort( o )
        end
        refresh( o )
        return result
    end

    if token == :esc
        retcode = :exit_nothing
    elseif token == :up
        dorefresh = moveby(-1)
    elseif token == :down
        dorefresh = moveby(1)
    elseif token == :shift_left # TODO ctrl-left
        if o.data.currentLeft > 1
            o.data.currentLeft -= 1
            dorefresh = true
        else
            beep()
        end
    elseif token == :ctrlshift_left # TODO ctrl-left
        if o.data.currentLeft > 1
            o.data.currentLeft = 1
            dorefresh = true
        else
            beep()
        end
    elseif token == :shift_right
        if o.data.currentLeft + viewContentWidth < o.data.datawidth
            o.data.currentLeft += 1
            dorefresh = true
        else
            beep()
        end
    elseif token == :ctrlshift_right
        if o.data.currentLeft + viewContentWidth < o.data.datawidth
            o.data.currentLeft = o.data.datawidth - viewContentWidth
            dorefresh = true
        else
            beep()
        end
    elseif token == :pageup
        dorefresh = moveby( -viewContentHeight )
    elseif token == :pagedown
        dorefresh = moveby( viewContentHeight )
    elseif token == :KEY_MOUSE
        (mstate,x,y, bs ) = getmouse()
        if mstate == :scroll_up
            dorefresh = moveby( -int( viewContentHeight/10 ) )
        elseif mstate == :scroll_down
            dorefresh = moveby( int( viewContentHeight/10 ) )
        elseif mstate == :button1_pressed
            begy,begx = getwinbegyx( o.window )
            relx = x - begx
            rely = y - begy
            if 0<=relx<o.width && 0<=rely<o.height
                o.data.currentLine = o.data.currentTop + rely - o.borderSizeH + 1
                dorefresh = true
            end
        end
    elseif  token == :home
        if o.data.currentTop != 1 || o.data.currentLeft != 1 || o.data.currentLine != 1
            o.data.currentTop = 1
            o.data.currentLeft = 1
            o.data.currentLine = 1
            dorefresh = true
        else
            beep()
        end
    elseif in( token, { symbol("end") } )
        if o.data.currentTop + o.height-2 < o.data.datalistlen
            o.data.currentTop = o.data.datalistlen - o.height+ 2
            dorefresh = true
        else
            beep()
        end
    elseif token == :F6
        m = o.data.datalist[o.data.currentLine][3]
        tshow( m, title = string( m.func.code.name ))
        dorefresh = true
    elseif token == :F8
        m = o.data.datalist[o.data.currentLine][3]
        try
            f = eval( m.func.code.name )
            edit( f, m.sig )
        end
        dorefresh = true
    else
        retcode = :pass # I don't know what to do with it
    end

    if dorefresh
        refresh(o)
    end

    return retcode
end
