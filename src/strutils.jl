
function ensure_length( s::String, w::Int, pad::Bool = true )
    t = replace( s, "\n", " " )
    if length(t)<= w
        if pad
            return t * repeat( " ", w - length( t ) )
        else
            return t
        end
    else # ellipsis
        return t[ 1:chr2ind( t, w-1) ] * string( char( 0x2026 ) )
    end
end

function wordwrap( x::String, width::Int )
    spaceleft = width
    lines = String[]
    currline = ""
    words = split( x, " ", true ) # don't keep empty words
    for w in words
        wlen = length(w)
        if wlen>width && spaceleft == width
            push!( lines, SubString( w, 1, width-3 ) * " .." )
        elseif wlen+1 > spaceleft
            push!( lines, currline )
            currline = w * " "
            spaceleft = width - wlen - 1
        else
            currline = currline * w * " "
            spaceleft = spaceleft - wlen -1
        end
    end
    if currline != ""
        push!(lines, currline )
    end
    return lines
end

# edit distance on signatures, should work on utf-8 strings too.
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

