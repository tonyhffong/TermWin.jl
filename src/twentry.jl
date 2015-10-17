# hand-crafted numeric and string input field

defaultEntryStringHelpText = utf8("""
<-, -> : move cursor
ctrl-a : move cursor to start
ctrl-e : move cursor to end
ctrl-k : empty entry
ctrl-r : Toggle insertion/overwrite mode

Edges are highlighted if more beyond boundary
""")

defaultEntryNumberHelpText = utf8("""
<-, -> : move cursor
ctrl-a : move cursor to start
ctrl-e : move cursor to end
ctrl-k : empty entry
,      : Clean up format (add commas)
.      : Decimal point. If already exists, jump there
m      : Multiply by 1,000. So 1mm becomes 1 million
e      : (Floating Point only) exponent. 1e6 for 1,000,000.0
ctrl-r : Toggle insertion/overwrite mode
Shft-up: If configured, increase value by a tick-size
Shft-dn: If configured, decrease value by a tick-size
""")

defaultEntryDateHelpText = utf8("""
Format : YYYY-MM-DD standard, but allows formats such as
         20140101, 1/1/2014, 1Jan2014, 1 January 2014
         2014.01.01
<-, -> : move cursor
ctrl-a : move cursor to start
ctrl-e : move cursor to end
ctrl-k : empty entry
,      : Clean up format
ctrl-r : Toggle insertion/overwrite mode
?      : View calendar
Shft-up: If configured, increase value by a tick-size
Shft-dn: If configured, decrease value by a tick-size
""")
type TwEntryData
    valueType::DataType
    showHelp::Bool
    helpText::UTF8String
    inputText::UTF8String
    cursorPos::Int # where is the next char going to be
    fieldLeftPos::Int # what is the position of the first char on the field
    tickSize::Any
    titleLeft::Bool
    overwriteMode::Bool
    incomplete::Bool # is the input not yet done?
    limitToWidth::Bool # TODO: not implemented yet
    precision::Int
    commas::Bool
    stripzeros::Bool
    conversion::ASCIIString
    function TwEntryData( dt::DataType )
        o = new( dt, false, utf8(""), utf8(""), 1, 1, 0, true, false, false, false,
           -1, true, true, "" )
        if dt <: AbstractString
            o.helpText = defaultEntryStringHelpText
            o.conversion = "s"
        elseif dt <: Number
            o.helpText = defaultEntryNumberHelpText
            if dt <: Unsigned
                o.conversion = "x"
            elseif dt <: Integer
                o.conversion = "d"
            else
                o.conversion = "f"
            end
        elseif dt <: Date
            o.helpText = defaultEntryDateHelpText
            o.conversion = ""
        end
        o
    end
end

# the ways to use it:
# standalone panel
# as a subwin as part of another widget (see next function)
# w include title width, if it's shown on the left

# this one only creates a subwin, do not make a panel out of it, and don't
# register it to a screen
# so to use it, the container widget must keep track of its update and input
# y and x is relative to parentwin
function newTwEntry( parent::TwObj, dt::DataType;
    width::Real=30,posy::Any=:staggered,posx::Any=:staggered,
    box=true, showHelp=true, titleLeft=true, title = utf8(""),
    precision=-1, stripzeros= (precision == -1), conversion="" )

    data = TwEntryData( dt )
    data.showHelp = showHelp
    data.titleLeft = titleLeft
    data.precision = precision
    data.stripzeros = stripzeros
    if conversion != ""
        data.conversion = conversion
    end

    obj = TwObj( data, Val{:Entry} )

    obj.box = box
    obj.title = title
    obj.borderSizeV= box ? 1 : 0
    obj.borderSizeH= box ? 1 : 0

    h = box ? 3 : 1
    link_parent_child( parent, obj, h, width, posy, posx )
    obj
end

function getFieldDimension( o::TwObj )
    if o.data.titleLeft && !isempty( o.title )
        fieldcount = o.width - length(o.title) - o.borderSizeH* 2
        remainspacecount = fieldcount - strwidth( o.data.inputText )
    else
        fieldcount = o.width - ( o.box?2: 0 )
        remainspacecount = fieldcount - strwidth( o.data.inputText )
    end
    (fieldcount, remainspacecount)
end

function draw( o::TwObj{TwEntryData} )
    werase( o.window )
    if o.box
        box( o.window, 0,0 )
    end
    if !isempty( o.title ) && !o.data.titleLeft && o.box
        mvwprintw( o.window, 0, (@compat round(Int, ( o.width - length(o.title) )/2 )), "%s", o.title )
    end
    starty = o.borderSizeV
    startx = o.borderSizeH

    fieldcount, remainspacecount = getFieldDimension( o )
    if o.data.titleLeft && !isempty( o.title )
        mvwprintw( o.window, starty, startx, "%s", o.title )
        startx += length(o.title)
    end
    if o.data.valueType <: Number && o.data.valueType != Bool # right justifed
        if remainspacecount <= 0
            rcursPos = max( 1, min( fieldcount, o.data.cursorPos ) )
            outstr = repeat( "#", fieldcount-1 ) * " "
        else
            rcursPos =  max(1,min( remainspacecount + o.data.cursorPos-1, fieldcount ))
            outstr = repeat( " ", remainspacecount-1 ) * o.data.inputText * " "
        end
    elseif o.data.valueType <: Date
        if remainspacecount <= 0
            rcursPos = max( 1, min( fieldcount, o.data.cursorPos ) )
            outstr = repeat( "#", fieldcount-1 ) * " "
        else
            rcursPos =  max(1,min( o.data.cursorPos, fieldcount ))
            outstr = o.data.inputText * repeat( " ", remainspacecount )
        end
    else
        if remainspacecount <= 0
            rcursPos = min( fieldcount, max(1, o.data.cursorPos - o.data.fieldLeftPos+1 ) )
            outstr = substr_by_width( o.data.inputText, o.data.fieldLeftPos-1, fieldcount )
            strw = strwidth( outstr )
            if strw < fieldcount
                outstr *= repeat(" ", fieldcount - strw )
            end
        else
            outstr = o.data.inputText * repeat( " ", remainspacecount )
            rcursPos = o.data.cursorPos
        end
    end
    if o.hasFocus
        inputflag = COLOR_PAIR(15)
    elseif o.data.incomplete
        inputflag = COLOR_PAIR(12)
    else
        inputflag = COLOR_PAIR(30)
    end
    wattron( o.window, inputflag )
    mvwprintw( o.window, starty, startx, "%s", outstr )
    # print the cursor
    firstflag = inputflag
    lastflag = inputflag
    if o.hasFocus
        c = substr_by_width( outstr, rcursPos-1, 1 )
        if o.data.overwriteMode
            flag = inputflag | A_REVERSE
        else
            flag = inputflag | A_UNDERLINE
        end
        wattron( o.window, flag )
        mvwprintw( o.window, starty, startx + rcursPos-1, "%s", string(c) )
        wattroff( o.window, flag )
        if rcursPos == 1
            firstflag = flag
        end
        if rcursPos == fieldcount
            lastflag = flag
        end
    end
    # visual way to show there are more content beyond the field boundaries
    if o.data.valueType <: AbstractString
        if o.data.fieldLeftPos > 1
            c = substr_by_width( outstr, 0, 1 )
            wattron( o.window, firstflag | A_BOLD )
            mvwprintw( o.window, starty, startx, "%s", string(c) )
            wattroff( o.window, firstflag | A_BOLD )
        end
        if o.data.fieldLeftPos + fieldcount <= strwidth(o.data.inputText)
            c = substr_by_width( outstr, fieldcount-1, 1 )
            wattron( o.window, lastflag | A_BOLD )
            mvwprintw( o.window, starty, startx+fieldcount-1, "%s", string(c) )
            wattroff( o.window, lastflag | A_BOLD )
        end
    end
    wattroff( o.window, inputflag )
end

function inject( o::TwObj{TwEntryData}, token )
    dorefresh = false
    retcode = :got_it # default behavior is that we know what to do with it

    insertchar = ( c ) -> begin
        o.data.inputText = insertstring( o.data.inputText, c, o.data.cursorPos, o.data.overwriteMode )
        o.data.cursorPos += strwidth( c )
    end

    checkcursor = ()-> begin
        fieldcount, remainspacecount = getFieldDimension( o )
        if o.data.inputText == ""
            o.data.cursorPos = 1
        else
            o.data.cursorPos = max( 1, min( length( o.data.inputText )+1, o.data.cursorPos ) )
        end
        if o.data.valueType <: AbstractString
            if remainspacecount <= 0
                if o.data.cursorPos - o.data.fieldLeftPos > fieldcount -1
                    o.data.fieldLeftPos = o.data.cursorPos - fieldcount +1
                elseif o.data.fieldLeftPos > o.data.cursorPos
                    o.data.fieldLeftPos = o.data.cursorPos
                end
            else
                o.data.fieldLeftPos = 1
            end
        end
    end

    if token == :esc
        retcode = :exit_nothing
    elseif token == :shift_up && o.data.valueType <: Real && o.data.tickSize != 0
        (fieldcount, remainspacecount ) = getFieldDimension( o )
        (v,s) = evalNFormat( o.data, o.data.inputText, fieldcount )
        if v != nothing
            v += o.data.tickSize
            o.value = v
            o.data.inputText = myNumFormat( o.value, o.data, fieldcount )
            checkcursor()
            o.data.incomplete = false
            dorefresh = true
        end
    elseif token == :shift_down && o.data.valueType <: Real && o.data.tickSize != 0
        (fieldcount, remainspacecount ) = getFieldDimension( o )
        (v,s) = evalNFormat( o.data, o.data.inputText, fieldcount )
        if v != nothing
            if o.data.valueType <: Unsigned && v < o.data.tickSize
                v = convert( o.data.valueType, 0 )
            else
                v -= o.data.tickSize
            end
            o.data.inputText = myNumFormat( o.value, o.data, fieldcount )
            checkcursor()
            o.data.incomplete = false
            dorefresh = true
        end
    elseif token == :left
        if o.data.cursorPos > 1
            o.data.cursorPos -= 1
            checkcursor()
            dorefresh = true
        else
            beep()
        end
    elseif token == :ctrl_a
        if o.data.cursorPos > 1
            o.data.cursorPos = 1
            checkcursor()
            dorefresh = true
        else
            beep()
        end
    elseif token == :right
        if o.data.cursorPos < length(o.data.inputText)+1
            o.data.cursorPos += 1
            checkcursor()
            dorefresh = true
        else
            beep()
        end
    elseif token == :ctrl_e
        if o.data.cursorPos < length(o.data.inputText)+1
            o.data.cursorPos = length( o.data.inputText) + 1
            checkcursor()
            dorefresh = true
        else
            beep()
        end
    elseif token == :delete
        p = o.data.cursorPos
        utfs = delete_char_at( o.data.inputText, o.data.cursorPos )
        if utfs != o.data.inputText
            o.data.inputText = utfs
            checkcursor()
            dorefresh = true
        else
            beep()
        end
    elseif token == :backspace
        p = o.data.cursorPos
        utfs, newpos = delete_char_before( o.data.inputText, o.data.cursorPos )
        if utfs != o.data.inputText
            o.data.inputText = utfs
            o.data.cursorPos = newpos
            checkcursor()
            dorefresh = true
        else
            beep()
        end
    elseif token == :ctrl_r || token == :insert
        o.data.overwriteMode = !o.data.overwriteMode
        dorefresh = true
    elseif token == :ctrl_k # kill the buffer
        o.data.inputText = ""
        o.data.cursorPos = 1
        o.data.fieldLeftPos = 1
        dorefresh = true
    elseif token == "m"  && o.data.valueType <: Real && o.data.valueType != Bool # add 000
        (fieldcount, remainspacecount ) = getFieldDimension( o )
        (v,s) = evalNFormat( o.data, o.data.inputText, fieldcount )
        if v!=nothing
            o.value = v * 1000
            o.data.inputText = myNumFormat( o.value, o.data, fieldcount )
            checkcursor()
            dorefresh = true
        else
            beep()
        end
    elseif o.data.valueType == Bool && typeof( token ) <: AbstractString && isprint( token )
        if token == "t"
            o.data.inputText = "true"
            o.data.cursorPos = 1
            dorefresh = true
        elseif token == "f"
            o.data.inputText = "false"
            o.data.cursorPos = 1
            dorefresh = true
        else
            beep()
        end
    elseif typeof( token ) <: AbstractString && o.data.valueType <: Date && !in( token, [ "?", "," ] )
        insertchar( token )
        dorefresh = true
    elseif token == "?" && o.data.valueType <: Date
        global rootTwScreen
        (fieldcount, remainspacecount ) = getFieldDimension( o )
        (v,s) = evalNFormat( o.data, o.data.inputText, fieldcount )
        if v == nothing
            v = today()
        end
        w = newTwCalendar( rootTwScreen, v; posy=:center, posx=:center )
        activateTwObj( w )
        if typeof( w.value ) <: Date
            o.data.inputText = string( w.value )
            checkcursor()
            dorefresh = true
        end
        unregisterTwObj( rootTwScreen, w )
    elseif token == "," && o.data.valueType <: Date
        (fieldcount, remainspacecount ) = getFieldDimension( o )
        (v,s) = evalNFormat( o.data, o.data.inputText, fieldcount )
        if v != nothing
            o.data.inputText = s
            checkcursor()
            o.data.incomplete = false
            dorefresh = true
        else
            o.data.incomplete = true
            beep()
        end
    elseif typeof( token ) <: AbstractString && o.data.valueType <: Number && o.data.valueType != Bool &&
        ( isdigit( token ) || token == "," ||
          o.data.valueType <: AbstractFloat && in( token, [ ".", "e", "+", "-" ] ) ||
          o.data.valueType <: Rational && in( token, [ ".", "+", "-" ] ) ||
          o.data.valueType <: Signed && in( token, ["+", "-"] ) )

        if token == "e" # it may or may not be ok, just allow it if there is no e in the string
            if contains( o.data.inputText, "e" ) # disallowed, do nothing
                return :got_it
            else
                insertchar( "e" )
                dorefresh = true
            end
        elseif token == "-" || token == "+" # only allowed at the beginning and just after an "e"
            epos = findfirst( o.data.inputText, 'e' )
            if o.data.cursorPos == 1 && ( findfirst( o.data.inputText, '-' ) == 1 ||
                findfirst( o.data.inputText, '+' ) == 1 ) ||
                o.data.cursorPos != 1 &&  ( epos == 0 || o.data.cursorPos != epos+1 )
                return :got_it
            else
                insertchar( token )
                dorefresh = true
            end
        elseif token == "." # add a decimal point, or if one exists, jump right to it
            epos = findfirst( o.data.inputText, 'e' )
            dpos = findfirst( o.data.inputText, '.' )
            if dpos != 0
                o.data.cursorPos=dpos+1
                dorefresh = true
            else
                insertchar( "." )
                dorefresh = true
            end
        elseif token == "," # try to add commas to all
            (fieldcount, remainspacecount ) = getFieldDimension( o )
            (v,s) = evalNFormat( o.data, o.data.inputText, fieldcount )
            if v != nothing
                o.data.inputText = s
                checkcursor()
                o.data.incomplete = false
                dorefresh = true
            else
                o.data.incomplete = true
                beep()
            end
        else
            insertchar( token )
            dorefresh = true
        end
    elseif typeof( token ) <: AbstractString && o.data.valueType <: AbstractString && isprint( token )
        insertchar( token )
        checkcursor()
        dorefresh = true
    elseif token == :enter || token == Symbol( "return" )
        (fieldcount, remainspacecount ) = getFieldDimension( o )
        (v,s) = evalNFormat( o.data, o.data.inputText, fieldcount )
        if v != nothing
            o.value = v
            o.data.inputText = s
            checkcursor()
            o.data.incomplete = false
            retcode = :exit_ok
        else
            o.data.incomplete = true
            beep()
        end
    elseif token == :focus_off
        (fieldcount, remainspacecount ) = getFieldDimension( o )
        (v,s) = evalNFormat( o.data, o.data.inputText, fieldcount )
        if v != nothing
            o.value = v
            o.data.inputText = s
            o.data.incomplete = false
            checkcursor()
            retcode = :exit_ok
        else
            o.data.incomplete = true
        end
    else
        retcode = :pass # I don't know what to do with it
    end

    if dorefresh
        refresh(o)
    end

    return retcode
end

function myNumFormat( v, data::TwEntryData, fieldcount::Int )
    s = format(v,
        precision=data.precision,
        commas=data.commas, stripzeros=data.stripzeros,
        conversion=data.conversion )
    if length(s) > fieldcount
        s = replace( s, ",", "", length(s)-fieldcount )
    end
    s
end

function evalNFormat( data::TwEntryData, s::AbstractString, fieldcount::Int )
    @lintpragma( "Ignore unstable type variable v")
    @lintpragma( "Ignore unstable type variable iv")
    dt = data.valueType
    if dt <: AbstractString
        return( s, s )
    elseif dt == Bool
        if s == "true"
            v = true
        elseif s == "false"
            v = false
        else
            v = nothing
        end
        return v, s
    elseif dt <: AbstractFloat
        v = nothing
        stmp = replace( s, ",", "" )
        try
            if length(stmp)==0
                v = 0.0
            else
                v = parse( dt, stmp )
            end
        end
        if v != nothing
            v = convert(dt, v)
            return (v, myNumFormat( v, data, fieldcount ) )
        end
    elseif dt <: Rational
        v = nothing
        stmp = replace( s, ",", "" )
        dpos = findfirst( stmp, '.' )
        if dpos == 0
            try
                if length(stmp) == 0
                    v= 0
                else
                    v = parse( dt.types[1], stmp )
                end
            end
            if v != nothing
                v = convert( dt, v)
                return (v, myNumFormat( v, data, fieldcount ) )
            end
        else
            iv = nothing
            fv = nothing
            try
                if dpos == 1
                    iv = 0
                else
                    iv = parse( dt.types[1], stmp[1:dpos-1] )
                end
                if dpos == length( stmp )
                    fv = 0 // 1
                else
                    tail = stmp[dpos+1:end]
                    fv = parse( dt.types[2], tail ) // ( 10 ^ length(tail) )
                end
            end
            if iv != nothing && fv != nothing
                v = iv + (sign(iv) > 0? fv : -fv )
                return (v, myNumFormat( v, data, fieldcount ) )
            end
        end
    elseif dt <: Integer # assume int
        v = nothing
        stmp = replace( s, ",", "" )
        try
            if length(stmp)==0
                v = 0
            else
                v = parse( dt, stmp )
            end
        end
        if v != nothing
            v = convert( dt, v)
            return (v, myNumFormat( v, data, fieldcount ) )
        end
    elseif dt <: Date
        v = nothing
        s = strip( s )
        res = Compat.@Dict( r"^[0-9]{2}[a-z]{3}[0-9]{4}$"i => "dduuuyyyy",
                r"^[0-9][a-z]{3}[0-9]{4}$"i => "duuuyyyy",
                r"^[0-9]{2}[a-z]{3}[0-9]{2}$"i => "dduuuyy",
                r"^[0-9][a-z]{3}[0-9]{2}$"i => "duuuyy",
                r"^[0-9]{2}[a-z]{3}$"i => "dduuu",
                r"^[0-9][a-z]{3}$"i => "duuu",
                r"^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}$" => "yyyy-mm-dd",
                r"^[0-9]{4} [0-9]{1,2} [0-9]{1,2}$" => "yyyy mm dd",
                r"^[0-9]{4}.[0-9]{1,2}.[0-9]{1,2}$" => "yyyy.mm.dd",
                r"^[0-9]{4}/[0-9]{1,2}/[0-9]{1,2}$" => "yyyy/mm/dd",
                r"^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$" => "mm/dd/yyyy", # assume american
                r"^[0-9]{1,2} +[a-z]{3} +[0-9]{4}$"i => "dd uuu yyyy",
                r"^[0-9]{1,2} +[a-z]{4,} +[0-9]{4}$"i => "dd U yyyy",
                r"^[0-9]{8}$" => "yyyymmdd",
                r"^[0-9]{1,2} [0-9]{1,2}$" => "mm dd"
                )
        fmt = "yyyy-mm-dd"
        for (r,f) in res
            m = match( r, s )
            if m != nothing
                try
                    v = Date( s, f )
                end
                if v != nothing
                    fmt = f
                    if !contains( fmt, "yyyy" ) && contains( fmt, "yy" ) && year(v) < 100
                        smally = year(v)
                        thisy = year(today())
                        cent = @compat trunc( Int, floor( thisy, -2 ) )
                        if abs(cent+smally - thisy)<=50
                            v = v + Year( cent )
                        else
                            v = v + Year( cent - 100 )
                        end
                        fmt = replace( fmt, "yy", "yyyy" )
                    end
                    if !contains( fmt, "y" ) && year(v) < 100 # get to the nearest half year
                        smally = year(v)
                        thisy = year(today())
                        if (@compat Int( v + Year( thisy - smally + 1) - today() )) < 182
                            v = v + Year( thisy - smally + 1)
                        else
                            v = v + Year( thisy - smally )
                        end
                        fmt = "yyyy-mm-dd"
                    end
                    if fmt == "mm/dd/yyyy" || fmt == "yyyymmdd"  # the more ambiguous formats
                        fmt = "yyyy-mm-dd"
                    end
                    break
                end
            end
        end
        if v != nothing
            return (v,Dates.format(v,fmt))
        end
    end
    return (nothing, s)
end

function helptext( o::TwObj{TwEntryData} )
    if !o.data.showHelp
        return utf8("")
    end
    o.data.helpText
end
