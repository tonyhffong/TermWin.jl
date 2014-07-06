defaultTreeHelpText = """
PgUp/PgDn,
Arrow keys : standard navigation
<spc>,<rtn>: toggle leaf expansion
Home       : jump to the start
End        : jump to the end
ctrl_arrow : jump to the start/end of the line
+, -       : expand/collapse one level
_          : collapse all
/          : search popup window
F6         : popup window for value
"""

modulenames = Dict{ Module, Array{ Symbol, 1 } }()
typefields  = Dict{ Any, Array{ Symbol, 1 } }()

typefields[ Method ] = [ :sig ]
typefields[ LambdaStaticData ] = [ :name, :module, :file, :line ]

treeTypeMaxWidth = 40
treeValueMaxWidth = 40

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
    searchText::String
    TwTreeData() = new( Dict{ Any, Bool }(), {}, 0, 0, 0, 0, 1, 1, 1, true, "", true, defaultTreeHelpText, "" )
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
    tree_data( ex, title, obj.data.datalist, obj.data.openstatemap, {} )
    updateTreeDimensions( obj )
    obj.data.showLineInfo = showLineInfo
    obj.data.showHelp = showHelp
    obj.data.bottomText = bottomText
    alignxy!( obj, h, w, x, y )
    configure_newwinpanel!( obj )
    obj
end

# x is the value, name is a pretty-print identifier
# stack is the pathway to get to x so far
# skiplines are hints where we should not draw the vertical lines to the left
# because it corresponds the end of some list at a lower depth level

function tree_data( x, name, list, openstatemap, stack, skiplines=Int[] )
    global modulenames, typefields
    isexp = haskey( openstatemap, stack ) && openstatemap[ stack ]
    typx = typeof( x )

    intern_tree_data = ( subx, subn, substack, islast )->begin
        if islast
            newskip = copy(skiplines)
            push!( newskip, length(stack) +1)
            tree_data( subx, subn, list, openstatemap, substack, newskip )
        else
            tree_data( subx, subn, list, openstatemap, substack, skiplines )
        end
    end
    if typx == Symbol || typx <: Number ||
        typx == Any || typx == DataType ||
        typx <: Ptr || typx <: String
        s = string( name )
        t = string( typx )
        if typx <: Integer && typx <: Unsigned
            v = @sprintf( "0x%x", x )
        else
            v = ensure_length( string( x ), treeValueMaxWidth, false )
        end
        push!( list, (s, t, v, stack, :single, skiplines ) )
    elseif typx == WeakRef
        s = string( name )
        t = string( typx )
        v = x.value == nothing? "<nothing>" : @sprintf( "id:0x%x", object_id( x.value ) )
        push!( list, (s, t, v, stack, :single, skiplines ) )
    elseif typx <: Array || typx <: Tuple
        s = string( name )
        if typx <: Tuple
            t = "Tuple"
        else
            t = string( typx)
        end
        len = length(x)
        szstr = string( len )
        v = "size=" * szstr
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
    elseif typx <: Dict
        s = string( name )
        t = string( typx)
        len = length(x)
        szstr = string( len )
        v = "size=" * szstr
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
    elseif typx == Function
        s = string( name )
        t = string( typx)
        mt = methods( x )
        len = length( mt )
        szstr = string( len )
        v = "num methods=" * szstr
        #v = "*"
        expandhint = len==0 ? :single : (isexp ? :open : :close )
        push!( list, (s,t,v, stack, expandhint, skiplines ))
        if isexp
            szdigits = length( szstr )
            for (i,m) in enumerate( mt )
                istr = string(i)
                subname = "Method[" * repeat( " ", szdigits - length(istr)) * istr * "]"
                newstack = copy( stack )
                push!( newstack, i )
                intern_tree_data( m, subname, newstack, i==len )
            end
        end
    elseif typx == Module && !isempty( stack ) # don't want to recursively descend
        s = string( name )
        t = string( typx )
        v = ensure_length( string( x ), treeValueMaxWidth, false )
        push!( list, (s, t, v, stack, :single, skiplines ) )
    else
        ns = Symbol[]
        if typx == Module
            if haskey( modulenames, x )
                ns = modulenames[ x ]
            else
                ns = names( x, true )
                sort!( ns )
                modulenames[ x ] = ns
            end
        else
            if haskey( typefields, typx )
                ns = typefields[ typx ]
            else
                try
                    ns = names( typx )
                    if length(ns) > 20
                        sort!(ns)
                    end
                end
                typefields[ typx ] = ns
            end
        end
        s = string( name )
        expandhint = isempty(ns) ? :single : (isexp ? :open : :close )
        t = string( typx )
        v = ensure_length( string( x ), treeValueMaxWidth, false )
        len = length(ns)
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
                    intern_tree_data( ErrorException(string(err)), subname, newstack, i==len )
                    if typx == Module
                        todel = find( y->y==n, modulenames[ x] )
                        deleteat!( modulenames[x], todel[1] )
                    else
                        todel = find( y->y==n, typefields[ typx ] )
                        deleteat!( typefields[ typx ], todel[1] )
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
    if typeof( x ) <: Array || typeof( x ) <: Dict || typeof( x ) <: Tuple
        return getvaluebypath( x[key], path )
    elseif typeof( x ) == Function
        mt = methods( x )
        for (i,m) in enumerate( mt )
            if i == key
                return getvaluebypath( m, path )
            end
        end
        return nothing
    else
        return getvaluebypath( getfield( x, key ), path )
    end
end

function updateTreeDimensions( o::TwObj )
    global treeTypeMaxWidth, treeValueMaxWidth

    o.data.datalistlen = length( o.data.datalist )
    o.data.datatreewidth = maximum( map( x->length(x[1]) + 2 +2 * length(x[4]), o.data.datalist ) )
    o.data.datatypewidth = min( treeTypeMaxWidth, max( 15, maximum( map( x->length(x[2]), o.data.datalist ) ) ) )
    o.data.datavaluewidth= min( treeValueMaxWidth, maximum( map( x->length(x[3]), o.data.datalist ) ) )
    nothing
end

function drawTwTree( o::TwObj )
    updateTreeDimensions( o )
    viewContentHeight = o.height - 2 * o.borderSizeV

    if o.box
        box( o.window, 0,0 )
    end
    if !isempty( o.title ) && o.box
        mvwprintw( o.window, 0, int( ( o.width - length(o.title) )/2 ), "%s", o.title )
    end
    if o.data.showLineInfo && o.box
        if o.data.datalistlen <= viewContentHeight
            info = "ALL"
            mvwprintw( o.window, 0, o.width - 13, "%10s", "ALL" )
        else
           info = @sprintf( "%d/%d %5.1f%%", o.data.currentLine, o.data.datalistlen,
                o.data.currentLine / o.data.datalistlen * 100 )
        end
        mvwprintw( o.window, 0, o.width - length(info)-3, "%s", info )
    end
    for r in o.data.currentTop:min( o.data.currentTop + viewContentHeight - 1, o.data.datalistlen )
        stacklen = length( o.data.datalist[r][4])
        s = ensure_length( repeat( " ", 2*stacklen + 1) * o.data.datalist[r][1], o.data.datatreewidth ) * "|"
        t = ensure_length( o.data.datalist[r][2], o.data.datatypewidth ) * "|"
        v = ensure_length( o.data.datalist[r][3], o.data.datavaluewidth, false )
        rest = t*v
        rest = rest[ chr2ind( rest, o.data.currentLeft ) : end ]
        rest = ensure_length( rest, o.width - o.borderSizeH * 2 - o.data.datatreewidth  -1, false )
        line = s * rest

        if r == o.data.currentLine
            wattron( o.window, A_BOLD | COLOR_PAIR(15) )
        end
        mvwprintw( o.window, 1+r-o.data.currentTop, 2, "%s", line )
        for i in 1:stacklen - 1
            if !in( i, o.data.datalist[r][6] ) # skiplines
                mvwaddch( o.window, 1+r-o.data.currentTop, 2*i, get_acs_val( 'x' ) ) # vertical line
            end
        end
        if stacklen != 0
            contchar = get_acs_val('t') # tee pointing right
            if r == o.data.datalistlen ||  # end of the whole thing
                length(o.data.datalist[r+1][4]) < stacklen || # next one is going back in level
                ( length(o.data.datalist[r+1][4]) > stacklen && in( stacklen, o.data.datalist[r+1][6] ) ) # going deeping in level
                contchar = get_acs_val( 'm' ) # LL corner
            end
            mvwaddch( o.window, 1+r-o.data.currentTop, 2*stacklen, contchar )
            mvwaddch( o.window, 1+r-o.data.currentTop, 2*stacklen+1, get_acs_val('q') ) # horizontal line
        end
        if o.data.datalist[r][5] == :single
            mvwaddch( o.window, 1+r-o.data.currentTop, 2*stacklen+2, get_acs_val('q') ) # horizontal line
        elseif o.data.datalist[r][5] == :close
            mvwaddch( o.window, 1+r-o.data.currentTop, 2*stacklen+2, get_acs_val('+') ) # arrow pointing right
        else
            mvwaddch( o.window, 1+r-o.data.currentTop, 2*stacklen+2, get_acs_val('w') ) # arrow pointing down
        end

        if r == o.data.currentLine
            wattroff( o.window, A_BOLD | COLOR_PAIR(15) )
        end
    end
    if length( o.data.bottomText ) != 0 && o.box
        mvwprintw( o.window, o.height-1, int( (o.width - length(o.data.bottomText))/2 ), "%s", o.data.bottomText )
    end
end

function injectTwTree( o::TwObj, token )
    dorefresh = false
    retcode = :got_it # default behavior is that we know what to do with it
    viewContentHeight = o.height - 2 * o.borderSizeV
    viewContentWidth = o.data.datatreewidth + o.data.datatypewidth+o.data.datavaluewidth + 2

    update_tree_data = ()->begin
        o.data.datalist = {}
        tree_data( o.value, o.title, o.data.datalist, o.data.openstatemap, {} )
        updateTreeDimensions(o)
        viewContentWidth = o.data.datatreewidth + o.data.datatypewidth+o.data.datavaluewidth + 2
    end

    checkTop = () -> begin
        if o.data.currentTop < 1
            o.data.currentTop = 1
        elseif o.data.currentTop > o.data.datalistlen - viewContentHeight + 1
            o.data.currentTop = o.data.datalistlen - viewContentHeight + 1
        end
        if o.data.currentTop > o.data.currentLine
            o.data.currentTop = o.data.currentLine
        elseif o.data.currentLine - o.data.currentTop > viewContentHeight-1
            o.data.currentTop = o.data.currentLine - viewContentHeight+1
        end
    end
    moveby = n -> begin
        oldline = o.data.currentLine
        o.data.currentLine = max(1, min( o.data.datalistlen, o.data.currentLine + n) )
        if oldline != o.data.currentLine
            checkTop()
            return true
        else
            beep()
            return false
        end
    end

    searchNext = (step, trivialstop)->begin # if the currentLine contains the term, is it a success?
        start = o.data.currentLine
        o.data.searchText = lowercase(o.data.searchText)
        i = trivialstop == true ? start : ( mod( start-1+step, o.data.datalistlen ) + 1 )
        while true
            if contains( lowercase( o.data.datalist[i][1]), o.data.searchText ) ||
                contains( lowercase( o.data.datalist[i][3]), o.data.searchText )
                o.data.currentLine = i
                if abs( i-start ) > viewContentHeight
                    o.data.currentTop = o.data.currentLine - (viewContentHeight>>1)
                end
                checkTop()
                return i
            end
            i = mod( i-1+step, o.data.datalistlen ) + 1
            if i == start
                beep()
                return 0
            end
        end
    end

    if token == :esc
        retcode = :exit_nothing
    elseif token == " " || token == symbol( "return" ) || token == :enter
        expandhint = o.data.datalist[ o.data.currentLine ][5]
        if expandhint != :single
            stack = o.data.datalist[ o.data.currentLine ][4]
            if !haskey( o.data.openstatemap, stack ) || !o.data.openstatemap[ stack ]
                o.data.openstatemap[ stack ] = true
            else
                o.data.openstatemap[ stack ] = false
            end
            update_tree_data()
            dorefresh = true
        end
    elseif token == "+" # the tricky part is to preserve the currentLine
        currentstack = o.data.datalist[ o.data.currentLine ][4]
        somethingchanged = false
        for i in 1:o.data.datalistlen
            expandhint = o.data.datalist[ i ][5]
            if expandhint != :single
                stack = o.data.datalist[ i ][ 4 ]
                if !haskey( o.data.openstatemap, stack ) || !o.data.openstatemap[ stack ]
                    o.data.openstatemap[ stack ] = true
                    somethingchanged = true
                end
            end
        end
        if somethingchanged
            update_tree_data()
            for i in o.data.currentLine:o.data.datalistlen
                if currentstack == o.data.datalist[ i ][4]
                    o.data.currentLine = i
                    break
                end
            end
            checkTop()
            dorefresh = true
        else
            beep()
        end
    elseif token == "-" # the tricky part is to preserve the currentLine
        currentstack = copy(o.data.datalist[ o.data.currentLine ][4])
        somethingchanged = false
        maxstackdepth = maximum( map( x->length(x[4]), o.data.datalist ) )
        if maxstackdepth > 1
            for i in 1:o.data.datalistlen
                expandhint = o.data.datalist[ i ][5]
                stack = o.data.datalist[ i ][ 4 ]
                if expandhint != :single && length(stack) == maxstackdepth-1
                    if haskey( o.data.openstatemap, stack ) && o.data.openstatemap[ stack ]
                        o.data.openstatemap[ stack ] = false
                        somethingchanged = true
                    end
                end
            end
            if somethingchanged
                update_tree_data()
                if length( currentstack ) == maxstackdepth
                    pop!( currentstack )
                end
                prevline = o.data.currentLine
                o.data.currentLine = 1
                for i in 1:min(prevline,o.data.datalistlen)
                    if currentstack == o.data.datalist[ i ][4]
                        o.data.currentLine = i
                        break
                    end
                end
                checkTop()
                dorefresh = true
            end
        else
            beep()
        end
    elseif token == "_"
        o.data.openstatemap = Dict{Any,Bool}()
        o.data.openstatemap[ {} ] = true
        o.data.currentLine = 1
        o.data.currentTop = 1
        update_tree_data()
        dorefresh = true
    elseif token == :F6
        stack = copy( o.data.datalist[ o.data.currentLine ][4] )
        if !isempty( stack )
            lastkey = stack[end]
        else
            lastkey = o.title
        end
        v = getvaluebypath( o.value, stack )
        if typeof( v ) == Method
            try
                f = eval( v.func.code.name )
                edit( f, v.sig )
                dorefresh = true
            catch err
                tshow( "Error showing Method\n" * string( err ), title=string(lastkey) )
                dorefresh = true
            end
        elseif !in( v, [ nothing, None, Any ] )
            tshow( v, title=string(lastkey) )
            dorefresh = true
        end
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
    elseif token == :ctrl_left
        if o.data.currentLeft > 1
            o.data.currentLeft = 1
            dorefresh = true
        else
            beep()
        end
    elseif token == :right
        if o.data.currentLeft + o.width - 2*o.borderSizeH < viewContentWidth
            o.data.currentLeft += 1
            dorefresh = true
        else
            beep()
        end
    elseif token == :ctrl_right
        if o.data.currentLeft + o.width - 2*o.borderSizeH < viewContentWidth
            o.data.currentLeft = viewContentWidth - o.width + 2*o.borderSizeH
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
    elseif token == "/"
        helper = newTwEntry( o.screen.value, String, 30, :center, :center, title = "Search: " )
        helper.data.inputText = o.data.searchText
        s = activateTwObj( helper )
        unregisterTwObj( o.screen.value, helper )
        if s != "" && o.data.searchText != s
            o.data.searchText = s
            searchNext( 1, true )
        end
        dorefresh = true
    elseif token == "n" || token == "p" || token == "N"
        if o.data.searchText != ""
            searchNext( (token == "n" ? 1 : -1), false )
        end
        dorefresh = true
    elseif in( token, { symbol("end") } )
        if o.data.currentTop + viewContentHeight -1 < o.data.datalistlen
            o.data.currentTop = o.data.datalistlen - viewContentHeight + 1
            o.data.currentLine = o.data.datalistlen
            dorefresh = true
        else
            beep()
        end
    elseif token == "L" # move half-way toward the end
        target = min( int(ceil((o.data.currentLine + o.data.datalistlen)/2)), o.data.datalistlen )
        if target != o.data.currentLine
            o.data.currentLine = target
            checkTop()
            dorefresh = true
        else
            beep()
        end
    elseif token == "l" # move half-way toward the beginning
        target = max( int(floor( o.data.currentLine /2)), 1)
        if target != o.data.currentLine
            o.data.currentLine = target
            checkTop()
            dorefresh = true
        else
            beep()
        end
    elseif token == :F1 && o.data.showHelp
        helper = newTwViewer( o.screen.value, o.data.helpText, :center, :center, showHelp=false, showLineInfo=false, bottomText = "Esc to continue" )
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
