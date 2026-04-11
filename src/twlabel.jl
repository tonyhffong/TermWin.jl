# twlabel.jl — lightweight non-interactive layout helpers
#
# TwSpacer : blank gap (vertical rows or horizontal columns)
# TwLabel  : static text line with optional styling

# ── TwSpacer ────────────────────────────────────────────────────────────────

struct TwSpacerData end

"""
    newTwSpacer(parent; height=1, width=1.0, posy=:top, posx=:left)

Insert a blank gap into a `vstack`/`hstack`/`@twlayout` layout.
`height` and `width` follow the same convention as other widgets:
an integer means rows/columns; a float in `(0,1]` means a fraction of the parent.

In a vertical layout pass `height=N` (default 1).
In a horizontal layout pass `width=N, height=1.0`.
"""
function newTwSpacer(
    parent::TwObj;
    height::Real = 1,
    width::Real = 1.0,
    posy::Any = :top,
    posx::Any = :left,
)
    obj = TwObj(TwSpacerData(), Val{:Spacer})
    obj.acceptsFocus = false
    obj.box = false
    obj.borderSizeV = 0
    obj.borderSizeH = 0
    link_parent_child(parent, obj, height, width, posy, posx)
    obj
end

draw(o::TwObj{TwSpacerData}) = werase(o.window)

# ── TwLabel ─────────────────────────────────────────────────────────────────

struct TwLabelData
    text::String
    style::Symbol   # :plain | :header | :divider
end

"""
    newTwLabel(parent, text=""; height=1, width=1.0, style=:plain)

Insert a static text line into a `vstack`/`hstack`/`@twlayout` layout.

`style` controls the visual appearance:
- `:plain`   — text at column 0, default terminal colour
- `:header`  — bold yellow on black (`COLOR_PAIR(3)`); use for section titles
- `:divider` — white on dark-gray (`COLOR_PAIR(13)`); renders as
               `── text ─────────────` filling the full widget width.
               When `text` is empty, renders a bare horizontal rule.
"""
function newTwLabel(
    parent::TwObj,
    text::String = "";
    height::Real = 1,
    width::Real = 1.0,
    style::Symbol = :plain,
    posy::Any = :top,
    posx::Any = :left,
)
    obj = TwObj(TwLabelData(text, style), Val{:Label})
    obj.acceptsFocus = false
    obj.box = false
    obj.borderSizeV = 0
    obj.borderSizeH = 0
    link_parent_child(parent, obj, height, width, posy, posx)
    obj
end

function draw(o::TwObj{TwLabelData})
    werase(o.window)
    text = o.data.text
    style = o.data.style
    w = o.width

    if style == :plain
        mvwprintw(o.window, 0, 0, "%s", text)

    elseif style == :header
        wattron(o.window, COLOR_PAIR(3) | A_BOLD)
        mvwprintw(o.window, 0, 0, "%s", text)
        wattroff(o.window, COLOR_PAIR(3) | A_BOLD)

    elseif style == :divider
        if isempty(text)
            line = repeat("─", w)
        else
            prefix = "── " * text * " "
            remaining = max(0, w - textwidth(prefix))
            line = prefix * repeat("─", remaining)
        end
        wattron(o.window, COLOR_PAIR(13))
        mvwprintw(o.window, 0, 0, "%s", line)
        wattroff(o.window, COLOR_PAIR(13))
    end
end
