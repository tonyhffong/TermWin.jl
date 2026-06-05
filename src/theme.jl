# ===== Theme: semantic color/style tokens over COLOR_PAIR =====
#
# `COLOR_PAIR(n)` already returns a `TwAttr` (the hard channel/style separation
# lives in consts.jl). The only missing piece is a name → TwAttr indirection so
# widgets stop hardcoding integers like `COLOR_PAIR(15)` = "focused selection".
# See design/termwin-widget-authoring-rearchitecture.md, Part B.
#
# IMPORTANT: theme tokens that use COLOR_PAIR must be *built* after
# `color_channel_table` is populated (in initsession), otherwise COLOR_PAIR
# resolves to channels=0. `refresh_theme!()` (called from initsession) rebuilds
# the active theme so its tokens capture real channels. Before a session exists
# the theme still builds — tokens just carry the same channels=0 COLOR_PAIR would
# return at that point, which is harmless for headless unit tests.

struct Theme
    name::Symbol
    tokens::Dict{Symbol,Any}   # value: TwAttr | Char (e.g. focus indicator glyph)
end

# ----- Theme builders (called lazily / at initsession) -----

function default_theme()
    Theme(:default, Dict{Symbol,Any}(
        :selection_focused   => COLOR_PAIR(15),         # white on blue
        :selection_unfocused => COLOR_PAIR(30),         # white on dark blue
        :header              => COLOR_PAIR(3),          # yellow
        :divider             => COLOR_PAIR(13),         # white on dark gray
        :negative            => COLOR_PAIR(1),          # red
        :emphasis            => make_attr(A_BOLD, A_UNDERLINE),
        :focus_indicator     => '▶',
    ))
end

# A higher-contrast variant, proving the table is swappable. Uses reverse video
# for the focused row and bold for emphasis so it reads on monochrome terminals.
function high_contrast_theme()
    Theme(:high_contrast, Dict{Symbol,Any}(
        :selection_focused   => make_attr(COLOR_PAIR(7), A_REVERSE),
        :selection_unfocused => COLOR_PAIR(13),
        :header              => make_attr(COLOR_PAIR(7), A_BOLD),
        :divider             => COLOR_PAIR(7),
        :negative            => make_attr(COLOR_PAIR(1), A_BOLD),
        :emphasis            => make_attr(A_BOLD, A_UNDERLINE),
        :focus_indicator     => '▶',
    ))
end

const THEME_BUILDERS = Dict{Symbol,Function}(
    :default       => default_theme,
    :high_contrast => high_contrast_theme,
)

# The active theme. A Ref so a swap is a single assignment; widgets read through
# `theme(sym)` so they pick up the change on their next draw.
const current_theme = Ref{Theme}()

function _ensure_theme()
    isassigned(current_theme) || (current_theme[] = default_theme())
    return current_theme[]
end

"""
    theme(sym::Symbol) -> TwAttr | Char

Resolve a semantic token (e.g. `:selection_focused`, `:header`) to its `TwAttr`
under the active theme. Replaces scattered `COLOR_PAIR(n)` magic numbers.
"""
function theme(sym::Symbol)
    t = _ensure_theme()
    haskey(t.tokens, sym) || error("unknown theme token :" * string(sym))
    return t.tokens[sym]
end

"""
    set_theme!(name::Symbol)

Switch the active theme by name (`:default`, `:high_contrast`). Rebuilds the
token table so COLOR_PAIR tokens capture the current channels.
"""
function set_theme!(name::Symbol)
    haskey(THEME_BUILDERS, name) || error("unknown theme :" * string(name))
    current_theme[] = THEME_BUILDERS[name]()
    return current_theme[]
end

# Rebuild the active theme in place. Called from initsession() after
# color_channel_table is populated so COLOR_PAIR tokens resolve to real channels.
function refresh_theme!()
    name = isassigned(current_theme) ? current_theme[].name : :default
    builder = get(THEME_BUILDERS, name, default_theme)
    current_theme[] = builder()
    return current_theme[]
end
