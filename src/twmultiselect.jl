# multi selection widget

SELECTEDORDERABLE    = 1 # whether selected items are orderable, selected always on top
SELECTSUBSTR         = 2 # search by substring (default by prefix)

defaultMultiSelectHelpText = utf8("""
arrows : move cursor
home   : move to top
end    : move to bottom
shft-up: move the item up
shft-dn: move the item down
space  : toggle selection
enter  : finalize selection

Search box:
alt-space: enter space inside search box
ctrl-a : move search cursor to start
ctrl-e : move search cursor to end
ctrl-k : empty search entry
ctrl-r : Toggle insertion/overwrite mode

ctrl-n : move to the next matched item
ctrl-p : move to the previous matched item
""")

type TwMultiSelectData
    choices::Array{UTF8String,1}
    selected::Array{UTF8String,1}
    datalist::Array{Any, 1}
    maxchoicelength::Int
    searchbox::Any
    currentLine::Int
    currentLeft::Int
    currentTop::Int
    selectmode::Int
    helpText::UTF8String
    TwMultiSelectData( arr::Array{UTF8String,1}, selected::Array{UTF8String,1} ) = new( arr, selected, Any[], 0, nothing, 1, 1, 1, 0, utf8("") )
end
TwMultiSelectData{T<:AbstractString,T2<:AbstractString}( arr::Array{T,1}, selected::Array{T2,1} ) = TwMultiSelectData( map( x->utf8( x ), arr ), map( x->utf8(x), selected ) )

# the ways to use it:
# standalone panel
# as a subwin as part of another widget (see next function)
# w include title width, if it's shown on the left
function newTwMultiSelect{T<:AbstractString}( scr::TwObj, arr::Array{T,1};
        posy::Any = :center,posx::Any = :center,
        selected = UTF8String[],
        title = utf8(""), maxwidth = 50, maxheight = 20, minwidth = 25,
        orderable = false, substrsearch=false )
    obj = TwObj( TwMultiSelectData( arr, UTF8String[ utf8(string(_)) for _ in selected ] ), Val{ :MultiSelect } )
    obj.box = true
    obj.title = title
    obj.borderSizeV= 1
    obj.borderSizeH= 1
    if  orderable
        obj.data.selectmode |= SELECTEDORDERABLE
    end
    if substrsearch
        obj.data.selectmode |= SELECTSUBSTR
    end
    rebuild_select_datalist( obj )
    obj.data.helpText = defaultMultiSelectHelpText
    obj.data.maxchoicelength = 0
    if !isempty(arr)
        obj.data.maxchoicelength = maximum( map(_->length(_), arr ) )
    end

    h = 2 + min( length( arr ), maxheight )
    w = 4 + max( min( max( length( title ), obj.data.maxchoicelength ), maxwidth ), minwidth )

    link_parent_child( scr, obj, h,w, posy, posx )

    obj.data.searchbox = newTwEntry( obj, UTF8String, width=minwidth, posy=:bottom, posx=1, box=false )
    obj.data.searchbox.title = utf8("?")
    obj.data.searchbox.hasFocus = false
    obj
end

function rebuild_select_datalist( o::TwObj{TwMultiSelectData} )
    o.data.datalist = Any[]
    if o.data.selectmode & SELECTEDORDERABLE != 0
        for s in o.data.selected
            push!( o.data.datalist, [ s, true ] )
        end
        for s in o.data.choices
            if !in( s, o.data.selected )
                push!( o.data.datalist, [s, false ] )
            end
        end
    else
        for s in o.data.choices
            push!( o.data.datalist, [s, in( s, o.data.selected ) ] )
        end
    end
end

function draw( o::TwObj{TwMultiSelectData} )
    werase( o.window )
    if o.box
        box( o.window, 0,0 )
    end
    if !isempty( o.title ) && o.box
        mvwprintw( o.window, 0, (@compat round(Int, ( o.width - length(o.title) )/2 )), "%s", o.title )
    end
    starty = o.borderSizeV
    viewContentHeight = o.height - o.borderSizeV * 2
    viewContentWidth  = o.width - o.borderSizeH * 2
    n = length( o.data.datalist )
    for r in o.data.currentTop:min( o.data.currentTop + viewContentHeight-1, n )
        flag = 0
        if r == o.data.currentLine
            flag = A_BOLD | COLOR_PAIR(o.hasFocus ? 15 : 30 )
        end
        s = o.data.datalist[r][1]
        if o.data.datalist[r][2]
            s = string( '\U2612' ) * " " * s
        else
            s = string( '\U2610' ) * " " * s
        end
        s = substr_by_width( s, o.data.currentLeft-1, viewContentWidth )

        wattron( o.window, flag )
        mvwprintw( o.window, r - o.data.currentTop + starty, o.borderSizeH, "%s", s )
        wattroff( o.window, flag )
    end
    draw( o.data.searchbox )
end

function select_search_next( o::TwObj{TwMultiSelectData}, step::Int, trivialstop::Bool )
    st = o.data.currentLine
    tmpstr = lowercase(o.data.searchbox.data.inputText)
    if length(tmpstr) == 0
        TermWin.beep()
        return 0
    end

    n = length( o.data.datalist )

    local i::Int = trivialstop ? st : mod1( st+step,n )
    local usesubstr::Bool = o.data.selectmode * SELECTSUBSTR != 0
    while true
        if usesubstr
            if contains( lowercase( o.data.datalist[i][1] ), tmpstr )
                o.data.currentLine = i
                return i
            end
        else
            if startswith( lowercase( o.data.datalist[i][1] ), tmpstr )
                o.data.currentLine = i
                return i
            end
        end
        i = mod1(i+step,n )
        if i == st
            TermWin.beep()
            return 0
        end
    end
end

function inject( o::TwObj{TwMultiSelectData}, token )
    @lintpragma( "Ignore incompatible type comparison")
    dorefresh = false
    retcode = :got_it # default behavior is that we know what to do with it

    viewContentWidth = o.width - o.borderSizeH * 2
    viewContentHeight = o.height - 2 * o.borderSizeV

    checkTop = () -> begin
        if o.data.currentTop > o.data.currentLine
            o.data.currentTop = o.data.currentLine
        elseif o.data.currentLine - o.data.currentTop > viewContentHeight - 1
            o.data.currentTop = o.data.currentLine - viewContentHeight + 1
        end
    end
    moveby = n -> begin
        sz = length( o.data.datalist )

        o.data.currentLine = max(1, min( sz, o.data.currentLine + n) )
        checkTop()
        return true
    end

    if token != :F1 && token != " "
        inputText = o.data.searchbox.data.inputText
        if token == " " # no break space
            token = " "
        end
        result = inject( o.data.searchbox, token )

        if result == :got_it
            if inputText != o.data.searchbox.data.inputText
                select_search_next( o, 1, true )
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
        select_search_next( o, 1, false )
        checkTop()
        dorefresh = true
    elseif token == :ctrl_p
        select_search_next( o, -1, false )
        checkTop()
        dorefresh = true
    elseif token == :KEY_MOUSE
        (mstate,x,y, bs ) = getmouse()
        if mstate == :scroll_up
            dorefresh = moveby( -(@compat round(Int, viewContentHeight/10 )) )
        elseif mstate == :scroll_down
            dorefresh = moveby( (@compat round(Int, viewContentHeight/10 )) )
        elseif mstate == :button1_pressed && o.data.trackLine
            (rely,relx) = screen_to_relative( o.window, y, x )
            if 0<=relx<o.width && 0<=rely<o.height
                o.data.currentLine = o.data.currentTop + rely - o.borderSizeH + 1
                dorefresh = true
            else
                retcode = :pass
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
    elseif in( token, Any[ Symbol("end") ] )
        n = length( o.data.datalist )
        if o.data.currentLine != n
            o.data.currentLine = n
            checkTop()
            dorefresh = true
        else
            beep()
        end
    elseif o.data.selectmode & SELECTEDORDERABLE != 0 && token == :shift_up
        currstatus = o.data.datalist[ o.data.currentLine][2]
        if currstatus && o.data.currentLine > 1
            currstr = o.data.datalist[o.data.currentLine][1]
            idx = findfirst( o.data.selected, currstr )
            o.data.selected[ idx-1], o.data.selected[ idx ] = (o.data.selected[ idx ], o.data.selected[ idx - 1] )
            o.data.currentLine -=1
            rebuild_select_datalist( o )
            checkTop()
            dorefresh = true
        else
            beep()
        end
    elseif o.data.selectmode & SELECTEDORDERABLE != 0 && token == :shift_down
        currstatus = o.data.datalist[ o.data.currentLine][2]
        if currstatus && o.data.currentLine < length( o.data.selected )
            currstr = o.data.datalist[o.data.currentLine][1]
            idx = findfirst( o.data.selected, currstr )
            o.data.selected[ idx+1], o.data.selected[ idx ] = (o.data.selected[ idx ], o.data.selected[ idx + 1] )
            o.data.currentLine +=1
            rebuild_select_datalist( o )
            checkTop()
            dorefresh = true
        else
            beep()
        end
    elseif token == " "
        currstr = o.data.datalist[o.data.currentLine][1]
        currstatus = o.data.datalist[ o.data.currentLine][2]
        if !currstatus # we are selecting it
            push!( o.data.selected, currstr )
            if o.data.selectmode & SELECTEDORDERABLE != 0
                rebuild_select_datalist( o )
            else
                o.data.datalist[o.data.currentLine][2] = true
            end
        else # we are de-selecting it
            idx = findfirst( o.data.selected, currstr )
            deleteat!( o.data.selected, idx )
            if o.data.selectmode & SELECTEDORDERABLE != 0
                rebuild_select_datalist( o )
            else
                o.data.datalist[o.data.currentLine][2] = false
            end
        end
        dorefresh = true
    elseif token == :enter || token == Symbol( "return" )
        o.value = o.data.selected
        retcode = :exit_ok
    else
        retcode = :pass # I don't know what to do with it
    end

    if dorefresh
        refresh(o)
    end

    return retcode
end

function helptext( o::TwObj{TwMultiSelectData} )
    o.data.helpText
end
