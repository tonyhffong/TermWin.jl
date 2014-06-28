# edit distance on signatures
function levenstein_distance( s1, s2 )
    if s1==s2
        return 0
    end
    if length(s1)==0
        return length(s2)
    end
    if length(s2)==0
        return length(s1)
    end

    v0 = [0:length(s2)]
    v1 = Array( Int, length(s2)+1)
    for (i,c1) in enumerate(s1)
        v1[1] = i
        for (j,c2) in enumerate( s2 )
            cost = ( c1 == c2 ) ? 0 : 1
            v1[j+1] = min( v1[j] + 1, v0[ j+1 ] + 1, v0[j]+cost )
        end

        for j in 1:length( v0 )
            v0[j]=v1[j]
        end
    end
    return v1[end]
end

function tshow_( f::Function; title="Function" )
    funloc = "(anonymous)"
    try
        funloc = string( functionloc( f ) )
    end
    if funloc == "(anonymous)"
        tshow_( string(f) * ":" * funloc, title=title )
        return
    end
    tshow_( methods( f ), title=title )
end

function tshow_( mt::MethodTable; title="MethodTable" )
    ms = Method[]
    d = start(mt)
    while !is(d,())
        push!( ms, d )
        d = d.next
    end
    tshow_methods( ms, title = title )
end

function tshow_methods( ms::Array{ Method, 1 }; title = "Methods" )
    datalist = {}
    for d in ms
        s = string(d.sig)*" : " * string(d)
        push!( datalist, { lowercase(s), s, d, 0.0 } )
    end

    global rootwin, A_BOLD
    needy = needx= maxy = maxx= height= width= 0
    lastsearchterm = ""
    searchterm = ""
    filterlist = {}
    needy = length( datalist )
    needx = maximum( map( x->length( x[2] ), datalist ) )

    update_score_sort = ()-> begin
        for row in datalist
            if length( searchterm ) == 0
                row[4] = 0.0
            else
                ld = levenstein_distance( lowercase( searchterm ), row[1] )
                l1 = length(searchterm)
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
        sort!( datalist, lt=(x,y)-> x[4] < y[4] )
    end

    update_dimensions = ()-> begin
        (maxy, maxx) = getwinmaxyx( rootwin )
        height = maxy
        width = maxx
        #height=min( maxy, max( 20, min( maxy-2, needy )+2 ) ) # including the borders
        #width =min( maxx, max( 50, min( maxx-4, needx+2 )+4 ) ) # including the borders
    end

    update_dimensions()

    #win = winnewcenter( height, width )
    win = rootwin
    #panel = new_panel( win )

    currentTop = 1
    currentLeft = 1
    currentLine = 1

    redrawviewer = ()->begin
        werase( win )
        box( win, 0, 0 )
        for r in currentTop:min(currentTop+height-3, length( datalist ) )
            line = datalist[r][2]
            line = string( SubString( line, currentLeft, currentLeft + width - 5 ) )

            if r == currentLine
                wattron( win, A_BOLD )
            end
            mvwprintw( win, 1+r-currentTop, 2, "%s", line )
            if r == currentLine
                wattroff( win, A_BOLD )
            end
        end
        mvwprintw( win, 0, 3, "Search Term: %s", searchterm )
        if needy <= height-2
            mvwprintw( win, 0, width-13, "%10s", "ALL" )
        else
            mvwprintw( win, 0, width-13, "%10s", @sprintf( "%9.2f%%", currentLine / needy * 100.0 ) )
        end
        s = "F1:Help  F6:explore  F7:edit  Esc:exit"
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
            #move_panel( panel, int(floor( (maxy-height-1)/2)), int( floor( (maxx-width)/2)))
            wclear( win )
            wrefresh( win )
            wresize( win, height, width )
            #replace_panel( panel, win )
            checkTop()
            #update_panels()
            #doupdate()
        elseif maxyold != maxy || maxxold != maxx
            wclear( win )
            touchwin( win )
            #move_panel( panel, int(floor( (maxy-height)/2)), int( floor( (maxx-width)/2)))
            checkTop()
            #update_panels()
            #doupdate()
        end
    end

    while( (token = readtoken( win )) != :esc )
        dorefresh = false
        if token == :F6
            m = datalist[currentLine][3]
            tshow_tree( m, title = string( m.func.code.name ))
            dorefresh = true
        elseif token == :F8
            m = datalist[currentLine][3]
            f = eval( m.func.code.name )
            edit( f, m.sig )
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
        elseif token == :ctrl_left
            if currentLeft > 1
                currentLeft = 1
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
        elseif token == :ctrl_right
            if currentLeft + width-4 < needx
                currentLeft = needx - width + 4
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
        elseif token == symbol("end" )
            if currentLine != needy
                currentLine = needy
                dorefresh = true
                checkTop()
            else
                beep()
            end
        elseif token == :ctrl_r
            wclear( win )
            dorefresh = true
        elseif token == :ctrl_k
            searchterm = ""
        elseif token == :F1
            tshow_(
            """
PgUp/PgDn,
Arrow keys : standard navigation
ctrl-left/right arrows : move left/right ends
<ascii>    : build search term
ctrl-k     : clear search term
F6         : explore Method as tree
F8         : edit method
home       : jump to the start
end        : jump to the end
            """, title = "Help", showprogress= false, showkeyhelper=false
            )
            dorefresh = true
        elseif token == :KEY_RESIZE || is_term_resized( maxy, maxx )
            rebuildwindow()
            dorefresh = true
            #TODO search, jump to line, etc.
        elseif token == :delete || token ==:backspace || token == :ctrl_h
            searchterm = string( SubString( searchterm, 1, length( searchterm ) - 1 ) )
            continue
        elseif isa(token, String) && isprint(token)
            searchterm *= token
            continue
        end

        if searchterm != lastsearchterm
            lastsearchterm = searchterm
            update_score_sort()
            dorefresh = true
        end

        if dorefresh
            redrawviewer()
        end
        ct = strftime( "%H:%M:%S", time() )
        mvwprintw( win, height-1, width-10, "%s", ct )
        #update_panels()
        #doupdate()
        wrefresh( win )
    end
    #del_panel( panel )
    #delwin( win )
end
