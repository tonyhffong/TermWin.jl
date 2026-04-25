# Input system using Notcurses structured input.
# Returns the same symbol tokens as the old ncurses readtoken
# for backward compatibility with widget inject() methods.

# Map Notcurses Key enums to TermWin symbol tokens
const NC_KEY_TO_SYMBOL = Dict{NC.Key.T,Symbol}(
    NC.Key.UP => :up,
    NC.Key.DOWN => :down,
    NC.Key.LEFT => :left,
    NC.Key.RIGHT => :right,
    NC.Key.HOME => :home,
    NC.Key.END => Symbol("end"),
    NC.Key.PGUP => :pageup,
    NC.Key.PGDOWN => :pagedown,
    NC.Key.INS => :insert,
    NC.Key.DEL => :delete,
    NC.Key.BACKSPACE => :backspace,
    NC.Key.ENTER => :enter,
    NC.Key.TAB => :tab,
    NC.Key.ESC => :esc,
    NC.Key.F01 => :F1,
    NC.Key.F02 => :F2,
    NC.Key.F03 => :F3,
    NC.Key.F04 => :F4,
    NC.Key.F05 => :F5,
    NC.Key.F06 => :F6,
    NC.Key.F07 => :F7,
    NC.Key.F08 => :F8,
    NC.Key.F09 => :F9,
    NC.Key.F10 => :F10,
    NC.Key.F11 => :F11,
    NC.Key.F12 => :F12,
    # Shifted function keys (F13–F24 = Shift+F1–F12 on traditional terminals)
    NC.Key.F13 => :shift_F1,
    NC.Key.F14 => :shift_F2,
    NC.Key.F15 => :shift_F3,
    NC.Key.F16 => :shift_F4,
    NC.Key.F17 => :shift_F5,
    NC.Key.F18 => :shift_F6,
    NC.Key.F19 => :shift_F7,
    NC.Key.F20 => :shift_F8,
    NC.Key.F21 => :shift_F9,
    NC.Key.F22 => :shift_F10,
    NC.Key.F23 => :shift_F11,
    NC.Key.F24 => :shift_F12,
    # Ctrl+function keys (F25–F36 = Ctrl+F1–F12 on traditional terminals)
    NC.Key.F25 => :ctrl_F1,
    NC.Key.F26 => :ctrl_F2,
    NC.Key.F27 => :ctrl_F3,
    NC.Key.F28 => :ctrl_F4,
    NC.Key.F29 => :ctrl_F5,
    NC.Key.F30 => :ctrl_F6,
    NC.Key.F31 => :ctrl_F7,
    NC.Key.F32 => :ctrl_F8,
    NC.Key.F33 => :ctrl_F9,
    NC.Key.F34 => :ctrl_F10,
    NC.Key.F35 => :ctrl_F11,
    NC.Key.F36 => :ctrl_F12,
    # Ctrl+Shift+function keys (F37–F48 = Ctrl+Shift+F1–F12 on traditional terminals)
    NC.Key.F37 => :ctrlshift_F1,
    NC.Key.F38 => :ctrlshift_F2,
    NC.Key.F39 => :ctrlshift_F3,
    NC.Key.F40 => :ctrlshift_F4,
    NC.Key.F41 => :ctrlshift_F5,
    NC.Key.F42 => :ctrlshift_F6,
    NC.Key.F43 => :ctrlshift_F7,
    NC.Key.F44 => :ctrlshift_F8,
    NC.Key.F45 => :ctrlshift_F9,
    NC.Key.F46 => :ctrlshift_F10,
    NC.Key.F47 => :ctrlshift_F11,
    NC.Key.F48 => :ctrlshift_F12,
    NC.Key.RESIZE => :KEY_RESIZE,
)

# returns either a string or a symbol
function readtoken(nc::NC.NotcursesObject)
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

        # Apply modifiers — check most-specific combos first
        has_shift = ni.shift
        has_ctrl = ni.ctrl
        has_alt = ni.alt

        if has_ctrl && has_shift && has_alt
            return Symbol("ctrlshiftalt_" * string(base_sym))
        elseif has_ctrl && has_alt
            return Symbol("ctrlalt_" * string(base_sym))
        elseif has_ctrl && has_shift
            return Symbol("ctrlshift_" * string(base_sym))
        elseif has_alt && has_shift
            return Symbol("altshift_" * string(base_sym))
        elseif has_ctrl
            return Symbol("ctrl_" * string(base_sym))
        elseif has_alt
            return Symbol("alt_" * string(base_sym))
        elseif has_shift
            # shift + function keys
            if base_sym in (:F1, :F2, :F3, :F4, :F5, :F6, :F7, :F8, :F9, :F10, :F11, :F12)
                return Symbol("shift_" * string(base_sym))
            elseif base_sym in
                   (:up, :down, :left, :right, :home, Symbol("end"), :pageup, :pagedown)
                return Symbol("shift_" * string(base_sym))
            elseif base_sym == :tab
                return :shift_tab
            else
                return base_sym
            end
        else
            return base_sym
        end
    end

    # Printable character
    if key isa Char
        c = key
        code = UInt32(c)
        has_ctrl = ni.ctrl
        has_shift = ni.shift
        has_alt = ni.alt

        # Handle ctrl flag + letter (lowercase, uppercase, or raw control code)
        if has_ctrl
            local base_letter::Union{Char,Nothing} = nothing
            if code >= UInt32('a') && code <= UInt32('z')
                base_letter = c
            elseif code >= UInt32('A') && code <= UInt32('Z')
                base_letter = lowercase(c)
            elseif code >= 0x01 && code <= 0x1a
                base_letter = Char(code + UInt32('a') - 1)
            end
            if base_letter !== nothing
                prefix = if has_shift && has_alt
                    "ctrlshiftalt_"
                elseif has_alt
                    "ctrlalt_"
                elseif has_shift
                    "ctrlshift_"
                else
                    "ctrl_"
                end
                return Symbol(prefix * string(base_letter))
            end
        end

        # Raw control characters (terminals that don't set ni.ctrl flag)
        # Check before alt handler so raw codes aren't misinterpreted
        if code == 0x09
            return has_shift ? :shift_tab : :tab
        elseif code == 0x0a
            return :enter
        elseif code == 0x0d
            return Symbol("return")
        elseif code == 0x1b
            return :esc
        elseif code == 0x7f
            return :backspace
        elseif code < 0x20
            # Raw control code from terminal that doesn't set ni.ctrl
            letter = Char(code + UInt32('a') - 1)
            if has_alt
                return Symbol("ctrlalt_" * string(letter))
            else
                return Symbol("ctrl_" * string(letter))
            end
        end

        # Alt + printable character (no ctrl)
        if has_alt
            base_str = isletter(c) ? string(lowercase(c)) : string(c)
            if has_shift
                return Symbol("altshift_" * base_str)
            else
                return Symbol("alt_" * base_str)
            end
        end

        # Regular printable character: return as String
        return string(c)
    end

    return :nochar
end

# Backward-compatible overload: readtoken on a Plane just uses nc_context
function readtoken(win::NC.Plane)
    global nc_context
    readtoken(nc_context)
end
