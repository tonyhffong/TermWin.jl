function tree_data( x, name, list, openstatemap, stack )
    isexp = haskey( openstatemap, stack ) && openstatemap[ stack ]

    if typeof( x ) == Expr
        s = " " * (isexp? "+" : "=")* string( name )
        t = string( typeof( x) )
        v = string( x )
        if length( v ) > 25
            v = string( SubString( v, 1, 23 ) ) * ".."
        end
        push!( list, (s, t, v, stack ) )
        if isexp
            for f in [ :head, :args, :typ ]
                newstack = copy( stack )
                push!( newstack, f )
                tree_data( getfield( x, f ), f, list, openstatemap, newstack)
            end
        end
    elseif typeof( x ) == Symbol || typeof( x ) <: Number || typeof( x ) == Any
        s = " +" * string( name )
        t = string( typeof( x) )
        v = string( x )
        if length( v ) > 25
            v = string( SubString( v, 1, 23 ) ) * ".."
        end
        push!( list, (s, t, v, stack ) )
    elseif typeof( x ) <: String
        s = " +" * string( name )
        t = string( typeof( x) )
        if length( x ) > 25
            v = string( SubString( x, 1, 23 ) ) * ".."
        else
            v = string( x )
        end
        push!( list, (s, t, v, stack ) )
    elseif typeof( x ) <: Array
        s = " " * ( isexp ? "+" : "=" ) * string( name )
        t = string( typeof( x ))
        szstr = string( length( x ) )
        v = "Size=" * szstr
        push!( list, (s,t,v, stack ))
        if isexp
            szdigits = length( szstr )
            for (i,a) in enumerate( x )
                istr = string(i)
                subname = "[" * repeat( " ", szdigits - length(istr)) * istr * "]"
                newstack = copy( stack )
                push!( newstack, i )
                tree_data( a, subname, list, openstatemap, newstack )
            end
        end
    elseif typeof( x ) <: Dict
        s = " " * ( isexp ? "+" : "=" ) * string( name )
        t = string( typeof( x ))
        szstr = string( length( x ) )
        v = "Size=" * szstr
        push!( list, (s,t,v, stack ))
        if isexp
            for (k,v) in x
                subname = repr( k )
                newstack = copy( stack )
                push!( newstack, k )
                tree_data( v, subname, list, openstatemap, newstack )
            end
        end
    elseif typeof( x ) == Function
        s = " +" * string( name )
        t = string( typeof( x) )
        if length( string(x) ) > 25
            v = string( SubString( x, 1, 23 ) ) * ".."
        else
            v = string( x )
        end
        push!( list, (s, t, v, stack ) )
    else
        ns = Symbol[]
        if typeof(x) == Module
            ns = names( x, true )
        else
            try
                ns = names( x )
            end
        end
        sort!(ns)
        s = " " * (isempty(ns) || isexp ? "+" : "=") * string( name )
        t = string( typeof( x) )
        v = string( x )
        if length( v ) > 25
            v = string( SubString( v, 1, 23 ) ) * ".."
        end
        push!( list, (s, t, v, stack ) )
        if isexp && !isempty( ns )
            for n in ns
                subname = n
                newstack = copy( stack )
                push!( newstack, n )
                try
                    v = getfield( x, n )
                    tree_data( getfield( x, n ), subname, list, openstatemap, newstack )
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

tshow_( x::Symbol; title="Symbol" ) = tshow_( ":"*string(x), title=title )
function tshow_( x::Function; title="Function" )
    funloc = "(anonymous)"
    try
        funloc = string( functionloc( x ) )
    end
    tshow_( string(x) * ":" * funloc, title=title )
end
tshow_( x::Ptr; title="Ptr" ) = tshow_( string(x), title=title )
tshow_( x; title=string(typeof(x)) ) = tshow_tree( x, title=title )

function tshow_tree( ex; title = string(typeof( ex ) ) )
    global rootwin, A_BOLD
    needy = needx = needxs = needxt = needxv = maxy= maxx= height= width= 0
    datalist = {}

    openstatemap = Dict{ Any, Bool }()
    openstatemap[ {} ] = true
    tree_data( ex, title, datalist, openstatemap, {} )

    update_dimensions = ()-> begin
        needy = length(datalist)
        needxs = maximum( map( x->length(x[1]) + 2 * length(x[4]) , datalist ) )
        needxt = max( 15, maximum( map( x->length(x[2]), datalist ) ) )
        needxv = min( 25, maximum( map( x->length(x[3]), datalist ) ) )
        needx = needxs + needxt + needxv
        (maxy, maxx) = getwinmaxyx( rootwin )
        height=min( maxy, max( 20, min( maxy-2, needy )+2 ) ) # including the borders
        width =min( maxx, max( 50, min( maxx-4, needx+2 )+4 ) ) # including the borders
    end

    update_dimensions()

    win = winnewcenter( height, width )
    panel = new_panel( win )

    currentTop = 1
    currentLeft = 1
    currentLine = 1

    redrawviewer = ()->begin
        werase( win )
        box( win, 0, 0 )
        height, width = getwinmaxyx( win )
        npushed = 0
        for r in currentTop:min(currentTop+height-3, needy)
            s = repeat( " |", length( datalist[ r][4] )) * datalist[r][1]
            s *= repeat( " ", max(0,needxs - length(s)) ) * "|"
            t =  @sprintf( "%-15s|", datalist[r][2] )
            v = datalist[r][3]
            line = string( SubString( s*t*v, currentLeft, currentLeft + width - 5 ) )

            if r == currentLine
                wattron( win, A_BOLD )
            end
            mvwprintw( win, 1 + r-currentTop, 2, "%s", line )
            if r == currentLine
                wattroff( win, A_BOLD )
            end
            npushed += length(line)
            if npushed > 200
                refresh()
                wrefresh( win )
                #update_panels()
                #doupdate()
                npushed = 0
            end
        end
        if needy <= height-2
            mvwprintw( win, 0, width-13, "%10s", "ALL" )
        else
            mvwprintw( win, 0, width-13, "%10s", @sprintf( "%9.2f%%", currentLine / needy * 100.0 ) )
        end
        s = "F1:Help  Spc:Expand  Esc:exit"
        mvwprintw( win, height-1, int((width-length(s))/2), "%s", s )
        update_panels()
        doupdate()
    end

    redrawviewer()
    token = 0
    checkTop = () -> begin
        if currentTop > currentLine
            currentTop = currentLine
        elseif height-3 < currentLine - currentTop
            currentTop = currentLine - height + 3
        end
    end

    rebuildwindow = ()->begin
        datalist = {}
        tree_data( ex, title, datalist, openstatemap, {} )
        local hold = height
        local wold = width
        wclear( win )
        wrefresh( win )
        update_dimensions()
        if hold != height || wold != width
            wresize( win, height, width )
            move_panel( panel, int(floor( (maxy-height)/2)), int( floor( (maxx-width)/2)))
        end
    end

    while( (token = readtoken()) != :esc )
        dorefresh = false
        if token == " " || token == symbol( "return" )
            stack = datalist[ currentLine ][4]
            if !haskey( openstatemap, stack ) || !openstatemap[ stack ]
                openstatemap[ stack ] = true
            else
                openstatemap[ stack ] = false
            end
            rebuildwindow()
            dorefresh = true
        elseif token == :F6
            stack = copy( datalist[ currentLine ][4] )
            if !isempty( stack )
                lastkey = stack[end]
            else
                lastkey = title
            end
            v = getvaluebypath( ex, stack )
            if !in( v, [ nothing, None, Any ] )
                tshow_( v, title=string(lastkey) )
                dorefresh = true
            end
        elseif token == "-"
            openstatemap = Dict{Any,Bool}()
            openstatemap[ {} ] = true
            currentLine = 1
            currentTop = 1
            rebuildwindow()
            dorefresh = true
        elseif token == :up
            if currentLine > 1
                currentLine -= 1
                dorefresh = true
                checkTop()
            else
                flash()
            end
        elseif token == :down
            if currentLine < needy
                currentLine += 1
                dorefresh= true
                checkTop()
            else
                flash()
            end
        elseif token == :left
            if currentLeft > 1
                currentLeft -= 1
                dorefresh = true
            else
                flash()
            end
        elseif token == :right
            if currentLeft + width-4 < needx
                currentLeft += 1
                dorefresh = true
            else
                flash()
            end
        elseif token == :pageup
            if currentLine > 1
                currentLine = max( 1, currentLine - (height-2) )
                checkTop()
                dorefresh = true
            else
                flash()
            end
        elseif token == :pagedown
            if currentLine < needy
                currentLine = min( needy, currentLine + height - 2 )
                dorefresh= true
            else
                flash()
            end
            checkTop()
        elseif  token == :home
            if currentTop != 1 || currentLeft != 1 || currentLine != 1
                currentTop = 1
                currentLine = 1
                currentLeft = 1
                dorefresh = true
            else
                flash()
            end
        elseif in( token, [ "<", "0", "g" ] )
            if currentTop != 1 || currentLine != 1
                currentTop = 1
                currentLine = 1
                dorefresh = true
            else
                flash()
            end
        elseif in( token, { ">", "G", symbol("end" ) } )
            if currentLine != needy
                currentLine = needy
                dorefresh = true
                checkTop()
            else
                flash()
            end
        elseif token == "L" # move half-way toward the end
            target = min( int(ceil((currentTop + needy)/2)), needy )
            if target != currentLine
                currentLine = target
                checkTop()
                dorefresh = true
            else
                flash()
            end
        elseif token == "l" # move half-way toward the beginning
            target = max( int(floor( currentLine /2)), 1)
            if target != currentLine
                currentLine = target
                checkTop()
                dorefresh = true
            else
                flash()
            end
        elseif token == :F1
            tshow_(
            """
PgUp/PgDn,
Arrow keys : standard navigation
<spc>,<rtn>: toggle leaf expansion
F6         : popup window for value
-          : collapse all
l          : move halfway toward the start
L          : move halfway to the end
<,0,g      : jump to the start
>, G       : jump to the end
            """, title = "Help", showprogress= false, showkeyhelper=false
            )
            dorefresh = true
        elseif token == :KEY_RESIZE || is_term_resized( maxy, maxx )
            update_dimensions()
            wresize( win, height, width )
            dorefresh = true
            #TODO search, jump to line, etc.
        end

        if dorefresh
            redrawviewer()
        end
    end
    del_panel( panel )
    delwin( win )
end
