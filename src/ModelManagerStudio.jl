module ModelManagerStudio

# Write your package code here.
using QML, LightXML, Compat, Distributions
import InteractiveUtils

#! ModelManager is the only model-management dependency. A simulator backend
#! (PhysiCellModelManager, BergiCellModelManager, ...) is a `[weakdeps]` entry reached through
#! a package extension, so Studio builds and loads without any particular simulator.
#!
#! Names MM exports but does not re-export cleanly are reached as `MM.` deliberately:
#! `variationTarget` and `variationValues` are NOT exported by MM, so going through a
#! re-exporting backend was an UndefVarError that only showed at runtime.
import ModelManager as MM
#! Also brought in unqualified, because Studio constructs MM's exported types directly
#! (`InputFolders`, `ElementaryVariation`, `DiscreteVariation`, `DistributedVariation`) and
#! calls its exported `run`. These used to arrive via the backend's re-export of MM, which is
#! exactly the coupling this extension split removes.
using ModelManager

#! Imported by the backend extensions, which add methods to these.
@compat public studio_open_project, studio_transcript_preamble, studio_no_project_message,
               studio_token_color, studio_project_is_open, token_name

#! `launch` is the package's entire purpose, so it is exported. The previous arrangement was
#! backwards: `main` (which a user never calls interactively) was exported while `launch`
#! (which is the documented entry point, and what README and the tests use) was only
#! `@compat public`, so `using ModelManagerStudio; launch()` -- the documented invocation --
#! raised UndefVarError. Verified no `launch` export collides across PhysiCellModelManager,
#! ModelManager, QML, Distributions or LightXML.
export launch, main

include("backend.jl")
include("colors.jl")
include("base_documents.jl")
include("value_parser.jl")
include("record.jl")
#! Unconditional: main.jl itself chooses between the `@main` entrypoint (1.11+) and a plain
#! exported `main` function, so the LTS this package claims compat with is not left with an
#! exported name that does not exist.
include("main.jl")

global current_required_locations
global current_optional_locations
global inputs
global tokens_avs = Tuple[]

#! What an optional location's dropdown shows when no folder is chosen. Defined once and
#! handed to QML in `create_project_configuration_properties`, because it was a magic string
#! duplicated on both sides of the Julia/QML boundary -- exactly the kind of literal that
#! drifts when one side changes.
const NO_FOLDER_SENTINEL = "--NONE--"


"""
    launch()
    launch(path_to_project::AbstractString)
    launch(physicell_dir::AbstractString, data_dir::AbstractString)

Launch the Model Manager Studio GUI for a particular project.

If no arguments are provided, it will initialize the Model Manager within the current working directory, i.e., using `data_dir = "./data"` and `physicell_dir = "./PhysiCell"`.
If a single argument is provided, it will use that as the base directory and append `data` and `PhysiCell` to it, i.e., `data_dir = "\$(path_to_project)/data"` and `physicell_dir = "\$(path_to_project)/PhysiCell"`.
If two arguments are provided, they will be used as the `physicell_dir` and `data_dir`, respectively.

# Examples
```julia
using ModelManagerStudio
launch()  # Launches with default paths in the current directory, i.e., `data_dir = "./data"` and `physicell_dir = "./PhysiCell"`
launch("path/to/project")  # Launches with specified project path (will ask if paths differ)
launch("path/to/PhysiCell", "path/to/data")  # Launches with specified PhysiCell and data directories
```
"""
function launch(args...; kwargs...)
    # Run the application
    _ = init_model_manager_gui(args...; kwargs...)
    exec()
end

"""
    init_model_manager_gui(args::Vararg{AbstractString}; kwargs...)

Internal function to initialize the Model Manager GUI with the specified arguments.
Called by [`launch`](@ref).
"""
function init_model_manager_gui(args::Vararg{AbstractString}; kwargs...)
    if !studio_initialize_model_manager(args...; kwargs...)
        throw("Error initializing Model Manager. Please make sure you are in the correct directory.")
    end

    initialize_record()

    #! Every name here must exist; `@qmlfunction` on a deleted one is an UndefVarError at
    #! launch, from inside the macro, which is how the removed vocabulary helpers showed up.
    @qmlfunction get_folders set_input_folders get_input_folder get_varied_locations
    @qmlfunction get_next_model get_token_kinds get_token_colors get_target_path is_resolvable_target
    @qmlfunction create_variation get_current_variations variation_exists
    @qmlfunction delete_variation clear_variations
    @qmlfunction value_spec_error variation_blocker allowed_distribution_names
    @qmlfunction run_simulation location_label is_varied_location

    # absolute path in case working dir is overridden
    qml_file = joinpath(@__DIR__, "..", "assets", "ModelManagerStudio.qml")

    #! Pin the Qt Quick Controls style. On macOS the "NativeStyle" plugin shipped with the
    #! Qt6 build in jlqml_jll segfaults while drawing a ComboBox
    #! (objc_msgSend -> QMacStylePrivate::drawNSViewInRect -> QMacStyle::drawComplexControl).
    #! Note QT_QPA_PLATFORM=offscreen does NOT avoid this: the platform plugin and the
    #! controls style are chosen independently. "Basic" is also the only style that honors
    #! the custom `background` Rectangles this GUI defines, so the look is unchanged.
    #! Respect an explicit user choice.
    get!(ENV, "QT_QUICK_CONTROLS_STYLE", "Basic")

    # See if in testing mode
    testing = get(ENV, "MODEL_MANAGER_STUDIO_TESTING", "false") == "true"

    # Load the QML file
    return loadqml(qml_file; reqLocModel=required_input_folders(), optLocModel=optional_input_folders(), guiproperties=color_scheme(), project_configuration_properties=create_project_configuration_properties(), testing=JuliaPropertyMap("testing" => testing))
end

"""
    studio_initialize_model_manager(args::Vararg{AbstractString})

Internal function to initialize the Model Manager with the specified arguments.
Called by [`init_model_manager_gui`](@ref).
"""
function studio_initialize_model_manager(args::Vararg{AbstractString})
    sim = studio_backend()
    if isnothing(sim)
        model_manager_studio_error(studio_no_backend_message())
        return false
    end

    #! With no arguments, adopt whatever project is already open rather than re-deriving paths
    #! from the working directory. The backend package attempts initialization in its own
    #! `__init__`, and the user may have called `initializeModelManager` explicitly before
    #! launching; re-deriving would point Studio at a different project, or fail from a
    #! directory that is perfectly valid to launch from. Explicit arguments always win.
    if isempty(args) && studio_project_is_open()
        model_manager_studio_info("Using the already-open project at $(MM.dataDir()).")
        return true
    end

    return studio_open_project(sim, args...)
end



function get_folders(location::AbstractString, required::Bool)
    out = required ? String[] : String[NO_FOLDER_SENTINEL]
    location_directory = location |> Symbol |> MM.locationPath
    folders = readdir(location_directory; join=true)
    filter!(isdir, folders)
    append!(out, basename.(folders))
    return out
end

function set_input_folders()
    global current_required_locations, current_optional_locations, inputs

    kwargs = Dict{Symbol, String}()
    for loc in current_required_locations ∪ current_optional_locations
        kwargs[Symbol(loc.location)] = loc.folder == NO_FOLDER_SENTINEL ? "" : loc.folder
    end

    inputs = InputFolders(; kwargs...)

    #! Documents cached against the previous selection are now stale.
    invalidate_base_documents!()

    model_manager_studio_info(string(inputs))

    record_inputs()
end

function get_input_folder(location::AbstractString)
    global inputs
    if !isdefined(ModelManagerStudio, :inputs)
        return "inputs not set"
    end
    out = inputs[Symbol(location)].folder
    return isempty(out) ? NO_FOLDER_SENTINEL : out
end














"""
    get_next_model(tokens::Vararg{AbstractString})

Child tokens for the chain `tokens` (first entry is the location). Called from QML.
"""
function get_next_model(tokens::Vararg{AbstractString})
    toks = [String.(tokens)...]
    location = popfirst!(toks)
    return get_tokens(String(location), toks)
end

#! Attributes used to tell same-tag siblings apart, in priority order. Mirrors the priority in
#! ModelManager's own `recurseToGetParameterValues!` ("name", "ID", "id"), so a browser token
#! matches the column name MM gives the same parameter, plus "type" for the IC files.
const ID_ATTRIBUTES = ["name", "ID", "id", "type"]

"""
    get_tokens(location, previous_tokens)

Child tokens of the element at `previous_tokens` in `location`'s base document; `String[]` at a
leaf, or when the document is unavailable.

A plain walk of the XML. Tokens ARE path elements, so a chain is an `XMLPath` and the target is
`columnName` of it — there is no translation table to keep in step with the simulator's own
path builders, and no vocabulary that can disagree with them.

Termination is structural: a finite document, one token per level, nothing below a leaf.
"""
function get_tokens(location::AbstractString, previous_tokens::Vector{String})
    element = _element_at(location, previous_tokens)
    isnothing(element) && return String[]
    return get_next_xml_path_elements(element, ID_ATTRIBUTES)
end

"""
    _element_at(location, chain)

The element `chain` names in `location`'s base document, or `nothing`. Never throws: an
unselected folder, a location this project lacks, and a path that is not in the document all
come back as `nothing`, because every caller is reached from a QML callback.
"""
function _element_at(location::AbstractString, chain::Vector{String})
    doc = base_document(Symbol(location))
    isnothing(doc) && return nothing
    path = [t for t in chain if !isempty(t)]
    #! `retrieveElement` starts at the root, so an empty chain needs no special case.
    return try
        MM.retrieveElement(doc, path; required=false)
    catch
        nothing
    end
end

"""
    token_name(token)

The *name* an attribute-disambiguated token carries, or `""` for a plain structural tag.

`"cell_definition:name:tumor"` yields `"tumor"`. Provided for backends writing a
[`studio_token_color`](@ref) method: deciding that a token names one of the model's cell
definitions means comparing that name against the ones the model declares.

Split with `limit=3` to match `retrieveElement`, so a name containing a colon survives intact.
"""
function token_name(token::AbstractString)
    parts = split(String(token), ':'; limit=3)
    return length(parts) == 3 ? String(parts[3]) : ""
end

#! A colour the browser can actually draw. Anything else from a backend is dropped rather than
#! handed to QML, where an unparseable `color:` is a binding warning and an invisible token.
const HEX_COLOR = r"^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"

"""
    get_token_colors(tokens::Vararg{AbstractString})

Hex colour per entry, parallel to [`get_next_model`](@ref); `""` where the backend gave none, in
which case the GUI uses its own default. Called from QML.

The colour is the backend's statement that an entry belongs to a category of its model -- a cell
definition, a substrate -- so that the category reads the same everywhere it appears.
"""
function get_token_colors(tokens::Vararg{AbstractString})
    toks = [String.(tokens)...]
    location = popfirst!(toks)
    candidates = get_next_model(String(location), toks...)
    sim = studio_backend()
    isnothing(sim) && return fill("", length(candidates))
    chain = [t for t in toks if !isempty(t)]
    return [token_color(sim, Symbol(location), chain, t) for t in candidates]
end

"""
    token_color(sim, location, chain, token)

[`studio_token_color`](@ref) reduced to a hex string or `""`.

Never throws and never returns something QML cannot draw: this is reached from a property
binding, where a backend's bad return value would otherwise surface as a Qt warning on a token
the user is looking at.
"""
function token_color(sim, location::Symbol, chain::Vector{String}, token::AbstractString)
    raw = try
        studio_token_color(sim, location, chain, token)
    catch e
        model_manager_studio_debug("studio_token_color failed for $(token): $(sprint(showerror, e))")
        return ""
    end
    (isnothing(raw) || ismissing(raw)) && return ""
    raw isa AbstractString || return ""
    hex = String(raw)
    if !occursin(HEX_COLOR, hex)
        model_manager_studio_debug("studio_token_color returned $(repr(hex)) for $(token), which is not a hex colour.")
        return ""
    end
    return hex
end

"""
    get_token_kinds(tokens::Vararg{AbstractString})

`"branch"` or `"leaf"` per entry, parallel to [`get_next_model`](@ref). Called from QML to mark
which entries open another menu.
"""
function get_token_kinds(tokens::Vararg{AbstractString})
    toks = [String.(tokens)...]
    location = popfirst!(toks)
    chain = [t for t in toks if !isempty(t)]
    return map(get_next_model(String(location), toks...)) do t
        child = _element_at(String(location), [chain; t])
        (isnothing(child) || MM.elementIsTerminal(child)) ? "leaf" : "branch"
    end
end





function get_next_xml_path_elements(e::XMLElement, id_attributes::Vector{String})
    child_elements_ = child_elements(e)
    #! Group children by tag, preserving document order. An untyped `Dict` here made the
    #! ComboBox ordering vary between runs, since Dict iteration order is unspecified.
    tag_order = String[]
    grouped = Dict{String,Vector{XMLElement}}()
    for ce in child_elements_
        tag = name(ce)
        if !haskey(grouped, tag)
            push!(tag_order, tag)
            grouped[tag] = XMLElement[]
        end
        push!(grouped[tag], ce)
    end
    out = String[]
    for tag in tag_order
        ces = grouped[tag]
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
            #! Three parts, not two. `ModelManager.retrieveElement` splits a token on ":"
            #! with `limit=3` and `getChildByAttribute` destructures exactly three values,
            #! so a "tag:value" token raises a BoundsError once the path is resolved. The
            #! single-child branch above already emitted three parts; this one did not.
            append!(out, ["$(tag):$(unique_attribute):$(attribute(ce, unique_attribute))" for ce in ces])
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

#! Sentinel prefix for a target path that could not be resolved. `get_target_path` has to
#! return a String because QML can only receive primitives, so failure is encoded in the
#! string — but it is encoded in ONE place with ONE marker, and `is_resolvable_target` is the
#! only thing allowed to interpret it. Previously each failure invented its own prose
#! ("INVALID PATH", "Invalid rule path: not enough tokens"), and nothing checked for them.
const TARGET_ERROR_PREFIX = "\u26a0 "

target_error(msg::AbstractString) = TARGET_ERROR_PREFIX * msg

"""
    is_resolvable_target(target::AbstractString)

Whether `target` is a real parameter path rather than a placeholder or an error report from
[`get_target_path`](@ref). The GUI uses this to gate variation creation.
"""
function is_resolvable_target(target::AbstractString)
    t = strip(String(target))
    return !isempty(t) && !startswith(t, TARGET_ERROR_PREFIX)
end

"""
    get_target_path(location, tokens...)

The display path for the chain, or a [`target_error`](@ref) when it does not name a parameter.

The chain is already the XML path, so this is just its column name. It replaces a per-location
dispatch onto the simulator's path builders (`configPath`, `rulePath`, `icCellsPath`,
`icECMPath`) — each of which could disagree with the token vocabulary that fed it, which is
exactly how unresolvable targets arose.
"""
function get_target_path(location::AbstractString, tokens::Vararg{AbstractString})
    chain = [t for t in String.(tokens) if !isempty(t)]
    isempty(chain) && return target_error("Choose a parameter.")

    element = _element_at(location, chain)
    isnothing(element) && return target_error("Not a parameter in this model.")
    MM.elementIsTerminal(element) || return target_error("Keep going — this is not a parameter yet.")

    return MM.columnName(MM.XMLPath(chain))
end


"""
    value_spec_error(spec::AbstractString)

Return `""` if `spec` is a usable variation value, or a message explaining why it is not.
Never throws. Called from QML on every keystroke so the Create/Edit button can be disabled
with a stated reason instead of silently doing nothing when clicked.

An empty `spec` is "incomplete", not "wrong", and returns `""` — the button is already gated
on non-empty text, and showing an error before the user has typed anything is noise.
"""
function value_spec_error(spec::AbstractString)
    isempty(strip(String(spec))) && return ""
    try
        parse_value_spec(spec)
        return ""
    catch e
        e isa ValueSpecError || rethrow()
        return sprint(showerror, e)
    end
end

"""
    variation_blocker(target::AbstractString, vals::AbstractString)

Return `""` when a variation can be created from `target` and `vals`, or the reason it cannot.
The single predicate behind the button's enabled state, so the UI cannot disagree with what
[`create_variation`](@ref) will actually accept.
"""
function variation_blocker(target::AbstractString, vals::AbstractString)
    is_resolvable_target(target) || return "Finish choosing a parameter."
    isempty(strip(String(vals))) && return "Enter a value, list, range, or distribution."
    return value_spec_error(vals)
end

function create_variation(target::AbstractString, vals::AbstractString, tokens::Vararg{AbstractString})
    global tokens_avs
    tokens = [t for t in String.(tokens) if !isempty(t)]

    #! Refuse a target that is really an error message. `get_target_path` reports failure by
    #! returning strings like "INVALID PATH", which the UI renders and then hands straight
    #! back here. `columnNameToXMLPath` is just `split(s, "/")`, so those strings construct a
    #! perfectly valid-looking ElementaryVariation that is written to the transcript and fails
    #! only once the simulation runs.
    if !is_resolvable_target(target)
        msg = "Cannot create a variation: \"$(target)\" is not a parameter path. Finish choosing a parameter first."
        model_manager_studio_error(msg)
        return msg
    end

    target = target |> String |> MM.columnNameToXMLPath
    try
        vals = parse_value_spec(vals)
    catch e
        e isa ValueSpecError || rethrow()
        msg = "Could not use that value: $(sprint(showerror, e))"
        model_manager_studio_error(msg)
        return msg
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
    #! "" means success. QML shows a dialog when this comes back non-empty, so a failure is
    #! visible in the window rather than only on stderr, which a windowed app cannot show.
    return ""
end

function get_current_variations()
    global tokens_avs
    return [["$(join(tokens, " "))", "$(join(value_string(av), " "))"] for (tokens, av) in tokens_avs]
end

function variation_exists(target::AbstractString)
    is_resolvable_target(target) || return false
    target = target |> String |> MM.columnNameToXMLPath
    return find_variation_index(target) |> !isnothing
end

"""
    delete_variation(index::Int)

Remove the variation at 1-based `index` from the pending design and rewrite the transcript.
Returns `true` if a variation was removed.

Called from QML. Until this existed, `tokens_avs` could only ever grow — a mistaken variation
could be removed only by restarting the application.
"""
function delete_variation(index::Int)
    global tokens_avs
    if index < 1 || index > length(tokens_avs)
        model_manager_studio_warn("No variation at position $(index) to delete.")
        return false
    end
    deleteat!(tokens_avs, index)
    record_variations()
    return true
end

"""
    clear_variations()

Discard every pending variation and rewrite the transcript. Called from QML.
"""
function clear_variations()
    global tokens_avs
    empty!(tokens_avs)
    record_variations()
    return true
end

function find_variation_index(target::Vector{<:AbstractString})
    global tokens_avs
    return findfirst(tokens_av -> MM.variationTarget(tokens_av[2]).xml_path == target, tokens_avs)
end

"""
    run_simulation()

Run the pending campaign and always report an outcome to the GUI.

Called from QML. Still synchronous — the window is unresponsive for the duration — but a
failure can no longer strand the interface. The non-blocking version is Phase 1 work; see
[PRD.md](PRD.md), "Run and progress".
"""
function run_simulation()
    global inputs, tokens_avs

    if !isdefined(ModelManagerStudio, :inputs)
        model_manager_studio_error("Create inputs before running.")
        @emit simulationFinished()
        return
    end

    avs = [av for (_, av) in tokens_avs]

    #! `record_run` used to be called BEFORE the run, so a campaign that threw was still
    #! written to the transcript as though it had happened — the one thing the transcript is
    #! supposed to guarantee. Record only after a successful return.
    try
        run(inputs, avs)
        record_run()
    catch e
        #! Without this, `@emit simulationFinished()` never fired: the run button stayed
        #! disabled forever and the only trace was on stderr, which a windowed app has no
        #! way to show. Always emit, so the UI can recover.
        model_manager_studio_error("The run failed:\n$(sprint(showerror, e))")
    finally
        @emit simulationFinished()
    end
end

model_manager_studio_info(message::AbstractString; kws...) = model_manager_studio_log(:info, message; kws...)
model_manager_studio_warn(message::AbstractString; kws...) = model_manager_studio_log(:warn, message; kws...)
model_manager_studio_error(message::AbstractString; kws...) = model_manager_studio_log(:error, message; kws...)
model_manager_studio_debug(message::AbstractString; kws...) = model_manager_studio_log(:debug, message; kws...)

function model_manager_studio_log(type::Symbol, message::AbstractString; kws...)
    @assert type ∈ [:info, :warn, :error, :debug] "Log type must be either :info, :warn, :error, or :debug, got $type"
    msg = "<ModelManagerStudio.jl>\n$message"
    if type == :info
        @info msg kws...
    elseif type == :warn
        @warn msg kws...
    elseif type == :error
        @error msg kws...
    elseif type == :debug
        @debug msg kws...
    end
end

function create_project_configuration_properties()
    pl = MM.projectLocations()
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
        "req_locations" => String.(req_locs), "opt_locations" => String.(opt_locs),
        "no_folder_sentinel" => NO_FOLDER_SENTINEL)
end

function location_label(location::AbstractString)
    out = replace(location, "_" => " ", "ecm" => "ECM", "dc" => "DC")
    # be careful to only replace "ic" at the start of the string when it indicates the initial conditions
    if startswith(out, "ic ")
        out = "IC $(out[4:end])"
    end
    return uppercasefirst(out) * " folder"
end

is_varied_location(location::AbstractString) = Symbol(location) ∈ MM.projectLocations().varied

function is_varied_location(location::AbstractString, folder::AbstractString)
    folder = String(folder)
    if isempty(folder) || folder == NO_FOLDER_SENTINEL
        return false
    end
    input_folder = MM.InputFolder(Symbol(location), folder)
    return input_folder.varied
end

mutable struct MMSFolder
    location::String
    labelText::String
    folder::String
end

function required_input_folders()
    global current_required_locations
    pl = MM.projectLocations()
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
    pl = MM.projectLocations()
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