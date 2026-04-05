# Input system using Notcurses structured input.
# Returns the same symbol tokens as the old ncurses readtoken
# for backward compatibility with widget inject() methods.

# Map Notcurses Key enums to TermWin symbol tokens
const NC_KEY_TO_SYMBOL = Dict{NC.Key.T, Symbol}(
    NC.Key.UP        => :up,
    NC.Key.DOWN      => :down,
    NC.Key.LEFT      => :left,
    NC.Key.RIGHT     => :right,
    NC.Key.HOME      => :home,
    NC.Key.END       => Symbol("end"),
    NC.Key.PGUP      => :pageup,
    NC.Key.PGDOWN    => :pagedown,
    NC.Key.INS       => :insert,
    NC.Key.DEL       => :delete,
    NC.Key.BACKSPACE => :backspace,
    NC.Key.ENTER     => :enter,
    NC.Key.TAB       => :tab,
    NC.Key.ESC       => :esc,
    NC.Key.F01       => :F1,
    NC.Key.F02       => :F2,
    NC.Key.F03       => :F3,
    NC.Key.F04       => :F4,
    NC.Key.F05       => :F5,
    NC.Key.F06       => :F6,
    NC.Key.F07       => :F7,
    NC.Key.F08       => :F8,
    NC.Key.F09       => :F9,
    NC.Key.F10       => :F10,
    NC.Key.F11       => :F11,
    NC.Key.F12       => :F12,
    NC.Key.RESIZE    => :KEY_RESIZE,
)

# returns either a string or a symbol
function readtoken( nc::NC.NotcursesObject )
    result = NC.get_nblock(nc)

    if result === nothing
        return :nochar
    end

    key, ni = result

    # Skip key release events — only process press and repeat
    if ni.evtype == NC.LibNotcurses.NCTYPE_RELEASE
        return :nochar
    end

    # Mouse events
    if key isa NC.Key.T
        if key == NC.Key.BUTTON1
            _last_mouse_event[] = (:button1_pressed, Int(ni.x), Int(ni.y), nothing)
            return :KEY_MOUSE
        elseif key == NC.Key.BUTTON4 || key == NC.Key.SCROLL_UP
            _last_mouse_event[] = (:scroll_up, Int(ni.x), Int(ni.y), nothing)
            return :KEY_MOUSE
        elseif key == NC.Key.BUTTON5 || key == NC.Key.SCROLL_DOWN
            _last_mouse_event[] = (:scroll_down, Int(ni.x), Int(ni.y), nothing)
            return :KEY_MOUSE
        elseif key == NC.Key.MOTION
            return :nochar  # Ignore pure mouse motion
        end
    end

    # Synthesized keys (special keys)
    if key isa NC.Key.T
        base_sym = get(NC_KEY_TO_SYMBOL, key, nothing)
        if base_sym === nothing
            return :nochar  # Unknown special key
        end

        # Apply modifiers
        has_shift = ni.shift
        has_ctrl  = ni.ctrl
        has_alt   = ni.alt

        if has_ctrl && has_shift
            return Symbol("ctrlshift_" * string(base_sym))
        elseif has_ctrl
            return Symbol("ctrl_" * string(base_sym))
        elseif has_shift
            # shift + function keys
            if base_sym in (:F1,:F2,:F3,:F4,:F5,:F6,:F7,:F8,:F9,:F10,:F11,:F12)
                return Symbol("shift_" * string(base_sym))
            elseif base_sym in (:up,:down,:left,:right,:home,Symbol("end"),:pageup,:pagedown)
                return Symbol("shift_" * string(base_sym))
            elseif base_sym == :tab
                return :shift_tab
            else
                return base_sym
            end
        elseif has_alt && has_shift
            return Symbol("altshift_" * string(base_sym))
        elseif has_alt
            return Symbol("alt_" * string(base_sym))
        else
            return base_sym
        end
    end

    # Printable character
    if key isa Char
        c = key
        # Handle ctrl+letter combinations
        if ni.ctrl
            code = UInt32(c)
            if code == UInt32('a') || code == 0x01
                return :ctrl_a
            elseif code == UInt32('b') || code == 0x02
                return :ctrl_b
            elseif code == UInt32('c') || code == 0x03
                return :ctrl_c
            elseif code == UInt32('d') || code == 0x04
                return :ctrl_d
            elseif code == UInt32('e') || code == 0x05
                return :ctrl_e
            elseif code == UInt32('f') || code == 0x06
                return :ctrl_f
            elseif code == UInt32('g') || code == 0x07
                return :ctrl_g
            elseif code == UInt32('h') || code == 0x08
                return :ctrl_h
            elseif code == UInt32('k') || code == 0x0b
                return :ctrl_k
            elseif code == UInt32('l') || code == 0x0c
                return :ctrl_l
            elseif code == UInt32('n') || code == 0x0e
                return :ctrl_n
            elseif code == UInt32('o') || code == 0x0f
                return :ctrl_o
            elseif code == UInt32('p') || code == 0x10
                return :ctrl_p
            elseif code == UInt32('q') || code == 0x11
                return :ctrl_q
            elseif code == UInt32('r') || code == 0x12
                return :ctrl_r
            elseif code == UInt32('s') || code == 0x13
                return :ctrl_s
            elseif code == UInt32('t') || code == 0x14
                return :ctrl_t
            elseif code == UInt32('u') || code == 0x15
                return :ctrl_u
            elseif code == UInt32('v') || code == 0x16
                return :ctrl_v
            elseif code == UInt32('w') || code == 0x17
                return :ctrl_w
            elseif code == UInt32('x') || code == 0x18
                return :ctrl_x
            elseif code == UInt32('y') || code == 0x19
                return :ctrl_y
            elseif code == UInt32('z') || code == 0x1a
                return :ctrl_z
            end
        end

        # Raw control characters (without ctrl flag set)
        code = UInt32(c)
        if code == 0x09
            return :tab
        elseif code == 0x0a
            return :enter
        elseif code == 0x0d
            return Symbol("return")
        elseif code == 0x1b
            return :esc
        elseif code == 0x7f
            return :backspace
        elseif code < 0x20 && code != 0x09 && code != 0x0a && code != 0x0d
            # Other control characters
            letter = Char(code + UInt32('a') - 1)
            return Symbol("ctrl_" * string(letter))
        end

        # Regular printable character: return as String
        return string(c)
    end

    return :nochar
end

# Backward-compatible overload: readtoken on a Plane just uses nc_context
function readtoken( win::NC.Plane )
    global nc_context
    readtoken( nc_context )
end
