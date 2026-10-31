"""
    StudioPhysiCellModelManagerExt

PhysiCell support for ModelManagerStudio.

Loaded automatically when both ModelManagerStudio and PhysiCellModelManager are present. It
supplies the three things about PhysiCell that Studio's generic layer cannot know: that a
project is a `PhysiCell/` tree beside a `data/` tree, what a reproducible script must say to
reopen one, and how to point a lost user at `createProject`.

The parameter browser needs nothing here — it walks each location's base XML, which is the same
operation for any backend whose inputs are XML files.
"""
module StudioPhysiCellModelManagerExt

using ModelManagerStudio
using PhysiCellModelManager
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

end # module
