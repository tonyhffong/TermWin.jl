using TermWin

# write your own tests here

# dftests.jl / aggrspecs.jl moved to the DataFrameAggrSpec package (the DSL now lives
# there; TermWin re-exports its surface and is tested for integration via dataframe.jl)
include( "strtests.jl" )
include( "progress_unit.jl" )
include( "primitives_unit.jl" )
include( "sizing_unit.jl" )
include( "editor_unit.jl" )
include( "widget_registry_unit.jl" )
include( "custom_keys_unit.jl" )
include( "calendar_clear_unit.jl" )
include( "visibility_unit.jl" )
include( "arrow_nav_unit.jl" )
include( "window_raise_unit.jl" )
include( "window_resize_unit.jl" )
