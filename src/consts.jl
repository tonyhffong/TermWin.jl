const COLOR_BLACK   = 0
const COLOR_RED     = 1
const COLOR_GREEN   = 2
const COLOR_YELLOW  = 3
const COLOR_BLUE    = 4
const COLOR_MAGENTA = 5
const COLOR_CYAN    = 6
const COLOR_WHITE   = 7

const NCURSES_ATTR_SHIFT =8
function NCURSES_BITS( m, shf)
    m << (shf + NCURSES_ATTR_SHIFT)
end

COLOR_PAIR( n ) = NCURSES_BITS(n, 0)

const A_NORMAL     = @compat UInt32(0)
const A_ATTRIBUTES = ~(@compat UInt32(0))
const A_CHARTEXT   = (NCURSES_BITS((@compat UInt32(1)),0) - (@compat UInt32(1)))
const A_COLOR      = NCURSES_BITS(((@compat UInt32(1)) << 8) - (@compat UInt32(1)),0)
const A_STANDOUT   = NCURSES_BITS((@compat UInt32(1)),8)
const A_UNDERLINE  = NCURSES_BITS((@compat UInt32(1)),9)
const A_REVERSE    = NCURSES_BITS((@compat UInt32(1)),10)
const A_BLINK      = NCURSES_BITS((@compat UInt32(1)),11)
const A_DIM        = NCURSES_BITS((@compat UInt32(1)),12)
const A_BOLD       = NCURSES_BITS((@compat UInt32(1)),13)
const A_ALTCHARSET = NCURSES_BITS((@compat UInt32(1)),14)
const A_INVIS      = NCURSES_BITS((@compat UInt32(1)),15)
const A_PROTECT    = NCURSES_BITS((@compat UInt32(1)),16)
const A_HORIZONTAL = NCURSES_BITS((@compat UInt32(1)),17)
const A_LEFT       = NCURSES_BITS((@compat UInt32(1)),18)
const A_LOW        = NCURSES_BITS((@compat UInt32(1)),19)
const A_RIGHT      = NCURSES_BITS((@compat UInt32(1)),20)
const A_TOP        = NCURSES_BITS((@compat UInt32(1)),21)
const A_VERTICAL   = NCURSES_BITS((@compat UInt32(1)),22)

# not really used. See getmouse() hack in ccall.jl
NCURSES_MOUSE_MASK(b,m) = m<<((b-1)*6) # NCURSES_MOUSE_VERSION=1
const NCURSES_BUTTON_PRESSED = @compat UInt32(2)
const BUTTON1_PRESSED = NCURSES_MOUSE_MASK( 1, NCURSES_BUTTON_PRESSED )
const BUTTON2_PRESSED = NCURSES_MOUSE_MASK( 2, NCURSES_BUTTON_PRESSED )
const BUTTON3_PRESSED = NCURSES_MOUSE_MASK( 3, NCURSES_BUTTON_PRESSED )
const BUTTON4_PRESSED = NCURSES_MOUSE_MASK( 4, NCURSES_BUTTON_PRESSED )
const REPORT_MOUSE_POSITION = NCURSES_MOUSE_MASK( 5, 8 ) # NCURSES_MOUSE_VERSION=1
