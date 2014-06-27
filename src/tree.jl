modulenames = Dict{ Module, Array{ Symbol, 1 } }()
typefields  = Dict{ Any, Array{ Symbol, 1 } }()

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
        push!( list, (s,t,v, stack, (isexp? :open : :close), skiplines ))
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
        push!( list, (s,t,v, stack, (isexp ? :open : :close), skiplines ))
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
    elseif typeof( x ) == Function
        s = string( name )
        t = string( typeof( x) )
        if length( string(x) ) > 25
            v = string( SubString( x, 1, 23 ) ) * ".."
        else
            v = string( x )
        end
        push!( list, (s, t, v, stack, :single, skiplines ) )
    else
        ns = Symbol[]
        if typeof(x) == Module
            if haskey( modulenames, x )
                ns = modulenames[ x ]
            else
                ns = names( x, true )
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
                    println(err)
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

    update_tree_data = ()-> begin
        datalist = {}
        tree_data( ex, title, datalist, openstatemap, {} )
        needy = length(datalist)
        needxs = maximum( map( x->length(x[1]) + 2 +2 * length(x[4]), datalist ) )
        needxt = max( 15, maximum( map( x->length(x[2]), datalist ) ) )
        needxv = min( 25, maximum( map( x->length(x[3]), datalist ) ) )
        needx = needxs + needxt + needxv
    end

    update_tree_data()

    update_dimensions = ()-> begin
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
        for r in currentTop:min(currentTop+height-3, needy)
            stacklen = length( datalist[r][4])
            s = repeat( " ", 2*stacklen + 1) * datalist[r][1]
            s *= repeat( " ", max(0,needxs - length(s)) ) * "|"
            t =  datalist[r][2]
            t *= repeat( " ", max( 0, needxt - length(t))) * "|"
            v = datalist[r][3]
            line = string( SubString( s*t*v, currentLeft, currentLeft + width - 5 ) )

            if r == currentLine
                wattron( win, A_BOLD )
            end
            mvwprintw( win, 1+r-currentTop, 2, "%s", line )
            for i in 1:stacklen - 1
                if !in( i, datalist[r][6] ) # skiplines
                    mvwaddch( win, 1+r-currentTop, 2*i, get_acs_val( 'x' ) ) # vertical line
                end
            end
            if stacklen != 0
                contchar = get_acs_val('t') # tee pointing right
                if r == length( datalist ) ||  # end of the whole thing
                    length(datalist[r+1][4]) < stacklen || # next one is going back in level
                    ( length(datalist[r+1][4]) > stacklen && in( stacklen, datalist[r+1][6] ) ) # going deeping in level
                    contchar = get_acs_val( 'm' ) # LL corner
                end
                mvwaddch( win, 1+r-currentTop, 2*stacklen, contchar )
                mvwaddch( win, 1+r-currentTop, 2*stacklen+1, get_acs_val('q') ) # horizontal line
            end
            if datalist[r][5] == :single
                mvwaddch( win, 1+r-currentTop, 2*stacklen+2, get_acs_val('q') ) # horizontal line
            elseif datalist[r][5] == :close
                mvwaddch( win, 1+r-currentTop, 2*stacklen+2, get_acs_val('+') ) # arrow pointing right
            else
                mvwaddch( win, 1+r-currentTop, 2*stacklen+2, get_acs_val('w') ) # arrow pointing down
            end

            if r == currentLine
                wattroff( win, A_BOLD )
            end
        end
        if needy <= height-2
            mvwprintw( win, 0, width-13, "%10s", "ALL" )
        else
            mvwprintw( win, 0, width-13, "%10s", @sprintf( "%9.2f%%", currentLine / needy * 100.0 ) )
        end
        s = "F1:Help  Spc:Expand  Esc:exit"
        mvwprintw( win, height-1, 3, "%s", s )
        #update_panels()
        #doupdate()
    end

    redrawviewer()
    token = 0
    checkTop = () -> begin
        if currentTop > currentLine
            currentTop = currentLine
        elseif height-3 < currentLine - currentTop # if they are too far apart
            currentTop = currentLine - height + 3
        end
    end

    rebuildwindow = ()->begin
        local hold = height
        local wold = width
        local maxyold = maxy
        local maxxold = maxx
        #=
        from HOWTO:
        Resizing a panel is slightly complex. There is no straight forward function just to resize 
        the window associated with a panel. A solution to resize a panel is to create a new 
        window with the desired sizes, change the window associated with the panel using 
        replace_panel(). Don't forget to delete the old window. The window associated with a 
        panel can be found by using the function panel_window().

        Some testing shows it's a segfault magnet...

        From man page:
          replace_panel(pan,window)
              replaces the current window of panel with window (useful, for  example  if
              you  want  to  resize  a  panel;  if  you're  using  ncurses, you can call
              replace_panel on the output of wresize(3X)).  It does not change the posi-
              tion of the panel in the stack.
        =#

        update_dimensions()
        if hold != height || wold != width
            move_panel( panel, int(floor( (maxy-height-1)/2)), int( floor( (maxx-width-1)/2)))
            wclear( win )
            wrefresh( win )
            wresize( win, height, width )
            replace_panel( panel, win )
            checkTop()
            #update_panels()
            #doupdate()
        elseif maxyold != maxy || maxxold != maxx
            move_panel( panel, int(floor( (maxy-height-1)/2)), int( floor( (maxx-width-1)/2)))
            checkTop()
            #update_panels()
            #doupdate()
        end
    end

    while( (token = readtoken( win )) != :esc )
        dorefresh = false
        if token == " " || token == symbol( "return" ) || token == :enter
            stack = datalist[ currentLine ][4]
            if !haskey( openstatemap, stack ) || !openstatemap[ stack ]
                openstatemap[ stack ] = true
            else
                openstatemap[ stack ] = false
            end
            update_tree_data()
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
            update_tree_data()
            rebuildwindow()
            dorefresh = true
        elseif token == :up
            if currentLine > 1
                currentLine -= 1
                dorefresh = true
                checkTop()
            else
                beep()
            end
        elseif token == :down
            if currentLine < needy
                currentLine += 1
                dorefresh= true
                checkTop()
            else
                beep()
            end
        elseif token == :left
            if currentLeft > 1
                currentLeft -= 1
                dorefresh = true
            else
                beep()
            end
        elseif token == :right
            if currentLeft + width-4 < needx
                currentLeft += 1
                dorefresh = true
            else
                beep()
            end
        elseif token == :pageup
            if currentLine > 1
                currentLine = max( 1, currentLine - (height-2) )
                checkTop()
                dorefresh = true
            else
                beep()
            end
        elseif token == :pagedown
            if currentLine < needy
                currentLine = min( needy, currentLine + height - 2 )
                dorefresh= true
            else
                beep()
            end
            checkTop()
        elseif  token == :home
            if currentTop != 1 || currentLeft != 1 || currentLine != 1
                currentTop = 1
                currentLine = 1
                currentLeft = 1
                dorefresh = true
            else
                beep()
            end
        elseif in( token, [ "<", "0", "g" ] )
            if currentTop != 1 || currentLine != 1
                currentTop = 1
                currentLine = 1
                dorefresh = true
            else
                beep()
            end
        elseif in( token, { ">", "G", symbol("end" ) } )
            if currentLine != needy
                currentLine = needy
                dorefresh = true
                checkTop()
            else
                beep()
            end
        elseif token == "L" # move half-way toward the end
            target = min( int(ceil((currentTop + needy)/2)), needy )
            if target != currentLine
                currentLine = target
                checkTop()
                dorefresh = true
            else
                beep()
            end
        elseif token == "l" # move half-way toward the beginning
            target = max( int(floor( currentLine /2)), 1)
            if target != currentLine
                currentLine = target
                checkTop()
                dorefresh = true
            else
                beep()
            end
        elseif token == :ctrl_r
            wclear( win )
            dorefresh = true
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
            rebuildwindow()
            dorefresh = true
            #TODO search, jump to line, etc.
        end

        if dorefresh
            redrawviewer()
        end
        ct = strftime( "%H:%M:%S", time() )
        mvwprintw( win, height-1, width-10, "%s", ct )
        update_panels()
        doupdate()
    end
    del_panel( panel )
    delwin( win )
end
