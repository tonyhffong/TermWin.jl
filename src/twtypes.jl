# heavily modeled after CDK

# a list of functions that any widget would have
# At a minimum, a new widget MUST have their own drawTw<widgetname> function
# All other methods with their TwObj dummy default behavior, which may
# or may not do what you want.
# The functions are automatically discovered as long as they are either defined in
# TermWin, or exported to Main.

mutable struct TwWindow
    parent::WeakRef # to another TwObj, or nothing
    yloc::Int # 0-based
    xloc::Int
    height::Int # this is to help do box/erase
    width::Int
end

mutable struct TwObj{T,S}
    screen::WeakRef # the parent screen
    screenIndex::Int
    window::Union{Nothing,NC.Plane,TwWindow}
    # panel field removed: Notcurses planes have built-in z-ordering
    height::Int
    width::Int
    xpos::Int
    ypos::Int
    box::Bool
    borderSizeV::Int # how thick is the border at top and botom
    borderSizeH::Int # how thick is the border at left and right edges
    acceptsFocus::Bool
    hasFocus::Bool
    grabUnusedKey::Bool
    isVisible::Bool
    data::T
    value::Any # the logical "content" that this object contains (return value if editable)
    title::String
    formkey::Union{Nothing,Symbol} # key for form collection; nothing means not a form field
    # Original size/position spec passed to link_parent_child. Preserved so that
    # the widget can be re-laid out against a new parent size on terminal resize.
    # `nothing` means the widget was constructed without going through
    # link_parent_child (e.g. the root TwScreen) and is not auto-relayoutable.
    desiredHeight::Any
    desiredWidth::Any
    desiredPosy::Any
    desiredPosx::Any
    listeners::Dict{Symbol,Array} # event=>array of registered listeners. each listener is of the type (o, ev)->Nothing
    session_id::Int # which session created this widget
    function TwObj{T,S}(data::T) where {T,S}
        log("TwObj datatype=" * string(T) * " TwObjSubtype=" * string(S))
        x = new{T,S}(
            WeakRef(),
            0,
            nothing,
            0,
            0,
            0,
            0,
            false,
            0,
            0,
            true,
            true,
            false,
            true,
            data,
            nothing,
            "",
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            Dict{Symbol,Array{Function,1}}(),
            current_session_id,
        )
        finalizer(
            y->begin
                global rootplane, nc_context, current_session_id
                # Only destroy the plane when the active session is the same one that
                # created this widget.  If a different session is active (or none),
                # NC.stop() has already freed every plane from the old session, so
                # calling NC.destroy here would be a double-free / use-after-free.
                if nc_context !== nothing &&
                   y.session_id == current_session_id &&
                   isa(y.window, NC.Plane) &&
                   y.window != rootplane
                    NC.destroy(y.window)
                    y.window = nothing
                end
                if y.screen.value !== nothing &&
                   nc_context !== nothing &&
                   y.session_id == current_session_id
                    unregisterTwObj(y.screen.value, y)
                    y.screen = WeakRef()
                end
                y.listeners = Dict{Symbol,Array{Function,1}}()
            end,
            x,
        )
        x
    end
end

# bookkeeping data for a screen
mutable struct TwScreenData
    objects::Vector{TwObj}
    focus::Int
    TwScreenData() = new(TwObj[], 0)
end

mutable struct TwListData
    horizontal::Bool
    widgets::Vector{TwObj} # this is static.
    focus::Int # which of the widgets has the focus
    canvasheight::Int
    canvaswidth::Int
    pad::Union{Nothing,NC.Plane} # nothing, or Notcurses Plane for the canvas
    canvaslocx::Int # 0-based, view's location on canvas
    canvaslocy::Int # 0-based
    showLineInfo::Bool
    navigationmode::Bool
    isForm::Bool
    bottomText::String
    session_id::Int
    function TwListData()
        ret = new(
            false,
            TwObj[],
            0,
            0,
            0,
            nothing,
            0,
            0,
            false,
            false,
            false,
            "",
            current_session_id,
        )
        finalizer(
            y->begin
                global nc_context, current_session_id
                if nc_context !== nothing &&
                   y.session_id == current_session_id &&
                   y.pad !== nothing
                    NC.destroy(y.pad)
                end
            end,
            ret,
        )
        ret
    end
end

const TwScreen = TwObj{TwScreenData}

function TwObj(d::T, ::Type{Val{S}}) where {T,S}
    return (TwObj{T,S}(d))
end
import Base.show

function Base.show(io::IO, o::TwObj{TwListData})
    if o.data.horizontal
        print(io, "HList(")
    else
        print(io, "VList(")
    end
    for w in o.data.widgets
        strs = split(string(w), "\n")
        for s in strs
            print(io, "\n  ")
            print(io, s)
        end
    end
    print(io, ")")
end

function Base.show(io::IO, o::TwObj)
    print(io, "TwObj("*string(objtype(o))*"="*string(o.value)*")")
end

draw(p::TwObj) = error(string(p) * " draw is undefined.")
objtype(_::TwObj{T,S}) where {T,S} = S

# Fallback: widget types without an apply_default! method are silently skipped.
apply_default!(::TwObj, ::Any) = nothing
