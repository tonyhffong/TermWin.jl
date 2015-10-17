# progress bar

type TwProgressData
    uiChannel::RemoteRef
    statusChannel::RemoteRef
    progress::Float64
    showProgress::Bool
    cursorPos::Int # where is the progress bar cursor
    text::UTF8String
    redrawTime::Float64
    statusTime::Float64
    startTime::Float64
    TwProgressData() = new( RemoteRef(), RemoteRef(), 0.0, true, 1, utf8(""), time(), time(), time() )
end

twGlobProgressData = TwProgressData()

function updateProgressChannel( status::Symbol, v::Any )
    global twGlobProgressData
    if isready( twGlobProgressData.statusChannel )
        take!( twGlobProgressData.statusChannel )
    end
    put!( twGlobProgressData.statusChannel, ( status, v ) )
end

function progressMessage( s::UTF8String )
    global twGlobProgressData
    st = :normal
    val = nothing
    if isready( twGlobProgressData.statusChannel )
        (st, val) = take!( twGlobProgressData.statusChannel )
        if st == :init
            st = :normal
        end
    end
    if typeof( val ) <: Dict && eltype( val ) <: (Symbol, Any)
        val[ :message ] = utf8(s)
        put!( twGlobProgressData.statusChannel, ( st, val ) )
    else
        if st != :error && st != :done
            put!( twGlobProgressData.statusChannel, (st, @compat Dict{Symbol,Any}( :message => utf8(s) ) ) )
        end
    end
end

function progressUpdate( n::Float64 )
    global twGlobProgressData
    st = :normal
    val = nothing
    if isready( twGlobProgressData.statusChannel )
        (st, val) = take!( twGlobProgressData.statusChannel )
        if st == :init
            st = :normal
        end
    end
    if typeof( val ) <: Dict && eltype( val ) <: (Symbol, Any)
        val[ :progress ] = n
        put!( twGlobProgressData.statusChannel, ( st, val ) )
    else
        if st != :error && st != :done
            put!( twGlobProgressData.statusChannel, (st, @compat Dict{Symbol,Any}( :progress => n ) ) )
        end
    end
end

# standalone panel
# as a subwin as part of another widget (see next function)
# w include title width, if it's shown on the left
# the function f takes no argument. It's started right-away
# the function can call
# * TermWin.progressMessage( s::UTF8String ) # make sure height can accommodate the content
# * TermWin.progressUpdate( n::Float64 ) # 0.0 <= n <= 1.0
function newTwProgress( scr::TwObj; height::Real=5, width::Real=40, posy::Any=:center,posx::Any=:center, box=true, title = utf8("") )
    global twGlobProgressData
    obj = TwObj( TwProgressData(), Val{ :Progress } )
    obj.data = twGlobProgressData
    obj.box = box
    obj.title = title
    obj.borderSizeV= box ? 1 : 0
    obj.borderSizeH= box ? 1 : 0
    link_parent_child( scr, obj, height,width,posy,posx )
    obj
end

function draw( o::TwObj{TwProgressData} )
    werase( o.window )
    if o.box
        box( o.window, 0,0 )
    end
    if !isempty( o.title ) && o.box
        mvwprintw( o.window, 0, (@compat round(Int, ( o.width - length(o.title) )/2 )), "%s", o.title )
    end
    starty = o.borderSizeV
    startx = o.borderSizeH
    viewContentHeight = o.height - o.borderSizeV * 2
    viewContentWidth  = o.width  - o.borderSizeH * 2

    wattron( o.window, COLOR_PAIR(15)) #white on blue for progress bar

    p = max( 0.0, min( 1.0, twGlobProgressData.progress ) )
    left = max( 0, (@compat round(Int, viewContentWidth * p )) - 1 )
    bar = repeat( string( '\U2592' ), left+1 ) * repeat( " ", viewContentWidth - left - 1 )
    mvwprintw( o.window, starty, startx, "%s", bar )
    wattroff( o.window, COLOR_PAIR(15))
    if twGlobProgressData.text != ""
        mvwprintw( o.window, starty+1,startx, "%s", twGlobProgressData.text )
    end
end

function inject( o::TwObj{TwProgressData}, token::Any )
    global twGlobProgressData
    t = time()
    dorefresh = (t - twGlobProgressData.redrawTime) > 1.0
    retcode = :got_it # default behavior is that we know what to do with it

    if token == :progressupdate
        (st, val) = take!( twGlobProgressData.statusChannel )
        twGlobProgressData.statusTime = t
        if st == :init
            twGlobProgressData.startTime = t
            twGlobProgressData.progress = 0.0
            twGlobProgressData.text = utf8( "init" * strftime( " %H:%M:%S", time() )  )
        elseif st == :error
            o.value = val
            retcode = :exit_nothing
        elseif st == :done
            o.value = val
            retcode = :exit_ok
        else
            if typeof( val ) <: Dict && eltype( val ) <: (Symbol,Any)
                if haskey( val, :message ) && typeof( val[:message] ) <: AbstractString
                    twGlobProgressData.text = utf8( val[ :message ] )
                end
                if haskey( val, :progress ) && typeof( val[ :progress ] ) == Float64
                    twGlobProgressData.progress = val[ :progress ]
                    #twGlobProgressData.text = utf8( string( st ) * strftime( " %H:%M:%S", time() ) )
                end
            end
            dorefresh = true
        end
    elseif token == :ctrl_k # kill, preemptively
    elseif token == :ctrl_p # pause, cooperatively
    else
        retcode = :pass # I don't know what to do with it
    end

    if dorefresh
        twGlobProgressData.redrawTime = t
        refresh(o)
    end

    return retcode
end
