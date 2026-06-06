# history.jl — fixed-capacity snapshot ring for undo/redo

# snapshots[cursor] == current state at all times.
# push_snapshot!(h, new_state) is called AFTER each mutation with the post-mutation state.
# undo!/redo! slide the cursor; the returned snapshot is a reference (caller copies if needed).
mutable struct EditHistory{T}
    snapshots::Vector{T}
    cursor::Int     # index into snapshots of the "now" state
    capacity::Int
end

EditHistory{T}(initial::T, capacity::Int = 20) where {T} =
    EditHistory{T}(T[initial], 1, capacity)

function push_snapshot!(h::EditHistory{T}, state::T) where {T}
    # Erase redo tail
    if h.cursor < length(h.snapshots)
        deleteat!(h.snapshots, (h.cursor + 1):length(h.snapshots))
    end
    push!(h.snapshots, state)
    h.cursor = length(h.snapshots)
    # Trim oldest entries to stay within capacity
    excess = length(h.snapshots) - h.capacity
    if excess > 0
        deleteat!(h.snapshots, 1:excess)
        h.cursor -= excess
    end
    nothing
end

can_undo(h::EditHistory) = h.cursor > 1
can_redo(h::EditHistory) = h.cursor < length(h.snapshots)

function undo!(h::EditHistory{T}) where {T}
    can_undo(h) || return (nothing, false)
    h.cursor -= 1
    (h.snapshots[h.cursor], true)
end

function redo!(h::EditHistory{T}) where {T}
    can_redo(h) || return (nothing, false)
    h.cursor += 1
    (h.snapshots[h.cursor], true)
end
