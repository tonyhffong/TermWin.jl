# ===== Bindings as data =====
#
# A widget's keymap, footer string, and F1 help are written three times today
# (the inject ladder, the default*BottomText constant, the default*HelpText
# constant) and drift apart. A `Binding` declares a key→action once; the footer
# and help are *generated* from the same table, and `inject_via_table` provides
# dispatch. Widgets opt in incrementally by overriding `bindings(o)`.
# See design/termwin-widget-authoring-rearchitecture.md, Part D.

struct Binding
    # Tokens that trigger this action. A token is whatever readtoken produces:
    # a Symbol for special keys (`:F7`, `:ctrl_n`, `:up`) or a String for
    # printable characters (`"d"`, `"."`). Hence the element type is Any.
    keys::Vector{Any}
    label::String          # human label → footer + help
    scope::Symbol          # :global | :tree_leaf | :edittable_cell | :form | ...
    when::Function         # o -> Bool   context guard (default: always)
    action::Function       # o -> InjectResult
end

# Convenience constructor. `keys` is a single token (Symbol or String) or a
# vector of tokens: `Binding(:F7, "Save")`, `Binding(["y", :pagedown], "+year")`.
function Binding(keys, label::AbstractString;
                 scope::Symbol = :global,
                 when::Function = _ -> true,
                 action::Function = _ -> Ignored)
    ks = keys isa AbstractVector ? collect(Any, keys) : Any[keys]
    Binding(ks, String(label), scope, when, action)
end

# Default: no declared bindings. Unconverted widgets keep their own `inject`.
bindings(::TwObj) = Binding[]

# Bindings whose `when` guard currently holds (drives footer + help + dispatch).
active_bindings(o::TwObj) = Binding[b for b in bindings(o) if b.when(o)]

# ----- key → human label -----

const KEY_LABELS = Dict{Symbol,String}(
    :enter => "Enter", Symbol("return") => "Enter", :esc => "Esc",
    :up => "↑", :down => "↓", :left => "←", :right => "→",
    :pageup => "PgUp", :pagedown => "PgDn", :home => "Home", Symbol("end") => "End",
    :tab => "Tab", :space => "Spc", :backspace => "Bksp", :delete => "Del",
)

# Printable-character tokens are their own label ("d", ".", "?").
keylabel(k::AbstractString) = String(k)
keylabel(k) = string(k)

function keylabel(k::Symbol)
    haskey(KEY_LABELS, k) && return KEY_LABELS[k]
    s = string(k)
    if startswith(s, "ctrlshift_"); return "Ctrl-Shift-" * uppercase(s[11:end]); end
    if startswith(s, "ctrlalt_");   return "Ctrl-Alt-"   * uppercase(s[9:end]);  end
    if startswith(s, "altshift_");  return "Alt-Shift-"  * s[10:end];            end
    if startswith(s, "ctrl_");      return "Ctrl-"       * uppercase(s[6:end]);  end
    if startswith(s, "alt_");       return "Alt-"        * s[5:end];             end
    if startswith(s, "shift_");     return "Shift-"      * s[7:end];             end
    return s
end

binding_keylabel(b::Binding) = join((keylabel(k) for k in b.keys), "/")

"""
    footer(o) -> String

Bottom-text string generated from the widget's active bindings — the single
source that replaces hand-maintained `default*BottomText` constants.
"""
footer(o::TwObj) =
    join((binding_keylabel(b) * ":" * b.label for b in active_bindings(o)), "  ")

"""
    helptext_from_bindings(o) -> String

F1 help screen generated from the widget's active bindings.
"""
function helptext_from_bindings(o::TwObj)
    io = IOBuffer()
    for b in active_bindings(o)
        println(io, rpad(binding_keylabel(b), 14), " : ", b.label)
    end
    String(take!(io))
end

"""
    inject_via_table(o, token) -> InjectResult

Generic dispatch: the first binding whose key matches and whose `when` guard
holds runs its action; otherwise `Ignored`. A widget converts by routing its
`inject` through this.
"""
function inject_via_table(o::TwObj, token)
    for b in bindings(o)
        if token in b.keys && b.when(o)
            return b.action(o)
        end
    end
    return Ignored
end
