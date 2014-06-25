ncnummap = (Int=>Symbol) [
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
    int( 0x232 ) => :ctrl_up,
    int( 0x233 ) => :ctrlshift_up,
    int( 0x209 ) => :ctrl_down,
    int( 0x20a ) => :ctrlshift_down,
    int( 0x21d ) => :ctrl_left,
    int( 0x21e ) => :ctrlshift_left,
    int( 0x22c ) => :ctrl_right,
    int( 0x22d ) => :ctrlshift_right,
    int(0o0402) => :down,
    int(0o0403) => :up,
    int(0o0404) => :left,
    int(0o0405) => :right,
    int(0o0406) => :home,
    int(0o0407) => :backspace,
    int(0o0411) => :F1,
    int(0o0412) => :F2,
    int(0o0413) => :F3,
    int(0o0414) => :F4,
    int(0o0415) => :F5,
    int(0o0416) => :F6,
    int(0o0417) => :F7,
    int(0o0420) => :F8,
    int(0o0421) => :F9,
    int(0o0422) => :F10,
    int(0o0423) => :F11,
    int(0o0424) => :F12,
    int(0o0425) => :shift_F1,
    int(0o0426) => :shift_F2,
    int(0o0427) => :shift_F3,
    int(0o0430) => :shift_F4,
    int(0o0431) => :shift_F5,
    int(0o0432) => :shift_F6,
    int(0o0433) => :shift_F7,
    int(0o0434) => :shift_F8,
    int(0o0435) => :shift_F9,
    int(0o0436) => :shift_F10,
    int(0o0437) => :shift_F11,
    int(0o0440) => :shift_F12,

    int(0o0510) => :KEY_DL,
    int(0o0511) => :insert,
    int(0o0512) => :delete,
    int(0o0513) => :KEY_IC,
    int(0o0514) => :KEY_EIC,
    int(0o0515) => :KEY_CLEAR,
    int(0o0516) => :KEY_EOS,
    int(0o0517) => :KEY_EOL,
    int(0o0520) => :shift_down,
    int(0o0521) => :shift_up,
    int(0o0522) => :pagedown,
    int(0o0523) => :pageup,
    int(0o0524) => :KEY_STAB,
    int(0o0525) => :KEY_CTAB,
    int(0o0526) => :KEY_CATAB,
    int(0o0527) => :enter,
    int(0o0532) => :KEY_PRINT,
    int(0o0533) => :KEY_LL,
    int(0o0534) => :KEY_A1,
    int(0o0535) => :KEY_A3,
    int(0o0536) => :KEY_B2,
    int(0o0537) => :KEY_C1,
    int(0o0540) => :KEY_C3,
    int(0o0541) => :KEY_BTAB,
    int(0o0542) => :KEY_BEG,
    int(0o0543) => :KEY_CANCEL,
    int(0o0544) => :KEY_CLOSE,
    int(0o0545) => :KEY_COMMAND,
    int(0o0546) => :KEY_COPY,
    int(0o0547) => :KEY_CREATE,
    int(0o0550) => symbol( "end" ),
    int(0o0551) => :KEY_EXIT,
    int(0o0552) => :KEY_FIND,
    int(0o0553) => :KEY_HELP,
    int(0o0554) => :KEY_MARK,
    int(0o0555) => :KEY_MESSAGE,
    int(0o0556) => :KEY_MOVE,
    int(0o0557) => :KEY_NEXT,
    int(0o0560) => :KEY_OPEN,
    int(0o0561) => :KEY_OPTIONS,
    int(0o0562) => :KEY_PREVIOUS,
    int(0o0563) => :KEY_REDO,
    int(0o0564) => :KEY_REFERENCE,
    int(0o0565) => :KEY_REFRESH,
    int(0o0566) => :KEY_REPLACE,
    int(0o0567) => :KEY_RESTART,
    int(0o0570) => :KEY_RESUME,
    int(0o0571) => :KEY_SAVE,
    int(0o0572) => :KEY_SBEG,
    int(0o0573) => :KEY_SCANCEL,
    int(0o0574) => :KEY_SCOMMAND,
    int(0o0575) => :KEY_SCOPY,
    int(0o0576) => :KEY_SCREATE,
    int(0o0577) => :KEY_SDC,
    int(0o0600) => :KEY_SDL,
    int(0o0601) => :KEY_SELECT,
    int(0o0602) => :shift_end,
    int(0o0603) => :KEY_SEOL,
    int(0o0604) => :KEY_SEXIT,
    int(0o0605) => :KEY_SFIND,
    int(0o0606) => :KEY_SHELP,
    int(0o0607) => :shift_home,
    int(0o0610) => :KEY_SIC,
    int(0o0611) => :shift_left,
    int(0o0612) => :KEY_SMESSAGE,
    int(0o0613) => :KEY_SMOVE,
    int(0o0614) => :KEY_SNEXT,
    int(0o0615) => :KEY_SOPTIONS,
    int(0o0616) => :KEY_SPREVIOUS,
    int(0o0617) => :KEY_SPRINT,
    int(0o0620) => :KEY_SREDO,
    int(0o0621) => :KEY_SREPLACE,
    int(0o0622) => :shift_right,
    int(0o0623) => :KEY_SRSUME,
    int(0o0624) => :KEY_SSAVE,
    int(0o0625) => :KEY_SSUSPEND,
    int(0o0626) => :KEY_SUNDO,
    int(0o0627) => :KEY_SUSPEND,
    int(0o0630) => :KEY_UNDO,
    int(0o0631) => :KEY_MOUSE,
    int(0o0632) => :KEY_RESIZE,
    int(0o0633) => :KEY_EVENT
]

function readtoken( win::Ptr{Void} )
    c = wgetch( win )
    if c == 27
        nodelay( win, true )
        notimeout( win, false )
        s = string( char( c ) )
        # This part gets around a MacOS ncurses bug, which hasn't been fixed
        # for quite some time...
        while( ( nc = wgetch(win ) ) != char(-1) )
            s *= string(char(nc))
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
        nodelay( win, false )
        notimeout( win, true )
        return ret
    end
    if haskey( ncnummap, c )
        return ncnummap[ c]
    else
        return string( char( c ) )
    end
end
