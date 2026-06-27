# Precompile workload: forces compilation of the hot draw/inject/layout paths
# at package-build time so they're cached in TermWin's package image instead of
# being JIT-compiled on a user's first interactive call.
#
# Two tiers, both individually wrapped so a failure in either NEVER fails
# package precompilation (this code reruns on every `Pkg.precompile()`/dev
# reload, in environments that may not have a real terminal attached):
#   - "pure": logic with no window/session dependency (sizing, theme, bindings
#     dispatch, InlineEditor) — same code paths test/sizing_unit.jl,
#     test/primitives_unit.jl, and test/editor_unit.jl exercise headlessly.
#   - "session": a handful of real top-level widgets (screen/list/popup/entry)
#     built via initsession(), driven directly through draw/inject (NEVER
#     through activateTwObj, which blocks on real keyboard input). Skipped
#     silently if initsession() can't acquire a terminal — exactly the
#     fallback test/window_raise_unit.jl already relies on.

function _precompile_workload_pure()
    resolve_dim(10, 80, 5; main = true)
    resolve_dim(0.5, 80, 5; main = true)
    resolve_dim(:content, 80, 5; main = true)
    resolve_dim(:fill, 80, 5; main = true)
    resolve_dim(Flex(1), 80, 5; main = true)
    allocate_main(Any[:fill, :content, 10], [1, 1, 10], [1, 3, 10], 40)

    for tok in (:header, :selection_focused, :selection_unfocused, :divider, :negative, :emphasis, :focus_indicator)
        theme(tok)
    end

    b = on_key(:F5, "Preview", _ -> Handled)
    list = TwObj(TwListData(), Val{:List})
    list.data.widgets = TwObj[]
    list.data.focus = 0
    list.data.userbindings = Any[b]
    inject_via_table(list, :F5)
    inject_via_table(list, :tab)

    for (T, sample) in ((String, "hello"), (Int, 42), (Float64, 3.14))
        ie = InlineEditor(T)
        editor_load!(ie, sample)
        editor_handle(ie, "x")
        editor_handle(ie, :left)
        editor_handle(ie, :backspace)
        editor_commit(ie)
        editor_render(ie)
    end
    nothing
end

function _precompile_workload_session()
    withsession() do
        scr = rootTwScreen

        popup = newTwPopup(scr, ["a", "b", "c"]; posy = 2, posx = 2, title = "Precompile")
        draw(scr)
        inject(scr, :down)
        inject(scr, :up)

        newTwEntry(scr, String; posy = 2, posx = 40, title = "Name", width = 20)
        draw(scr)
        inject(scr, "x")
        inject(scr, :backspace)

        vstack(scr; form = true, title = "Precompile Form") do s
            newTwEntry(s, String; key = :a, title = "A")
            newTwEntry(s, Int; key = :b, title = "B")
        end
        draw(scr)
        inject(scr, :tab)
        inject(scr, :shift_tab)
        inject(scr, :F1)

        # Mouse-driven move/resize: arm + drive a corner resize (exercises
        # _resize_corner_at, _resize_move! → relayout!) and a title-bar drag
        # (_drag_move!), then release. Same headless path as
        # test/window_resize_unit.jl / window_raise_unit.jl — poke the cache
        # readtoken fills, then inject the synthetic mouse tokens.
        raiseTwObject(popup)
        let cy = popup.ypos + popup.height - 1, cx = popup.xpos + popup.width - 1
            _last_mouse_event[] = (:button1_pressed, cx, cy, nothing)
            inject(scr, :KEY_MOUSE)
            _last_mouse_event[] = (:motion, cx + 2, cy + 2, nothing)
            inject(scr, :KEY_MOUSE_MOTION)
            _last_mouse_event[] = (:button1_released, cx + 2, cy + 2, nothing)
            inject(scr, :KEY_MOUSE)
        end
        let ty = popup.ypos, tx = popup.xpos + 1
            _last_mouse_event[] = (:button1_pressed, tx, ty, nothing)
            inject(scr, :KEY_MOUSE)
            _last_mouse_event[] = (:motion, tx + 2, ty + 1, nothing)
            inject(scr, :KEY_MOUSE_MOTION)
            _last_mouse_event[] = (:button1_released, tx + 2, ty + 1, nothing)
            inject(scr, :KEY_MOUSE)
        end
    end
    nothing
end

@setup_workload begin
    @compile_workload begin
        try
            _precompile_workload_pure()
        catch
        end
        try
            _precompile_workload_session()
        catch
        end
    end
end
