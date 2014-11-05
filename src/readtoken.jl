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
    int(0x7f) => :backspace,
    int(0x01) => :ctrl_a,
    int(0x02) => :ctrl_b,
    int(0x03) => :ctrl_c, #intercepted
    int(0x04) => :ctrl_d,
    int(0x05) => :ctrl_e,
    int(0x06) => :ctrl_f,
    int(0x07) => :ctrl_g,
    int(0x08) => :ctrl_h,
    int(0x09) => :tab,
    int(0x0a) => :enter,
    int(0x0b) => :ctrl_k,
    int(0x0c) => :ctrl_l,
    int(0x0d) => symbol("return"),
    int(0x0e) => :ctrl_n,
    int(0x0f) => :ctrl_o, #seems to pause output
    int(0x10) => :ctrl_p,
    int(0x11) => :ctrl_q, #intercepted
    int(0x12) => :ctrl_r,
    int(0x13) => :ctrl_s, #intercepted
    int(0x14) => :ctrl_t,
    int(0x15) => :ctrl_u,
    int(0x16) => :ctrl_v,
    int(0x17) => :ctrl_w,
    int(0x18) => :ctrl_x,
    int(0x19) => :ctrl_y, #intercepted
    int(0x1a) => :ctrl_z, #intercepted
    int(0x1b) => :esc,
    int(0x0102)=>:down,
    int(0x0103)=>:up,
    int(0x0104)=>:left,
    int(0x0105)=>:right,
    int(0x0106)=>:home,
    int(0x0107)=>:backspace,
    int(0x0109)=>:F1,
    int(0x010a)=>:F2,
    int(0x010b)=>:F3,
    int(0x010c)=>:F4,
    int(0x010d)=>:F5,
    int(0x010e)=>:F6,
    int(0x010f)=>:F7,
    int(0x0110)=>:F8,
    int(0x0111)=>:F9,
    int(0x0112)=>:F10,
    int(0x0113)=>:F11,
    int(0x0114)=>:F12,
    int(0x0115)=>:shift_F1,
    int(0x0116)=>:shift_F2,
    int(0x0117)=>:shift_F3,
    int(0x0118)=>:shift_F4,
    int(0x0119)=>:shift_F5,
    int(0x011a)=>:shift_F6,
    int(0x011b)=>:shift_F7,
    int(0x011c)=>:shift_F8,
    int(0x011d)=>:shift_F9,
    int(0x011e)=>:shift_F10,
    int(0x011f)=>:shift_F11,
    int(0x0120)=>:shift_F12,
    int(0x0148)=>:KEY_DL,
    int(0x0149)=>:insert,
    int(0x014a)=>:delete,
    int(0x014b)=>:KEY_IC,
    int(0x014c)=>:KEY_EIC,
    int(0x014d)=>:KEY_CLEAR,
    int(0x014e)=>:KEY_EOS,
    int(0x014f)=>:KEY_EOL,
    int(0x0150)=>:shift_down,
    int(0x0151)=>:shift_up,
    int(0x0152)=>:pagedown,
    int(0x0153)=>:pageup,
    int(0x0154)=>:KEY_STAB,
    int(0x0155)=>:KEY_CTAB,
    int(0x0156)=>:KEY_CATAB,
    int(0x0157)=>:enter,
    int(0x015a)=>:KEY_PRINT,
    int(0x015b)=>:KEY_LL,
    int(0x015c)=>:KEY_A1,
    int(0x015d)=>:KEY_A3,
    int(0x015e)=>:KEY_B2,
    int(0x015f)=>:KEY_C1,
    int(0x0160)=>:KEY_C3,
    int(0x0161)=>:shift_tab,
    int(0x0162)=>:KEY_BEG,
    int(0x0163)=>:KEY_CANCEL,
    int(0x0164)=>:KEY_CLOSE,
    int(0x0165)=>:KEY_COMMAND,
    int(0x0166)=>:KEY_COPY,
    int(0x0167)=>:KEY_CREATE,
    int(0x0168)=>symbol("end"),
    int(0x0169)=>:KEY_EXIT,
    int(0x016a)=>:KEY_FIND,
    int(0x016b)=>:KEY_HELP,
    int(0x016c)=>:KEY_MARK,
    int(0x016d)=>:KEY_MESSAGE,
    int(0x016e)=>:KEY_MOVE,
    int(0x016f)=>:KEY_NEXT,
    int(0x0170)=>:KEY_OPEN,
    int(0x0171)=>:KEY_OPTIONS,
    int(0x0172)=>:KEY_PREVIOUS,
    int(0x0173)=>:KEY_REDO,
    int(0x0174)=>:KEY_REFERENCE,
    int(0x0175)=>:KEY_REFRESH,
    int(0x0176)=>:KEY_REPLACE,
    int(0x0177)=>:KEY_RESTART,
    int(0x0178)=>:KEY_RESUME,
    int(0x0179)=>:KEY_SAVE,
    int(0x017a)=>:KEY_SBEG,
    int(0x017b)=>:KEY_SCANCEL,
    int(0x017c)=>:KEY_SCOMMAND,
    int(0x017d)=>:KEY_SCOPY,
    int(0x017e)=>:KEY_SCREATE,
    int(0x017f)=>:KEY_SDC,
    int(0x0180)=>:KEY_SDL,
    int(0x0181)=>:KEY_SELECT,
    int(0x0182)=>:shift_end,
    int(0x0183)=>:KEY_SEOL,
    int(0x0184)=>:KEY_SEXIT,
    int(0x0185)=>:KEY_SFIND,
    int(0x0186)=>:KEY_SHELP,
    int(0x0187)=>:shift_home,
    int(0x0188)=>:KEY_SIC,
    int(0x0189)=>:shift_left,
    int(0x018a)=>:KEY_SMESSAGE,
    int(0x018b)=>:KEY_SMOVE,
    int(0x018c)=>:KEY_SNEXT,
    int(0x018d)=>:KEY_SOPTIONS,
    int(0x018e)=>:KEY_SPREVIOUS,
    int(0x018f)=>:KEY_SPRINT,
    int(0x0190)=>:KEY_SREDO,
    int(0x0191)=>:KEY_SREPLACE,
    int(0x0192)=>:shift_right,
    int(0x0193)=>:KEY_SRSUME,
    int(0x0194)=>:KEY_SSAVE,
    int(0x0195)=>:KEY_SSUSPEND,
    int(0x0196)=>:KEY_SUNDO,
    int(0x0197)=>:KEY_SUSPEND,
    int(0x0198)=>:KEY_UNDO,
    int(0x0199)=>:KEY_MOUSE,
    int(0x019a)=>:KEY_RESIZE,
    int(0x019b)=>:KEY_EVENT,
    int(0x0209) => :ctrl_down,
    int(0x020a) => :ctrlshift_down,
    int(0x020e) => :ctrl_end,
    int(0x020f) => :ctrlshift_end,
    int(0x0213) => :ctrl_home,
    int(0x0214) => :ctrlshift_home,
    int(0x021d) => :ctrl_left,
    int(0x021e) => :ctrlshift_left,
    int(0x022c) => :ctrl_right,
    int(0x022d) => :ctrlshift_right,
    int(0x0232) => :ctrl_up,
    int(0x0233) => :ctrlshift_up,
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
    c = wgetch( win )
    if c == 27
        s = string( char( c ) )
        # This part gets around a MacOS ncurses bug, which hasn't been fixed
        # for quite some time...
        # so sometimes I get a single key code, but sometimes I get
        # a sequence of escape codes
        while( ( nc = wgetch(win ) ) != 0xff )
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
    if c == 0xff
        return :nochar
    end
    if c < 192 || c > 253
        if haskey( ncnummap, c )
            return ncnummap[ c]
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
