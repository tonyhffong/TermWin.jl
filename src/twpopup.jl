# popup selection widget
# default behavior is a simple scrollable box of strings that is selectable
# quickselect enable a searchbox. Users can type in a string and the cursor will jump to the first item matching 
# that as a prefix

# Additional modification of the behavior:
# if substr is enabled, it'd search for any substr instead of a faster beginswith
# if hideunmatched is enabled, any choice that doesn't match will be hidden. deleting the search string will revert
# if sortmatched is enabled (usually in conjunction with substr and but not hideunmatched), a levenstein distance
#  score will be generated and the result sorted according to the match score
# if allownew is enabled, the search box is also an entry box to enter new text, as long as there is no match.
#   Use trailing space to disambiguate. They will be stripped afterwards.

# But if no additional modification is used, tab-completion is enabled.

POPUPQUICKSELECT    = 1
POPUPSUBSTR         = 2
POPUPHIDEUNMATCHED  = 4
POPUPSORTMATCHED    = 8
POPUPALLOWNEW       = 16

defaultPopupHelpText = """
arrows : move cursor
home   : move to top
end    : move to bottom
enter  : select
"""

defaultPopupQuickHelpText = """
arrows : move item cursor
home   : move to top
end    : move to bottom
enter  : select

Search box:
ctrl-a : move search cursor to start
ctrl-e : move search cursor to end
ctrl-k : empty search entry
ctrl-r : Toggle insertion/overwrite mode

ctrl-n : move to the next matched item
ctrl-p : move to the previous matched item
"""

type TwPopupData
    choices::Array{UTF8String,1}
    datalist::Array{Any, 1}
    maxchoicelength::Int
    searchbox::Any
    currentLine::Int
    currentLeft::Int
    currentTop::Int
    selectmode::Int
    helpText::String
    TwPopupData( arr::Array{UTF8String,1} ) = new( arr, Any[], maximum( map( z->length(z), arr ) ), nothing, 1, 1, 1, 0, "" )
end
TwPopupData{ T<:String} ( arr::Array{T, 1 } ) = TwPopupData( map( x->utf8( x ), arr ) )

# the ways to use it:
# standalone panel
# as a subwin as part of another widget (see next function)
# w include title width, if it's shown on the left
function newTwPopup{T<:String}( scr::TwScreen, arr::Array{T,1}, y::Any,x::Any;
        title = "", maxwidth = 50, maxheight = 15, minwidth = 20,
        quickselect = false, substrsearch=false, hideunmatched=false, sortmatched=false, allownew=false )
    obj = TwObj( twFuncFactory( :Popup ) )
    registerTwObj( scr, obj )
    box = true
    obj.box = box
    obj.title = title
    obj.borderSizeV= box ? 1 : 0
    obj.borderSizeH= box ? 1 : 0
    obj.data = TwPopupData( arr )
    if quickselect
        obj.data.selectmode |= POPUPQUICKSELECT
    end
    if substrsearch
        obj.data.selectmode |= POPUPQUICKSELECT | POPUPSUBSTR
    end
    if hideunmatched
        obj.data.selectmode |= POPUPQUICKSELECT | POPUPHIDEUNMATCHED
    end
    if sortmatched
        obj.data.selectmode |= POPUPQUICKSELECT | POPUPSUBSTR | POPUPSORTMATCHED
    end
    if allownew
        obj.data.selectmode |= POPUPQUICKSELECT | POPUPSUBSTR | POPUPHIDEUNMATCHED | POPUPALLOWNEW
    end
    usedatalist = popup_use_datalist( obj )
    if usedatalist
        rebuild_popup_datalist( obj )
    end
    if obj.data.selectmode & POPUPQUICKSELECT != 0
        obj.data.helpText = defaultPopupQuickHelpText
    else
        obj.data.helpText = defaultPopupHelpText
    end

    h = (box?2 : 0) + min( length( arr ), maxheight )
    w = (box?2 : 0) + max( min( max( length( title ), obj.data.maxchoicelength ), maxwidth ), minwidth )
    alignxy!( obj, h, w, x, y)
    configure_newwinpanel!( obj )

    obj.data.searchbox = newTwEntry( obj.window, String, minwidth, :bottom, 1, box=false )
    obj.data.searchbox.title = "?"
    obj
end

function popup_use_datalist( o::TwObj )
    o.data.selectmode & POPUPHIDEUNMATCHED != 0 || o.data.selectmode & POPUPSORTMATCHED != 0
end

function longest_common_prefix( s1::String, s2::String )
    m = min( length( s1 ), length( s2 ) )
    lcpidx = 0
    for i in 1:m
        if s1[i] != s2[i]
            break
        end
        lcpidx = i
    end
    return s1[ 1:lcpidx ]
    #= Julia's utf8 substring seems tolerant enough for now, otherwise we have to do something like this
    while lcpidx > 0
        chr = 0
        try
            chr = ind2chr( s1, lcpidx )
        catch
            lcpidx -= 1
        end
        if chr != 0
            return s1[ 1:lcpidx ]
        end
    end
    return ""
    =#
end

function rebuild_popup_datalist( o::TwObj )
    o.data.datalist = Any[]
    for (i, c) in enumerate( o.data.choices )
        searchstring = c
        push!( o.data.datalist, {lowercase( searchstring ), c, i, 0.0 } )
    end
end

function drawTwPopup( o::TwObj )
    werase( o.window )
    if o.box
        box( o.window, 0,0 )
    end
    if !isempty( o.title ) && o.box
        mvwprintw( o.window, 0, int( ( o.width - length(o.title) )/2 ), "%s", o.title )
    end
    starty = o.borderSizeV
    viewContentHeight = o.height - o.borderSizeV * 2
    viewContentWidth  = o.width - o.borderSizeH * 2
    usedatalist = popup_use_datalist( o )
    if usedatalist
        n = length( o.data.datalist )
    else
        n = length( o.data.choices )
    end
    for r in o.data.currentTop:min( o.data.currentTop + viewContentHeight-1, n )
        flag = 0
        if r == o.data.currentLine
            flag = A_BOLD | COLOR_PAIR(15)
        end
        if usedatalist
            s = o.data.datalist[r][2]
        else
            s = o.data.choices[r]
        end
        endpos = o.data.currentLeft + o.width - 2 * o.borderSizeH - 1
        s = s[ chr2ind( s, o.data.currentLeft ) : end ]
        if length( s ) > viewContentWidth
            s = s[ 1: chr2ind( s, viewContentWidth ) ]
        end

        wattron( o.window, flag )
        mvwprintw( o.window, r - o.data.currentTop + starty, o.borderSizeH, "%s", s )
        wattroff( o.window, flag )
    end
    if o.data.selectmode & POPUPQUICKSELECT != 0
        draw( o.data.searchbox )
    end
end

function popup_search_next( o::TwObj, step::Int, trivialstop::Bool )
    st = o.data.currentLine
    tmpstr = lowercase(o.data.searchbox.data.inputText)
    if length(tmpstr) == 0
        TermWin.beep()
        return 0
    end

    usedatalist = popup_use_datalist( o )
    if usedatalist
        n = length( o.data.datalist )
    else
        n = length( o.data.choices )
    end

    i = trivialstop ? st : ( mod( st-1+step, n ) + 1 )
    while true
        if o.data.selectmode & POPUPSUBSTR != 0
            if usedatalist
                if contains( o.data.datalist[i][1], tmpstr )
                    o.data.currentLine = i
                    return i
                end
            else
                if contains( lowercase( o.data.choices[i] ), tmpstr )
                    o.data.currentLine = i
                    return i
                end
            end
        else
            if beginswith( lowercase( o.data.choices[i] ), tmpstr )
                o.data.currentLine = i
                return i
            end
        end
        i = mod( i-1+step, n ) + 1
        if i == st
            TermWin.beep()
            return 0
        end
    end
end

function update_popup_score( o::TwObj )
    searchterm = o.data.searchbox.data.inputText
    needx = o.data.maxchoicelength

    l1 = length(searchterm)
    usedatalist = popup_use_datalist( o )

    if usedatalist
        prevchoice = ""
        if length( o.data.datalist ) >= o.data.currentLine >= 1
            prevchoice = o.data.datalist[ o.data.currentLine ][2]
        else
            o.data.currentLine = 1
        end
        if l1 == 0
            rebuild_popup_datalist( o )
            for (i, row) in enumerate( o.data.datalist)
                if row[2] == prevchoice
                    o.data.currentLine = i
                end
            end
        else
            if o.data.selectmode & POPUPHIDEUNMATCHED != 0
                o.data.datalist = Any[]
                if o.data.selectmode & POPUPSUBSTR != 0
                    for (i,c) in enumerate( o.data.choices )
                        if contains( lowercase( c ), lowercase( searchterm ) )
                            push!( o.data.datalist, { lowercase( c ), c, i, search( lowercase( c ), lowercase( searchterm ) )[1] + length( c ) / needx } )
                        end
                    end
                else
                    for (i,c) in enumerate( o.data.choices )
                        if beginswith( lowercase( c ), lowercase( searchterm ) )
                            push!( o.data.datalist, { lowercase( c ), c, i, length(c) } )
                        end
                    end
                end
                if o.data.selectmode & POPUPSORTMATCHED != 0
                    sort!( o.data.datalist, lt=(x,y)-> x[4] < y[4] )
                    for (i,row) in o.data.datalist
                        if prevchoice == row[2]
                            o.data.currentLine = i
                        end
                    end
                end
            else # show everything
                # sort
                if o.data.selectmode & POPUPSORTMATCHED != 0
                    if o.data.selectmode & POPUPSUBSTR != 0
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
                    # prefix-based
                    else
                        for row in o.data.datalist
                            if beginswith( row[1], lowercase( searchterm ) )
                                row[4] = length( row[1] )
                            else
                                row[4] = length( row[1] ) + needx
                            end
                        end
                    end
                    sort!( o.data.datalist, lt=(x,y)-> x[4] < y[4] )
                    o.data.currentLine = 1
                    o.data.currentTop = 1
                else # don't sort, but jump to the next match one
                    popup_search_next( o, 1, true )
                end
            end
        end
    else # just jump to the first term with the matched
        popup_search_next( o, 1, true )
    end
end

function injectTwPopup( o::TwObj, token::Any )
    dorefresh = false
    retcode = :got_it # default behavior is that we know what to do with it

    viewContentWidth = o.width - o.borderSizeH * 2
    viewContentHeight = o.height - 2 * o.borderSizeV

    usedatalist = popup_use_datalist( o )
    tabcomplete = ( o.data.selectmode & POPUPQUICKSELECT != 0 ) && (o.data.selectmode & POPUPSUBSTR == 0 )

    checkTop = () -> begin
        if o.data.currentTop > o.data.currentLine
            o.data.currentTop = o.data.currentLine
        elseif o.data.currentLine - o.data.currentTop > viewContentHeight - 1
            o.data.currentTop = o.data.currentLine - viewContentHeight + 1
        end
    end
    moveby = n -> begin
        if o.data.selectmode & POPUPHIDEUNMATCHED != 0
            sz = length( o.data.datalist )
        else
            sz = length( o.data.choices )
        end

        o.data.currentLine = max(1, min( sz, o.data.currentLine + n) )
        checkTop()
        return true
    end

    if o.data.selectmode & POPUPQUICKSELECT != 0 && token != :F1
        inputText = o.data.searchbox.data.inputText
        result = inject( o.data.searchbox, token )

        if result == :got_it
            if inputText != o.data.searchbox.data.inputText
                update_popup_score( o )
                checkTop()
            end
            refresh( o )
            return result
        end
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
        if o.data.currentLeft + viewContentWidth < o.data.maxchoicelength
            o.data.currentLeft += 1
            dorefresh = true
        else
            beep()
        end
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
        if o.data.currentLeft + viewContentWidth < o.data.maxchoicelength
            o.data.currentLeft += 1
            dorefresh = true
        else
            beep()
        end
    elseif token == :ctrlshift_right
        if o.data.currentLeft + viewContentWidth < o.data.maxchoicelength
            o.data.currentLeft = o.data.maxchoicelength - viewContentWidth
            dorefresh = true
        else
            beep()
        end
    elseif token == :pageup
        dorefresh = moveby( -viewContentHeight )
    elseif token == :pagedown
        dorefresh = moveby( viewContentHeight )
    elseif token == :ctrl_n
        popup_search_next( o, 1, false )
        checkTop()
        dorefresh = true
    elseif token == :ctrl_p
        popup_search_next( o, -1, false )
        checkTop()
        dorefresh = true
    elseif token == :KEY_MOUSE
        (mstate,x,y, bs ) = getmouse()
        if mstate == :scroll_up
            dorefresh = moveby( -int( viewContentHeight/10 ) )
        elseif mstate == :scroll_down
            dorefresh = moveby( int( viewContentHeight/10 ) )
        elseif mstate == :button1_pressed && o.data.trackLine
            begy,begx = getwinbegyx( o.window )
            relx = x - begx
            rely = y - begy
            if 0<=relx<o.width && 0<=rely<o.height
                o.data.currentLine = o.data.currentTop + rely - o.borderSizeH + 1
                dorefresh = true
            end
        end
    elseif token == :tab && tabcomplete
        # auto-input the search text to be the longest common prefix of the current line and the next line,
        # as long as the current search text content can be appended.
        nextstr = ""
        currstr = ""
        if usedatalist
            if o.data.currentLine < length( o.data.datalist )
                currstr = o.data.datalist[ o.data.currentLine     ][2]
                nextstr = o.data.datalist[ o.data.currentLine + 1 ][2]
            end
        else
            if o.data.currentLine < length( o.data.choices )
                currstr = o.data.choices[ o.data.currentLine    ]
                nextstr = o.data.choices[ o.data.currentLine + 1]
            end
        end
        lcp = longest_common_prefix( currstr, nextstr )
        if beginswith( lcp, o.data.searchbox.data.inputText )
            o.data.searchbox.data.inputText = lcp
            inject( o.data.searchbox, :ctrl_e ) # move the cursor to the end
            dorefresh = true
        else
            beep()
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
        if usedatalist
            n = length( o.data.datalist )
        else
            n = length( o.data.choices )
        end
        if o.data.currentLine != n
            o.data.currentLine = n
            checkTop()
            dorefresh = true
        else
            beep()
        end
    elseif token == :enter || token == symbol( "return" )
        if usedatalist
            if o.data.currentLine <= length( o.data.datalist )
                o.value = o.data.datalist[ o.data.currentLine ][ 2]
                retcode = :exit_ok
            elseif o.data.selectmode & POPUPALLOWNEW != 0
                o.value = strip( o.data.searchbox.data.inputText )
                retcode = :exit_ok
            end
        else
            if o.data.currentLine <= length( o.data.choices )
                o.value = o.data.choices[ o.data.currentLine ]
                retcode = :exit_ok
            end
        end
    elseif token == :F1
        global rootTwScreen
        s = o.data.helpText
        if tabcomplete
            s *= "tab    : tab-completion"
        end
        helper = newTwViewer( rootTwScreen, s, :center, :center, showHelp=false, showLineInfo=false, bottomText = "Esc to continue" )
        activateTwObj( helper )
        unregisterTwObj( rootTwScreen, helper )
        dorefresh = true
    else
        retcode = :pass # I don't know what to do with it
    end

    if dorefresh
        refresh(o)
    end

    return retcode
end
