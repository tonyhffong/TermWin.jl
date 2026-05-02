# dicttree_edit.jl — editable Dict tree demo
#
# Scenario: application configuration editor.
# The widget lets you browse and edit a nested configuration dict in-place,
# with support for scalar editing, structural add/delete/rename, and Vector
# element reordering — all without writing any per-field boilerplate.
#
# Usage:
#   julia --project=. test/dicttree_edit.jl
#
# Things to try:
#   1. Navigate to "debug" (Bool leaf) → press Enter → type "t" → Enter to flip it true.
#   2. Navigate to "database" → expand it → navigate to "host" → press e to edit inline.
#   3. Navigate to "auth" → expand → navigate to "allowed_domains" Vector →
#      expand it → press Alt-Down on a domain to reorder it.
#   4. Navigate to "feature_flags" → expand → press Ctrl-N to add a new flag.
#   5. Navigate to any Dict key → press r to rename it.
#   6. Navigate to any entry → press Ctrl-D to delete it.
#   7. Navigate to "rate_limits" → expand → Ctrl-N → choose Dict{String,Any} →
#      then Ctrl-N on the new empty Dict to add entries inside it.
#   8. Press / to search; n / p to cycle matches.
#   9. Press F10 to submit, Esc to cancel.
#
# Controls:
#   Enter / e / F2   : edit a leaf value inline
#   Enter (container): toggle expand / collapse
#   Ctrl-N           : add entry  (child if on a container, sibling if on a leaf)
#   Ctrl-D           : delete current entry
#   r                : rename current Dict key
#   Alt-Up / Alt-Dn  : move a Vector element up / down
#   Ctrl-Left        : jump to parent node
#   Ctrl-Up / Ctrl-Dn: jump to prev / next sibling
#   + / -            : expand / collapse one level
#   _                : collapse all
#   /                : search; n / p = next / previous match
#   F6               : popup viewer for the value at the cursor
#   F1               : full help text
#   F10              : submit and return the edited dict
#   Esc              : cancel — original dict is unchanged

using TermWin, Dates, Printf

# ── Sample configuration dict ─────────────────────────────────────────────────

config = Dict{String,Any}(
    "app_name"    => "MyService",
    "version"     => "2.4.1",
    "debug"       => false,
    "max_workers" => 8,
    "timeout_sec" => 30.0,
    "launch_date" => Date(2024, 3, 15),

    "database" => Dict{String,Any}(
        "host"     => "db.internal",
        "port"     => 5432,
        "name"     => "production",
        "pool_min" => 2,
        "pool_max" => 20,
        "ssl"      => true,
    ),

    "cache" => Dict{String,Any}(
        "backend"  => "redis",
        "host"     => "cache.internal",
        "port"     => 6379,
        "ttl_sec"  => 3600,
    ),

    "auth" => Dict{String,Any}(
        "provider"        => "oauth2",
        "token_expiry_hr" => 24,
        "require_mfa"     => false,
        "allowed_domains" => Vector{String}([
            "example.com",
            "partner.org",
            "internal.net",
        ]),
    ),

    "feature_flags" => Dict{String,Any}(
        "new_dashboard"  => true,
        "beta_api"       => false,
        "dark_mode"      => true,
        "experiment_xyz" => false,
    ),

    "rate_limits" => Dict{String,Any}(
        "requests_per_min" => 1000,
        "burst"            => 250,
        "endpoints" => Vector{Any}([
            Dict{String,Any}("path" => "/api/upload", "limit" => 10),
            Dict{String,Any}("path" => "/api/search", "limit" => 100),
        ]),
    ),
)

# ── Launch the editor ─────────────────────────────────────────────────────────

TermWin.initsession()

widget = newTwDictTree(
    rootTwScreen, config;
    title = "Application Config  [F10: save · Esc: cancel]",
)

activateTwObj(rootTwScreen)
edited = widget.value   # the modified copy, or nothing if Esc was pressed
TermWin.endsession()

# ── Show results ──────────────────────────────────────────────────────────────

if edited === nothing
    println("\nCancelled — original config unchanged.")
else
    println("\nSubmitted config (top-level keys):\n")
    for k in sort(collect(keys(edited)))
        v = edited[k]
        if isa(v, AbstractDict)
            @printf("  %-20s  =>  <%s, %d keys>\n", k, string(typeof(v)), length(v))
        elseif isa(v, AbstractVector)
            @printf("  %-20s  =>  <%s, %d items>\n", k, string(typeof(v)), length(v))
        else
            @printf("  %-20s  =>  %s\n", k, repr(v))
        end
    end

    println()
    println("Selected nested values:\n")
    try; @printf("  database.host          = %s\n",  edited["database"]["host"]);    catch; end
    try; @printf("  database.port          = %d\n",  edited["database"]["port"]);    catch; end
    try; @printf("  database.ssl           = %s\n",  edited["database"]["ssl"]);     catch; end
    try; @printf("  auth.provider          = %s\n",  edited["auth"]["provider"]);    catch; end
    try; @printf("  auth.require_mfa       = %s\n",  edited["auth"]["require_mfa"]); catch; end
    try
        domains = edited["auth"]["allowed_domains"]
        @printf("  auth.allowed_domains   = [%s]\n", join(domains, ", "))
    catch; end
    try; @printf("  feature_flags.beta_api = %s\n",  edited["feature_flags"]["beta_api"]);     catch; end
    try; @printf("  feature_flags.dark_mode= %s\n",  edited["feature_flags"]["dark_mode"]);    catch; end
    try; @printf("  rate_limits.burst      = %d\n",  edited["rate_limits"]["burst"]);           catch; end
end
