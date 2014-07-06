# heavily modeled after CDK

# a list of functions that any widget would have
# At a minimum, a new widget MUST have their own drawTw<widgetname> function
# All other methods with their TwObj dummy default behavior, which may
# or may not do what you want.
# The functions are automatically discovered as long as they are either defined in
# TermWin, or exported to Main.

type TwFunc
    objtype::Symbol
    draw::Function
    erase::Function # default to eraseTwObj
    move::Function # default to moveTwObj
    inject::Function # send a key to this thing. Tips: make it small to minimize initial jit-delay
    focus::Function # default to dummy
    unfocus::Function # default to dummy
    refresh::Function # default to dummy
end

type TwObj
    screen::WeakRef # the parent screen
    screenIndex::Int
    window::Union( Nothing, Ptr{Void} )
    panel::Union( Nothing, Ptr{Void} )
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
    data::Any
    value::Any # the logical "content" that this object contains (return value if editable)
    title::String
    fn::TwFunc
    listeners::Dict{ Symbol, Array } # event=>array of registered listeners. each listener is of the type (o, ev)->Nothing
    function TwObj( f::TwFunc )
        x = new( WeakRef(), 0,
            nothing,
            nothing,
            0, 0, 0, 0,
            false, 0, 0,
            true, true, false, true, nothing, nothing, "", f, Dict{Symbol, Array{Function,1} }() )
        finalizer( x, y->begin
            if y.panel != nothing
                del_panel( y.panel )
                y.panel = nothing
            end
            if y.window != nothing && y.window != rootwin
                delwin( y.window )
                y.window = nothing
            end
            if y.screen.value != nothing
                unregisterTwObj( y.screen.value, y )
                y.screen = WeakRef()
            end
            y.listeners = Dict{Symbol,Array{Function,1}}()
        end )
        x
    end
end
import Base.show

function Base.show( io::IO, o::TwObj )
    print( io, "TwObj("*string(o.fn.objtype)*")")
end
function Base.show( io::IO, f::TwFunc )
    print( io, "TwFunc("*string(f.objtype)*")")
end

draw( p::TwObj ) = p.fn.draw( p )
erase( p::TwObj ) = p.fn.erase( p )
move( p::TwObj, y, x, relative, refresh ) = p.fn.move( p, y, x, relative, refresh )
inject( p::TwObj, k ) = p.fn.inject( p, k )
focus( p::TwObj ) = p.fn.focus( p )
unfocus( p::TwObj ) = p.fn.unfocus( p )
refresh( p::TwObj ) = p.fn.refresh( p )
objtype( p::TwObj ) = p.fn.objtype
