#! Cached access to each location's base XML document.
#!
#! Every parameter-browser helper used to do its own `prepareBaseFile` + `parse_file`, thirteen
#! times over, and none of them called `free`. Two consequences: a libxml2 document leaked on
#! every combo interaction, and because the QML delegate calls into the vocabulary helpers from
#! inside per-item property bindings, opening one dropdown re-read the config from disk once
#! per visible item per binding.
#!
#! Caching is keyed by the folder actually in use, so switching input folders invalidates
#! automatically rather than relying on a caller to remember.

"""
    BaseDocumentCache

Parsed base documents, one per location, tagged with the input folder they came from.

`folders` records which folder each cached document was parsed from; a mismatch on lookup means
the user changed the selection, so the stale document is freed and re-read. That makes staleness
impossible to get wrong by forgetting to call an invalidation function.
"""
mutable struct BaseDocumentCache
    docs::Dict{Symbol,XMLDocument}
    folders::Dict{Symbol,String}
end

BaseDocumentCache() = BaseDocumentCache(Dict{Symbol,XMLDocument}(), Dict{Symbol,String}())

const BASE_DOCUMENTS = BaseDocumentCache()

"""
    invalidate_base_documents!()

Free every cached document and forget it. Called whenever the input folders change.
"""
function invalidate_base_documents!()
    for (_, doc) in BASE_DOCUMENTS.docs
        try
            free(doc)
        catch
            #! A document already freed elsewhere must not stop the rest being released.
        end
    end
    empty!(BASE_DOCUMENTS.docs)
    empty!(BASE_DOCUMENTS.folders)
    return nothing
end

"""
    base_document(location::Symbol)

Return the parsed base document for `location`, or `nothing` when there is nothing to read.

Returns `nothing` — never throws — when no inputs have been created, when `location` is not part
of this project, when its folder is unselected, or when the simulator cannot prepare a base file.
That last case matters: `prepareBaseFile` on an unselected folder raises an `AssertionError` from
deep inside the simulator's own dependencies, which is not something a GUI callback can act on.

The returned document is owned by the cache. Do not `free` it.
"""
function base_document(location::Symbol)
    isdefined(ModelManagerStudio, :inputs) || return nothing
    location in MM.projectLocations().all || return nothing

    input_folder = try
        inputs[location]
    catch
        return nothing
    end
    folder = input_folder.folder
    isempty(folder) && return nothing

    #! Reuse only when the folder still matches; otherwise the cached document belongs to a
    #! selection the user has since changed.
    if haskey(BASE_DOCUMENTS.docs, location) && get(BASE_DOCUMENTS.folders, location, "") == folder
        return BASE_DOCUMENTS.docs[location]
    end

    if haskey(BASE_DOCUMENTS.docs, location)
        try
            free(BASE_DOCUMENTS.docs[location])
        catch
        end
        delete!(BASE_DOCUMENTS.docs, location)
        delete!(BASE_DOCUMENTS.folders, location)
    end

    doc = try
        parse_file(PhysiCellModelManager.prepareBaseFile(input_folder))
    catch e
        model_manager_studio_debug("Could not read the base file for $(location): $(sprint(showerror, e))")
        return nothing
    end

    BASE_DOCUMENTS.docs[location] = doc
    BASE_DOCUMENTS.folders[location] = folder
    return doc
end

"""
    base_element(location::Symbol, xml_path::Vector{<:AbstractString})

Return the element at `xml_path` within `location`'s base document, or `nothing` if the location
is unavailable or the path does not exist. Never throws.
"""
function base_element(location::Symbol, xml_path::Vector{<:AbstractString})
    doc = base_document(location)
    isnothing(doc) && return nothing
    return try
        MM.retrieveElement(doc, xml_path; required=false)
    catch
        nothing
    end
end
