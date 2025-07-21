
function color_scheme()
    token = "STUDIO_COLOR_TOKEN" in keys(ENV) ? ENV["STUDIO_COLOR_TOKEN"] : rand(random_color_scheme_list())
    model_manager_studio_info("Using color scheme: $token")
    if token == "dodgers"
        colors = ["#005A9C", "#EF3E42", "#A5ACAF"]
    elseif token == "michigan"
        colors = ["#ffcb05", "#00274C", "#75988D"]
    elseif token == "orioles"
        colors = ["#df4601", "#000000", "#a2aaad"]
    elseif token == "ravens"
        colors = ["#241773", "#000000", "#9E7C0C"]
    elseif token == "angels"
        colors = ["#003263", "#BA0021", "#C4CED4"]
    elseif token == "umb"
        colors = ["#C8102E", "#FFCD00", "#BCBAB9"]
    elseif token == "hopkins"
        colors = ["#002D72", "#68ACE5", "#CBA052"]
    elseif token == "csulb"
        colors = ["#000000", "#FFC61E", "#FFC61E"]
    elseif token == "uci"
        colors = ["#255799", "#fecc07", "#c6beb5"]
    end
    return JuliaPropertyMap("color_top" => colors[1], "color_bottom" => colors[2], "color_button" => colors[3])
end

random_color_scheme_list() = ["dodgers", "michigan", "orioles", "ravens", "angels", "umb", "hopkins", "csulb", "uci"]