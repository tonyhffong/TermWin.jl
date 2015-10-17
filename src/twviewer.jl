
defaultViewerHelpText = """
PgUp/PgDn,
Arrow keys : standard navigation
l          : move halfway toward the start
L          : move halfway to the end
Home       : jump to the start
End        : jump to the end
"""

type TwViewerData
    messages::Array
    msglen::Int
    msgwidth::Int
    currentTop::Int
    currentLine::Int
    currentLeft::Int
    showLineInfo::Bool # e.g.1/100 1.0% at top right corner
    bottomText::UTF8String
    trackLine::Bool
    showHelp::Bool
    helpText::UTF8String
    tabWidth::Int
    TwViewerData() = new( UTF8String[], 0, 0, 1, 1, 1, true, "", false, true, defaultViewerHelpText, 4 )
end

# the ways to use it:
# exact dimensions known: h,w,y,x, content to add later
# exact dimensions unknown, but content known and content drives dimensions
function newTwViewer( scr::TwScreen; height::Real=0.5,width::Real=0.8,posy::Any=:staggered,posx::Any=:staggered,
        box=true, showLineInfo=true, showHelp=true, bottomText = "", tabWidth = 4, trackLine = false, title="" )
    obj = TwObj( TwViewerData(), Val{ :Viewer } )
    obj.box = box
    obj.title = title
    obj.borderSizeV= box ? 1 : 0
    obj.borderSizeH= box ? 2 : 0
    obj.data.showLineInfo = showLineInfo
    obj.data.showHelp = showHelp
    obj.data.tabWidth = tabWidth
    obj.data.bottomText = bottomText
    obj.data.trackLine = trackLine
    link_parent_child( scr, obj, height,width,posy,posx )
    obj.data.viewContentHeight = obj.height - ( box? obj.borderSizeV *2 : 1 )
    obj
end

function newTwViewer( scr::TwObj, msgs::Array;
        posy::Any=:staggered,posx::Any=:staggered,
        box=true, showLineInfo=true, bottomText = "", showHelp=true, tabWidth = 4, trackLine = false, title="" )
    newmsgs = map( z->escape_string( replace( z, "\t", repeat( " ", tabWidth ) ) ), msgs )
    obj = TwObj( TwViewerData(), Val{ :Viewer } )
    obj.title = title
    setTwViewerMsgs( obj, newmsgs )
    obj.box = box
    obj.borderSizeV= box ? 1 : 0
    obj.borderSizeH= box ? 2 : 0
    obj.data.showLineInfo = showLineInfo
    obj.data.showHelp = showHelp
    obj.data.tabWidth = tabWidth
    obj.data.bottomText = bottomText
    obj.data.trackLine = trackLine

    h = obj.data.msglen + obj.borderSizeV * 2 + (!box && !isempty( obj.data.bottomText )? 1 : 0 )
    w = max( 25, obj.data.msgwidth + obj.borderSizeH * 2, length(title)+6 )

    link_parent_child( scr, obj, h,w,posy,posx )
    obj
end

function newTwViewer{T<:AbstractString}( scr::TwScreen, msg::T; kwargs... )
    newTwViewer( scr, split(msg,"\n"); kwargs... )
end

function viewContentDimensions( o::TwObj{TwViewerData} )
    vh = o.height
    vstart = 0
    if o.box
        vh -= o.borderSizeV * 2
        vstart = 1
    else
        if !isempty( o.title ) || o.data.showLineInfo
            vh -= 1
            vstart = 1
        end
        if !isempty( o.data.bottomText )
            vh -= 1
        end
    end
    vw = o.width - (o.box ? o.borderSizeH * 2 : 0 )
    (vh, vw, vstart)
end

function draw( o::TwObj{TwViewerData} )
    viewContentHeight, viewContentWidth, viewStartRow = viewContentDimensions( o )

    if o.box
        box( o.window, 0,0 )
    end
    if !isempty( o.title )
        mvwprintw( o.window, 0, (@compat round(Int, ( o.width - length(o.title) )/2 )), "%s", o.title )
    end
    if o.data.showLineInfo
        if o.data.msglen <= o.height - 2 * o.borderSizeV
            msg = "ALL"
        else
            if o.data.trackLine
                msg = @sprintf( "%d/%d %5.1f%%", o.data.currentLine, o.data.msglen,
                    o.data.currentLine / o.data.msglen * 100 )
            else
                msg = @sprintf( "%d/%d %5.1f%%", o.data.currentTop, o.data.msglen,
                    o.data.currentTop / (o.data.msglen - o.height + 2 * o.borderSizeV ) * 100 )
            end
        end
        mvwprintw( o.window, 0, o.width - length(msg)-3, "%s", msg )
    end
    for r in o.data.currentTop:min( o.data.currentTop + viewContentHeight - 1, o.data.msglen )
        s = o.data.messages[r]
        endpos=o.data.currentLeft + o.width - 2 * o.borderSizeH - 1
        if endpos < length(s)
            s = s[o.data.currentLeft:endpos]
        else
            s = s[o.data.currentLeft:end]
        end
        if o.data.trackLine && r == o.data.currentLine
            wattron( o.window, A_BOLD | COLOR_PAIR( o.hasFocus? 15 : 30 ) )
            s *= repeat( " ", max(0,viewContentWidth - length(s) ) )
        end
        mvwprintw( o.window, r - o.data.currentTop + viewStartRow, o.borderSizeH, "%s", s )
        if o.data.trackLine && r == o.data.currentLine
            wattroff( o.window, A_BOLD | COLOR_PAIR( o.hasFocus? 15 : 30 ) )
        end
    end
    if length( o.data.bottomText ) != 0
        mvwprintw( o.window, o.height-1, (@compat round(Int, (o.width - length(o.data.bottomText))/2 )), "%s", o.data.bottomText )
    end
end

function inject( o::TwObj{TwViewerData}, token )
    dorefresh = false
    retcode = :got_it # default behavior is that we know what to do with it
    viewContentHeight, viewContentWidth, viewStartRow = viewContentDimensions( o )

    checkTop = () -> begin
        if o.data.currentTop > o.data.currentLine
            o.data.currentTop = o.data.currentLine
        elseif o.data.currentLine - o.data.currentTop > viewContentHeight - 1
            o.data.currentTop = o.data.currentLine - viewContentHeight + 1
        end
    end
    moveby = n -> begin
        if o.data.trackLine
            o.data.currentLine = max(1, min( o.data.msglen, o.data.currentLine + n) )
            checkTop()
        else
            o.data.currentTop = max( 1, min( o.data.msglen - viewContentHeight, o.data.currentTop + n ) )
        end
        true
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
        if o.data.currentLeft + viewContentWidth < o.data.msgwidth
            o.data.currentLeft += 1
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
            dorefresh = moveby( -(@compat round(Int, viewContentHeight/10 )) )
        elseif mstate == :scroll_down
            dorefresh = moveby( @compat round(Int, viewContentHeight/10 ) )
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
        if o.data.currentTop + o.height-2 < o.data.msglen
            o.data.currentTop = o.data.msglen - o.height+ 2
            dorefresh = true
        else
            beep()
        end
    elseif (token == :enter || token== Symbol( "return" )) && o.data.trackLine
        if haskey( o.listeners, :select )
            for f in o.listeners[ :select ]
                retcode = f( :select, o )
            end
        end
        dorefresh = true
    elseif token == "L" # move half-way toward the end
        if o.data.trackLine
            target = min( (@compat round(Int, ceil((o.data.currentLine + o.data.msglen)/2))), o.data.msglen )
            if target != o.data.currentLine
                o.data.currentLine = target
                checkTop()
                dorefresh = true
            else
                beep()
            end
        else
            target = min( (@compat round(Int,ceil((o.data.currentTop + o.data.msglen - o.height+2)/2))), o.data.msglen - o.height + 2 )
            if target != o.data.currentTop
                o.data.currentTop = target
                dorefresh = true
            else
                beep()
            end
        end
    elseif token == "l" # move half-way toward the beginning
        if o.data.trackLine
            target = max( (@compat round(Int,floor( o.data.currentLine /2))), 1)
            if target != o.data.currentLine
                o.data.currentLine = target
                checkTop()
                dorefresh = true
            else
                beep()
            end
        else
            target = max( (@compat round(Int, floor( o.data.currentTop /2))), 1)
            if target != o.data.currentTop
                o.data.currentTop = target
                dorefresh = true
            else
                beep()
            end
        end
    else
        retcode = :pass # I don't know what to do with it
    end

    if dorefresh
        refresh(o)
    end

    return retcode
end

function helptext( o::TwObj{TwViewerData} )
    if o.data.showHelp
        o.data.helpText
    else
        ""
    end
end

function setTwViewerMsgs( o::TwObj{TwViewerData}, msgs::Array )
    o.data.messages = msgs
    o.data.msglen = length(msgs)
    o.data.msgwidth = maximum( map( x->length(x), msgs ) )
end

