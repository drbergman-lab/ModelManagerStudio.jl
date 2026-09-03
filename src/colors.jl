
#! Palettes are keyed rather than selected by an if/elseif chain. The chain had no `else`, so
#! any STUDIO_COLOR_TOKEN outside the nine known values left `colors` undefined and
#! `color_scheme()` threw an UndefVarError *before the window opened* — a typo in an
#! environment variable should not be fatal.
const COLOR_SCHEMES = Dict{String,Vector{String}}(
    "dodgers"  => ["#005A9C", "#EF3E42", "#A5ACAF"],
    "michigan" => ["#ffcb05", "#00274C", "#75988D"],
    "orioles"  => ["#df4601", "#000000", "#a2aaad"],
    "ravens"   => ["#241773", "#000000", "#9E7C0C"],
    "angels"   => ["#003263", "#BA0021", "#C4CED4"],
    "umb"      => ["#C8102E", "#FFCD00", "#BCBAB9"],
    "hopkins"  => ["#002D72", "#68ACE5", "#CBA052"],
    "csulb"    => ["#000000", "#FFC61E", "#FFC61E"],
    "uci"      => ["#255799", "#fecc07", "#c6beb5"],
)

const DEFAULT_COLOR_SCHEME = "umb"

"""
    color_scheme()

Resolve the GUI palette. Honors `STUDIO_COLOR_TOKEN`; falls back to a random scheme when it is
unset, and to [`DEFAULT_COLOR_SCHEME`](@ref) with a warning when it names something unknown.
"""
function color_scheme()
    requested = get(ENV, "STUDIO_COLOR_TOKEN", "")
    if isempty(requested)
        token = rand(random_color_scheme_list())
    elseif haskey(COLOR_SCHEMES, requested)
        token = requested
    else
        model_manager_studio_warn("Unknown STUDIO_COLOR_TOKEN \"$(requested)\". Using \"$(DEFAULT_COLOR_SCHEME)\". Known schemes: $(join(random_color_scheme_list(), ", ")).")
        token = DEFAULT_COLOR_SCHEME
    end
    model_manager_studio_info("Using color scheme: $token")
    colors = COLOR_SCHEMES[token]
    return JuliaPropertyMap("color_top" => colors[1], "color_bottom" => colors[2], "color_button" => colors[3])
end

random_color_scheme_list() = sort!(collect(keys(COLOR_SCHEMES)))
