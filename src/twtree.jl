defaultTreeHelpText = """
PgUp/PgDn,
Arrow keys : standard navigation
<spc>,<rtn>: toggle leaf expansion
Home       : jump to the start
End        : jump to the end
-          : collapse all
F6         : popup window for value
"""

modulenames = Dict{ Module, Array{ Symbol, 1 } }()
typefields  = Dict{ Any, Array{ Symbol, 1 } }()

typefields[ Function ] = []
typefields[ Method ] = [ :sig ]
typefields[ LambdaStaticData ] = [ :name, :module, :file ]

type TwTreeData
    openstatemap::Dict{ Any, Bool }
    datalist::Array{Any, 1}
    datalistlen::Int
    datatreewidth::Int
    datatypewidth::Int
    datavaluewidth::Int
    currentTop::Int
    currentLine::Int
    currentLeft::Int
    showLineInfo::Bool # e.g.1/100 1.0% at top right corner
    bottomText::String
    showHelp::Bool
    helpText::String
    TwTreeData() = new( Dict{ Any, Bool }(), {}, 0, 0, 0, 0, 1, 1, 1, true, "", true, defaultTreeHelpText )
end

function newTwTree( scr::TwScreen, ex, h::Real,w::Real,y::Any,x::Any; title = string(typeof( ex ) ), box=true, showLineInfo=true, showHelp=true, bottomText = "", tabWidth = 4, trackLine = false )
    obj = TwObj( twFuncFactory( :Tree ) )
    registerTwObj( scr, obj )
    obj.value = ex
    obj.title = title
    obj.box = box
    obj.borderSizeV= box ? 1 : 0
    obj.borderSizeH= box ? 2 : 0
    obj.data = TwTreeData()
    obj.data.openstatemap[ {} ] = true
    tree_data( ex, title, obj.data.datalist, o.data.openstatemap, {} )
    obj.data.showLineInfo = showLineInfo
    obj.data.showHelp = showHelp
    obj.data.bottomText = bottomText
    configure_newwinpanel!( obj, h, w, y, x )
    obj
end

# x is the value, name is a pretty-print identifier
# stack is the pathway to get to x so far
# skiplines are hints where we should not draw the vertical lines to the left
# because it corresponds the end of some list at a lower depth level

function tree_data( x, name, list, openstatemap, stack, skiplines=Int[] )
    global modulenames, typefields
    isexp = haskey( openstatemap, stack ) && openstatemap[ stack ]

    intern_tree_data = ( subx, subn, substack, islast )->begin
        if islast
            newskip = copy(skiplines)
            push!( newskip, length(stack) +1)
            tree_data( subx, subn, list, openstatemap, substack, newskip )
        else
            tree_data( subx, subn, list, openstatemap, substack, skiplines )
        end
    end
    if typeof( x ) == Symbol || typeof( x ) <: Number || typeof( x ) == Any || typeof( x ) == DataType
        s = string( name )
        t = string( typeof( x) )
        v = string( x )
        if length( v ) > 25
            v = string( SubString( v, 1, 23 ) ) * ".."
        end
        push!( list, (s, t, v, stack, :single, skiplines ) )
    elseif typeof( x ) <: String
        s = string( name )
        t = string( typeof( x) )
        if length( x ) > 25
            v = string( SubString( x, 1, 23 ) ) * ".."
        else
            v = string( x )
        end
        push!( list, (s, t, v, stack, :single, skiplines ) )
    elseif typeof( x ) <: Array || typeof( x ) <: Tuple
        s = string( name )
        t = string( typeof( x ))
        len = length(x)
        szstr = string( len )
        v = "Size=" * szstr
        expandhint = isempty(x) ? :single : (isexp ? :open : :close )
        push!( list, (s,t,v, stack, expandhint, skiplines ))
        if isexp
            szdigits = length( szstr )
            for (i,a) in enumerate( x )
                istr = string(i)
                subname = "[" * repeat( " ", szdigits - length(istr)) * istr * "]"
                newstack = copy( stack )
                push!( newstack, i )
                intern_tree_data( a, subname, newstack, i==len )
            end
        end
    elseif typeof( x ) <: Dict
        s = string( name )
        t = string( typeof( x ))
        len = length(s)
        szstr = string( len )
        v = "Size=" * szstr
        expandhint = isempty(x) ? :single : (isexp ? :open : :close )
        push!( list, (s,t,v, stack, expandhint, skiplines ))
        if isexp
            ktype = eltype(x)[1]
            ks = collect( keys( x ) )
            if ktype <: Real || ktype <: String || ktype == Symbol
                sort!(ks)
            end
            for (i,k) in enumerate( ks )
                v = x[k]
                subname = repr( k )
                newstack = copy( stack )
                push!( newstack, k )
                intern_tree_data( v, subname, newstack, i==len )
            end
        end
    elseif typeof(x) == Module && !isempty( stack ) # don't want to recursively descend
        s = string( name )
        t = string( typeof( x) )
        v = string( x )
        if length( v ) > 25
            v = string( SubString( v, 1, 23 ) ) * ".."
        end
        push!( list, (s, t, v, stack, :single, skiplines ) )
    #=
    elseif typeof( x ) == Function
        s = string( name )
        t = string( typeof( x) )
        if length( string(x) ) > 25
            v = string( SubString( x, 1, 23 ) ) * ".."
        else
            v = string( x )
        end
        push!( list, (s, t, v, stack, :single, skiplines ) )
    =#
    else
        ns = Symbol[]
        if typeof(x) == Module
            if haskey( modulenames, x )
                ns = modulenames[ x ]
            else
                ns = names( x, true )
                sort!( ns )
                modulenames[ x ] = ns
            end
        else
            if haskey( typefields, typeof(x) )
                ns = typefields[ typeof(x) ]
            else
                try
                    ns = names( typeof(x) )
                    if length(ns) > 20
                        sort!(ns)
                    end
                end
                typefields[ typeof(x) ] = ns
            end
        end
        s = string( name )
        expandhint = isempty(ns) ? :single : (isexp ? :open : :close )
        t = string( typeof( x) )
        v = string( x )
        len = length(ns)
        if length( v ) > 25
            v = string( SubString( v, 1, 23 ) ) * ".."
        end
        push!( list, (s, t, v, stack, expandhint, skiplines ) )
        if isexp && !isempty( ns )
            for (i,n) in enumerate(ns)
                subname = string(n)
                newstack = copy( stack )
                push!( newstack, n )
                try
                    v = getfield(x,n)
                    intern_tree_data( v, subname, newstack, i==len )
                catch err
                    println(n, ":", err)
                    sleep(1)
                    if typeof(x) == Module
                        todel = find( y->y==n, modulenames[ x] )
                        deleteat!( modulenames[x], todel[1] )
                    else
                        todel = find( y->y==n, typefields[ typeof(x) ] )
                        deleteat!( typefields[ typeof(x) ], todel[1] )
                    end
                end
            end
        end
    end
end

function getvaluebypath( x, path )
    if isempty( path )
        return x
    end
    key = shift!( path )
    if typeof( x ) <: Array || typeof( x ) <: Dict
        return getvaluebypath( x[key], path )
    else
        return getvaluebypath( getfield( x, key ), path )
    end
end

function updateContentDimensions( o::TwObj )
    o.data.datalistlen = length( o.data.datalist )
    o.data.datatreewidth = maximum( map( x->length(x[1]) + 2 +2 * length(x[4]), o.data.datalist ) )
    o.data.datatypewidth = min( 40, max( 15, maximum( map( x->length(x[2]), datalist ) ) ) )
    o.data.datavaluewidth= min( 40, maximum( map( x->length(x[3]), datalist ) ) )
end

function drawTwTree( o::TwObj )
    viewContentHeight, viewContentWidth, viewStartRow = viewContentDimensions( o )

    if o.box
        box( o.window, 0,0 )
    end
    if !isempty( o.title )
        mvwprintw( o.window, 0, int( ( o.width - length(o.title) )/2 ), "%s", title )
    end
    if o.data.showLineInfo
        if o.data.msglen <= o.height - 2 * o.borderSizeV
            info = "ALL"
            mvwprintw( o.window, 0, o.width - 13, "%10s", "ALL" )
        else
            if o.data.trackLine
                info = @sprintf( "%d/%d %5.1f%%", o.data.currentTop, o.data.msglen,
                    o.data.currentLine / o.data.msglen * 100 )
            else
                info = @sprintf( "%d/%d %5.1f%%", o.data.currentTop, o.data.msglen,
                    o.data.currentTop / (o.data.msglen - o.height + 2 * o.borderSizeV ) * 100 )
            end
        end
        mvwprintw( o.window, 0, o.width - length(info)-3, "%s", info )
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
            wattron( o.window, A_BOLD | COLOR_PAIR(15) )
            s *= repeat( " ", max(0,viewContentWidth - length(s) ) )
        end
        mvwprintw( o.window, r - o.data.currentTop + viewStartRow, o.borderSizeH, "%s", s )
        if o.data.trackLine && r == o.data.currentLine
            wattroff( o.window, A_BOLD | COLOR_PAIR(15) )
        end
    end
    if length( o.data.bottomText ) != 0
        mvwprintw( o.window, o.height-1, int( (o.width - length(o.data.bottomText))/2 ), "%s", o.data.bottomText )
    end
end

function injectTwTree( o::TwObj, token )
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
            dorefresh = moveby( -int( viewContentHeight/5 ) )
        elseif mstate == :scroll_down
            dorefresh = moveby( int( viewContentHeight/5 ) )
        elseif mstate == :button1_pressed && o.data.trackLine
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
        if o.data.currentTop + o.height-2 < o.data.msglen
            o.data.currentTop = o.data.msglen - o.height+ 2
            dorefresh = true
        else
            beep()
        end
    elseif (token == :enter || token== symbol( "return" )) && o.data.trackLine
        if haskey( o.listeners, :select )
            for f in o.listeners[ :select ]
                retcode = f( :select, o )
            end
        end
        dorefresh = true
    elseif token == "L" # move half-way toward the end
        if o.data.trackLine
            target = min( int(ceil((o.data.currentLine + o.data.msglen)/2)), o.data.msglen )
            if target != o.data.currentLine
                o.data.currentLine = target
                checkTop()
                dorefresh = true
            else
                beep()
            end
        else
            target = min( int(ceil((o.data.currentTop + o.data.msglen - o.height+2)/2)), o.data.msglen - o.height + 2 )
            if target != o.data.currentTop
                o.data.currentTop = target
                dorefresh = true
            else
                beep()
            end
        end
    elseif token == "l" # move half-way toward the beginning
        if o.data.trackLine
            target = max( int(floor( o.data.currentLine /2)), 1)
            if target != o.data.currentLine
                o.data.currentLine = target
                checkTop()
                dorefresh = true
            else
                beep()
            end
        else
            target = max( int(floor( o.data.currentTop /2)), 1)
            if target != o.data.currentTop
                o.data.currentTop = target
                dorefresh = true
            else
                beep()
            end
        end
    elseif token == :F1 && o.data.showHelp
        helper = newTwTree( o.screen.value, o.data.helpText, :center, :center, showHelp=false, showLineInfo=false, bottomText = "Esc to continue" )
        activateTwObj( helper )
        unregisterTwObj( o.screen.value, helper )
        dorefresh = true
        #TODO search, jump to line, etc.
    else
        retcode = :pass # I don't know what to do with it
    end

    if dorefresh
        refresh(o)
    end

    return retcode
end

function setTwTreeMsgs( o::TwObj, msgs::Array )
    o.data.messages = msgs
    o.data.msglen = length(msgs)
    o.data.msgwidth = maximum( map( x->length(x), msgs ) )
end

