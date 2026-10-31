#! The simulator-backend seam.
#!
#! Studio depends on ModelManager alone. Everything a backend does differently — how its
#! projects are laid out on disk, what a reproducible script has to say to reopen one, and how
#! to tell a user they are not in a project — reaches Studio through the three functions below,
#! dispatched on `ModelManager.AbstractSimulator`.
#!
#! Each has a working generic default, so a backend that implements none of them still drives
#! the GUI. PhysiCell overrides all three in `ext/StudioPhysiCellModelManagerExt.jl`.
#!
#! The parameter browser is deliberately NOT part of this seam: it reads the location's base
#! document directly, which works for any backend whose inputs are XML, so there is nothing
#! per-backend left to dispatch on.

"""
    studio_open_project(sim::ModelManager.AbstractSimulator, args::AbstractString...)

Open a project for `sim` and return whether one is now initialized.

The generic default treats a single argument as the data directory, which is ModelManager's own
unit of a project (`<data_dir>/inputs/inputs.toml`), and defaults to `"data"` with no arguments.

A backend whose projects span more than a data directory overrides this. PhysiCell, for example,
pairs a `PhysiCell/` tree with a `data/` tree, so its method accepts the two of them or a parent
holding both.
"""
function studio_open_project(sim::MM.AbstractSimulator, args::AbstractString...)
    @assert length(args) <= 1 "Expected at most 1 argument (the data directory), got $(length(args))"
    data_dir = isempty(args) ? "data" : args[1]
    MM.initializeModelManager(sim, abspath(normpath(data_dir)))
    return studio_project_is_open()
end

"""
    studio_transcript_preamble(sim::ModelManager.AbstractSimulator)

The opening lines of the session transcript: the `using` line and the call that reopens this
project, so the recorded script runs standalone.

The generic default emits ModelManager's own two-argument form. A backend overrides this when
reopening its projects takes something else — which is the whole reason the transcript cannot be
written generically.
"""
function studio_transcript_preamble(::MM.AbstractSimulator)
    return """
    using ModelManager, Distributions
    initializeModelManager(simulator(), \"$(MM.dataDir())\")
    """
end

"""
    studio_no_project_message(sim::ModelManager.AbstractSimulator)

What to tell a user who launched outside a project. A backend overrides this to name its own
project-creation function, which is the first thing such a user needs.
"""
function studio_no_project_message(::MM.AbstractSimulator)
    return """
    Studio needs an existing project. Either run it from a project directory, or pass one:

        using ModelManagerStudio
        launch("path/to/project")
    """
end

"""
    studio_token_emphasis(sim, location::Symbol, chain::Vector{String}, token::AbstractString)

Whether `token` deserves visual emphasis in the parameter browser, as a short label, or `""`.

The generic default emphasizes nothing: the browser reads the document, and a document cannot
say which of its elements are interesting. A backend knows things the XML does not — PhysiCell's
`custom_data` children are user-defined rather than part of the schema, which is worth marking
and is not inferable from the element itself.

Returned labels are backend-defined; the GUI styles anything non-empty and shows the label in a
tooltip, so a backend can introduce one without a change here.
"""
studio_token_emphasis(::MM.AbstractSimulator, ::Symbol, ::Vector{String}, ::AbstractString) = ""

"""
    studio_backend()

The active simulator, or `nothing` when no backend package has registered one.

Returning `nothing` rather than throwing matters because this is reached from `launch`, and
"you have not loaded a backend" deserves an explanation rather than an `AssertionError` out of
`mm_globals()`.
"""
function studio_backend()
    isnothing(MM.mm_globals_ref[]) && return nothing
    return MM.simulator()
end

"""
    studio_no_backend_message()

What to tell a user who loaded Studio without a simulator backend. Studio on its own cannot run
anything — it needs a package that implements `ModelManager.AbstractSimulator`.
"""
function studio_no_backend_message()
    return """
    No simulator backend is loaded, so there is nothing for Studio to drive.

    Load one before Studio, which also loads the matching Studio extension:

        using PhysiCellModelManager   # or another ModelManager backend
        using ModelManagerStudio
        launch("path/to/project")
    """
end

"""
    studio_project_is_open()

Whether a project is currently initialized, without assuming a backend has registered.

`ModelManager.isInitialized` reads `mm_globals()`, which asserts when nothing has populated
`mm_globals_ref[]` — so calling it unguarded turns "no backend loaded" into an `AssertionError`
rather than a `false`.
"""
function studio_project_is_open()
    isnothing(MM.mm_globals_ref[]) && return false
    return MM.isInitialized()
end
