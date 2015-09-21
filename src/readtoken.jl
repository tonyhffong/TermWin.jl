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

    "\eOF"    => Symbol("end"),
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
    "\e[1;3P" => :alt_F1,
    "\e[1;3Q" => :alt_F2,
    "\e[1;3R" => :alt_F3,
    "\e[1;3S" => :alt_F4,
    "\e[15;3~" => :alt_F5,
    "\e[17;3~" => :alt_F6,
    "\e[18;3~" => :alt_F7,
    "\e[19;3~" => :alt_F8,
    "\e[20;3~" => :alt_F9,
    "\e[21;3~" => :alt_F10,
    "\e[23;3~" => :alt_F11,
    "\e[24;3~" => :alt_F12,
    "\e[1;5P" => :ctrl_F1,
    "\e[1;5Q" => :ctrl_F2,
    "\e[1;5R" => :ctrl_F3,
    "\e[1;5S" => :ctrl_F4,
    "\e[15;5~" => :ctrl_F5,
    "\e[17;5~" => :ctrl_F6,
    "\e[18;5~" => :ctrl_F7,
    "\e[19;5~" => :ctrl_F8,
    "\e[20;5~" => :ctrl_F9,
    "\e[21;5~" => :ctrl_F10,
    "\e[23;5~" => :ctrl_F11,
    "\e[24;5~" => :ctrl_F12,

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
    "\e"*string(@compat Char(0x153)) => :alt_pageup,
    "\e"*string(@compat Char(0x152)) => :alt_pagedown
)

ncnummap = Compat.@Dict(
    (@compat UInt(0x7f)) => :backspace,
    (@compat UInt(0x01)) => :ctrl_a,
    (@compat UInt(0x02)) => :ctrl_b,
    (@compat UInt(0x03)) => :ctrl_c, #intercepted
    (@compat UInt(0x04)) => :ctrl_d,
    (@compat UInt(0x05)) => :ctrl_e,
    (@compat UInt(0x06)) => :ctrl_f,
    (@compat UInt(0x07)) => :ctrl_g,
    (@compat UInt(0x08)) => :ctrl_h,
    (@compat UInt(0x09)) => :tab,
    (@compat UInt(0x0a)) => :enter,
    (@compat UInt(0x0b)) => :ctrl_k,
    (@compat UInt(0x0c)) => :ctrl_l,
    (@compat UInt(0x0d)) => Symbol("return"),
    (@compat UInt(0x0e)) => :ctrl_n,
    (@compat UInt(0x0f)) => :ctrl_o, #seems to pause output
    (@compat UInt(0x10)) => :ctrl_p,
    (@compat UInt(0x11)) => :ctrl_q, #intercepted
    (@compat UInt(0x12)) => :ctrl_r,
    (@compat UInt(0x13)) => :ctrl_s, #intercepted
    (@compat UInt(0x14)) => :ctrl_t,
    (@compat UInt(0x15)) => :ctrl_u,
    (@compat UInt(0x16)) => :ctrl_v,
    (@compat UInt(0x17)) => :ctrl_w,
    (@compat UInt(0x18)) => :ctrl_x,
    (@compat UInt(0x19)) => :ctrl_y, #intercepted
    (@compat UInt(0x1a)) => :ctrl_z, #intercepted
    (@compat UInt(0x1b)) => :esc,
    (@compat UInt(0x0102))=>:down,
    (@compat UInt(0x0103))=>:up,
    (@compat UInt(0x0104))=>:left,
    (@compat UInt(0x0105))=>:right,
    (@compat UInt(0x0106))=>:home,
    (@compat UInt(0x0107))=>:backspace,
    (@compat UInt(0x0109))=>:F1,
    (@compat UInt(0x010a))=>:F2,
    (@compat UInt(0x010b))=>:F3,
    (@compat UInt(0x010c))=>:F4,
    (@compat UInt(0x010d))=>:F5,
    (@compat UInt(0x010e))=>:F6,
    (@compat UInt(0x010f))=>:F7,
    (@compat UInt(0x0110))=>:F8,
    (@compat UInt(0x0111))=>:F9,
    (@compat UInt(0x0112))=>:F10,
    (@compat UInt(0x0113))=>:F11,
    (@compat UInt(0x0114))=>:F12,
    (@compat UInt(0x0115))=>:shift_F1,
    (@compat UInt(0x0116))=>:shift_F2,
    (@compat UInt(0x0117))=>:shift_F3,
    (@compat UInt(0x0118))=>:shift_F4,
    (@compat UInt(0x0119))=>:shift_F5,
    (@compat UInt(0x011a))=>:shift_F6,
    (@compat UInt(0x011b))=>:shift_F7,
    (@compat UInt(0x011c))=>:shift_F8,
    (@compat UInt(0x011d))=>:shift_F9,
    (@compat UInt(0x011e))=>:shift_F10,
    (@compat UInt(0x011f))=>:shift_F11,
    (@compat UInt(0x0120))=>:shift_F12,
    (@compat UInt(0x0121))=>:ctrl_F1,
    (@compat UInt(0x0122))=>:ctrl_F2,
    (@compat UInt(0x0123))=>:ctrl_F3,
    (@compat UInt(0x0124))=>:ctrl_F4,
    (@compat UInt(0x0125))=>:ctrl_F5,
    (@compat UInt(0x0126))=>:ctrl_F6,
    (@compat UInt(0x0127))=>:ctrl_F7,
    (@compat UInt(0x0128))=>:ctrl_F8,
    (@compat UInt(0x0129))=>:ctrl_F9,
    (@compat UInt(0x012a))=>:ctrl_F10,
    (@compat UInt(0x012b))=>:ctrl_F11,
    (@compat UInt(0x012c))=>:ctrl_F12,
    (@compat UInt(0x0139))=>:alt_F1,
    (@compat UInt(0x013a))=>:alt_F2,
    (@compat UInt(0x013b))=>:alt_F3,
    (@compat UInt(0x013c))=>:alt_F4,
    (@compat UInt(0x013d))=>:alt_F5,
    (@compat UInt(0x013e))=>:alt_F6,
    (@compat UInt(0x013f))=>:alt_F7,
    (@compat UInt(0x0140))=>:alt_F8,
    (@compat UInt(0x0141))=>:alt_F9,
    (@compat UInt(0x0142))=>:alt_F10,
    (@compat UInt(0x0143))=>:alt_F11,
    (@compat UInt(0x0144))=>:alt_F12,
    (@compat UInt(0x0148))=>:KEY_DL,
    (@compat UInt(0x0149))=>:insert,
    (@compat UInt(0x014a))=>:delete,
    (@compat UInt(0x014b))=>:KEY_IC,
    (@compat UInt(0x014c))=>:KEY_EIC,
    (@compat UInt(0x014d))=>:KEY_CLEAR,
    (@compat UInt(0x014e))=>:KEY_EOS,
    (@compat UInt(0x014f))=>:KEY_EOL,
    (@compat UInt(0x0150))=>:shift_down,
    (@compat UInt(0x0151))=>:shift_up,
    (@compat UInt(0x0152))=>:pagedown,
    (@compat UInt(0x0153))=>:pageup,
    (@compat UInt(0x0154))=>:KEY_STAB,
    (@compat UInt(0x0155))=>:KEY_CTAB,
    (@compat UInt(0x0156))=>:KEY_CATAB,
    (@compat UInt(0x0157))=>:enter,
    (@compat UInt(0x015a))=>:KEY_PRINT,
    (@compat UInt(0x015b))=>:KEY_LL,
    (@compat UInt(0x015c))=>:KEY_A1,
    (@compat UInt(0x015d))=>:KEY_A3,
    (@compat UInt(0x015e))=>:KEY_B2,
    (@compat UInt(0x015f))=>:KEY_C1,
    (@compat UInt(0x0160))=>:KEY_C3,
    (@compat UInt(0x0161))=>:shift_tab,
    (@compat UInt(0x0162))=>:KEY_BEG,
    (@compat UInt(0x0163))=>:KEY_CANCEL,
    (@compat UInt(0x0164))=>:KEY_CLOSE,
    (@compat UInt(0x0165))=>:KEY_COMMAND,
    (@compat UInt(0x0166))=>:KEY_COPY,
    (@compat UInt(0x0167))=>:KEY_CREATE,
    (@compat UInt(0x0168))=>Symbol("end"),
    (@compat UInt(0x0169))=>:KEY_EXIT,
    (@compat UInt(0x016a))=>:KEY_FIND,
    (@compat UInt(0x016b))=>:KEY_HELP,
    (@compat UInt(0x016c))=>:KEY_MARK,
    (@compat UInt(0x016d))=>:KEY_MESSAGE,
    (@compat UInt(0x016e))=>:KEY_MOVE,
    (@compat UInt(0x016f))=>:KEY_NEXT,
    (@compat UInt(0x0170))=>:KEY_OPEN,
    (@compat UInt(0x0171))=>:KEY_OPTIONS,
    (@compat UInt(0x0172))=>:KEY_PREVIOUS,
    (@compat UInt(0x0173))=>:KEY_REDO,
    (@compat UInt(0x0174))=>:KEY_REFERENCE,
    (@compat UInt(0x0175))=>:KEY_REFRESH,
    (@compat UInt(0x0176))=>:KEY_REPLACE,
    (@compat UInt(0x0177))=>:KEY_RESTART,
    (@compat UInt(0x0178))=>:KEY_RESUME,
    (@compat UInt(0x0179))=>:KEY_SAVE,
    (@compat UInt(0x017a))=>:KEY_SBEG,
    (@compat UInt(0x017b))=>:KEY_SCANCEL,
    (@compat UInt(0x017c))=>:KEY_SCOMMAND,
    (@compat UInt(0x017d))=>:KEY_SCOPY,
    (@compat UInt(0x017e))=>:KEY_SCREATE,
    (@compat UInt(0x017f))=>:KEY_SDC,
    (@compat UInt(0x0180))=>:KEY_SDL,
    (@compat UInt(0x0181))=>:KEY_SELECT,
    (@compat UInt(0x0182))=>:shift_end,
    (@compat UInt(0x0183))=>:KEY_SEOL,
    (@compat UInt(0x0184))=>:KEY_SEXIT,
    (@compat UInt(0x0185))=>:KEY_SFIND,
    (@compat UInt(0x0186))=>:KEY_SHELP,
    (@compat UInt(0x0187))=>:shift_home,
    (@compat UInt(0x0188))=>:KEY_SIC,
    (@compat UInt(0x0189))=>:shift_left,
    (@compat UInt(0x018a))=>:KEY_SMESSAGE,
    (@compat UInt(0x018b))=>:KEY_SMOVE,
    (@compat UInt(0x018c))=>:KEY_SNEXT,
    (@compat UInt(0x018d))=>:KEY_SOPTIONS,
    (@compat UInt(0x018e))=>:KEY_SPREVIOUS,
    (@compat UInt(0x018f))=>:KEY_SPRINT,
    (@compat UInt(0x0190))=>:KEY_SREDO,
    (@compat UInt(0x0191))=>:KEY_SREPLACE,
    (@compat UInt(0x0192))=>:shift_right,
    (@compat UInt(0x0193))=>:KEY_SRSUME,
    (@compat UInt(0x0194))=>:KEY_SSAVE,
    (@compat UInt(0x0195))=>:KEY_SSUSPEND,
    (@compat UInt(0x0196))=>:KEY_SUNDO,
    (@compat UInt(0x0197))=>:KEY_SUSPEND,
    (@compat UInt(0x0198))=>:KEY_UNDO,
    (@compat UInt(0x0199))=>:KEY_MOUSE,
    (@compat UInt(0x019a))=>:KEY_RESIZE,
    (@compat UInt(0x019b))=>:KEY_EVENT,
    (@compat UInt(0x0209)) => :ctrl_down,
    (@compat UInt(0x020a)) => :ctrlshift_down,
    (@compat UInt(0x020e)) => :ctrl_end,
    (@compat UInt(0x020f)) => :ctrlshift_end,
    (@compat UInt(0x0213)) => :ctrl_home,
    (@compat UInt(0x0214)) => :ctrlshift_home,
    (@compat UInt(0x021d)) => :ctrl_left,
    (@compat UInt(0x021e)) => :ctrlshift_left,
    (@compat UInt(0x022c)) => :ctrl_right,
    (@compat UInt(0x022d)) => :ctrlshift_right,
    (@compat UInt(0x0232)) => :ctrl_up,
    (@compat UInt(0x0233)) => :ctrlshift_up,
)


const keypadmap = Compat.@Dict(
    :keypad_dot => ".",
    :keypad_enter => Symbol( "return" ),
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
    local c::UInt32
    local nc::UInt32

    nocharval = typemax( UInt32 )

    c = wgetch( win )
    if c == 27
        s = string( @compat Char( c ) )
        # This part gets around a MacOS ncurses bug, which hasn't been fixed
        # for quite some time...
        # so sometimes I get a single key code, but sometimes I get
        # a sequence of escape codes
        while( ( nc = wgetch(win ) ) != nocharval )
            s *= string( @compat Char(nc))
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
        if haskey( ncnummap, @compat UInt( c ) )
            return ncnummap[ @compat UInt( c ) ]
        else
            return string( @compat Char( c ) )
        end
    elseif 192 <= c <= 223 # utf8 based logic starts here
        bs = Array( UInt8, 2 )
        bs[1] = @compat UInt8( c )
        bs[2] = @compat UInt8( wgetch( win ) )
        return convert( UTF8String, bs )
    elseif  224 <= c <= 239
        bs = Array( UInt8, 3 )
        bs[1] = @compat UInt8( c )
        bs[2] = @compat UInt8( wgetch( win ) )
        bs[3] = @compat UInt8( wgetch( win ) )
        return convert( UTF8String, bs )
    elseif  240 <= c <= 247
        bs = Array( UInt8, 4 )
        bs[1] = @compat UInt8( c )
        bs[2] = @compat UInt8( wgetch( win ) )
        bs[3] = @compat UInt8( wgetch( win ) )
        bs[4] = @compat UInt8( wgetch( win ) )
        return convert( UTF8String, bs )
    elseif  248 <= c <= 251
        bs = Array( UInt8, 5 )
        bs[1] = @compat UInt8( c )
        bs[2] = @compat UInt8( wgetch( win ) )
        bs[3] = @compat UInt8( wgetch( win ) )
        bs[4] = @compat UInt8( wgetch( win ) )
        bs[5] = @compat UInt8( wgetch( win ) )
        return convert( UTF8String, bs )
    elseif  252 <= c <= 253
        bs = Array( UInt8, 6 )
        bs[1] = @compat UInt8( c )
        bs[2] = @compat UInt8( wgetch( win ) )
        bs[3] = @compat UInt8( wgetch( win ) )
        bs[4] = @compat UInt8( wgetch( win ) )
        bs[5] = @compat UInt8( wgetch( win ) )
        bs[6] = @compat UInt8( wgetch( win ) )
        return convert( UTF8String, bs )
    end
end
