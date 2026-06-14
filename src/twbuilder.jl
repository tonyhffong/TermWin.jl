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

# Sizing
Let content size itself; impose dimensions only on the **outermost** container —
it is the on-screen window, and the one place `height`/`width`/`posx`/`posy`
take effect. A nested `vstack`/`hstack` shrink-wraps to its content, so a size
passed to an inner list is ignored. If a view is just two columns, make the
`hstack` the root rather than wrapping it in a single-child `vstack`.

Two gotchas:
- A child whose effective size after border-stripping is ≤ 0 collapses to
  nothing and the children after it pile on top of it. A boxed widget
  (`borderSizeV=1`) needs `height ≥ 3`; in general leave a one-line widget's
  height unset rather than forcing a small number.
- A fraction-sized child (`width=1.0`) inside a shrink-wrapped list resolves
  against the list's *default* canvas (128×80) and balloons it. Give full-width
  helpers (e.g. a header `newTwLabel` in a column) an explicit width.

See `hstack` for the horizontal counterpart; both re-place their children after
the `do` block so nested columns/rows land in the right place.
"""
function vstack(
    f::Function,
    parent::TwObj = rootTwScreen;
    height::Real = 1.0,
    width::Real = 1.0,
    posy::Any = :top,
    posx::Any = :left,
    defaults = nothing,
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
    reflow_children!(list)      # re-place children now that their sizes are settled
    defaults !== nothing && apply_defaults!(list, defaults)
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
    defaults = nothing,
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
    reflow_children!(list)      # re-place children now that their sizes are settled
    defaults !== nothing && apply_defaults!(list, defaults)
    list
end

# ---------------------------------------------------------------------------
# @twlayout macro — flat-layout DSL
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Widget registry — short names recognised inside @twlayout / vstack / hstack
# ---------------------------------------------------------------------------
#
# Maps a short name (e.g. :viewer) to a widget *constructor function*. The DSL
# injects the layout container as the constructor's first argument, so a
# registered constructor must accept `ctor(parent::TwObj, args...; kwargs...)`.
#
# This registry is mutable and resolved at *runtime* (see `_twlayout_lookup`,
# used by macro-generated code). That is what makes the layout DSL extensible:
# an external package registers its own widget at load time and the short name
# becomes usable in any subsequent @twlayout / vstack / hstack body — without
# the constructor having to live in the TermWin module.
const _TWLAYOUT_REGISTRY = Dict{Symbol,Function}()

"""
    register_twlayout_widget!(name::Symbol, ctor::Function)

Register a widget constructor under a short `name` usable inside `@twlayout`,
`vstack`, and `hstack` bodies. The layout container is injected automatically as
the constructor's first positional argument, so `ctor` must have the shape

    ctor(parent::TwObj, args...; kwargs...) -> TwObj

and typically ends by calling [`link_parent_child`](@ref). Re-registering an
existing name overwrites it (so a package may override a built-in).

See also [`unregister_twlayout_widget!`](@ref), [`twlayout_widgets`](@ref).
"""
function register_twlayout_widget!(name::Symbol, ctor::Function)
    _TWLAYOUT_REGISTRY[name] = ctor
    return nothing
end

"""
    unregister_twlayout_widget!(name::Symbol)

Remove a short name previously added with [`register_twlayout_widget!`](@ref).
No-op if the name is not registered.
"""
function unregister_twlayout_widget!(name::Symbol)
    delete!(_TWLAYOUT_REGISTRY, name)
    return nothing
end

"""
    twlayout_widgets() -> Vector{Symbol}

Sorted list of all short names currently registered for the layout DSL
(built-ins plus any added via [`register_twlayout_widget!`](@ref)).
"""
twlayout_widgets() = sort!(collect(keys(_TWLAYOUT_REGISTRY)))

# Runtime resolver used by macro-generated code; returns the constructor or
# `nothing` (in which case the macro falls back to evaluating the call as-is).
_twlayout_lookup(name::Symbol) = get(_TWLAYOUT_REGISTRY, name, nothing)

# Transform one statement from a @twlayout body.
# Recognised forms:
#   vstack(begin...end; kwargs...) / hstack(begin...end; kwargs...)
#       → vstack(list_sym; kwargs...) do #inner; transformed_body; end
#   viewer(args...; kw...) etc (short widget names)
#       → newTwViewer(list_sym, args...; kw...)
#   Everything else passes through as-is (escaped to caller scope).
function _twlayout_transform(list_sym::Symbol, stmt)
    if stmt isa Expr && stmt.head == :call
        fname = stmt.args[1]

        # ── vstack / hstack with begin...end body ───────────────────────────
        if fname isa Symbol && fname in (:vstack, :hstack)
            has_kw   = length(stmt.args) >= 2 &&
                       stmt.args[2] isa Expr &&
                       stmt.args[2].head == :parameters
            kw_node  = has_kw ? stmt.args[2] : nothing
            pos_args = stmt.args[(has_kw ? 3 : 2):end]

            if !isempty(pos_args) &&
               pos_args[1] isa Expr && pos_args[1].head == :block
                block_expr = pos_args[1]
                inner_sym  = gensym("inner")

                inner_stmts = Any[]
                for s in block_expr.args
                    s isa LineNumberNode && continue
                    push!(inner_stmts, _twlayout_transform(inner_sym, s))
                end

                new_call_args = Any[GlobalRef(_TWBUILDER_MODULE, fname), list_sym]
                new_call = Expr(:call, new_call_args...)
                if kw_node !== nothing
                    escaped_kws = map(kw_node.args) do kw
                        kw isa Expr && kw.head == :kw ?
                            Expr(:kw, kw.args[1], esc(kw.args[2])) : esc(kw)
                    end
                    insert!(new_call.args, 2, Expr(:parameters, escaped_kws...))
                end

                lambda = Expr(:->, Expr(:tuple, inner_sym), Expr(:block, inner_stmts...))
                return Expr(:do, new_call, lambda)
            end
        end

        # ── registered widget short name (resolved at runtime) ───────────────
        # Any bare-symbol call that is not vstack/hstack becomes a runtime-guarded
        # form:
        #     let _ctor = TermWin._twlayout_lookup(:name)
        #         _ctor === nothing ? <original call> : _ctor(list_sym, args...; kw...)
        #     end
        # If :name is registered (built-in or external), the parent container is
        # injected and the widget is built. Otherwise the original call runs
        # unchanged — so arbitrary user code (e.g. println(...)) still passes
        # through, exactly as before. Resolution is deferred to runtime so that
        # load-time registrations from external packages are visible.
        if fname isa Symbol && !(fname in (:vstack, :hstack))
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

            ctor_sym = gensym("ctor")

            # _ctor(list_sym, escaped_pos...; escaped_kw...)
            ctor_call = Expr(:call, ctor_sym, list_sym)
            for i = pos_start:length(stmt.args)
                push!(ctor_call.args, esc(stmt.args[i]))
            end
            if kw_params !== nothing
                escaped_kws = map(kw_params.args) do kw
                    if kw isa Expr && kw.head == :kw
                        Expr(:kw, kw.args[1], esc(kw.args[2]))
                    else
                        esc(kw)     # handle splatted kwargs: f(; pairs...)
                    end
                end
                insert!(ctor_call.args, 2, Expr(:parameters, escaped_kws...))
            end

            lookup_call = Expr(:call,
                GlobalRef(_TWBUILDER_MODULE, :_twlayout_lookup), QuoteNode(fname))
            ternary = Expr(:if,
                Expr(:call, :(===), ctor_sym, :nothing),
                esc(stmt),       # not registered → run the original call as-is
                ctor_call)       # registered → build with parent injected
            return Expr(:let, Expr(:(=), ctor_sym, lookup_call), ternary)
        end
    end
    # Not a recognised call — pass through escaped (caller scope)
    return esc(stmt)
end

# Core implementation shared by both macro arities.
function _twlayout_impl(opts, body)
    # --- Optional options tuple (height=, width=, title=, ...) ---
    # A single kwarg: (title=x)   → Expr(:(=), :title, x)
    # Multiple kwargs: (h=x, w=y) → Expr(:tuple, Expr(:(=),:h,x), Expr(:(=),:w,y))
    all_opt_args = if opts !== nothing
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

    # Extract `defaults=...` — handled separately; not forwarded to newTwList
    defaults_expr = nothing
    opt_args = Expr[]
    for arg in all_opt_args
        nm = arg isa Expr && arg.head in (:(=), :kw) ? arg.args[1] : nothing
        if nm == :defaults
            defaults_expr = esc(arg.args[2])
        else
            push!(opt_args, arg)
        end
    end

    # Collect names the user explicitly specified so we don't duplicate defaults
    user_kwarg_names = Set{Symbol}(
        arg.args[1] for arg in opt_args if arg isa Expr && arg.head in (:(=), :kw)
    )

    # Build newTwList keyword args: defaults first, then user overrides.
    # Root list is always a vstack (horizontal=false); for a horizontal root,
    # nest a single hstack(begin...end) inside the body.
    list_kwargs = Expr[Expr(:kw, :horizontal, false)]
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
    reflow_ref = GlobalRef(_TWBUILDER_MODULE, :reflow_children!)
    apply_defaults_ref = GlobalRef(_TWBUILDER_MODULE, :apply_defaults!)

    # defaults_sym holds the evaluated defaults expression (or nothing)
    defaults_sym = gensym("twdefaults")

    return quote
        local $list_sym = $newTwList_ref($rootTwScreen_ref; $(list_kwargs...))
        $(transformed...)
        $update_canvas_ref($list_sym)
        $reflow_ref($list_sym)
        local $defaults_sym = $defaults_expr
        $defaults_sym !== nothing && $apply_defaults_ref($list_sym, $defaults_sym)
        $list_sym
    end
end

"""
    @twlayout begin ... end
    @twlayout (key=val, ...) begin ... end

Build a full-screen TUI layout as a vertical stacking `TwList` (vstack).

Inside the `begin...end` block, use short widget names as function calls — they
are automatically rewritten to include the layout container as their first
argument. The recognised names come from a **runtime registry**; the built-ins
are:

`viewer` `dftable` `popup` `entry` `tree` `multiselect` `calendar` `spacer`
`label` `separator` `filebrowser` `edittable`

(`viewer` → `newTwViewer`, `dftable` → `newTwDfTable`, and so on.) Call
[`twlayout_widgets`](@ref) for the live list.

**Extensibility** — an external package can add its own short name with
[`register_twlayout_widget!`](@ref); it then works inside any `@twlayout` /
`vstack` / `hstack` body just like a built-in (the container is injected as the
constructor's first argument). Resolution happens at runtime, so a name
registered at package load time is immediately usable.

**Nesting** — `vstack` and `hstack` are supported inside the body using a
`begin...end` block as their sole positional argument. The macro injects a
gensym parent argument automatically, so no lambda is needed:

```julia
hstack(begin
    viewer(left_text; width=0.5)
    viewer(right_text; width=0.5)
end)
```

Kwargs (e.g. `title=`, `box=`) may follow the block: `vstack(begin...end; title="Sub")`.

Any other expression is passed through unchanged (escaped to the caller's scope).

The optional first argument is a named-tuple forwarded to `newTwList` —
useful for `height`, `width`, `title`, `box`, etc.  If omitted, the layout
fills the entire screen (`height=1.0, width=1.0`).

# Examples

```julia
# Two-panel layout filling the screen:
function TermWin.tshow_(r::MyResult; kwargs...)
    @twlayout begin
        viewer(format_summary(r); height=0.3, title="Summary")
        dftable(r.data;           height=0.7, title="Data")
    end
end

# With explicit sizing and a title for the container:
@twlayout (height=0.9, width=0.9, title="Results") begin
    viewer(text;  height=0.4)
    dftable(df;   height=0.6)
end

# Nested containers with begin...end syntax:
@twlayout (title="Split view") begin
    viewer(header; height=3)
    hstack(begin
        dftable(left_df;  width=0.5, title="Left")
        vstack(begin
            separator()
            dftable(right_df; title="Right-top")
            separator()
        end)
    end)
end
```
"""
macro twlayout(body)
    _twlayout_impl(nothing, body)
end

macro twlayout(opts, body)
    _twlayout_impl(opts, body)
end

# ---------------------------------------------------------------------------
# Register the built-in widgets. (Their constructors are defined in files
# included before twbuilder.jl, so they are available at module-load time.)
# External packages add their own via register_twlayout_widget!.
# ---------------------------------------------------------------------------
register_twlayout_widget!(:viewer,      newTwViewer)
register_twlayout_widget!(:dftable,     newTwDfTable)
register_twlayout_widget!(:popup,       newTwPopup)
register_twlayout_widget!(:entry,       newTwEntry)
register_twlayout_widget!(:tree,        newTwTree)
register_twlayout_widget!(:multiselect, newTwMultiSelect)
register_twlayout_widget!(:calendar,    newTwCalendar)
register_twlayout_widget!(:spacer,      newTwSpacer)
register_twlayout_widget!(:label,       newTwLabel)
register_twlayout_widget!(:separator,   newTwSeparator)
register_twlayout_widget!(:filebrowser, newTwFileBrowser)
register_twlayout_widget!(:edittable,   newTwEditTable)
