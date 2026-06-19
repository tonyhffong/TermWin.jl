# Headless unit tests for custom layout key bindings (on_key + newTwList `keys`).
# No TTY required — a TwList and its keyed leaf widgets are built manually and the
# Binding's action is driven directly, exercising the snapshot callback path,
# the InjectResult semantics, and dispatch through inject_via_table.
#
# Run:
#   julia --project=. test/custom_keys_unit.jl

using Test
using TermWin

const TW = TermWin

# A minimal leaf widget data type (no special behaviour needed).
struct _CKLeaf end

# Build a leaf carrying a form key + value, the shape collect_form_values reads.
function _ck_field(key::Symbol, val)
    o = TW.TwObj(_CKLeaf(), Val{:Leaf})
    o.formkey = key
    o.value = val
    o
end

# Build a TwList (window stays nothing → not a root NC.Plane) holding the fields.
function _ck_mklist(fields...; keys = TermWin.Binding[])
    o = TW.TwObj(TW.TwListData(), Val{:List})
    o.data.widgets = collect(TW.TwObj, fields)
    o.data.focus = 1
    o.data.userbindings = collect(Any, keys)
    o
end

@testset "on_key builds a Binding" begin
    b = on_key(:F5, "Preview", _ -> Handled)
    @test b isa TermWin.Binding
    @test :F5 in b.keys
    @test b.label == "Preview"
    # Multiple tokens for one action.
    b2 = on_key([:ctrl_s, :F2], "Save", _ -> Handled)
    @test :ctrl_s in b2.keys && :F2 in b2.keys
end

@testset "callback receives the data snapshot" begin
    seen = Ref{Any}(nothing)
    b = on_key(:F5, "Preview", snap -> (seen[] = snap; Handled))
    list = _ck_mklist(_ck_field(:title, "hello"), _ck_field(:n, 42))
    r = b.action(list)
    @test r === Handled
    @test seen[] == Dict(:title => "hello", :n => 42)
end

@testset "Accept stores the snapshot into the list value (early submit)" begin
    b = on_key(:ctrl_s, "Save", snap -> Accept)
    list = _ck_mklist(_ck_field(:title, "draft"))
    r = b.action(list)
    @test r === Accept
    @test list.value == Dict(:title => "draft")
end

@testset "non-InjectResult return is treated as Handled" begin
    b = on_key(:F5, "Noop", snap -> nothing)
    list = _ck_mklist(_ck_field(:a, 1))
    @test b.action(list) === Handled
end

@testset "explicit Cancel / Ignored are passed through" begin
    list = _ck_mklist(_ck_field(:a, 1))
    @test on_key(:esc, "Quit", _ -> Cancel).action(list) === Cancel
    @test on_key(:x,   "Pass", _ -> Ignored).action(list) === Ignored
end

@testset "user bindings appear after built-ins and dispatch via inject_via_table" begin
    hit = Ref(false)
    list = _ck_mklist(_ck_field(:a, 1);
                   keys = [on_key(:F5, "Preview", _ -> (hit[] = true; Handled))])
    bs = bindings(list)
    # Built-ins still present, user binding is last.
    labels = [b.label for b in bs]
    @test "submit form" in labels
    @test last(bs).label == "Preview"
    # Dispatch: F5 routes to the custom action.
    @test inject_via_table(list, :F5) === Handled
    @test hit[]
    # An unbound key is ignored.
    @test inject_via_table(list, :F9) === Ignored
end

@testset "no user bindings → only built-ins" begin
    list = _ck_mklist(_ck_field(:a, 1))
    @test all(b -> b.label != "Preview", bindings(list))
end

println("custom_keys_unit.jl: all tests passed")
