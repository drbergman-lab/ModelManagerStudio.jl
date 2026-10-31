"""
    StudioPhysiCellModelManagerExt

PhysiCell support for ModelManagerStudio.

Loaded automatically when both ModelManagerStudio and PhysiCellModelManager are present. It
supplies the things about PhysiCell that Studio's generic layer cannot know: that a project is
a `PhysiCell/` tree beside a `data/` tree, what a reproducible script must say to reopen one,
how to point a lost user at `createProject`, and which tokens in the parameter browser name a
cell definition, a substrate, or a user-defined custom-data entry.

The browser's *walk* needs nothing here — it reads each location's base XML, the same operation
for any backend whose inputs are XML files. Only the reading of those tokens is PhysiCell's.
"""
module StudioPhysiCellModelManagerExt

using ModelManagerStudio
using PhysiCellModelManager
using LightXML
import ModelManager as MM

const MMS = ModelManagerStudio

"""
    physicell_project_paths(args...)

Resolve Studio's launch arguments to a `(physicell_dir, data_dir)` pair.

- none — `./PhysiCell` and `./data`
- one — `<arg>/PhysiCell` and `<arg>/data`
- two — used as given

Both are absolutized and normalized, so the result does not depend on the working directory
later in the session.
"""
function physicell_project_paths(args::AbstractString...)
    @assert length(args) <= 2 "Expected at most 2 arguments, got $(length(args))"
    if isempty(args)
        physicell_dir, data_dir = "PhysiCell", "data"
    elseif length(args) == 1
        physicell_dir, data_dir = joinpath(args[1], "PhysiCell"), joinpath(args[1], "data")
    else
        physicell_dir, data_dir = args
    end
    return (physicell_dir, data_dir) .|> abspath .|> normpath
end

function MMS.studio_open_project(::PhysiCellSimulator, args::AbstractString...)
    physicell_dir, data_dir = physicell_project_paths(args...)
    PhysiCellModelManager.initializeModelManager(physicell_dir, data_dir)
    return MMS.studio_project_is_open()
end

function MMS.studio_transcript_preamble(::PhysiCellSimulator)
    #! The two-argument PCMM form, because a PhysiCell project is not reopenable from the data
    #! directory alone -- the generic preamble would produce a script that does not run.
    return """
    using PhysiCellModelManager, Distributions
    initializeModelManager(\"$(PhysiCellModelManager.physicellDir())\", \"$(MM.dataDir())\")
    """
end

function MMS.studio_no_project_message(::PhysiCellSimulator)
    return """
    Studio needs an existing PhysiCell project. Either run it from a project directory, or
    pass one:

        using PhysiCellModelManager, ModelManagerStudio
        launch("path/to/project")   # expects <project>/PhysiCell and <project>/data

    To create one first:

        using PhysiCellModelManager
        createProject("path/to/project")
    """
end

#! One hue per category of name in the user's model: cell definitions, substrates, custom data.
#! Everything else is PhysiCell's own schema and draws in the GUI's default colour.
const CELL_DEFINITION_COLOR = "#2060A0"
const SUBSTRATE_COLOR = "#206020"
const CUSTOM_DATA_COLOR = "#8C5A14"

#! PhysiCell's prefix for a custom-data entry used as a signal or behavior. Registered in
#! `PhysiCell_signal_behavior.cpp` as `"custom:" + name`, with `"custom: name"` as a synonym.
const CUSTOM_DATA_PREFIX = "custom:"

"""
    studio_token_color(::PhysiCellSimulator, location, chain, token)

Colour tokens that name something in the user's model.

- a cell definition, anywhere it appears: as a definition, an adhesion affinity, a phagocytosis
  rate, a transformation rate
- a substrate, likewise: a `<variable>`, a secretion entry, a chemotactic sensitivity
- a custom-data entry: in its own `<custom_data>` block, and as a rule's signal or behavior

Names are looked up in the config's own declarations rather than against a list of the tags they
can appear under. PhysiCell adds such tags (`attack_rate`, `fuse_rate`,
`chemotactic_sensitivity`, ...) with every release; a list here would go stale without failing.
"""
function MMS.studio_token_color(::PhysiCellSimulator, ::Symbol,
                                chain::Vector{String}, token::AbstractString)
    cell_definitions, substrates, custom_data = model_names()

    instance = MMS.token_name(token)
    if !isempty(instance)
        instance in cell_definitions && return CELL_DEFINITION_COLOR
        instance in substrates && return SUBSTRATE_COLOR
        #! A rule names a custom-data entry as a signal or a behavior, prefixed:
        #! `<behavior name="custom:damage_rate">`, `<signal name="custom:PKPD_D1_damage">`.
        #! An intracellular mapping's `physicell_name` carries the same form.
        custom_data_key(instance) in custom_data && return CUSTOM_DATA_COLOR
        return nothing
    end

    #! Unprefixed, a custom-data name is not unique, so a bare tag counts only inside
    #! `<custom_data>`. `sample_projects/cancer_biorobots` declares `damage_rate` as custom data
    #! while carrying PhysiCell's own `cell_integrity/damage_rate` in the same cell definitions,
    #! and PhysiCell keeps promoting custom-data names into the schema (`damage_rate`,
    #! `attachment_rate`), so the collision class grows with each release.
    (isempty(chain) || last(chain) != "custom_data") && return nothing
    return String(token) in custom_data ? CUSTOM_DATA_COLOR : nothing
end

"""
    custom_data_key(name)

The custom-data tag behind a prefixed signal or behavior name, or `""` if it is not one.

`"custom:damage_rate"` and `"custom: damage_rate"` both yield `"damage_rate"`.
"""
function custom_data_key(name::AbstractString)
    startswith(name, CUSTOM_DATA_PREFIX) || return ""
    return String(lstrip(SubString(name, length(CUSTOM_DATA_PREFIX) + 1)))
end

"""
    model_names()

The cell definition, substrate and custom-data names this project declares, as three sets.

Empty sets when the config is unreadable, which colours nothing rather than failing — this is
reached from a GUI property binding.

Not cached: `base_document` already holds the parsed config, so this is a walk over the
declaration blocks, run once per dropdown level rather than once per row.
"""
function model_names()
    doc = MMS.base_document(:config)
    isnothing(doc) && return (Set{String}(), Set{String}(), Set{String}())
    return (declared_names(doc, ["cell_definitions"], "cell_definition"),
            declared_names(doc, ["microenvironment_setup"], "variable"),
            custom_data_names(doc))
end

"""
    custom_data_names(doc)

Every tag declared under any cell definition's `<custom_data>`, unioned.

The union is not a formality. PhysiCell inherits a definition's custom data from its parent and
appends, so a later definition can declare tags no earlier one has:
`sample_projects/physimess` gives `ecm` eighteen entries against `cell`'s eleven, seven of which
appear in no other definition.
"""
function custom_data_names(doc::XMLDocument)
    cell_definitions = try
        MM.retrieveElement(doc, ["cell_definitions"]; required=false)
    catch
        nothing
    end
    isnothing(cell_definitions) && return Set{String}()
    out = Set{String}()
    for cell_definition in child_elements(cell_definitions)
        for block in get_elements_by_tagname(cell_definition, "custom_data")
            for entry in child_elements(block)
                push!(out, LightXML.name(entry))
            end
        end
    end
    return out
end

"""
    declared_names(doc, parent_path, tag)

The `name` attributes of `parent_path`'s `tag` children in `doc`.

Filtered by tag because the parent holds more than its declarations: `<microenvironment_setup>`
also carries `<options>` and `<ecm_setup>`, which are not substrates.
"""
function declared_names(doc::XMLDocument, parent_path::Vector{String}, tag::AbstractString)
    parent = try
        MM.retrieveElement(doc, parent_path; required=false)
    catch
        nothing
    end
    isnothing(parent) && return Set{String}()
    out = Set{String}()
    for child in child_elements(parent)
        LightXML.name(child) == tag || continue
        has_attribute(child, "name") || continue
        push!(out, attribute(child, "name"))
    end
    return out
end

end # module
