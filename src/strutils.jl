function repr_symbol( s::Symbol )
    v = string(s)
    if length(v) == 0
        v = ":\"\""
    elseif match( r"^[a-zA-Z_][0-9a-zA-Z_]*$", v ) !== nothing
        v = ":" * v
    else
        v = "sym\""*escape_string(v)*"\""
    end
    v
end

function delete_char_before( s::String, p::Int )
    if p == 1
        return (s,p)
    end
    local totalskip::Int = 0
    local last_byte_idx::Int = 0  # byte index of last character seen
    local lastcw::Int = 0
    idx = firstindex(s)
    for c in s
        cw = textwidth(string(c))
        if totalskip + cw < p
            totalskip += cw
            last_byte_idx = idx
            lastcw = cw
            idx = nextind(s, idx)
            continue
        else
            # Delete the character at last_byte_idx
            if last_byte_idx < firstindex(s)
                return (s[idx:end], p-lastcw)
            elseif last_byte_idx == firstindex(s)
                return (s[idx:end], p-lastcw)
            else
                return (s[1:prevind(s,last_byte_idx)] * s[idx:end], p-lastcw)
            end
        end
    end
    if last_byte_idx == 0
        return (s,p)
    end
    # Delete the last character in the string
    if last_byte_idx == firstindex(s)
        return ("", p-lastcw)
    end
    return (s[1:prevind(s,last_byte_idx)], p-lastcw)
end

function delete_char_at( s::String, p::Int )
    local totalskip::Int = 0
    local lastj::Int = 0
    for (j,c) in enumerate( s )
        cw = textwidth(string(c))
        if totalskip + cw < p
            totalskip += cw
            lastj = j
            continue
        else
            if lastj == 0
                return substr_by_width( s, p, -1 )
            else
                return s[1:prevind(s,nextind(s,0,j))] * substr_by_width( s, p, -1 )
            end
        end
    end
    s
end

# TODO: test this thoroughly!!
# Insert a (short) string at the "p" position
# p is interpreted as the width position
function insertstring( s::String, ch::T, p::Int, overwrite::Bool ) where {T<:AbstractString}
    wskip = p-1
    local totalskip::Int = 0
    chwidth = textwidth( ch )
    if chwidth == 0 && p == 1
        return s
    end
    idx = firstindex(s)
    for c in s
        cw = textwidth(string(c))
        if totalskip + cw <= wskip
            totalskip += cw
            idx = nextind(s, idx)
            continue
        else
            if idx == firstindex(s)
                out = ch
            else
                out = s[1:prevind(s,idx)] * ch
            end
            if overwrite
                out *= substr_by_width( s, wskip+chwidth, -1 )
            else
                out *= substr_by_width( s, wskip, -1 )
            end
            return out
        end
    end
    return s * ch
end

# get w charwidths worth of string, after skipping up to wskip widths
# greedy-skip: all trailing 0 width chars will be skipped
# greedy-include: all trailing 0-width chars will be included
# if w is -1, it would take all the rest of the string
function substr_by_width( s::T, wskip::Int, w::Int ) where {T<:AbstractString}
    local totalskip::Int = 0
    local totalwidth::Int = 0
    local startidx::Int = -1
    local endidx::Int = 0
    for (j,c) in enumerate( s )
        cw = textwidth(string(c))
        if startidx == -1
            if totalskip + cw <= wskip
                totalskip += cw
                continue
            else
                if w == -1 # just take until the end
                    return s[nextind(s,0,j):end]
                end
                startidx = j
                endidx = j
                if totalwidth + cw <= w
                    totalwidth += cw
                    continue
                else
                    return convert( T, "" )
                end
            end
        else
            if totalwidth + cw <= w
                totalwidth += cw
                endidx = j
                continue
            else
                break
            end
        end
    end
    if startidx == -1
        if w == -1
            return convert( T,"" )
        end
        startidx = 1
    end
    if w == -1
        return s[nextind(s,0,startidx):end]
    end
    if endidx < startidx
        return convert( T, "" )
    end
    return s[nextind(s,0,startidx):nextind(s,0,endidx)]
end

function ensure_length( s::T, w::Int, pad::Bool = true ) where {T<:AbstractString}
    t = replace( s, "\n" => "\\n" )
    t = replace( t, "\t" => " " )
    if w <= 0
        return ""
    end
    len = textwidth( t )
    if w ==1
        if len > 1
            return string( Char( 0x2026 ) )
        elseif len==1
            return t
        else
            if pad
                return " "
            else
                return ""
            end
        end
    end

    if len <= w
        if pad
            return t * repeat( " ", w - len )
        else
            return t
        end
    else # ellipsis
        return substr_by_width( t, 0, w-1 ) * string( Char( 0x2026 ) )
    end
end

function wordwrap( x::T, width::Int ) where {T<:AbstractString}
    spaceleft = width
    lines = String[]
    currline = convert( T,"" )
    words = split( x, " ", keepempty=true )
    for w in words
        wlen = textwidth(w)
        if wlen>width && spaceleft == width
            push!( lines, substr_by_width( w, 0, width-1 ) * string( Char( 0x2026 ) ) )
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

    v0 = collect(0:length(s2))
    v1 = Vector{Int}(undef, length(s2)+1)
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

function longest_common_prefix( s1::String, s2::String )
    m = min( length( s1 ), length( s2 ) )
    lcpidx = 0
    for i in 1:m
        if s1[i] != s2[i]
            break
        end
        lcpidx = i
    end
    return s1[ 1:lcpidx ]
end
