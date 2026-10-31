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

#! One colour per category of PhysiCell name, not one per name. The three categories a
#! modeller actually distinguishes while picking a parameter are cell definitions, substrates
#! and their own custom data; everything else is PhysiCell's fixed schema and reads as ordinary
#! text. Colouring each *instance* separately -- "tumor" one colour, "macrophage" another --
#! only restates the word already on the row.
const CELL_DEFINITION_COLOR = "#2060A0"
const SUBSTRATE_COLOR = "#206020"
const CUSTOM_DATA_COLOR = "#8C5A14"

"""
    studio_token_color(::PhysiCellSimulator, location, chain, token)

Colour tokens that name something in the user's model.

- a cell definition, anywhere it appears: as a definition, an adhesion affinity, a phagocytosis
  rate, a transformation rate
- a substrate, likewise: a `<variable>`, a secretion entry, a chemotactic sensitivity
- a child of `<custom_data>`, which is the modeller's own parameter rather than PhysiCell's

The first two are decided by looking the name up in the config's own declarations rather than by
listing the tags it can appear under. PhysiCell adds tags that carry cell or substrate names
(`attack_rate`, `fuse_rate`, `chemotactic_sensitivity`, ...) with every release, and a list of
them here would silently go stale; the declarations cannot. Custom data has no name to look up
-- its children are plain tags -- so it is recognised by its parent.
"""
function MMS.studio_token_color(::PhysiCellSimulator, location::Symbol,
                                chain::Vector{String}, token::AbstractString)
    if location === :config && !isempty(chain) && last(chain) == "custom_data"
        return CUSTOM_DATA_COLOR
    end

    instance = MMS.token_name(token)
    isempty(instance) && return nothing

    #! Always the config's declarations, whatever location the token came from: a cell type
    #! named in the rules file is the same cell type, and should read the same.
    cell_definitions, substrates = model_names()
    instance in cell_definitions && return CELL_DEFINITION_COLOR
    instance in substrates && return SUBSTRATE_COLOR
    return nothing
end

"""
    model_names()

The cell definition and substrate names this project declares, as a pair of sets.

Empty sets when the config is unreadable, which colours nothing rather than failing — this is
reached from a GUI property binding.

Not cached: `base_document` already holds the parsed config, so this is a walk over the two
declaration blocks (a handful of elements), run once per dropdown level rather than per row.
"""
function model_names()
    doc = MMS.base_document(:config)
    isnothing(doc) && return (Set{String}(), Set{String}())
    return (declared_names(doc, ["cell_definitions"], "cell_definition"),
            declared_names(doc, ["microenvironment_setup"], "variable"))
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
