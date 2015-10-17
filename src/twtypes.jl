# heavily modeled after CDK

# a list of functions that any widget would have
# At a minimum, a new widget MUST have their own drawTw<widgetname> function
# All other methods with their TwObj dummy default behavior, which may
# or may not do what you want.
# The functions are automatically discovered as long as they are either defined in
# TermWin, or exported to Main.

if VERSION < v"0.4.0-dev+2275"
    immutable Val{T}
    end
    export Val
end

type TwWindow
    parent::WeakRef # to another TwObj, or nothing
    yloc::Int # 0-based
    xloc::Int
    height::Int # this is to help do box/erase
    width::Int
end

type TwObj{T,S}
    screen::WeakRef # the parent screen
    screenIndex::Int
    window::Union{ Void, Ptr{Void}, TwWindow }
    panel::Union{ Void, Ptr{Void} } # when window is a TwWindow, this is nothing
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
    title::UTF8String
    listeners::Dict{ Symbol, Array } # event=>array of registered listeners. each listener is of the type (o, ev)->Void
    function TwObj( data::T )
        log( "TwObj datatype=" * string( T ) * " TwObjSubtype="*string(S) )
        x = new( WeakRef(), 0,
            nothing,
            nothing,
            0, 0, 0, 0,
            false, 0, 0,
            true, true, false, true, data, nothing, utf8(""), Dict{Symbol, Array{Function,1} }() )
        finalizer( x, y->begin
            global rootwin
            if y.panel != nothing
                del_panel( y.panel )
                y.panel = nothing
            end
            if typeof( y.window ) <: Ptr && y.window != rootwin
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

# bookkeeping data for a screen
type TwScreenData
    objects::Array{TwObj, 1 }
    focus::Int
    TwScreenData() = new( TwObj[], 0 )
end

type TwListData
    horizontal::Bool
    widgets::Array{TwObj,1} # this is static.
    focus::Int # which of the widgets has the focus
    canvasheight::Int
    canvaswidth::Int
    pad::Union{ Void, Ptr{Void} } # nothing, or Ptr{Void} to the WINDOW from calling newpad()
    canvaslocx::Int # 0-based, view's location on canvas
    canvaslocy::Int # 0-based
    showLineInfo::Bool
    navigationmode::Bool
    bottomText::UTF8String
    function TwListData()
        ret = new( false, TwObj[], 0, 0, 0, nothing, 0, 0, false, false, utf8("") )
        finalizer( ret, y->begin
            if y.pad != nothing
                delwin( y.pad )
            end
        end)
        ret
    end
end

typealias TwScreen TwObj{TwScreenData}

function TwObj{T,S}( d::T, ::Type{Val{S}} ) 
    return( TwObj{T,S}(d) )
end
import Base.show

function Base.show( io::IO, o::TwObj{TwListData} )
    if o.data.horizontal
        print( io, "HList(")
    else
        print( io, "VList(")
    end
    for w in o.data.widgets
        strs = split( string(w), "\n" )
        for s in strs
            print( io, "\n  ")
            print( io, s )
        end
    end
    print( io, ")")
end

function Base.show( io::IO, o::TwObj )
    print( io, "TwObj("*string(objtype(o))*"="*string(o.value)*")")
end

draw( p::TwObj ) = error( string( p ) * " draw is undefined.")
objtype{T,S}( _::TwObj{T,S} ) = S
