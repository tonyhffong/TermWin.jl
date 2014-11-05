const keymap = Compat.@Dict(
    "\eOA"    => :up,
    "\e[1;2A" => :shift_up,
    "\e[1;5A" => :ctrl_up,
    "\e[1;6A" => :ctrlshift_up,
    "\e[1;9A" => :alt_up,
    "\e[1;10A" => :altshift_up,
    "\eOB"    => :down,
    "\e[1;2B" => :shift_down,
    "\e[1;5B" => :ctrl_down,
    "\e[1;6B" => :ctrlshift_down,
    "\e[1;9B" => :alt_down,
    "\e[1;10B" => :altshift_down,
    "\eOC"    => :right,
    "\e[1;2C" => :shift_right,
    "\e[1;5C" => :ctrl_right,
    "\e[1;6C" => :ctrlshift_right,
    "\e[1;9C" => :alt_right,
    "\e[1;10C" => :altshift_right,
    "\eOD"    => :left,
    "\e[1;2D" => :shift_left,
    "\e[1;5D" => :ctrl_left,
    "\e[1;6D" => :ctrlshift_left,
    "\e[1;9D" => :alt_left,
    "\e[1;10D" => :altshift_left,

    "\e[A"    => :up,
    "\e\e[A"  => :alt_up,
    "\e[B"    => :down,
    "\e\e[B"  => :alt_down,
    "\e[C"    => :right,
    "\e\e[C"  => :alt_right,
    "\e[D"    => :left,
    "\e\e[D"  => :alt_left,

    "\eOH"    => :home,
    "\e[1;2H" => :shift_home,
    "\e[H"    => :shift_home,
    "\e[1;5H" => :ctrl_home,
    "\e[1;9H" => :alt_home,
    "\e[1;10H" => :altshift_home,
    "\e[1;13H" => :altctrl_home,

    "\eOF"    => symbol("end"),
    "\e[1;2F" => :shift_end,
    "\e[F"    => :shift_end,
    "\e[1;5F" => :ctrl_end,
    "\e[1;9F" => :alt_end,
    "\e[1;10F" => :altshift_end,
    "\e[1;13F" => :altctrl_end,

    "\eOP"    => :F1,
    "\eOQ"    => :F2,
    "\eOR"    => :F3,
    "\eOS"    => :F4,
    "\e[15~"  => :F5,
    "\e[17~"  => :F6,
    "\e[18~"  => :F7,
    "\e[19~"  => :F8,
    "\e[20~"  => :F9,
    "\e[21~"  => :F10,
    "\e[23~"  => :F11,
    "\e[24~"  => :F12,
    "\e[1;2P" => :shift_F1, # shift_F1 == F13
    "\e[1;2Q" => :shift_F2, # shift_F2 == F14
    "\e[1;2R" => :shift_F3, # shift_F3 == F15
    "\e[1;2S" => :shift_F4,
    "\e[15;2~" => :shift_F5,
    "\e[17;2~" => :shift_F6,
    "\e[18;2~" => :shift_F7,
    "\e[19;2~" => :shift_F8,
    "\e[20;2~" => :shift_F9,
    "\e[21;2~" => :shift_F10,
    "\e[23;2~" => :shift_F11,
    "\e[24;2~" => :shift_F12,

    "\eOn"    => :keypad_dot,
    "\eOM"    => :keypad_enter,
    "\eOj"    => :keypad_asterisk,
    "\eOk"    => :keypad_plus,
    "\eOm"    => :keypad_minus,
    "\eOo"    => :keypad_slash,
    "\eOX"    => :keypad_equal,
    "\eOp"    => :keypad_0,
    "\eOq"    => :keypad_1,
    "\eOr"    => :keypad_2,
    "\eOs"    => :keypad_3,
    "\eOt"    => :keypad_4,
    "\eOu"    => :keypad_5,
    "\eOv"    => :keypad_6,
    "\eOw"    => :keypad_7,
    "\eOx"    => :keypad_8,
    "\eOy"    => :keypad_9,

    "\e[3~"   => :delete,
    "\e[5~"   => :pageup,
    "\e\e[5~" => :alt_pageup,
    "\e[6~"   => :pagedown,
    "\e\e[6~" => :alt_pagedown,
    "\e"*string(char(0x153)) => :alt_pageup,
    "\e"*string(char(0x152)) => :alt_pagedown
)

ncnummap = Compat.@Dict(
    uint(0x7f) => :backspace,
    uint(0x01) => :ctrl_a,
    uint(0x02) => :ctrl_b,
    uint(0x03) => :ctrl_c, #intercepted
    uint(0x04) => :ctrl_d,
    uint(0x05) => :ctrl_e,
    uint(0x06) => :ctrl_f,
    uint(0x07) => :ctrl_g,
    uint(0x08) => :ctrl_h,
    uint(0x09) => :tab,
    uint(0x0a) => :enter,
    uint(0x0b) => :ctrl_k,
    uint(0x0c) => :ctrl_l,
    uint(0x0d) => symbol("return"),
    uint(0x0e) => :ctrl_n,
    uint(0x0f) => :ctrl_o, #seems to pause output
    uint(0x10) => :ctrl_p,
    uint(0x11) => :ctrl_q, #intercepted
    uint(0x12) => :ctrl_r,
    uint(0x13) => :ctrl_s, #intercepted
    uint(0x14) => :ctrl_t,
    uint(0x15) => :ctrl_u,
    uint(0x16) => :ctrl_v,
    uint(0x17) => :ctrl_w,
    uint(0x18) => :ctrl_x,
    uint(0x19) => :ctrl_y, #intercepted
    uint(0x1a) => :ctrl_z, #intercepted
    uint(0x1b) => :esc,
    uint(0x0102)=>:down,
    uint(0x0103)=>:up,
    uint(0x0104)=>:left,
    uint(0x0105)=>:right,
    uint(0x0106)=>:home,
    uint(0x0107)=>:backspace,
    uint(0x0109)=>:F1,
    uint(0x010a)=>:F2,
    uint(0x010b)=>:F3,
    uint(0x010c)=>:F4,
    uint(0x010d)=>:F5,
    uint(0x010e)=>:F6,
    uint(0x010f)=>:F7,
    uint(0x0110)=>:F8,
    uint(0x0111)=>:F9,
    uint(0x0112)=>:F10,
    uint(0x0113)=>:F11,
    uint(0x0114)=>:F12,
    uint(0x0115)=>:shift_F1,
    uint(0x0116)=>:shift_F2,
    uint(0x0117)=>:shift_F3,
    uint(0x0118)=>:shift_F4,
    uint(0x0119)=>:shift_F5,
    uint(0x011a)=>:shift_F6,
    uint(0x011b)=>:shift_F7,
    uint(0x011c)=>:shift_F8,
    uint(0x011d)=>:shift_F9,
    uint(0x011e)=>:shift_F10,
    uint(0x011f)=>:shift_F11,
    uint(0x0120)=>:shift_F12,
    uint(0x0148)=>:KEY_DL,
    uint(0x0149)=>:insert,
    uint(0x014a)=>:delete,
    uint(0x014b)=>:KEY_IC,
    uint(0x014c)=>:KEY_EIC,
    uint(0x014d)=>:KEY_CLEAR,
    uint(0x014e)=>:KEY_EOS,
    uint(0x014f)=>:KEY_EOL,
    uint(0x0150)=>:shift_down,
    uint(0x0151)=>:shift_up,
    uint(0x0152)=>:pagedown,
    uint(0x0153)=>:pageup,
    uint(0x0154)=>:KEY_STAB,
    uint(0x0155)=>:KEY_CTAB,
    uint(0x0156)=>:KEY_CATAB,
    uint(0x0157)=>:enter,
    uint(0x015a)=>:KEY_PRINT,
    uint(0x015b)=>:KEY_LL,
    uint(0x015c)=>:KEY_A1,
    uint(0x015d)=>:KEY_A3,
    uint(0x015e)=>:KEY_B2,
    uint(0x015f)=>:KEY_C1,
    uint(0x0160)=>:KEY_C3,
    uint(0x0161)=>:shift_tab,
    uint(0x0162)=>:KEY_BEG,
    uint(0x0163)=>:KEY_CANCEL,
    uint(0x0164)=>:KEY_CLOSE,
    uint(0x0165)=>:KEY_COMMAND,
    uint(0x0166)=>:KEY_COPY,
    uint(0x0167)=>:KEY_CREATE,
    uint(0x0168)=>symbol("end"),
    uint(0x0169)=>:KEY_EXIT,
    uint(0x016a)=>:KEY_FIND,
    uint(0x016b)=>:KEY_HELP,
    uint(0x016c)=>:KEY_MARK,
    uint(0x016d)=>:KEY_MESSAGE,
    uint(0x016e)=>:KEY_MOVE,
    uint(0x016f)=>:KEY_NEXT,
    uint(0x0170)=>:KEY_OPEN,
    uint(0x0171)=>:KEY_OPTIONS,
    uint(0x0172)=>:KEY_PREVIOUS,
    uint(0x0173)=>:KEY_REDO,
    uint(0x0174)=>:KEY_REFERENCE,
    uint(0x0175)=>:KEY_REFRESH,
    uint(0x0176)=>:KEY_REPLACE,
    uint(0x0177)=>:KEY_RESTART,
    uint(0x0178)=>:KEY_RESUME,
    uint(0x0179)=>:KEY_SAVE,
    uint(0x017a)=>:KEY_SBEG,
    uint(0x017b)=>:KEY_SCANCEL,
    uint(0x017c)=>:KEY_SCOMMAND,
    uint(0x017d)=>:KEY_SCOPY,
    uint(0x017e)=>:KEY_SCREATE,
    uint(0x017f)=>:KEY_SDC,
    uint(0x0180)=>:KEY_SDL,
    uint(0x0181)=>:KEY_SELECT,
    uint(0x0182)=>:shift_end,
    uint(0x0183)=>:KEY_SEOL,
    uint(0x0184)=>:KEY_SEXIT,
    uint(0x0185)=>:KEY_SFIND,
    uint(0x0186)=>:KEY_SHELP,
    uint(0x0187)=>:shift_home,
    uint(0x0188)=>:KEY_SIC,
    uint(0x0189)=>:shift_left,
    uint(0x018a)=>:KEY_SMESSAGE,
    uint(0x018b)=>:KEY_SMOVE,
    uint(0x018c)=>:KEY_SNEXT,
    uint(0x018d)=>:KEY_SOPTIONS,
    uint(0x018e)=>:KEY_SPREVIOUS,
    uint(0x018f)=>:KEY_SPRINT,
    uint(0x0190)=>:KEY_SREDO,
    uint(0x0191)=>:KEY_SREPLACE,
    uint(0x0192)=>:shift_right,
    uint(0x0193)=>:KEY_SRSUME,
    uint(0x0194)=>:KEY_SSAVE,
    uint(0x0195)=>:KEY_SSUSPEND,
    uint(0x0196)=>:KEY_SUNDO,
    uint(0x0197)=>:KEY_SUSPEND,
    uint(0x0198)=>:KEY_UNDO,
    uint(0x0199)=>:KEY_MOUSE,
    uint(0x019a)=>:KEY_RESIZE,
    uint(0x019b)=>:KEY_EVENT,
    uint(0x0209) => :ctrl_down,
    uint(0x020a) => :ctrlshift_down,
    uint(0x020e) => :ctrl_end,
    uint(0x020f) => :ctrlshift_end,
    uint(0x0213) => :ctrl_home,
    uint(0x0214) => :ctrlshift_home,
    uint(0x021d) => :ctrl_left,
    uint(0x021e) => :ctrlshift_left,
    uint(0x022c) => :ctrl_right,
    uint(0x022d) => :ctrlshift_right,
    uint(0x0232) => :ctrl_up,
    uint(0x0233) => :ctrlshift_up,
)


const keypadmap = Compat.@Dict(
    :keypad_dot => ".",
    :keypad_enter => symbol( "return" ),
    :keypad_asterisk => "*",
    :keypad_plus  => "+",
    :keypad_minus  => "-",
    :keypad_slash => "/",
    :keypad_equal => "=",
    :keypad_0 => "0",
    :keypad_1 => "1",
    :keypad_2 => "2",
    :keypad_3 => "3",
    :keypad_4 => "4",
    :keypad_5 => "5",
    :keypad_6 => "6",
    :keypad_7 => "7",
    :keypad_8 => "8",
    :keypad_9 => "9"
)

function readtoken( win::Ptr{Void} )
    local c::Uint32
    local nc::Uint32

    nocharval = typemax( Uint32 )

    c = wgetch( win )
    if c == 27
        s = string( char( c ) )
        # This part gets around a MacOS ncurses bug, which hasn't been fixed
        # for quite some time...
        # so sometimes I get a single key code, but sometimes I get
        # a sequence of escape codes
        while( ( nc = wgetch(win ) ) != nocharval )
            s *= string(char(nc))
            if haskey( keymap, s ) # greedy matching
                break
            end
        end

        if length( s ) == 1
            ret = :esc
        else
            if haskey( keymap, s )
                ret = keymap[ s ]
                if typeof( ret ) == Symbol && haskey( keypadmap, ret )
                    ret = keypadmap[ ret ]
                end
            else
                ret = s
            end
        end
        return ret
    end
    if c == nocharval
        return :nochar
    end
    if c < 192 || c > 253
        if haskey( ncnummap, uint( c ) )
            return ncnummap[ uint( c ) ]
        else
            return string( char( c ) )
        end
    elseif 192 <= c <= 223 # utf8 based logic starts here
        bs = Array( Uint8, 2 )
        bs[1] = uint8( c )
        bs[2] = uint8( wgetch( win ) )
        return convert( UTF8String, bs )
    elseif  224 <= c <= 239
        bs = Array( Uint8, 3 )
        bs[1] = uint8( c )
        bs[2] = uint8( wgetch( win ) )
        bs[3] = uint8( wgetch( win ) )
        return convert( UTF8String, bs )
    elseif  240 <= c <= 247
        bs = Array( Uint8, 4 )
        bs[1] = uint8( c )
        bs[2] = uint8( wgetch( win ) )
        bs[3] = uint8( wgetch( win ) )
        bs[4] = uint8( wgetch( win ) )
        return convert( UTF8String, bs )
    elseif  248 <= c <= 251
        bs = Array( Uint8, 5 )
        bs[1] = uint8( c )
        bs[2] = uint8( wgetch( win ) )
        bs[3] = uint8( wgetch( win ) )
        bs[4] = uint8( wgetch( win ) )
        bs[5] = uint8( wgetch( win ) )
        return convert( UTF8String, bs )
    elseif  252 <= c <= 253
        bs = Array( Uint8, 6 )
        bs[1] = uint8( c )
        bs[2] = uint8( wgetch( win ) )
        bs[3] = uint8( wgetch( win ) )
        bs[4] = uint8( wgetch( win ) )
        bs[5] = uint8( wgetch( win ) )
        bs[6] = uint8( wgetch( win ) )
        return convert( UTF8String, bs )
    end
end
