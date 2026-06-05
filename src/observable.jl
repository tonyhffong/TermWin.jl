# ===== Observable: a minimal reactive value =====
#
# The progress bar's Channel+tick is "an island"; cross-widget wiring (file
# browser → preview → status footer) is manual. This is the smallest primitive
# that lets one value notify dependents without an Elm-style rewrite of the
# modal activateTwObj loop. Used sparingly (e.g. the active theme, a selection
# feeding a live status bar). See design/...rearchitecture.md, Part E.

mutable struct Observable{T}
    value::T
    subs::Vector{Function}   # each: (newvalue) -> anything (return ignored)
end
Observable(v::T) where {T} = Observable{T}(v, Function[])

getvalue(o::Observable) = o.value

"Set the observable's value and notify all subscribers with the new value."
function set!(o::Observable, v)
    o.value = v
    for f in o.subs
        f(v)
    end
    return v
end

"Subscribe `f` to changes; returns `f` so it can be passed to `off`."
function on(f::Function, o::Observable)
    push!(o.subs, f)
    return f
end

"Unsubscribe a previously-registered listener."
function off(f::Function, o::Observable)
    idx = findfirst(==(f), o.subs)
    idx !== nothing && deleteat!(o.subs, idx)
    return o
end
