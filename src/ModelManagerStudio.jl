module ModelManagerStudio

# Write your package code here.
using QML, PhysiCellModelManager, LightXML, Compat, Distributions

@compat public launch

include("colors.jl")
include("record.jl")

global current_required_locations
global current_optional_locations
global inputs
global tokens_avs = Tuple[]

"""
    init_model_manager_gui(args::Vararg{AbstractString}; kwargs...)

Internal function to initialize the Model Manager GUI with the specified arguments.
Called by [`launch`](@ref).
"""
function init_model_manager_gui(args::Vararg{AbstractString}; testing::Bool=false, kwargs...)
    if !studio_initialize_model_manager(args...; kwargs...)
        throw("Error initializing Model Manager. Please make sure you are in the correct directory.")
    end

    initialize_record()

    @qmlfunction get_folders joinpath set_input_folders run_simulation get_input_folder get_next_model get_varied_locations get_substrate_names
    @qmlfunction get_cell_type_names get_target_path create_variation get_current_variations variation_exists location_label is_varied_location

    # absolute path in case working dir is overridden
    qml_file = joinpath(@__DIR__, "..", "assets", "ModelManagerStudio.qml")

    # Load the QML file
    return loadqml(qml_file; reqLocModel=required_input_folders(), optLocModel=optional_input_folders(), guiproperties=color_scheme(), project_configuration_properties=create_project_configuration_properties(), testing=JuliaPropertyMap("testing" => testing))
end

"""
    launch()
    launch(path_to_project::AbstractString)
    launch(data_dir::AbstractString, physicell_dir::AbstractString)

Launch the Model Manager Studio GUI for a particular project.

If no arguments are provided, it will initialize the Model Manager within the current working directory, i.e., using `data_dir = "./data"` and `physicell_dir = "./PhysiCell"`.
If a single argument is provided, it will use that as the base directory and append `data` and `PhysiCell` to it, i.e., `data_dir = "\$(path_to_project)/data"` and `physicell_dir = "\$(path_to_project)/PhysiCell"`.
If two arguments are provided, they will be used as the `data_dir` and `physicell_dir`, respectively.

The `reinit_policy` keyword argument can be used to specify how the Model Manager should handle reinitialization if the paths differ from the previously initialized paths.
See [`ReinitPolicy`](@ref) for more options.
String or Symbol values can be used for `reinit_policy`.

# Examples
```julia
using ModelManagerStudio
launch()  # Launches with default paths in the current directory, i.e., `data_dir = "./data"` and `physicell_dir = "./PhysiCell"`
launch("path/to/project")  # Launches with specified project path (will ask if paths differ)
launch("path/to/data", "path/to/PhysiCell"; reinit_policy=:update)  # Launches with specified data and PhysiCell directories, updating if paths differ
launch("path/to/data", "path/to/PhysiCell"; reinit_policy="keep")  # Launches with specified directories, keeping previous paths if they differ
launch(; reinit_policy=ModelManagerStudio.ask)  # Launches with default paths, asking the user to confirm reinitialization if paths differ
```
"""
function launch(args...; kwargs...)
    # Run the application
    e = init_model_manager_gui(args...; kwargs...)
    println("Launching Model Manager Studio...")
    exec()
end

"""
    ReinitPolicy

An enum to specify the reinitialization policy for the Model Manager.

Uses the following values:
- `ask`: Prompt the user to confirm reinitialization if paths differ.
- `update`: Automatically reinitialize the Model Manager with new paths if they differ.
- `keep`: Keep the existing paths and do not reinitialize.
"""
@enum ReinitPolicy ask update keep

"""
    studio_initialize_model_manager(args::Vararg{AbstractString}; reinit_policy=ask)

Internal function to initialize the Model Manager with the specified arguments.
Called by [`init_model_manager_gui`](@ref).
"""
function studio_initialize_model_manager(args::Vararg{AbstractString}; reinit_policy=ask)
    data_dir, physicell_dir = get_pcmm_paths(args...)
    reinit_policy = reinit_policy isa ReinitPolicy ? reinit_policy : parse_reinit_policy(reinit_policy)
    if reinit_policy == update || !PhysiCellModelManager.pcmm_globals.initialized
        initializeModelManager(physicell_dir, data_dir)
    elseif reinit_policy != keep && length(args) == 0 && (PhysiCellModelManager.dataDir() != data_dir || PhysiCellModelManager.physicellDir() != physicell_dir)
        msg = """
        WARNING: Model Manager was previously initialized with the following paths:
            Data Directory: $(PhysiCellModelManager.dataDir())
            PhysiCell Directory: $(PhysiCellModelManager.physicellDir())

        You have since changed directories and are now trying to initialize with:
            Data Directory: $data_dir
            PhysiCell Directory: $physicell_dir

        Do you want to reinitialize with these new paths? (y/n)
        """
        print(msg)
        if lowercase(readline()) == "y"
            println("Reinitializing Model Manager with new paths...")
            initializeModelManager(physicell_dir, data_dir)
        else
            println("Keeping previous paths and not reinitializing Model Manager.")
        end
        println("To avoid this prompt in the future, you can use the `reinit_policy` keyword argument to specify `:ask`, `:update`, or `:keep`.")
    end

    return PhysiCellModelManager.pcmm_globals.initialized
end

"""
    parse_reinit_policy(policy::Symbol)
    parse_reinit_policy(policy::AbstractString)

Parse the reinitialization policy from a Symbol or String to a [`ReinitPolicy`](@ref) enum.
"""
function parse_reinit_policy(policy::Symbol)
    if policy == :ask
        return ask
    elseif policy == :update
        return update
    elseif policy == :keep
        return keep
    else
        throw(ArgumentError("Invalid reinit_policy: $policy. Must be one of :ask, :update, or :keep."))
    end
end

parse_reinit_policy(policy::AbstractString) = parse_reinit_policy(Symbol(policy))

"""
    get_pcmm_paths(args::Vararg{AbstractString})

Get the PhysiCell and data directories from the provided arguments.
See [`launch`](@ref) for details on how the arguments are interpreted.
"""
function get_pcmm_paths(args::Vararg{AbstractString})
    @assert length(args) <= 2 "Expected at most 2 arguments, got $(length(args))"
    if length(args) == 0
        data_dir = "data"
        physicell_dir = "PhysiCell"
    elseif length(args) == 1
        data_dir = joinpath(args[1], "data")
        physicell_dir = joinpath(args[1], "PhysiCell")
    else
        data_dir, physicell_dir = args
    end
    return abspath(data_dir), abspath(physicell_dir)
end

function get_folders(location::AbstractString, required::Bool)
    out = required ? String[] : String["--NONE--"]
    append!(out, location |> Symbol |> PhysiCellModelManager.locationPath |> readdir)
    return out
end

function set_input_folders()
    global current_required_locations, current_optional_locations, inputs

    kwargs = Dict{Symbol, String}()
    for loc in current_required_locations ∪ current_optional_locations
        kwargs[Symbol(loc.location)] = loc.folder == "--NONE--" ? "" : loc.folder
    end

    inputs = InputFolders(; kwargs...)

    model_manager_studio_info("Input folders set")
    display(inputs)

    record_inputs()
end

function get_input_folder(location::AbstractString)
    global inputs
    if !isdefined(ModelManagerStudio, :inputs)
        return "inputs not set"
    end
    out = inputs[Symbol(location)].folder
    return isempty(out) ? "--NONE--" : out
end

function get_substrate_names()
    global inputs
    path_to_xml = PhysiCellModelManager.prepareBaseFile(inputs[:config])
    xml_doc = parse_file(path_to_xml)
    microenvironment_element = PhysiCellModelManager.retrieveElement(xml_doc, ["microenvironment_setup"])
    substrate_names = String[]
    for ce in get_elements_by_tagname(microenvironment_element, "variable")
        push!(substrate_names, attribute(ce, "name"))
    end
    return substrate_names
end

function get_cell_type_names()
    global inputs
    path_to_xml = PhysiCellModelManager.prepareBaseFile(inputs[:config])
    xml_doc = parse_file(path_to_xml)
    cell_types_element = PhysiCellModelManager.retrieveElement(xml_doc, ["cell_definitions"])
    cell_type_names = String[]
    for ce in get_elements_by_tagname(cell_types_element, "cell_definition")
        push!(cell_type_names, attribute(ce, "name"))
    end
    return cell_type_names
end

function get_custom_tags()
    global inputs
    path_to_xml = PhysiCellModelManager.prepareBaseFile(inputs[:config])
    xml_doc = parse_file(path_to_xml)
    return [name(ce) for ce in (PhysiCellModelManager.retrieveElement(xml_doc, ["cell_definitions", "cell_definition", "custom_data"]) |> child_elements)]
end

function get_user_parameter_names()
    global inputs
    path_to_xml = PhysiCellModelManager.prepareBaseFile(inputs[:config])
    xml_doc = parse_file(path_to_xml)
    user_parameters_element = PhysiCellModelManager.retrieveElement(xml_doc, ["user_parameters"])
    return [name(ce) for ce in child_elements(user_parameters_element)]
end

function get_cycle_model_phase_tag(cell_type::AbstractString)
    global inputs
    path_to_xml = PhysiCellModelManager.prepareBaseFile(inputs[:config])
    xml_doc = parse_file(path_to_xml)
    cycle_model_element = PhysiCellModelManager.retrieveElement(xml_doc, PhysiCellModelManager.cyclePath(cell_type))
    is_rate = find_element(cycle_model_element, "phase_durations") |> isnothing
    return is_rate ? "rate" : "duration"
end

function get_cycle_model_phase_indexes(cell_type::AbstractString, cycle_model_phase_tag::AbstractString)
    global inputs
    path_to_xml = PhysiCellModelManager.prepareBaseFile(inputs[:config])
    xml_doc = parse_file(path_to_xml)
    if cycle_model_phase_tag == "rate"
        tag = "phase_transition_rates"
        attr_name = "start_index"
    else
        tag = "phase_durations"
        attr_name = "index"
    end
    cycle_model_element = PhysiCellModelManager.retrieveElement(xml_doc, PhysiCellModelManager.cyclePath(cell_type, tag))
    return [attribute(ce, attr_name) for ce in child_elements(cycle_model_element)]
end

function get_death_model_phase_tag(cell_type::AbstractString, death_model::Symbol)
    global inputs
    path_to_xml = PhysiCellModelManager.prepareBaseFile(inputs[:config])
    xml_doc = parse_file(path_to_xml)
    death_model_element = PhysiCellModelManager.retrieveElement(xml_doc, PhysiCellModelManager.deathPath(cell_type, "model:name:$(death_model)"))
    is_rate = find_element(death_model_element, "phase_durations") |> isnothing
    base_name = is_rate ? "transition_rate" : "duration"
    if death_model == :apoptosis
        return base_name
    elseif death_model == :necrosis
        return ["$(base_name)_$(i)" for i in 0:1]
    end
end

function get_initial_parameter_distribution_behaviors(cell_type::AbstractString)
    global inputs
    path_to_xml = PhysiCellModelManager.prepareBaseFile(inputs[:config])
    xml_doc = parse_file(path_to_xml)
    initial_parameter_distribution_element = PhysiCellModelManager.retrieveElement(xml_doc, PhysiCellModelManager.cellDefinitionPath(cell_type, "initial_parameter_distributions"))
    behaviors = String[]
    for ce in get_elements_by_tagname(initial_parameter_distribution_element, "distribution")
        ce_child = find_element(ce, "behavior")
        push!(behaviors, content(ce_child))
    end
    return behaviors
end

function get_initial_parameter_distribution_behavior_tags(cell_type::AbstractString, behavior::AbstractString)
    global inputs
    path_to_xml = PhysiCellModelManager.prepareBaseFile(inputs[:config])
    xml_doc = parse_file(path_to_xml)
    initial_parameter_distribution_element = PhysiCellModelManager.retrieveElement(xml_doc, PhysiCellModelManager.cellDefinitionPath(cell_type, "initial_parameter_distributions", "distribution::behavior:$(behavior)"))
    return [n for n in (initial_parameter_distribution_element |> child_elements .|> name) if n != "behavior"]
end

function config_single_tokens()
    return [
        get_cell_type_names();
        get_substrate_names();
        "x_min"; "x_max"; "y_min"; "y_max"; "z_min"; "z_max"; "dx"; "dy"; "dz"; "use_2D";
        "max_time"; "dt_intracellular"; "dt_diffusion"; "dt_mechanics"; "dt_phenotype";
        "full_data_save_interval"; "svg_data_save_interval";
        "user_parameter"
    ]
end

function config_second_tokens(first_token::AbstractString)
    if isempty(first_token)
        return String[]
    elseif first_token == "user_parameter"
        return get_user_parameter_names()
    elseif first_token ∈ get_substrate_names()
        return [
            "diffusion_coefficient"; "decay_rate";
            "initial_condition"; "universal_dirichlet_boundary_condition";
            "individual_dirichlet_boundary_condition"
        ]
    elseif first_token ∈ get_cell_type_names()
        return [
            get_substrate_names();
            "cycle"; "apoptosis"; "necrosis"; "adhesion"; "motility"; "chemotaxis"; "advanced_chemotaxis"; "phagocytosis"; "fusion"; "transformation"; "attack_rate";
            "total"; "fluid_fraction"; "nuclear"; "fluid_change_rate"; "cytoplasmic_biomass_change_rate"; "nuclear_biomass_change_rate"; "calcified_fraction"; "calcification_rate"; "relative_rupture_volume";
            "set_relative_equilibrium_distance"; "set_absolute_equilibrium_distance";
            "speed"; "persistence_time"; "migration_bias";
            "apoptotic_phagocytosis_rate"; "necrotic_phagocytosis_rate"; "other_dead_phagocytosis_rate"; "attack_damage_rate"; "attack_duration";
            "damage_rate"; "damage_repair_rate";
            ["custom:$(tag)" for tag in get_custom_tags()];
            "initial_parameter_distribution"
        ]
    else
        return String[]
    end
end

function config_third_tokens(first_token::AbstractString, second_token::AbstractString)
    if second_token == "individual_dirichlet_boundary_condition"
        return ["xmin"; "xmax"; "ymin"; "ymax"; "zmin"; "zmax"]
    elseif second_token ∈ ["apoptosis", "necrosis"]
        return ["death_rate"; "unlysed_fluid_change_rate"; "lysed_fluid_change_rate"; "cytoplasmic_biomass_change_rate"; "nuclear_biomass_change_rate"; "calcification_rate"; "relative_rupture_volume";
            get_death_model_phase_tag(first_token, Symbol(second_token))]
    elseif second_token ∈ ["adhesion", "phagocytosis", "fusion", "transformation", "attack_rate"]
        return get_cell_type_names()
    elseif second_token == "motility"
        return ["speed"; "persistence_time"; "migration_bias"; "enabled"; "use_2D"]
    elseif second_token == "chemotaxis"
        return ["enabled"; "substrate"; "direction"]
    elseif second_token == "advanced_chemotaxis"
        return [get_substrate_names(); "enabled"; "normalize_each_gradient"]
    elseif second_token ∈ get_substrate_names()
        return ["secretion_rate"; "secretion_target"; "uptake_rate"; "net_export_rate"]
    elseif second_token == "custom"
        return get_custom_tags()
    elseif second_token == "cycle"
        return [get_cycle_model_phase_tag(first_token)]
    elseif second_token == "initial_parameter_distribution"
        return get_initial_parameter_distribution_behaviors(first_token)
    else
        return String[]
    end
end

function config_fourth_tokens(first_token::AbstractString, second_token::AbstractString, third_token::AbstractString)
    if second_token == "cycle"
        return get_cycle_model_phase_indexes(first_token, third_token)
    elseif second_token == "initial_parameter_distribution"
        return get_initial_parameter_distribution_behavior_tags(first_token, third_token)
    else
        return String[]
    end
end

function get_next_model(tokens::Vararg{AbstractString})
    tokens = [String.(tokens)...]
    location = popfirst!(tokens)
    return get_tokens(String(location), tokens)
end

function get_tokens(location::AbstractString, previous_tokens::Vector{String})
    global inputs
    if !isdefined(ModelManagerStudio, :inputs)
        return String[]
    end
    n_tokens = length(previous_tokens)
    if location == "config"
        if n_tokens == 0
            return config_single_tokens()
        elseif n_tokens == 1
            return config_second_tokens(previous_tokens[1])
        elseif n_tokens == 2
            return config_third_tokens(previous_tokens[1], previous_tokens[2])
        else
            return config_fourth_tokens(previous_tokens[1], previous_tokens[2], previous_tokens[3])
        end
    elseif location == "rulesets_collection"
        if n_tokens == 0
            return get_cell_type_names()
        elseif n_tokens == 1
            return get_ruled_behaviors(previous_tokens[1])
        else
            return get_next_rule_tags(previous_tokens...)
        end
    elseif location == "ic_cell"
        if n_tokens == 0
            return get_cell_type_names()
        elseif n_tokens == 1
            return get_patch_types(previous_tokens[1])
        else
            return get_next_ic_cell_tags(previous_tokens...)
        end
    end
end

function get_ruled_behaviors(cell_type::AbstractString)
    global inputs
    path_to_xml = PhysiCellModelManager.prepareBaseFile(inputs[:rulesets_collection])
    xml_doc = parse_file(path_to_xml)
    rules_element = PhysiCellModelManager.retrieveElement(xml_doc, ["behavior_ruleset:name:$(cell_type)"])
    return [attribute(ce, "name") for ce in get_elements_by_tagname(rules_element, "behavior")]
end

function get_next_rule_tags(tokens::Vararg{AbstractString})
    global inputs
    path_to_xml = PhysiCellModelManager.prepareBaseFile(inputs[:rulesets_collection])
    xml_doc = parse_file(path_to_xml)
    rules_element = PhysiCellModelManager.retrieveElement(xml_doc, ["behavior_ruleset:name:$(tokens[1])"; "behavior:name:$(tokens[2])"; tokens[3:end]...])
    return get_next_xml_path_elements(rules_element, ["name"])
end

function get_patch_types(cell_type::AbstractString)
    global inputs
    path_to_xml = PhysiCellModelManager.prepareBaseFile(inputs[:ic_cell])
    xml_doc = parse_file(path_to_xml)
    ic_element = PhysiCellModelManager.retrieveElement(xml_doc, ["cell_patches:name:$(cell_type)"])
    return [attribute(ce, "type") for ce in get_elements_by_tagname(ic_element, "patch_collection")]
end

function get_next_ic_cell_tags(tokens::Vararg{AbstractString})
    global inputs
    path_to_xml = PhysiCellModelManager.prepareBaseFile(inputs[:ic_cell])
    xml_doc = parse_file(path_to_xml)
    ic_element = PhysiCellModelManager.retrieveElement(xml_doc, ["cell_patches:name:$(tokens[1])"; "patch_collection:type:$(tokens[2])"; String.(tokens[3:end])...])
    return get_next_xml_path_elements(ic_element, ["type", "ID"])
end

function get_next_xml_path_elements(e::XMLElement, id_attributes::Vector{String})
    child_elements_ = child_elements(e)
    temp_dict = Dict()
    for ce in child_elements_
        tag = name(ce)
        if tag ∉ keys(temp_dict)
            temp_dict[tag] = []
        end
        push!(temp_dict[tag], ce)
    end
    out = String[]
    for (tag, ces) in temp_dict
        if length(ces) == 1
            unique_attrs = [a for a in id_attributes if has_attribute(ces[1], a)]
            next_val = isempty(unique_attrs) ? tag : "$(tag):$(unique_attrs[1]):$(attribute(ces[1], unique_attrs[1]))"
            push!(out, next_val)
            continue
        end
        unique_attribute = ""
        for a in attributes_dict(ces[1]) |> keys
            if [has_attribute(ce, a) for ce in ces] |> !all
                continue #! skip if not all elements have the attribute
            end
            n_elements = length(ces)
            n_unique_values = [attribute(ce, a) for ce in ces] |> unique |> length
            if n_elements == n_unique_values
                unique_attribute = a
                break
            end
        end
        if unique_attribute == ""
            push!(out, "$(tag) (ambiguous)")
        else
            append!(out, ["$(tag):$(attribute(ce, unique_attribute))" for ce in ces])
        end
    end
    return out
end

function get_varied_locations()
    global inputs
    if !isdefined(ModelManagerStudio, :inputs)
        return String[]
    end
    return [f.location for f in values(inputs.input_folders) if f.varied] .|> String
end

function get_target_path(location::AbstractString, tokens::Vararg{AbstractString})
    if location == "config"
        return get_config_path(tokens...)
    elseif location == "rulesets_collection"
        return rulePath(tokens...) |> PhysiCellModelManager.columnName
    elseif location == "ic_cell"
        tokens = [String.(tokens)...]
        tokens[3] = split(tokens[3], ":")[end] # just get the ID part since icCellsPath just needs the ID (this gui is showing the ID to help make it make sense for the user)
        if length(tokens) > 4
            @assert tokens[4] == "carveout_patches" "Expected 'carveout_patches' as the fourth token for ic_cell location"
            tokens[5] = split(tokens[5], ":")[end] # just get the carveout patch type
            tokens[6] = split(tokens[6], ":")[end] # just get the carveout patch ID
            popat!(tokens, 4) # remove 'carveout_patches' token since icCellsPath doesn't need it
        end
        return icCellsPath(String.(tokens)...) |> PhysiCellModelManager.columnName
    elseif location == "ic_ecm"
        return icECMPath(tokens...) |> PhysiCellModelManager.columnName
    else
        return [t for t in String.(tokens) if !isempty(t)] |> PhysiCellModelManager.columnName
    end
end

function get_config_path(tokens::Vararg{AbstractString})
    tokens = [tokens...]
    if length(tokens) > 1
        if tokens[2] == "universal_dirichlet_boundary_condition"
            tokens[2] = "Dirichlet_boundary_condition"
        elseif tokens[2] == "individual_dirichlet_boundary_condition"
            tokens[2] = "Dirichlet_options"
        end
    end
    s = "INVALID PATH"
    try
        s = configPath([t for t in String.(tokens) if !isempty(t)]...) |> PhysiCellModelManager.columnName
    catch e
        model_manager_studio_warn("Invalid configuration path:\n\t$(join(tokens, " > "))")
        model_manager_studio_debug("Error details: $(e.msg)")
    end
    return s
end

function create_variation(target::AbstractString, vals::AbstractString, tokens::Vararg{AbstractString})
    global tokens_avs
    tokens = [t for t in String.(tokens) if !isempty(t)]
    target = target |> String |> PhysiCellModelManager.columnNameToXMLPath
    try
        vals = vals |> Meta.parse |> eval
    catch e
        msg = """
        Error parsing values for variation:
          vals: $vals
          error: $(e)
        """
        model_manager_studio_error(msg)
        return
    end
    if vals isa AbstractVector
        vals = collect(vals)
    end
    ind = find_variation_index(target)
    if isnothing(ind)
        push!(tokens_avs, (tokens, ElementaryVariation(target, vals)))
    else
        tokens_avs[ind] = (tokens, ElementaryVariation(target, vals))
    end
    record_variations()
end

function get_current_variations()
    global tokens_avs
    return [["$(join(tokens, " "))", "$(join(value_string(av), " "))"] for (tokens, av) in tokens_avs]
end

function variation_exists(target::AbstractString)
    target = target |> String |> PhysiCellModelManager.columnNameToXMLPath
    return find_variation_index(target) |> !isnothing
end

function find_variation_index(target::Vector{<:AbstractString})
    global tokens_avs
    return findfirst(tokens_av -> PhysiCellModelManager.variationTarget(tokens_av[2]).xml_path == target, tokens_avs)
end

function run_simulation()
    global inputs, tokens_avs

    record_run()
    
    # Run the simulation with the provided inputs
    run(inputs, [av for (_, av) in tokens_avs])

    # Emit signal when simulation is complete
    @emit simulationFinished()
end

model_manager_studio_info(message::AbstractString; kws...) = model_manager_studio_log(:info, message; kws...)
model_manager_studio_warn(message::AbstractString; kws...) = model_manager_studio_log(:warn, message; kws...)
model_manager_studio_error(message::AbstractString; kws...) = model_manager_studio_log(:error, message; kws...)
model_manager_studio_debug(message::AbstractString; kws...) = model_manager_studio_log(:debug, message; kws...)

function model_manager_studio_log(type::Symbol, message::AbstractString; kws...)
    @assert type ∈ [:info, :warn, :error, :debug] "Log type must be either :info, :warn, :error, or :debug, got $type"
    header = "---ModelManagerStudio.jl---"
    if type == :info
        @info header kws...
    elseif type == :warn
        @warn header kws...
    elseif type == :error
        @error header kws...
    elseif type == :debug
        @debug header kws...
    end
    println(message)
end

function create_project_configuration_properties()
    pl = PhysiCellModelManager.projectLocations()
    req_locs = [pl.required...]
    opt_locs = setdiff(pl.all, req_locs)

    n_req = length(req_locs)
    n_opt = length(opt_locs)

    max_per_row = 4
    req_n_rows = ceil(n_req / max_per_row) |> Int
    req_n_cols = min(max_per_row, n_req)
    opt_n_rows = ceil(n_opt / max_per_row) |> Int
    opt_n_cols = min(max_per_row, n_opt)
    return JuliaPropertyMap("req_n_rows" => req_n_rows, "req_n_cols" => req_n_cols, "opt_n_rows" => opt_n_rows, "opt_n_cols" => opt_n_cols,
        "req_locations" => String.(req_locs), "opt_locations" => String.(opt_locs))
end

function location_label(location::AbstractString)
    out = replace(location, "_" => " ", "ecm" => "ECM", "dc" => "DC")
    # be careful to only replace "ic" at the start of the string when it indicates the initial conditions
    if startswith(out, "ic ")
        out = "IC $(out[4:end])"
    end
    return uppercasefirst(out) * " folder"
end

is_varied_location(location::AbstractString) = Symbol(location) ∈ PhysiCellModelManager.projectLocations().varied

function is_varied_location(location::AbstractString, folder::AbstractString)
    folder = String(folder)
    if isempty(folder) || folder == "--NONE--"
        return false
    end
    input_folder = PhysiCellModelManager.InputFolder(Symbol(location), folder)
    return input_folder.varied
end

mutable struct MMSFolder
    location::String
    labelText::String
    folder::String
end

function required_input_folders()
    global current_required_locations
    pl = PhysiCellModelManager.projectLocations()
    current_required_locations = MMSFolder[]
    for loc in pl.required
        loc_str = String(loc)
        loc_folder = MMSFolder(loc_str, location_label(loc_str), "")
        push!(current_required_locations, loc_folder)
    end
    req_location_model = JuliaItemModel(current_required_locations)
    return req_location_model
end

function optional_input_folders()
    global current_optional_locations
    pl = PhysiCellModelManager.projectLocations()
    current_optional_locations = MMSFolder[]
    for loc in setdiff(pl.all, pl.required)
        loc_str = String(loc)
        loc_folder = MMSFolder(loc_str, location_label(loc_str), "")
        push!(current_optional_locations, loc_folder)
    end
    opt_location_model = JuliaItemModel(current_optional_locations)
    return opt_location_model
end

end