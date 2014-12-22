charDecorators = [
#=
Thai
These do not take visual spaces and they modify the look of the previous character
* Using the arrow key to move cursor by one cluster instead of by one character.
* Text insertion is allowed at cluster boundary only.
* Text deletion with Delete key will delete a whole cluster, not just a baseline character.
* Text deletion with Backspace key can be done character by character.
* Selection or deletion using character cluster boundaries means that an entire character cluster
  is selected or deleted as a single unit.
=#
0xe31
0xe34
0xe35
0xe36
0xe37
0xe38
0xe39
0xe3a
0xe47
0xe48
0xe49
0xe4a
0xe4b
0xe4c
0xe4d
0xe4e

#= Latin diacritic marks
0x300 - 0x36F
=#

]

function repr_symbol( s::Symbol )
    v = string(s)
    if length(v) == 0
        v = ":\"\""
    elseif match( r"^[a-zA-Z_][0-9a-zA-Z_]*$", v ) != nothing
        v = ":" * v
    else
        v = "sym\""*escape_string(v)*"\""
    end
    v
end

#delete a code_point before the p "width" position
function delete_char_before( s::String, p::Int )
    local totalskip::Int = 0
    local lastj::Int = 0
    local lastcw::Int = 0
    if p == 1
        return (s,p)
    end
    for (j,c) in enumerate( s )
        cw = charwidth( c )
        if totalskip + cw < p
            totalskip += cw
            lastj = j
            lastcw = cw
            continue
        else
            if lastj <= 1
                return (s[chr2ind(s,j):end], p-lastcw)
            else
                return (s[1:chr2ind(s,lastj-1)] * s[chr2ind(s,j):end], p-lastcw)
            end
        end
    end
    if lastj == 0
        return (s,p)
    end
    if lastj == 1
        return ("", p-lastcw)
    end
    return (s[1:chr2ind(s,lastj-1)], p-lastcw)
end

# delete at least 1 code point, could be more if there
# are trailing zero-width codepoints.
function delete_char_at( s::String, p::Int )
    local totalskip::Int = 0
    local lastj::Int = 0
    for (j,c) in enumerate( s )
        cw = charwidth( c )
        if totalskip + cw < p
            totalskip += cw
            lastj = j
            continue
        else
            if lastj == 0
                return substr_by_width( s, p, -1 )
            else
                return s[1:chr2ind(s,lastj)] * substr_by_width( s, p, -1 )
            end
        end
    end
    s
end

# TODO: test this thoroughly!!
# Insert a (short) string at the "p" position
# p is interpreted as the width position
function insertstring( s::String, ch::String, p::Int, overwrite::Bool )
    wskip = p-1
    local totalskip::Int = 0
    chwidth = strwidth( ch )
    if chwidth == 0 && p == 1
        return s
    end
    for (j,c) in enumerate( s )
        cw = charwidth( c )
        if totalskip + cw <= wskip
            totalskip += cw
            continue
        else
            if j == 1
                out = ch
            else
                out = s[1:chr2ind(s,j-1)] * ch
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
function substr_by_width( s::String, wskip::Int, w::Int )
    local totalskip::Int = 0
    local totalwidth::Int = 0
    local startidx::Int = -1
    local endidx::Int = 0
    for (j,c) in enumerate( s )
        cw = charwidth( c )
        if startidx == -1
            if totalskip + cw <= wskip
                totalskip += cw
                continue
            else
                if w == -1 # just take until the end
                    return s[chr2ind(s,j):end]
                end
                startidx = j
                if totalwidth + cw <= w
                    totalwidth += cw
                    continue
                else
                    return ""
                end
            end
        else
            if totalwidth + cw <= w
                totalwidth += cw
                continue
            else
                endidx = j-1
                break
            end
        end
    end
    if startidx == -1
        startidx = 1
    end
    if endidx < startidx
        return ""
    else
        return s[chr2ind(s,startidx):chr2ind(s,endidx)]
    end
end

function ensure_length( s::String, w::Int, pad::Bool = true )
    t = replace( s, "\n", "\\n" )
    t = replace( t, "\t", " " )
    if w <= 0
        return ""
    end
    len = strwidth( t )
    if w ==1
        if len > 1
            return string( char( 0x2026 ) )
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
        return substr_by_width( t, 0, w-1 ) * string( char( 0x2026 ) )
    end
end

function wordwrap( x::String, width::Int )
    spaceleft = width
    lines = String[]
    currline = ""
    words = @compat split( x, " ", keep=true ) # don't keep empty words
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

