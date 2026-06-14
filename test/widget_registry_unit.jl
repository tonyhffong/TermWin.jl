# widget_registry_unit.jl — headless tests for the @twlayout widget registry
#
# Covers the extensibility plumbing that lets external packages plug their own
# widgets into the @twlayout / vstack / hstack DSL. No TTY required: we exercise
# the registry API and the macro's expansion (not execution).
#
# Run standalone:  julia --project=. test/widget_registry_unit.jl

using TermWin
using Test

@testset "twlayout widget registry" begin

    @testset "built-ins registered" begin
        builtins = [:viewer, :dftable, :popup, :entry, :tree, :multiselect,
                    :calendar, :spacer, :label, :separator, :filebrowser, :edittable]
        registered = twlayout_widgets()
        for name in builtins
            @test name in registered
        end
        # The short name resolves to the actual constructor function.
        @test TermWin._twlayout_lookup(:viewer)  === newTwViewer
        @test TermWin._twlayout_lookup(:edittable) === newTwEditTable
    end

    @testset "register / lookup / unregister" begin
        dummy(parent; kw...) = (parent, kw)         # stand-in constructor
        @test TermWin._twlayout_lookup(:dummy_widget) === nothing

        register_twlayout_widget!(:dummy_widget, dummy)
        @test TermWin._twlayout_lookup(:dummy_widget) === dummy
        @test :dummy_widget in twlayout_widgets()

        # twlayout_widgets() is sorted.
        @test issorted(twlayout_widgets())

        unregister_twlayout_widget!(:dummy_widget)
        @test TermWin._twlayout_lookup(:dummy_widget) === nothing
        @test !(:dummy_widget in twlayout_widgets())

        # Unregistering an unknown name is a no-op (no error).
        @test unregister_twlayout_widget!(:never_registered) === nothing
    end

    @testset "macro expansion wires the runtime guard" begin
        # A bare-symbol call inside the body is rewritten to a runtime lookup so
        # that registrations (built-in or external) resolve at run time.
        ex = @macroexpand @twlayout begin
            myrating(; key = :r)
        end
        s = string(ex)
        @test occursin("_twlayout_lookup", s)

        # A non-call statement passes straight through — no lookup guard emitted.
        ex2 = @macroexpand @twlayout begin
            local z = 1
        end
        @test !occursin("_twlayout_lookup", string(ex2))
    end

end
