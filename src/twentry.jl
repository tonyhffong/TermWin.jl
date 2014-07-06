# hand-crafted numeric and string input field

defaultEntryHelpText = """
<-, -> : move cursor
ctrl-a : move cursor to start
ctrl-e : move cursor to end
ctrl-k : empty entry
,      : (Num only) clean up format (add commas)
.      : (Num only) decimal point. If already exists, jump there
m      : (Num only) multiply by 1,000. So 1mm becomes 1 million
e      : (Floating Point only) exponent. 1e6 for 1,000,000.0
ctrl-r : Toggle insertion/overwrite mode
ctrl-up: If configured, increase value by a tick-size
ctrl-dn: If configured, decrease value by a tick-size

n.b. (String only) Edges are highlighted if more beyond boundary
"""
type TwEntryData
    valueType::DataType
    showHelp::Bool
    helpText::String
    inputText::String
    cursorPos::Int # where is the next char going to be
    fieldLeftPos::Int # what is the position of the first char on the field
    tickSize::Any
    titleLeft::Bool
    overwriteMode::Bool
    limitToWidth::Bool # TODO: not implemented yet
    TwEntryData( dt::DataType ) = new( dt, false, defaultEntryHelpText, "", 1, 1, 0, true, false, false )
end

# the ways to use it:
# standalone panel
# as a subwin as part of another widget (see next function)
# w include title width, if it's shown on the left
function newTwEntry( scr::TwScreen, dt::DataType, w::Real,y::Any,x::Any; box=true, showHelp=true, titleLeft = true, title = "" )
    obj = TwObj( twFuncFactory( :Entry ) )
    registerTwObj( scr, obj )
    obj.box = box
    obj.title = title
    obj.borderSizeV= box ? 1 : 0
    obj.borderSizeH= box ? 1 : 0
    obj.data = TwEntryData( dt )
    obj.data.showHelp = showHelp
    h = box?3 : 1
    alignxy!( obj, h, w, x, y)
    configure_newwinpanel!( obj )
    obj
end

# this one only creates a subwin, do not make a panel out of it, and don't
# register it to a screen
# so to use it, the container widget must keep track of its update and input
# y and x is relative to parentwin
function newTwEntry( parentwin::Ptr{Void}, dt::DataType, w::Real, y::Any,x::Any; box=true, showHelp=true, titleLeft=true, title = "" )
    obj = TwObj( twFuncFactory( :Entry ) )
    parbegy, parbegx = getwinbegyx( parentwin )
    obj.data = TwEntryData( dt )
    obj.box = box
    obj.title = title
    obj.borderSizeV= box ? 1 : 0
    obj.borderSizeH= box ? 1 : 0
    obj.data.showHelp = showHelp

    h = box ? 3 : 1
    alignxy!( obj, h, w, x, y, parentwin = parentwin, derwin=true )
    obj.window = derwin( parentwin, obj.height, obj.width, obj.ypos, obj.xpos )
    obj
end

function getFieldDimension( o::TwObj )
    if o.data.titleLeft && !isempty( o.title )
        fieldcount = o.width - length(o.title) - o.borderSizeH* 2
        remainspacecount = fieldcount - length( o.data.inputText )
    else
        fieldcount = o.width - ( o.box?2: 0 )
        remainspacecount = fieldcount - length( o.data.inputText )
    end
    (fieldcount, remainspacecount)
end

function drawTwEntry( o::TwObj )
    werase( o.window )
    if o.box
        box( o.window, 0,0 )
    end
    if !isempty( o.title ) && !o.data.titleLeft && o.box
        mvwprintw( o.window, 0, int( ( o.width - length(o.title) )/2 ), "%s", o.title )
    end
    starty = o.borderSizeV
    startx = o.borderSizeH

    fieldcount, remainspacecount = getFieldDimension( o )
    if o.data.titleLeft && !isempty( o.title )
        mvwprintw( o.window, starty, startx, "%s", o.title )
        startx += length(o.title)
    end
    if o.data.valueType <: Number # right justifed
        if remainspacecount <= 0
            rcursPos = max( 1, min( fieldcount, o.data.cursorPos ) )
            outstr = repeat( "#", fieldcount-1 ) * " "
        else
            rcursPos =  max(1,min( remainspacecount + o.data.cursorPos-1, fieldcount ))
            outstr = repeat( " ", remainspacecount-1 ) * o.data.inputText * " "
        end
    else
        if remainspacecount <= 0
            rcursPos = min( fieldcount, max(1, o.data.cursorPos - o.data.fieldLeftPos+1 ) )
            outstr = o.data.inputText[chr2ind( o.data.inputText, o.data.fieldLeftPos):end]
            if length(outstr) > fieldcount
                outstr = outstr[ 1:chr2ind( outstr, fieldcount) ]
            elseif length(outstr) < fieldcount
                outstr *= repeat(" ", fieldcount - length(outstr) )
            end
        else
            outstr = o.data.inputText * repeat( " ", remainspacecount )
            rcursPos = o.data.cursorPos
        end
    end
    wattron( o.window, COLOR_PAIR(15)) #white on blue for data entry field
    mvwprintw( o.window, starty, startx, "%s", outstr )
    # print the cursor
    firstflag = 0
    lastflag = 0
    if o.hasFocus
        c = outstr[chr2ind( outstr,rcursPos )]
        if o.data.overwriteMode
            flag = A_REVERSE
        else
            flag = A_UNDERLINE
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
    if o.data.valueType <: String
        if o.data.fieldLeftPos > 1
            c = outstr[ chr2ind(outstr, 1 )]
            wattron( o.window, firstflag | A_BOLD )
            mvwprintw( o.window, starty, startx, "%s", string(c) )
            wattroff( o.window, firstflag | A_BOLD )
        end
        if o.data.fieldLeftPos + fieldcount - 1 < length(o.data.inputText)
            c = outstr[ chr2ind( outstr, fieldcount ) ]
            wattron( o.window, lastflag | A_BOLD )
            mvwprintw( o.window, starty, startx+fieldcount-1, "%s", string(c) )
            wattroff( o.window, lastflag | A_BOLD )
        end
    end
    wattroff( o.window, COLOR_PAIR(15))
end

function injectTwEntry( o::TwObj, token )
    dorefresh = false
    retcode = :got_it # default behavior is that we know what to do with it

    insertchar = ( c ) -> begin
        utfs = o.data.inputText
        p = o.data.cursorPos
        pm1 = p <= 1 ? 0 : chr2ind(utfs,p-1)
        pp = nextind( utfs, pm1 )
        if o.data.overwriteMode
            o.data.inputText = utfs[1:pm1] * c
            for j in 2:length(c)
                pp = nextind( utfs, pp )
            end
            if p+length(c) <= length(utfs)
                o.data.inputText *= utfs[ pp:end ]
            end
            o.data.cursorPos += length( c )
        else
            o.data.inputText = utfs[1:pm1] * c
            if p <= length(utfs)
                o.data.inputText *= utfs[ pp:end]
            end
            o.data.cursorPos += length( c )
        end
    end

    checkcursor = ()-> begin
        fieldcount, remainspacecount = getFieldDimension( o )
        if o.data.inputText == ""
            o.data.cursorPos = 1
        else
            o.data.cursorPos = max( 1, min( length( o.data.inputText )+1, o.data.cursorPos ) )
        end
        if o.data.valueType <: String
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
        (fieldcount, remainspacecount ) = getFieldDimension( o )
        (v,s) = evalNFormat( o.data.valueType, o.data.inputText, fieldcount )
        if v != nothing
            o.value = v
            o.data.inputText = s
            checkcursor()
        end
        retcode = :exit_nothing
    elseif token == :shift_up && o.data.valueType <: Real && o.data.tickSize != 0
        (fieldcount, remainspacecount ) = getFieldDimension( o )
        (v,s) = evalNFormat( o.data.valueType, o.data.inputText, fieldcount )
        if v != nothing
            v += o.data.tickSize
            o.value = v
            o.data.inputText = formatCommas( v, fieldcount )
            checkcursor()
            dorefresh = true
        end
    elseif token == :shift_down && o.data.valueType <: Real && o.data.tickSize != 0
        (fieldcount, remainspacecount ) = getFieldDimension( o )
        (v,s) = evalNFormat( o.data.valueType, o.data.inputText, fieldcount )
        if v != nothing
            if o.data.valueType <: Unsigned && v < o.data.tickSize
                v = convert( o.data.valueType, 0 )
            else
                v -= o.data.tickSize
            end
            o.data.inputText = formatCommas( v, fieldcount )
            checkcursor()
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
        utfs = o.data.inputText
        pp = chr2ind( utfs, p-1 )
        ppn = nextind( utfs, pp )
        if p <= length(o.data.inputText)
            ppnn = nextind( utfs, ppn )
            o.data.inputText = utfs[1:pp] * utfs[ppnn:end]
            checkcursor()
            dorefresh = true
        else
            beep()
        end
    elseif token == :backspace
        p = o.data.cursorPos
        if p > 1
            utfs = o.data.inputText
            ppprev = p > 2 ? chr2ind( utfs, p-2) : 0
            o.data.inputText = utfs[1:ppprev]
            pp = nextind( utfs, ppprev )
            ppn = nextind( utfs, pp )
            if p <= length( utfs )
                o.data.inputText *= utfs[ppn:end]
            end
            o.data.cursorPos = max( 1, p-1 )
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
    elseif token == "m"  && o.data.valueType <: Real # add 000
        (fieldcount, remainspacecount ) = getFieldDimension( o )
        (v,s) = evalNFormat( o.data.valueType, o.data.inputText, fieldcount )
        if v!=nothing
            o.value = v * 1000
            o.data.inputText = formatCommas( o.value, fieldcount )
            checkcursor()
            dorefresh = true
        end
    elseif typeof( token ) <: String && o.data.valueType <: Number &&
        ( isdigit( token ) || token == "," ||
          o.data.valueType <: FloatingPoint && in( token, [ ".", "e", "+", "-" ] ) ||
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
            (v,s) = evalNFormat( o.data.valueType, o.data.inputText, fieldcount )
            if v != nothing
                o.data.inputText = s
                o.value = v
                dorefresh = true
            end
        else
            insertchar( token )
            dorefresh = true
        end
    elseif typeof( token ) <: String && o.data.valueType <: String && isprint( token )
        insertchar( token )
        checkcursor()
        dorefresh = true
    elseif token == :enter || token == symbol( "return" )
        (fieldcount, remainspacecount ) = getFieldDimension( o )
        (v,s) = evalNFormat( o.data.valueType, o.data.inputText, fieldcount )
        if v != nothing
            o.value = v
            o.data.inputText = s
            checkcursor()
            retcode = :exit_ok
        end
    elseif token == :F1 && o.data.showHelp
        global rootTwScreen
        helper = newTwViewer( rootTwScreen, o.data.helpText, :center, :center, showHelp=false, showLineInfo=false, bottomText = "Esc to continue" )
        activateTwObj( helper )
        unregisterTwObj( rootTwScreen, helper )
        dorefresh = true
    else
        retcode = :pass # I don't know what to do with it
    end

    if dorefresh
        refresh(o)
    end

    return retcode
end

function formatCommas( n::Int )
    s = string( n )
    len = length(s)
    t = ""
    for i in 1:3:len
        if t != ""
            t = s[max(1,len-i-1):len-i+1] *"," * t
        else
            t = s[max(1,len-i-1):len-i+1]
        end
    end
    return t
end

function formatCommas( v::Real, fieldcount::Int )
    if typeof(v) <: FloatingPoint
        s = string( v )
    elseif typeof( v ) <: Rational # assume int
        ip,remp = divrem( v.num, v.den )
        ips = formatCommas( ip )
        rems = string( float( remp / v.den ))
        #println( remp, " ", v.den, " ", float( remp / v.den ), " ", ip, " ", rems )
        s = ips * rems[2:end]
        if length(s) > fieldcount-1
            s = replace( s, ",", "", length(s)-fieldcount+1 )
        end
    else # assume int
        s=formatCommas(v )
        if length(s) > fieldcount-1
            s = replace( s, ",", "", length(s)-fieldcount+1 )
        end
    end
    return s
end

function evalNFormat( dt::DataType, s::String, fieldcount::Int )
    if dt <: String
        return( s, s )
    elseif dt <: FloatingPoint
        v = nothing
        stmp = replace( s, ",", "" )
        try
            if length(stmp)==0
                v = 0.0
            else
                v = parsefloat( dt, replace( s, ",", "" ) )
            end
        end
        if v != nothing
            v = convert(dt, v)
            return (v, formatCommas( v, fieldcount ))
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
                    v = parseint( dt.types[1], stmp )
                end
            end
            if v != nothing
                v = convert( dt, v)
                return (v, formatCommas( v, fieldcount ))
            end
        else
            iv = nothing
            fv = nothing
            try
                if dpos == 1
                    iv = 0
                else
                    iv = parseint( dt.types[1], stmp[1:dpos-1] )
                end
                if dpos == length( stmp )
                    fv = 0
                else
                    tail = stmp[dpos+1:end]
                    fv = parseint( dt.types[2], tail ) // ( 10 ^ length(tail) )
                end
            end
            if iv != nothing && fv != nothing
                v = iv + fv
                return (v, formatCommas( v, fieldcount ))
            end
        end
    elseif dt <: Integer # assume int
        v = nothing
        stmp = replace( s, ",", "" )
        try
            if length(stmp)==0
                v = 0
            else
                v = parseint( dt, stmp )
            end
        end
        if v != nothing
            v = convert( dt, v)
            return (v, formatCommas( v, fieldcount ))
        end
    end
    return (nothing, s)
end
