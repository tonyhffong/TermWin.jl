defaultTreeHelpText = utf8("""
PgUp/PgDn,
Arrow keys : standard navigation
<spc>,<rtn>: toggle leaf expansion
Home       : jump to the start
End        : jump to the end
ctrl_arrow : jump to the start/end of the line
+, -       : expand/collapse one level
_          : collapse all
/          : search dialog
F6         : popup window for value
    Shift-F6   : popup window for type
            n, p       : Move to next/previous matched line
            m          : (Module Only) toggle export-only vs all names
""")

modulenames = Dict{ Module, Array{ Symbol, 1 } }()
moduleallnames = Dict{ Module, Array{ Symbol, 1 } }()
typefields  = Dict{ Any, Array{ Symbol, 1 } }()

typefields[ Method ] = [ :sig, :isstaged ]
typefields[ VERSION < v"0.5-" ? LambdaStaticData : LambdaInfo ] = [ :name, :module, :file, :line ]
typefields[ DataType ] = [ :name, :super, Symbol( "abstract" ), :mutable, :parameters ]
typefields[ TypeName ] = [ :name, :module, :primary ]

treeTypeMaxWidth = 30
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
    bottomText::UTF8String
    showHelp::Bool
    helpText::UTF8String
    searchText::UTF8String
    moduleall::Bool
    function TwTreeData()
        log( "TwTreeData 0")
        rv = new( Dict{ Any, Bool }(), Any[], 0, 0, 0, 0, 1, 1, 1, true,
            utf8(""), true, utf8(defaultTreeHelpText), utf8(""), true )
        log( "TwTreeData 1")
        return( rv )
    end
end

function newTwTree( scr::TwObj, ex; height::Real=0.8,width::Real=0.8,posy::Any=:staggered, posx::Any=:staggered,
        title::UTF8String = utf8( string( typeof( ex ) ) ), box::Bool=true, showLineInfo::Bool=true, showHelp::Bool=true,
        bottomText::UTF8String = utf8("") )
    log( "newTwTree 0")
    obj = TwObj( TwTreeData(), Val{ :Tree } )
    log( "newTwTree 1")
    obj.value = ex
    obj.title = title
    obj.box = box
    obj.borderSizeV= box ? 1 : 0
    obj.borderSizeH= box ? 2 : 0
    obj.data.openstatemap[ Any[] ] = true
    log( "newTwTree 2")
    tree_data( ex, title, obj.data.datalist, obj.data.openstatemap, Any[], Int[], true )
    log( "newTwTree 3")
    updateTreeDimensions( obj )
    obj.data.showLineInfo = showLineInfo
    obj.data.showHelp = showHelp
    obj.data.bottomText = bottomText

    link_parent_child( scr, obj, height,width,posy,posx )
    obj
end

# x is the value, name is a pretty-print identifier
# stack is the pathway to get to x so far
# skiplines are hints where we should not draw the vertical lines to the left
# because it corresponds the end of some list at a lower depth level

function tree_data{T}( x::Any, name::UTF8String, list::Array{T,1}, openstatemap::Dict{ Any, Bool }, stack::Array{Any,1}, skiplines::Array{Int,1}=Int[], moduleall::Bool = true )
    global modulenames, typefields
    isexp = haskey( openstatemap, stack ) && openstatemap[ stack ]
    typx = typeof( x )

    log( "tree leaf name="string(name) * " depth=" * string(length(list)) )
    intern_tree_data = ( subx, subn, substack, islast )->begin
        log( string(subn) * " type=" * string(typeof(subn)) )
        if islast
            newskip = copy(skiplines)
            push!( newskip, length(stack) +1)
            tree_data( subx, subn, list, openstatemap, substack, newskip )
        else
            tree_data( subx, subn, list, openstatemap, substack, skiplines )
        end
    end
    if typx == Symbol || typx <: Number ||
        typx == Any ||
        ( typx == DataType && !isempty( stack ) ) || # so won't expand deep
        typx <: Ptr || typx <: AbstractString
        s = string( name )
        t = string( typx )
        if typx <: Integer && typx <: Unsigned
            v = @sprintf( "0x%x", x )
        elseif typx == Symbol
            v = repr_symbol(x)
            v = ensure_length( v, treeValueMaxWidth, false )
        elseif typx <: AbstractString
            v = ensure_length( escape_string( x ), treeValueMaxWidth, false )
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
        len = length(x)
        if typx <: Tuple
            if len <= 2
                t = string( typx )
            else
                t = "Tuple"
            end
        else
            t = string( typx)
        end
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
                intern_tree_data( a, utf8(subname), newstack, i==len )
            end
        end
    elseif typx <: Associative
        s = string( name )
        t = string( typx)
        len = length(x)
        szstr = string( len )
        v = "size=" * szstr
        expandhint = isempty(x) ? :single : (isexp ? :open : :close )
        push!( list, (s,t,v, stack, expandhint, skiplines ))
        if isexp
            ktype = eltype(typx).parameters[1]
            ks = collect( keys( x ) )
            if ktype <: Real || ktype <: AbstractString || ktype == Symbol
                sort!(ks)
            end
            for (i,k) in enumerate( ks )
                v = x[k]
                if ktype == Symbol
                    subname = repr_symbol( k )
                else
                    subname = repr( k )
                end
                newstack = copy( stack )
                push!( newstack, k )
                intern_tree_data( v, utf8(subname), newstack, i==len )
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
                intern_tree_data( m, utf8(subname), newstack, i==len )
            end
        end
    elseif typx == Module && !isempty( stack ) # don't want to recursively descend
        s = string( name )
        t = string( typx )
        v = ensure_length( string( x ), treeValueMaxWidth, false )
        push!( list, (s, t, v, stack, :single, skiplines ) )
    else
        log( "  " * string( typx) )
        ns = Symbol[]
        if typx == Module
            if moduleall
                if haskey( moduleallnames, x )
                    ns = moduleallnames[ x ]
                else
                    ns = filter( y->!startswith( string(y), "@" ), names( x, true ) )
                    sort!( ns )
                    moduleallnames[ x ] = ns
                end
            else
                if haskey( modulenames, x )
                    ns = modulenames[ x ]
                else
                    ns = filter( y->!startswith( string(y), "@" ), names( x ) )
                    sort!( ns )
                    modulenames[ x ] = ns
                end
            end
        else
            if haskey( typefields, typx )
                ns = typefields[ typx ]
            else
                try
                    ns = fieldnames( typx )
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
                subname = utf8(string(n))
                newstack = copy( stack )
                push!( newstack, n )
                try
                    v = getfield(x,n)
                    intern_tree_data( v, subname, newstack, i==len )
                catch err
                    @lintpragma( "Ignore unthrown ErrorException" )
                    intern_tree_data( ErrorException(string(err)), subname, newstack, i==len )
                    if typx == Module
                        if moduleall
                            todel = find( y->y==n, moduleallnames[ x] )
                            deleteat!( moduleallnames[x], todel[1] )
                        else
                            todel = find( y->y==n, modulenames[ x] )
                            deleteat!( modulenames[x], todel[1] )
                        end
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
    if typeof( x ) <: Array || typeof( x ) <: Associative || typeof( x ) <: Tuple
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
    o.data.datatreewidth = maximum( map( x->length(x[1]) + 1 +2 * length(x[4]), o.data.datalist ) )
    o.data.datatypewidth = min( treeTypeMaxWidth, max( 15, maximum( map( x->length(x[2]), o.data.datalist ) ) ) )
    o.data.datavaluewidth= min( treeValueMaxWidth, maximum( map( x->length(x[3]), o.data.datalist ) ) )
    nothing
end

function draw( o::TwObj{TwTreeData} )
    updateTreeDimensions( o )
    viewContentHeight = o.height - 2 * o.borderSizeV
    viewContentWidth = o.width - 2 * o.borderSizeV

    if o.box
        box( o.window, 0,0 )
    end
    if !isempty( o.title ) && o.box
        titlestr = o.title
        if typeof( o.value ) == Module
            if o.data.moduleall
                titlestr *= "(all names)"
            else
                titlestr *= "(exported )"
            end
        end
        mvwprintw( o.window, 0, (@compat round(Int,( o.width - length(titlestr) )/2 )), "%s", titlestr )
    end
    if o.data.showLineInfo && o.box
        if o.data.datalistlen <= viewContentHeight
            msg = "ALL"
        else
            msg = @sprintf( "%d/%d %5.1f%%", o.data.currentLine, o.data.datalistlen,
                o.data.currentLine / o.data.datalistlen * 100 )
        end
        mvwprintw( o.window, 0, o.width - length(msg)-3, "%s", msg )
    end
    for r in o.data.currentTop:min( o.data.currentTop + viewContentHeight - 1, o.data.datalistlen )
        stacklen = length( o.data.datalist[r][4])
        s = ensure_length( repeat( " ", 2*stacklen + 1) * o.data.datalist[r][1], o.data.datatreewidth )
        t = ensure_length( o.data.datalist[r][2], o.data.datatypewidth )
        log( o.data.datalist[r][1] )
        log( o.data.datalist[r][3] )
        v = ensure_length( o.data.datalist[r][3], viewContentWidth-o.data.datatreewidth- o.data.datatypewidth-3, false )

        if r == o.data.currentLine
            wattron( o.window, A_BOLD | COLOR_PAIR( o.hasFocus ? 15 : 30 ) )
        end
        mvwprintw( o.window, 1+r-o.data.currentTop, 2, "%s", s )
        mvwaddch( o.window, 1+r-o.data.currentTop, 2+o.data.datatreewidth, get_acs_val( 'x' ) )
        mvwprintw( o.window, 1+r-o.data.currentTop, 2+o.data.datatreewidth+1, "%s", t )
        mvwaddch( o.window, 1+r-o.data.currentTop, 2+o.data.datatreewidth+o.data.datatypewidth+1, get_acs_val( 'x' ) )
        mvwprintw( o.window, 1+r-o.data.currentTop, 2+o.data.datatreewidth+o.data.datatypewidth+2, "%s", v )

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
        if o.data.datalist[r][5] == :close
            mvwprintw( o.window, 1+r-o.data.currentTop, 2*stacklen+2, "%s", string( @compat Char( 0x25b8 ) ) ) # right-pointing small triangle
        elseif o.data.datalist[r][5] == :open
            mvwprintw( o.window, 1+r-o.data.currentTop, 2*stacklen+2, "%s", string( @compat Char( 0x25be ) ) ) # down-pointing small triangle
        end

        if r == o.data.currentLine
            wattroff( o.window, A_BOLD | COLOR_PAIR( o.hasFocus ? 15 : 30 ) )
        end
    end
    if length( o.data.bottomText ) != 0 && o.box
        mvwprintw( o.window, o.height-1, (@compat round(Int, (o.width - length(o.data.bottomText))/2 )), "%s", o.data.bottomText )
    end
end

function inject( o::TwObj{TwTreeData}, token )
    dorefresh = false
    retcode = :got_it # default behavior is that we know what to do with it
    viewContentHeight = o.height - 2 * o.borderSizeV
    viewContentWidth = o.data.datatreewidth + o.data.datatypewidth+o.data.datavaluewidth + 2

    update_tree_data = ()->begin
        o.data.datalist = Any[]
        tree_data( o.value, utf8(o.title), o.data.datalist, o.data.openstatemap, Any[], Int[], o.data.moduleall )
        updateTreeDimensions(o)
        viewContentWidth = o.data.datatreewidth + o.data.datatypewidth+o.data.datavaluewidth + 2
    end

    checkTop = () -> begin
        if o.data.currentTop < 1
            o.data.currentTop = 1
        elseif o.data.currentTop > o.data.datalistlen - viewContentHeight + 1
            o.data.currentTop = max(1,o.data.datalistlen - viewContentHeight + 1)
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
        local st = o.data.currentLine
        o.data.searchText = lowercase(o.data.searchText)
        i = trivialstop ? st : ( mod( st-1+step, o.data.datalistlen ) + 1 )
        while true
            if contains( lowercase( o.data.datalist[i][1]), o.data.searchText ) ||
                contains( lowercase( o.data.datalist[i][3]), o.data.searchText )
                o.data.currentLine = i
                if abs( i-st ) > viewContentHeight
                    o.data.currentTop = o.data.currentLine - (viewContentHeight>>1)
                end
                checkTop()
                return i
            end
            i = mod( i-1+step, o.data.datalistlen ) + 1
            if i == st
                beep()
                return 0
            end
        end
    end

    if token == :esc
        retcode = :exit_nothing
    elseif token == " " || token == Symbol( "return" ) || token == :enter
        expandhint = o.data.datalist[ o.data.currentLine ][5]
        if expandhint != :single
            stck = o.data.datalist[ o.data.currentLine ][4]
            if !haskey( o.data.openstatemap, stck ) || !o.data.openstatemap[ stck ]
                o.data.openstatemap[ stck ] = true
            else
                o.data.openstatemap[ stck ] = false
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
                stck = o.data.datalist[ i ][ 4 ]
                if !haskey( o.data.openstatemap, stck ) || !o.data.openstatemap[ stck ]
                    o.data.openstatemap[ stck ] = true
                    somethingchanged = true
                end
            end
        end
        if somethingchanged
            prevline = o.data.currentLine
            update_tree_data()
            for i in o.data.currentLine:o.data.datalistlen
                if currentstack == o.data.datalist[ i ][4]
                    o.data.currentLine = i
                    if abs( i - prevline ) > viewContentHeight
                        o.data.currentTop = i - @compat round(Int,viewContentHeight/2)
                    end
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
                stck = o.data.datalist[ i ][ 4 ]
                if expandhint != :single && length(stck) == maxstackdepth-1
                    if haskey( o.data.openstatemap, stck ) && o.data.openstatemap[ stck ]
                        o.data.openstatemap[ stck ] = false
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
                        if abs( i-prevline ) > viewContentHeight
                            o.data.currentTop = i - @compat round(Int,viewContentHeight / 2)
                        end
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
        currentstack = copy(o.data.datalist[ o.data.currentLine ][4])
        if length( currentstack ) > 1
            currentstack = Any[ currentstack[1] ]
        end
        o.data.openstatemap = Dict{Any,Bool}()
        o.data.openstatemap[ Any[] ] = true
        update_tree_data()
        prevline = o.data.currentLine
        o.data.currentLine = 1
        for i in 1:min(prevline,o.data.datalistlen)
            if currentstack == o.data.datalist[ i ][4]
                o.data.currentLine = i
                if abs( i-prevline ) > viewContentHeight
                    o.data.currentTop = o.data.currentLine - @compat round(Int,viewContentHeight / 2)
                end
                break
            end
        end
        checkTop()
        dorefresh = true
    elseif token == "m" && typeof( o.value ) == Module
        o.data.moduleall = !o.data.moduleall
        prevstack = copy( o.data.datalist[ o.data.currentLine ][4] )
        update_tree_data()
        maxmatch = 0
        bestline = 0
        for i in 1:o.data.datalistlen
            stck = o.data.datalist[i][4]
            if length( prevstack ) > maxmatch && length( stck )> maxmatch &&
                isequal( prevstack[1:maxmatch+1], stck[1:maxmatch+1] )
                maxmatch += 1
                bestline = i
                continue
            elseif length( prevstack ) < maxmatch
                break
            elseif length( prevstack ) >= maxmatch && length( stck ) >= maxmatch &&
                !isequal( prevstack[1:maxmatch], stck[1:maxmatch] )
                break
            end
        end
        o.data.currentLine = max( 1, bestline )
        checkTop()
        dorefresh = true
    elseif token == :F6
        stck = copy( o.data.datalist[ o.data.currentLine ][4] )
        if !isempty( stck )
            lastkey = stck[end]
        else
            lastkey = o.title
        end
        v = getvaluebypath( o.value, stck )
        if typeof( v ) == Method
            try
                f = eval( v.func.code.name )
                edit( f, v.sig )
                dorefresh = true
            catch err
                tshow( "Error showing Method\n" * string( err ), title=string(lastkey) )
                dorefresh = true
            end
        elseif !in( v, [ nothing, Void, Any ] )
            tshow( v, title=string(lastkey) )
            dorefresh = true
        end
    elseif token == :shift_F6
        stck = copy( o.data.datalist[ o.data.currentLine ][4] )
        if !isempty( stck )
            lastkey = stck[end]
        else
            lastkey = o.title
        end
        v = getvaluebypath( o.value, stck )
        vtyp = typeof( v )
        if !in( v, [ nothing, Void, Any ] )
            tshow( vtyp )
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
            dorefresh = moveby( -(@compat round(Int, viewContentHeight/5 ) ))
        elseif mstate == :scroll_down
            dorefresh = moveby( @compat round(Int, viewContentHeight/5 ) )
        elseif mstate == :button1_pressed
            begy,begx = getwinbegyx( o.window )
            relx = x - begx
            rely = y - begy
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
    elseif token == "/"
        helper = newTwEntry( o.screen.value, UTF8String; width=30, posy=:center, posx=:center, title = "Search: " )
        helper.data.inputText = o.data.searchText
        s = activateTwObj( helper )
        unregisterTwObj( o.screen.value, helper )
        if s != nothing
            if s != "" && o.data.searchText != s
                o.data.searchText = s
                searchNext( 1, true )
            end
        end
        dorefresh = true
    elseif token == "n" || token == "p" || token == "N" || token == :ctrl_n || token == :ctrl_p
        if o.data.searchText != ""
            searchNext( ( (token == "n" || token == :ctrl_n ) ? 1 : -1), false )
        end
        dorefresh = true
    elseif in( token, Any[ Symbol("end") ] )
        if o.data.currentTop + viewContentHeight -1 < o.data.datalistlen
            o.data.currentTop = o.data.datalistlen - viewContentHeight + 1
            o.data.currentLine = o.data.datalistlen
            dorefresh = true
        else
            beep()
        end
    elseif token == "L" # move half-way toward the end
        target = min( (@compat round(Int, ceil((o.data.currentLine + o.data.datalistlen)/2))), o.data.datalistlen )
        if target != o.data.currentLine
            o.data.currentLine = target
            checkTop()
            dorefresh = true
        else
            beep()
        end
    elseif token == "l" # move half-way toward the beginning
        target = max( (@compat round(Int,floor( o.data.currentLine /2))), 1)
        if target != o.data.currentLine
            o.data.currentLine = target
            checkTop()
            dorefresh = true
        else
            beep()
        end
    else
        retcode = :pass # I don't know what to do with it
    end

    if dorefresh
        refresh(o)
    end

    return retcode
end

function helptext( o::TwObj{TwTreeData} )
    if o.data.showHelp
        o.data.helpText
    else
        utf8("")
    end
end
