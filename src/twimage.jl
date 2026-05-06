# twimage.jl — image widget that renders a raster image (PNG, JPEG, GIF,
# WebP, BMP, TIFF) into a TermWin pane via Notcurses' ncvisual API.
#
# Capability detection:
#   * NC.check_pixel_support(nc) returns an NcPixelImpl enum. Anything other
#     than NcPixelImpl.NONE means the terminal supports true raster pixels
#     (sixel / kitty graphics / iTerm2). We use Blitter.PIXEL in that case.
#   * Otherwise NC.media_defblitter(nc, scaling) picks the best Unicode
#     blitter for this terminal (sextant / quadrant / half-block / braille).
#
# Resize: relayout!() resizes the underlying plane on :KEY_RESIZE. The
# decoded NC.Visual is cached on the widget; only the rasterization (blit)
# is redone on the next draw.
#
# Cleanup: a finalizer on the widget calls NC.destroy on the Visual.
#
# Limitations (v1):
#   * Static — first frame only; no GIF / video animation
#   * No pan / zoom / rotate
#   * Only works when o.window is an NC.Plane (not when embedded inside a
#     TwList canvas, which uses TwWindow). Embedded use falls back to a
#     "(image not supported in nested layout)" message.

const _IMAGE_HELP = """
Esc : close the image
F1  : this help
"""

mutable struct TwImageData
    path::String
    visual::Union{Nothing,NC.Visual}
    blitter::NC.Blitter.T
    scaling::NC.Scale.T
    errorMsg::String
end

# Pick the best blitter for this terminal. Prefers PIXEL when the terminal
# supports it; otherwise falls back to the best Unicode-block blitter.
function _resolve_image_blitter(nc::NC.NotcursesObject, scaling::NC.Scale.T)
    has_pixel = false
    try
        has_pixel = NC.check_pixel_support(nc) !== NC.NcPixelImpl.NONE
    catch
        has_pixel = false
    end
    has_pixel ? NC.Blitter.PIXEL : NC.media_defblitter(nc, scaling)
end

"""
    newTwImage(parent, path; kwargs...)

Create an image widget that displays the file at `path`. Supported formats
depend on the libavformat backing notcurses (typically PNG, JPEG, GIF,
WebP, BMP, TIFF).

Keyword arguments:
- `height`, `width`  — pane size (integer cells or float fraction of parent).
                       Defaults to `20 × 60` when both are zero.
- `posy`, `posx`     — placement on the parent (`:center` by default).
- `box`              — draw a border (default `true`).
- `title`            — optional title text in the top border.
- `blitter`          — `NC.Blitter.T` to force a specific blitter; default
                       auto-detects (`PIXEL` if the terminal supports it,
                       otherwise the best Unicode blitter).
- `scaling`          — `NC.Scale.T`, default `Scale.SCALE` (preserve aspect).
                       Other useful values: `Scale.NONE`, `Scale.STRETCH`.

If the file cannot be loaded the widget renders an error message instead.
Press Esc to close.
"""
function newTwImage(
    scr::TwObj,
    path::AbstractString;
    height::Real = 0.8,
    width::Real  = 0.8,
    posy::Any    = :center,
    posx::Any    = :center,
    box          = true,
    title::AbstractString = "",
    blitter::Union{Nothing,NC.Blitter.T} = nothing,
    scaling::NC.Scale.T  = NC.Scale.SCALE,
)
    global nc_context
    obj = TwObj(
        TwImageData(
            String(path),
            nothing,
            blitter === nothing ? NC.Blitter.DEFAULT : blitter,
            scaling,
            "",
        ),
        Val{:Image},
    )
    obj.box = box
    obj.title = String(title)
    obj.borderSizeV = box ? 1 : 0
    obj.borderSizeH = box ? 1 : 0
    obj.acceptsFocus = true

    # Resolve auto blitter against the live terminal context
    if blitter === nothing && nc_context !== nothing
        try
            obj.data.blitter = _resolve_image_blitter(nc_context, scaling)
        catch er
            log("TwImage blitter resolution failed: " * sprint(showerror, er))
            obj.data.blitter = NC.Blitter.DEFAULT
        end
    end

    # Try to load the visual; if it fails, draw() will show the error.
    # We call ncvisual_from_file directly: NC.from_file in some binding
    # versions wraps the path with `Cstring(pointer(...))` which trips a
    # MethodError in unsafe_convert on current Julia. Passing a Julia
    # String directly lets ccall do the right cconvert dance.
    if !isfile(obj.data.path)
        obj.data.errorMsg = "(file not found: $(obj.data.path))"
    else
        try
            ptr = NC.LibNotcurses.ncvisual_from_file(obj.data.path)
            if ptr == C_NULL
                obj.data.errorMsg = "(could not decode image: $(obj.data.path))"
            else
                obj.data.visual = NC.Visual(ptr)
            end
        catch er
            obj.data.errorMsg = "(failed to decode: $(sprint(showerror, er)))"
        end
    end

    # Free the Visual when the widget is GC'd. Stacks on top of TwObj's
    # built-in plane finalizer (registered in TwObj{T,S}(d)).
    finalizer(obj) do o
        if o.data.visual !== nothing
            try
                NC.destroy(o.data.visual)
            catch
            end
            o.data.visual = nothing
        end
    end

    h = height != 0 ? height : 20
    w = width  != 0 ? width  : 60
    link_parent_child(scr, obj, h, w, posy, posx)
    obj
end

function draw(o::TwObj{TwImageData})
    werase(o.window)
    if o.box
        box(o.window, 0, 0)
    end
    if !isempty(o.title) && o.box
        mvwprintw(o.window, 0,
                  round(Int, (o.width - length(o.title)) / 2),
                  "%s", o.title)
    end

    contentH = o.height - 2 * o.borderSizeV
    contentW = o.width  - 2 * o.borderSizeH
    if contentH <= 0 || contentW <= 0
        return
    end

    # Embedded-in-list: o.window is a TwWindow on a shared canvas plane.
    # Pixel/cell blits to the canvas plane misalign with the list's scroll
    # offsets. Defer real support and show a helpful message.
    if !(o.window isa NC.Plane)
        msg = "(image preview unavailable inside list layout)"
        mvwprintw(o.window, max(o.borderSizeV, 0), o.borderSizeH,
                  "%s", ensure_length(msg, contentW, false))
        return
    end

    if o.data.visual === nothing
        msg = isempty(o.data.errorMsg) ? "(no image)" : o.data.errorMsg
        mvwprintw(o.window, max(o.borderSizeV, 0), o.borderSizeH,
                  "%s", ensure_length(msg, contentW, false))
        return
    end

    opts = NC.VisualOptions(;
        plane   = o.window,
        scaling = o.data.scaling,
        y       = o.borderSizeV,
        x       = o.borderSizeH,
        leny    = UInt(0),     # 0 means "entire visual height"
        lenx    = UInt(0),     # 0 means "entire visual width"
        blitter = o.data.blitter,
    )
    try
        NC.blit(nc_context, o.data.visual, opts)
    catch er
        log("TwImage blit failed: " * sprint(showerror, er))
        mvwprintw(o.window, max(o.borderSizeV, 0), o.borderSizeH,
                  "%s", ensure_length("(blit failed)", contentW, false))
    end
end

function inject(o::TwObj{TwImageData}, token)
    if token == :esc
        return :exit_nothing
    end
    return :pass
end

helptext(o::TwObj{TwImageData}) = _IMAGE_HELP
