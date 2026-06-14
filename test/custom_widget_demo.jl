# custom_widget_demo.jl — authoring a third-party widget and plugging it into the DSL
#
# This file is written exactly as an *external* package would write it: it only
# uses TermWin's public widget-authoring API (see
# design/termwin-widget-authoring-guide.md). It defines a small interactive
# `StarRating` widget, registers it under the short name `stars`, and then uses
# that short name inside a `@twlayout` form alongside a built-in `entry` — proving
# that registration, parent injection, and form collection all work for a widget
# TermWin has never heard of.
#
# Usage (interactive, needs a TTY):
#   julia --project=. test/custom_widget_demo.jl
#
# Controls inside the rating field:
#   ← / h     decrease    → / l     increase    1‥5  set directly
#   Tab       next field  F10       submit       Esc  cancel

using TermWin

# Extend these TermWin generics with methods for our own data type. Importing the
# names lets us define them unqualified; `TermWin.draw(...)` would work too.
import TermWin: draw, inject, bindings

# ── 1. Widget state ───────────────────────────────────────────────────────────
# All per-widget state lives in a data struct; the widget is a `TwObj{StarRatingData}`.

mutable struct StarRatingData
    maxstars::Int
    current::Int
end

# ── 2. Constructor ────────────────────────────────────────────────────────────
# Convention: first arg is the parent container; end by calling link_parent_child.
# `key` opts the widget into form collection; `o.value` is what the form harvests.

function newStarRating(parent::TwObj;
                       key::Union{Nothing,Symbol} = nothing,
                       maxstars::Int = 5,
                       value::Int = 0,
                       height::Real = 1,
                       width::Real = 1.0,
                       posy = :top,
                       posx = :left)
    data = StarRatingData(maxstars, clamp(value, 0, maxstars))
    o = TwObj(data, Val{:StarRating})
    o.acceptsFocus = true        # it takes keyboard focus
    o.box         = false
    o.borderSizeV = 0
    o.borderSizeH = 0
    o.value   = data.current     # logical value collected in forms
    o.formkey = key
    link_parent_child(parent, o, height, width, posy, posx)
    o
end

# ── 3. Rendering ──────────────────────────────────────────────────────────────
# Draw into `o.window` (an NC.Plane or, inside a layout, a TwWindow). Use the
# exported drawing primitives and semantic theme tokens — never magic color ints.

function draw(o::TwObj{StarRatingData})
    werase(o.window)
    d = o.data
    glyphs = repeat("★", d.current) * repeat("☆", d.maxstars - d.current)
    label  = glyphs * "  (" * string(d.current) * "/" * string(d.maxstars) * ")"
    focused = o.hasFocus
    focused && wattron(o.window, theme(:selection_focused))
    mvwprintw(o.window, 0, 0, "%s", label)
    focused && wattroff(o.window, theme(:selection_focused))
end

# ── 4. Key handling ───────────────────────────────────────────────────────────
# Declare the keymap once as data. `bindings` drives the auto-generated F1 help
# and footer; `inject_via_table` dispatches a token to the first matching action.
# Actions return an InjectResult (Handled / Ignored / Accept / Cancel).

function _star_set!(o, n)
    o.data.current = clamp(n, 0, o.data.maxstars)
    o.value = o.data.current     # keep the collectable value in sync
    Handled
end

function bindings(o::TwObj{StarRatingData})
    Binding[
        Binding([:left, "h"],  "−1 star", action = o -> _star_set!(o, o.data.current - 1)),
        Binding([:right, "l"], "+1 star", action = o -> _star_set!(o, o.data.current + 1)),
        Binding("1",           "1‥5 set", action = o -> _star_set!(o, 1)),  # 2‥5 handled in inject
        Binding(:enter,        "confirm", action = o -> Accept),            # in a form: advance field
    ]
end

function inject(o::TwObj{StarRatingData}, token)
    # A digit sets the rating directly. (inject_via_table can't see the token, so
    # multi-key digit handling lives here; the "1" binding above documents it.)
    if token isa String && length(token) == 1 && isdigit(token[1])
        return _star_set!(o, parse(Int, token))
    end
    return inject_via_table(o, token)   # Ignored if nothing matches → bubbles up (Tab/Esc)
end

# ── 5. Register the short name ────────────────────────────────────────────────
# After this, `stars(...)` works inside any @twlayout / vstack / hstack body.

register_twlayout_widget!(:stars, newStarRating)

# ── 6. Use it — a form mixing a built-in `entry` and our custom `stars` ────────

TermWin.initsession()

form = @twlayout (form = true, title = "Feedback", height = 0.4, width = 0.5) begin
    label("Rate your experience"; style = :header)
    entry(String; key = :name, title = "Name", width = 32, titlewidth = 8)
    stars(; key = :rating, maxstars = 5, value = 3)
    label("←/→ or 1‥5 to rate · Tab next · F10 submit · Esc cancel"; style = :divider)
end

activateTwObj(rootTwScreen)
result = form.value
TermWin.endsession()

# ── 7. Show what the form collected ───────────────────────────────────────────

if result === nothing
    println("Cancelled.")
else
    println("Submitted:")
    println("  name   : ", repr(get(result, :name, "")))
    println("  rating : ", get(result, :rating, 0), " / 5")
end
