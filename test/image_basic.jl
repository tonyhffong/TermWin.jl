# Manual test for the TwImage widget and tshow("…", "img") dispatch.
#
# Run:
#   julia --project=. test/image_basic.jl
#
# Override the test image with the TEST_IMAGE env var:
#   TEST_IMAGE=/path/to/your.png julia --project=. test/image_basic.jl
#
# The script runs four scenarios. After each one the dialog dismisses
# and the next scenario starts. Press Esc to advance.
#
#   1. EXPLICIT TITLE   — img:Title-from-hint dispatch
#   2. KWARG TITLE      — title= kwarg takes precedence over hint suffix
#   3. FILE NOT FOUND   — error path: "(file not found: …)"
#   4. NOT AN IMAGE     — error path: "(failed to decode: …)"
#
# What you should see depends on your terminal:
#   * iTerm2 / kitty / WezTerm / foot       → real raster pixels
#   * Terminal.app / xterm / others         → Unicode-block rendering
#                                              (sextant / quadrant / half / braille)

using TermWin

# Locate a usable test image.
function find_test_image()
    overridden = get(ENV, "TEST_IMAGE", "")
    if !isempty(overridden)
        if isfile(overridden)
            return overridden
        else
            error("TEST_IMAGE points to a non-existent file: $overridden")
        end
    end
    # Common fallback locations on macOS / Linux dev boxes
    candidates = String[
        joinpath(homedir(), "Pictures", "test.png"),
        joinpath(homedir(), "Desktop", "test.png"),
        "/System/Library/CoreServices/DefaultDesktop.heic",
        "/System/Library/CoreServices/DefaultBackground.png",
        "/usr/share/backgrounds/warty-final-ubuntu.png",
    ]
    for c in candidates
        isfile(c) && return c
    end
    error("""
    No test image found. Set the TEST_IMAGE environment variable to any
    PNG / JPEG / GIF / WebP / BMP file, e.g.:

        TEST_IMAGE=/path/to/cat.png julia --project=. test/image_basic.jl
    """)
end

img = find_test_image()
println("Using test image: $img")
println()

println("=== Test 1: img:Title-from-hint dispatch ===")
println("Press Esc to advance to test 2.\n")
tshow(img, "img:Title from hint")

println("\n=== Test 2: title= kwarg takes precedence ===")
println("The title bar should read 'Kwarg-supplied title', not 'Ignored'.\n")
tshow(img, "img:Ignored"; title = "Kwarg-supplied title")

println("\n=== Test 3: file not found ===")
println("The pane should display '(file not found: ...)'.\n")
tshow("/this/file/does/not/exist.png", "img")

println("\n=== Test 4: not a decodable image ===")
println("The pane should display '(failed to decode: ...)'.\n")
# /etc/hosts exists on macOS/Linux; pick something else if not
not_an_image = isfile("/etc/hosts") ? "/etc/hosts" : @__FILE__
tshow(not_an_image, "img:Not an image")

println("\nAll image tests done.")
