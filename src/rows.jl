# ===== Typed tree rows + generic sibling/parent navigation =====
#
# The tree / file-browser / popup row payloads are anonymous tuples today, so
# `row[4]` means different things in different files. These records give the
# navigation primitives a typed, self-documenting surface, and let the
# Ctrl-Left/Up/Down logic — duplicated identically across twtree.jl,
# twdicttree.jl and twfilebrowser.jl — collapse to one `tree_nav`.
# See design/termwin-widget-authoring-rearchitecture.md, Part A3.

abstract type AbstractRow end

# Every row carries a `stack`: the path of name-segments from the root to this
# node. Depth is its length; siblings share `stack[1:end-1]`.
stack_of(r::AbstractRow)      = r.stack
parent_prefix(r::AbstractRow) = (s = stack_of(r); s[1:end-1])
depth(r::AbstractRow)         = length(stack_of(r))

struct TreeRow <: AbstractRow
    name::String
    typestr::String
    valuestr::String
    stack::Vector{Any}        # path from root; depth == length(stack)
    expandhint::Symbol        # :single | :open | :close
    skiplines::Vector{Int}    # depths whose vertical connector is suppressed
end

struct FileRow <: AbstractRow
    name::String
    typestr::String
    sizestr::String
    mtimestr::String
    stack::Vector{Any}
    expandhint::Symbol
    skiplines::Vector{Int}
    abspath::String
    isdir::Bool
end

"""
    tree_nav(rows, cursor, dir) -> (target::Int, moved::Bool)

Generic tree navigation over a flat `Vector{<:AbstractRow}` given the current
`cursor` index and a direction:

- `:parent`       — nearest preceding row whose `stack` equals our parent prefix
- `:prev_sibling` — nearest preceding row at the same depth and parent; stops
                    (no move) when a shallower row is reached first
- `:next_sibling` — nearest following row at the same depth and parent; stops
                    after the last sibling

`moved == false` means there was nowhere to go (caller typically beeps).
"""
function tree_nav(rows::AbstractVector{<:AbstractRow}, cursor::Integer, dir::Symbol)
    (isempty(rows) || !(1 <= cursor <= length(rows))) && return (Int(cursor), false)
    cur = rows[cursor]

    if dir === :parent
        # Nearest preceding row whose stack equals our parent prefix. Note the
        # prefix may be empty: trees with an explicit depth-0 root row (twtree)
        # represent the root as stack == [], so a depth-1 node's parent is that
        # root. If no such row precedes us (we are the root), there's no move.
        target = parent_prefix(cur)
        for i in (cursor - 1):-1:1
            stack_of(rows[i]) == target && return (i, true)
        end
        return (Int(cursor), false)

    elseif dir === :prev_sibling
        d  = depth(cur)
        pp = parent_prefix(cur)
        for i in (cursor - 1):-1:1
            di = depth(rows[i])
            di < d && break
            (di == d && parent_prefix(rows[i]) == pp) && return (i, true)
        end
        return (Int(cursor), false)

    elseif dir === :next_sibling
        d  = depth(cur)
        pp = parent_prefix(cur)
        for i in (cursor + 1):length(rows)
            di = depth(rows[i])
            di < d && break
            (di == d && parent_prefix(rows[i]) == pp) && return (i, true)
        end
        return (Int(cursor), false)
    end

    return (Int(cursor), false)
end
