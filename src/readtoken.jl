const keymap = (String=>Symbol)[
    "\eOA"    => :up,
    "\e[1;2A" => :shift_up,
    "\e[1;5A" => :ctrl_up,
    "\e[1;6A" => :ctrlshift_up,
    "\e[1;10A" => :altshift_up,
    "\eOB"    => :down,
    "\e[1;2B" => :shift_down,
    "\e[1;5B" => :ctrl_down,
    "\e[1;6B" => :ctrlshift_down,
    "\e[1;10B" => :altshift_down,
    "\eOC"    => :right,
    "\e[1;2C" => :shift_right,
    "\e[1;5C" => :ctrl_right,
    "\e[1;6C" => :ctrlshift_right,
    "\e[1;10C" => :altshift_right,
    "\eOD"    => :left,
    "\e[1;2D" => :shift_left,
    "\e[1;5D" => :ctrl_left,
    "\e[1;6D" => :ctrlshift_left,
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
    "\e[1;5H" => :ctrl_home,
    "\e[1;9H" => :alt_home,
    "\e[1;10H" => :altshift_home,

    "\eOF"    => symbol("end"),
    "\e[1;2F" => :shift_end,
    "\e[1;5F" => :ctrl_end,
    "\e[1;9F" => :alt_end,
    "\e[1;10F" => :altshift_end,

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
    "\e\e[5~"   => :alt_pageup,
    "\e[6~"   => :pagedown,
    "\e\e[6~"   => :alt_pagedown
]

const charmap = (Char=>Symbol) [
    char(0x7f) => :backspace,
    char(0x01) => :ctrl_a,
    char(0x02) => :ctrl_b,
    char(0x03) => :ctrl_c, #intercepted
    char(0x04) => :ctrl_d,
    char(0x05) => :ctrl_e,
    char(0x06) => :ctrl_f,
    char(0x07) => :ctrl_g,
    char(0x08) => :ctrl_h,
    char(0x09) => :tab,
    char(0x0a) => :ctrl_j,
    char(0x0b) => :ctrl_k,
    char(0x0c) => :ctrl_l,
    char(0x0d) => symbol("return"),
    char(0x0e) => :ctrl_n,
    char(0x0f) => :ctrl_o, #seems to pause output
    char(0x10) => :ctrl_p,
    char(0x11) => :ctrl_q, #intercepted
    char(0x12) => :ctrl_r,
    char(0x13) => :ctrl_s, #intercepted
    char(0x14) => :ctrl_t,
    char(0x15) => :ctrl_u,
    char(0x16) => :ctrl_v,
    char(0x17) => :ctrl_w,
    char(0x18) => :ctrl_x,
    char(0x19) => :ctrl_y, #intercepted
    char(0x1a) => :ctrl_z, #intercepted
    char(0x1b) => :esc
    #char(0x1d) => :ctrl_rsqrbrkt
]

const keypadmap = (Symbol=>Any) [
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
]

# this implementation doesn't handle resize/mouse events
function readtoken( remapkeypad::Bool = true )
    global keymap
    keyqueue = readavailable( STDIN )
    if length( keyqueue ) == 1
        if haskey( charmap, keyqueue[1] )
            return charmap[ keyqueue[1] ]
        else
            return keyqueue
        end
    elseif beginswith( keyqueue, "\e" )
        if haskey( keymap, keyqueue )
            ret = keymap[ keyqueue ]
            if remapkeypad && typeof( ret ) == Symbol && haskey( keypadmap, ret )
                return keypadmap[ ret ]
            else
                return ret
            end
        else
            return keyqueue
        end
    else
        return keyqueue
    end
end

