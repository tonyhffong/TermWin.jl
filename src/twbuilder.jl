# twbuilder.jl — composable layout API for package developers
#
# Package developers can display their own types via TermWin by:
#   1. Defining  TermWin.tshow_(x::MyType; kwargs...)  (multiple dispatch)
#   2. Building layouts with  vstack / hstack  (do-block builders)
#   3. Using  @twlayout  for a concise flat-layout DSL
#
# All widget constructors accept a TwObj as their first argument; widgets
# constructed inside vstack/hstack with that list as parent are auto-stacked.

const _TWBUILDER_MODULE = @__MODULE__   # = TermWin, captured at compile time

# ---------------------------------------------------------------------------
# vstack / hstack — do-block layout builders
# ---------------------------------------------------------------------------

"""
    vstack([f,] [parent=rootTwScreen]; height=1.0, width=1.0, kwargs...) -> TwObj

Create a vertical stacking container backed by a `TwList` and pass it to `f`.
Widgets constructed inside `f` with the container as their first argument are
automatically stacked top-to-bottom. `height` and `width` may be `Int` (rows/cols)
or `Float64` in `(0,1]` (fraction of the parent's size).

# Example
```julia
function TermWin.tshow_(r::MyResult; kwargs...)
    vstack(; title=r.name) do parent
        newTwViewer(parent, summary(r); height=0.3, title="Summary")
        newTwDfTable(parent, r.data;    height=0.7, title="Data")
    end
end
```

For multi-panel nesting, call `hstack` or `vstack` inside the outer `do` block:
```julia
vstack(; title="Layout") do outer
    newTwViewer(outer, header_text; height=4)
    hstack(outer; height=0.9) do inner
        newTwDfTable(inner, left_df;  width=0.5)
        newTwDfTable(inner, right_df; width=0.5)
    end
end
```
"""
function vstack(
    f::Function,
    parent::TwObj = rootTwScreen;
    height::Real = 1.0,
    width::Real = 1.0,
    posy::Any = :top,
    posx::Any = :left,
    kwargs...,
)
    list = newTwList(
        parent;
        horizontal = false,
        height = height,
        width = width,
        posy = posy,
        posx = posx,
        kwargs...,
    )
    f(list)
    update_list_canvas(list)    # finalize canvas after all children are sized
    list
end

"""
    hstack([f,] [parent=rootTwScreen]; height=1.0, width=1.0, kwargs...) -> TwObj

Create a horizontal stacking container. Widgets constructed inside `f` with the
container as their first argument are stacked left-to-right. See `vstack` for
further details and examples.
"""
function hstack(
    f::Function,
    parent::TwObj = rootTwScreen;
    height::Real = 1.0,
    width::Real = 1.0,
    posy::Any = :top,
    posx::Any = :left,
    kwargs...,
)
    list = newTwList(
        parent;
        horizontal = true,
        height = height,
        width = width,
        posy = posy,
        posx = posx,
        kwargs...,
    )
    f(list)
    update_list_canvas(list)
    list
end

# ---------------------------------------------------------------------------
# @twlayout macro — flat-layout DSL
# ---------------------------------------------------------------------------

# Short widget names recognised inside a @twlayout body
const _TW_WIDGET_CTORS = Dict{Symbol,Symbol}(
    :viewer => :newTwViewer,
    :dftable => :newTwDfTable,
    :popup => :newTwPopup,
    :entry => :newTwEntry,
    :tree => :newTwTree,
    :multiselect => :newTwMultiSelect,
    :calendar => :newTwCalendar,
    :spacer => :newTwSpacer,
    :label => :newTwLabel,
    :filebrowser => :newTwFileBrowser,
)

# Transform one statement from a @twlayout body.
# Recognised widget calls: viewer(args...; kw...) → newTwViewer(list_sym, args...; kw...)
# Everything else passes through as-is (escaped to caller scope).
function _twlayout_transform(list_sym::Symbol, stmt)
    if stmt isa Expr && stmt.head == :call
        fname = stmt.args[1]
        if fname isa Symbol && haskey(_TW_WIDGET_CTORS, fname)
            ctor = GlobalRef(_TWBUILDER_MODULE, _TW_WIDGET_CTORS[fname])
            new_args = Any[ctor]

            # Keyword parameters node (:parameters) appears as the second arg in
            # the Julia AST when any keyword args are present: f(; k=v, pos_arg)
            kw_params = nothing
            pos_start = 2
            if length(stmt.args) >= 2 &&
               stmt.args[2] isa Expr &&
               stmt.args[2].head == :parameters
                kw_params = stmt.args[2]
                pos_start = 3
            end

            # First positional arg after the constructor is the list parent
            push!(new_args, list_sym)

            # Remaining positional args — escape them for caller scope
            for i = pos_start:length(stmt.args)
                push!(new_args, esc(stmt.args[i]))
            end

            result = Expr(:call, new_args...)

            # Re-attach keyword args with their values escaped
            if kw_params !== nothing
                escaped_kws = map(kw_params.args) do kw
                    if kw isa Expr && kw.head == :kw
                        Expr(:kw, kw.args[1], esc(kw.args[2]))
                    else
                        esc(kw)     # handle splatted kwargs: f(; pairs...)
                    end
                end
                insert!(result.args, 2, Expr(:parameters, escaped_kws...))
            end

            return result
        end
    end
    # Not a recognised widget call — pass through escaped (caller scope)
    return esc(stmt)
end

# Core implementation shared by both macro arities.
function _twlayout_impl(orientation, opts, body)
    # --- Orientation ---
    orient_sym = if orientation isa QuoteNode
        orientation.value
    elseif orientation isa Symbol
        orientation
    else
        error("@twlayout: first arg must be :vertical or :horizontal")
    end
    horizontal = (orient_sym == :horizontal)

    # --- Optional options tuple (height=, width=, title=, ...) ---
    # A single kwarg: (title=x)   → Expr(:(=), :title, x)
    # Multiple kwargs: (h=x, w=y) → Expr(:tuple, Expr(:(=),:h,x), Expr(:(=),:w,y))
    opt_args = if opts !== nothing
        if opts isa Expr && opts.head == :tuple
            opts.args
        elseif opts isa Expr && opts.head == :(=)
            [opts]
        else
            Expr[]
        end
    else
        Expr[]
    end

    # Collect names the user explicitly specified so we don't duplicate defaults
    user_kwarg_names = Set{Symbol}(
        arg.args[1] for arg in opt_args if arg isa Expr && arg.head in (:(=), :kw)
    )

    # Build newTwList keyword args: defaults first, then user overrides
    list_kwargs = Expr[Expr(:kw, :horizontal, horizontal)]
    :height ∉ user_kwarg_names && push!(list_kwargs, Expr(:kw, :height, 1.0))
    :width ∉ user_kwarg_names && push!(list_kwargs, Expr(:kw, :width, 1.0))
    :posy ∉ user_kwarg_names && push!(list_kwargs, Expr(:kw, :posy, QuoteNode(:top)))
    :posx ∉ user_kwarg_names && push!(list_kwargs, Expr(:kw, :posx, QuoteNode(:left)))
    for arg in opt_args
        if arg isa Expr && arg.head == :(=)
            push!(list_kwargs, Expr(:kw, arg.args[1], esc(arg.args[2])))
        elseif arg isa Expr && arg.head == :kw
            push!(list_kwargs, Expr(:kw, arg.args[1], esc(arg.args[2])))
        end
    end

    # --- Transform body ---
    body_stmts = body isa Expr && body.head == :block ? body.args : [body]

    list_sym = gensym("twlist")

    transformed = Any[]
    for stmt in body_stmts
        stmt isa LineNumberNode && continue
        push!(transformed, _twlayout_transform(list_sym, stmt))
    end

    # --- Generate code ---
    newTwList_ref = GlobalRef(_TWBUILDER_MODULE, :newTwList)
    rootTwScreen_ref = GlobalRef(_TWBUILDER_MODULE, :rootTwScreen)
    update_canvas_ref = GlobalRef(_TWBUILDER_MODULE, :update_list_canvas)

    return quote
        local $list_sym = $newTwList_ref($rootTwScreen_ref; $(list_kwargs...))
        $(transformed...)
        $update_canvas_ref($list_sym)
        $list_sym
    end
end

"""
    @twlayout orientation begin ... end
    @twlayout orientation (key=val, ...) begin ... end

Build a full-screen TUI layout as a vertical or horizontal `TwList`.

`orientation` must be `:vertical` or `:horizontal`.

Inside the `begin...end` block, use short widget names as function calls —
they are automatically rewritten to include the layout container as their
first argument:

| Short name   | Expands to          |
|:-------------|:--------------------|
| `viewer`     | `newTwViewer`       |
| `dftable`    | `newTwDfTable`      |
| `popup`      | `newTwPopup`        |
| `entry`      | `newTwEntry`        |
| `tree`       | `newTwTree`         |
| `multiselect`| `newTwMultiSelect`  |
| `calendar`   | `newTwCalendar`     |

Any other expression (including `vstack`/`hstack` calls for nesting) is
passed through unchanged.

The optional second argument is a named-tuple forwarded to `newTwList` —
useful for `height`, `width`, `title`, `box`, etc.  If omitted, the layout
fills the entire screen (`height=1.0, width=1.0`).

# Examples

```julia
# Two-panel layout filling the screen:
function TermWin.tshow_(r::MyResult; kwargs...)
    @twlayout :vertical begin
        viewer(format_summary(r); height=0.3, title="Summary")
        dftable(r.data;           height=0.7, title="Data")
    end
end

# With explicit sizing and a title for the container:
@twlayout :vertical (height=0.9, width=0.9, title="Results") begin
    viewer(text;  height=0.4)
    dftable(df;   height=0.6)
end

# Nested split — use vstack/hstack inside the body:
@twlayout :horizontal begin
    viewer(text; width=0.3)
    vstack(; width=0.7) do inner
        newTwDfTable(inner, top_df;    height=0.5)
        newTwDfTable(inner, bottom_df; height=0.5)
    end
end
```
"""
macro twlayout(orientation, body)
    _twlayout_impl(orientation, nothing, body)
end

macro twlayout(orientation, opts, body)
    _twlayout_impl(orientation, opts, body)
end
