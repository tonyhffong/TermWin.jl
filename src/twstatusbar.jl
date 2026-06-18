mutable struct TwStatusBarData
    text::String
end

function newTwStatusBar(
    scr::TwObj,
    obs::Observable{String};
    height::SizeSpec = 1,
    width::SizeSpec  = 1.0,
    posy::Any    = :top,
    posx::Any    = :left,
)
    data = TwStatusBarData(obs.value)
    obj  = TwObj(data, Val{:StatusBar})
    obj.box          = false
    obj.borderSizeV  = 0
    obj.borderSizeH  = 0
    obj.acceptsFocus = false
    link_parent_child(scr, obj, height, width, posy, posx)
    subscribe!(obs, obj) do s
        data.text = s
        refresh(obj)
    end
    obj
end

function draw(o::TwObj{TwStatusBarData})
    werase(o.window)
    isempty(o.data.text) && return
    wattron(o.window, theme(:divider))
    mvwprintw(o.window, 0, 0, "%s", ensure_length(o.data.text, o.width))
    wattroff(o.window, theme(:divider))
end

inject(::TwObj{TwStatusBarData}, ::Any) = Ignored
helptext(::TwObj{TwStatusBarData}) = ""
