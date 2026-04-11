# Constants for TermWin - Notcurses backend
# These maintain the same names as the old ncurses constants for compatibility,
# but map to Notcurses style bits and channel-based color system.

import Notcurses as NC

# ===== Basic color indices (same values as ncurses) =====
const COLOR_BLACK = 0
const COLOR_RED = 1
const COLOR_GREEN = 2
const COLOR_YELLOW = 3
const COLOR_BLUE = 4
const COLOR_MAGENTA = 5
const COLOR_CYAN = 6
const COLOR_WHITE = 7

# ===== RGB values for the 8 basic terminal colors =====
const BASIC_COLOR_RGB = Dict{Int,Tuple{UInt8,UInt8,UInt8}}(
    COLOR_BLACK => (0x00, 0x00, 0x00),
    COLOR_RED => (0xcc, 0x00, 0x00),
    COLOR_GREEN => (0x00, 0xcc, 0x00),
    COLOR_YELLOW => (0xcc, 0xcc, 0x00),
    COLOR_BLUE => (0x00, 0x00, 0xcc),
    COLOR_MAGENTA => (0xcc, 0x00, 0xcc),
    COLOR_CYAN => (0x00, 0xcc, 0xcc),
    COLOR_WHITE => (0xcc, 0xcc, 0xcc),
)

# ===== 256-color palette RGB values (for indices >= 8) =====
function color_index_to_rgb(idx::Int)
    if idx < 8
        return BASIC_COLOR_RGB[idx]
    elseif idx < 16
        # Bright colors
        bright = Dict(
            8 => (0x80, 0x80, 0x80),  # bright black (gray)
            9 => (0xff, 0x00, 0x00),
            10 => (0x00, 0xff, 0x00),
            11 => (0xff, 0xff, 0x00),
            12 => (0x00, 0x00, 0xff),
            13 => (0xff, 0x00, 0xff),
            14 => (0x00, 0xff, 0xff),
            15 => (0xff, 0xff, 0xff),
        )
        return bright[idx]
    elseif idx < 232
        # 6x6x6 color cube (indices 16-231)
        idx -= 16
        r = div(idx, 36)
        g = div(idx % 36, 6)
        b = idx % 6
        return (
            UInt8(r == 0 ? 0 : 55 + 40*r),
            UInt8(g == 0 ? 0 : 55 + 40*g),
            UInt8(b == 0 ? 0 : 55 + 40*b),
        )
    else
        # Grayscale (indices 232-255)
        v = UInt8(8 + (idx - 232) * 10)
        return (v, v, v)
    end
end

# ===== Channel construction helpers =====
# Build a 64-bit channel pair from fg and bg color indices
function make_channel_pair(fg_idx::Int, bg_idx::Int)
    fr, fg, fb = color_index_to_rgb(fg_idx)
    br, bg_, bb = color_index_to_rgb(bg_idx)
    # Notcurses 64-bit channels: upper 32 = fg, lower 32 = bg
    # Each 32-bit channel: bits 16-23 = R, 8-15 = G, 0-7 = B, bit 30 = "not default"
    fc = UInt64(fr) << 16 | UInt64(fg) << 8 | UInt64(fb) | (UInt64(1) << 30)  # RGB flag
    bc = UInt64(br) << 16 | UInt64(bg_) << 8 | UInt64(bb) | (UInt64(1) << 30)
    return (fc << 32) | bc
end

# ===== Color pair table (populated in initsession) =====
# Maps old COLOR_PAIR(n) numbers -> 64-bit Notcurses channels
const color_channel_table = Dict{Int,UInt64}()

# COLOR_PAIR(n): returns 64-bit channel value for pair n
function COLOR_PAIR(n::Integer)
    get(color_channel_table, Int(n), UInt64(0))
end

# ===== Style/attribute constants =====
# In Notcurses, styles are UInt16 (not UInt32 like ncurses attributes).
# We define these as UInt32 for backward compat with existing code that ORs them.
# The adapter layer will decompose combined (style | channels) values.

const NCSTYLE_BOLD = UInt32(NC.LibNotcurses.NCSTYLE_BOLD)
const NCSTYLE_UNDERLINE = UInt32(NC.LibNotcurses.NCSTYLE_UNDERLINE)
const NCSTYLE_ITALIC = UInt32(NC.LibNotcurses.NCSTYLE_ITALIC)
const NCSTYLE_STRUCK = UInt32(NC.LibNotcurses.NCSTYLE_STRUCK)
const NCSTYLE_UNDERCURL = UInt32(NC.LibNotcurses.NCSTYLE_UNDERCURL)

# Backward-compatible A_* names
const A_NORMAL = UInt32(0)
const A_BOLD = NCSTYLE_BOLD
const A_UNDERLINE = NCSTYLE_UNDERLINE
const A_ITALIC = NCSTYLE_ITALIC
const A_REVERSE = UInt32(0x80000000)  # Sentinel: no Notcurses equivalent, handled in adapter
const A_DIM = UInt32(0)           # Not supported in Notcurses
const A_BLINK = UInt32(0)           # Not supported in Notcurses
const A_STANDOUT = NCSTYLE_BOLD        # Map standout to bold
const A_ALTCHARSET = UInt32(0)           # Not needed: we use Unicode directly

# Mask to extract style bits (low 16 bits of the combined value)
const STYLE_MASK = UInt32(0x0000FFFF)
# Sentinel bit for A_REVERSE
const REVERSE_BIT = UInt32(0x80000000)

# ===== Decompose a combined attribute value into (style, channels, reverse) =====
# Old ncurses code does: wattron(win, COLOR_PAIR(15) | A_BOLD)
# COLOR_PAIR(15) returns a UInt64 channel, but it gets mixed with UInt32 style bits.
# We need a scheme: when attrs is UInt64, the high bits are channels.
# When attrs is UInt32, it may contain style bits + REVERSE sentinel.

function decompose_attrs(attrs)
    if attrs isa UInt64 && attrs > typemax(UInt32)
        # Pure channel value (from COLOR_PAIR), no style bits
        return (UInt16(0), attrs, false)
    end
    a = UInt32(attrs & 0xFFFFFFFF)
    style = UInt16(a & STYLE_MASK)
    reverse = (a & REVERSE_BIT) != 0
    return (style, UInt64(0), reverse)
end

# When OR-ing COLOR_PAIR(n) | A_BOLD, we need the result to carry both.
# We encode style bits in the upper 32 bits of a UInt64, channels in the lower 32...
# Actually, simpler: we use a struct.
struct TwAttr
    style::UInt16
    channels::UInt64
    reverse::Bool
end

function make_attr(args...)
    style = UInt16(0)
    channels = UInt64(0)
    reverse = false
    for a in args
        if a isa UInt64 && a > typemax(UInt32)
            channels = a
        elseif a isa TwAttr
            style |= a.style
            if a.channels != 0
                channels = a.channels
            end
            reverse |= a.reverse
        else
            s, c, r = decompose_attrs(a)
            style |= s
            if c != 0
                channels = c
            end
            reverse |= r
        end
    end
    TwAttr(style, channels, reverse)
end

# Allow bitwise OR of TwAttr values and integers for backward compat
Base.:|(a::TwAttr, b::TwAttr) = make_attr(a, b)
Base.:|(a::TwAttr, b::Integer) = make_attr(a, b)
Base.:|(a::Integer, b::TwAttr) = make_attr(a, b)

# ===== Mouse constants (kept for interface compatibility) =====
# These are not used directly with Notcurses but kept for existing code references
const BUTTON1_PRESSED = UInt32(0x02)
const REPORT_MOUSE_POSITION = UInt32(0x10000000)

# ===== ACS character map -> Unicode box-drawing =====
const ACS_MAP = Dict{Char,Char}(
    'l' => '┌',  # ACS_ULCORNER
    'm' => '└',  # ACS_LLCORNER
    'k' => '┐',  # ACS_URCORNER
    'j' => '┘',  # ACS_LRCORNER
    't' => '├',  # ACS_LTEE
    'u' => '┤',  # ACS_RTEE
    'v' => '┴',  # ACS_BTEE
    'w' => '┬',  # ACS_TTEE
    'q' => '─',  # ACS_HLINE
    'x' => '│',  # ACS_VLINE
    'n' => '┼',  # ACS_PLUS
    'o' => '⎺',  # ACS_S1 (scan line 1)
    's' => '⎽',  # ACS_S9 (scan line 9)
    '`' => '◆',  # ACS_DIAMOND
    'a' => '▒',  # ACS_CKBOARD
    'f' => '°',  # ACS_DEGREE
    'g' => '±',  # ACS_PLMINUS
    '~' => '·',  # ACS_BULLET
    ',' => '←',  # ACS_LARROW
    '+' => '→',  # ACS_RARROW
    '.' => '↓',  # ACS_DARROW
    '-' => '↑',  # ACS_UARROW
    'h' => '#',  # ACS_BOARD
    'i' => '☃',  # ACS_LANTERN
    '0' => '█',  # ACS_BLOCK
)
