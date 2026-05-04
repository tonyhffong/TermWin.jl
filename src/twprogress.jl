# Progress bar widget — driven by a Threads.@spawn worker.
#
# Architecture:
#   * The worker runs in a separate OS thread (via Threads.@spawn in trun()).
#   * The worker reports updates by calling a `report(...)` closure that
#     pushes onto a buffered Channel{ProgressUpdate}.
#   * The main thread's screen event loop calls `tick(o)` on this widget
#     every ~50ms. `tick` drains the channel, updates internal state,
#     refreshes the screen, and detects task completion.
#   * Esc / Ctrl-K set an Atomic{Bool} cancel flag. The worker is responsible
#     for checking it via the `cancelled()` closure (cooperative cancel).

struct ProgressUpdate
    progress::Union{Nothing,Float64}
    text::Union{Nothing,String}
end

mutable struct TwProgressData
    updates::Channel{ProgressUpdate}
    cancelFlag::Threads.Atomic{Bool}
    workTask::Task
    progress::Float64
    text::String
    startTime::Float64
    redrawTime::Float64
end

function newTwProgress(
    scr::TwObj;
    updates::Channel{ProgressUpdate},
    cancelFlag::Threads.Atomic{Bool},
    workTask::Task,
    title::AbstractString = "",
    height::Int = 5,
    width::Int = 50,
    posy::Any = :center,
    posx::Any = :center,
    box = true,
)
    obj = TwObj(
        TwProgressData(updates, cancelFlag, workTask, 0.0, "", time(), time()),
        Val{:Progress},
    )
    obj.box = box
    obj.title = String(title)
    obj.borderSizeV = box ? 1 : 0
    obj.borderSizeH = box ? 1 : 0
    obj.acceptsFocus = true
    link_parent_child(scr, obj, height, width, posy, posx)
    obj
end

function draw(o::TwObj{TwProgressData})
    werase(o.window)
    if o.box
        box(o.window, 0, 0)
    end
    if !isempty(o.title) && o.box
        mvwprintw(
            o.window,
            0,
            round(Int, (o.width - length(o.title)) / 2),
            "%s",
            o.title,
        )
    end
    starty = o.borderSizeV
    startx = o.borderSizeH
    contentW = o.width - 2 * o.borderSizeH
    contentH = o.height - 2 * o.borderSizeV

    p = clamp(o.data.progress, 0.0, 1.0)
    filled = round(Int, contentW * p)
    bar = repeat('▒', filled) * repeat(' ', max(0, contentW - filled))
    wattron(o.window, COLOR_PAIR(15))
    mvwprintw(o.window, starty, startx, "%s", bar)
    wattroff(o.window, COLOR_PAIR(15))
    if !isempty(o.data.text) && contentH >= 2
        # Truncate text to content width to avoid border overrun
        txt = o.data.text
        if length(txt) > contentW
            txt = txt[1:contentW]
        end
        mvwprintw(o.window, starty + 1, startx, "%s", txt)
    end
end

# Drain channel, refresh, check task. Called by screen loop every ~50ms.
function tick(o::TwObj{TwProgressData})
    dirty = false
    while isready(o.data.updates)
        u = take!(o.data.updates)
        if u.progress !== nothing
            o.data.progress = u.progress
            dirty = true
        end
        if u.text !== nothing
            o.data.text = u.text
            dirty = true
        end
    end

    if istaskdone(o.data.workTask)
        # Drain any final updates the worker pushed before finishing
        while isready(o.data.updates)
            u = take!(o.data.updates)
            u.progress !== nothing && (o.data.progress = u.progress)
            u.text !== nothing && (o.data.text = u.text)
        end
        if o.data.workTask.state === :failed
            o.value = nothing
            return :exit_nothing
        else
            o.value = o.data.workTask.result
            return :exit_ok
        end
    end

    # Throttle redraw: at most every 100ms even if many updates arrived
    t = time()
    if dirty && (t - o.data.redrawTime) > 0.1
        o.data.redrawTime = t
        refresh(o)
    end
    return :got_it
end

function inject(o::TwObj{TwProgressData}, token)
    if token == :esc || token == :ctrl_k
        o.data.cancelFlag[] = true
        return :got_it
    end
    return :pass
end

helptext(o::TwObj{TwProgressData}) =
    "Esc or Ctrl-K  : request cooperative cancel\n" *
    "                 (the worker must check `cancelled()` and stop)"
