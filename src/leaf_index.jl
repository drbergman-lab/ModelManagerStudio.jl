#! Every parameter a location's base document can reach, materialised once so one can be found
#! by name instead of walked to.
#!
#! The index is built from the same walk the browser's ComboBoxes use, so a hit is a chain the
#! browser can be driven to and `MM.XMLPath` can resolve. There is no second vocabulary that
#! could disagree with the first.

"""
    LeafEntry

One leaf parameter: the location holding it, the token chain reaching it, and the normalized
text a query matches against.

`chain` is exactly what the browser's ComboBoxes hold and what `MM.XMLPath` turns into a
target, so a searched-for parameter and a walked-to one resolve through the same code.
"""
struct LeafEntry
    location::Symbol
    chain::Vector{String}
    haystack::String
end

"""
    LeafIndexCache

Per-location leaf indexes, tagged with the input folder each was built from.

Keyed by the folder [`base_document`](@ref) recorded, so the index goes stale at exactly the
moment the document it was built from does, with no second staleness rule to keep in step.
"""
mutable struct LeafIndexCache
    entries::Dict{Symbol,Vector{LeafEntry}}
    folders::Dict{Symbol,String}
end

LeafIndexCache() = LeafIndexCache(Dict{Symbol,Vector{LeafEntry}}(), Dict{Symbol,String}())

const LEAF_INDEXES = LeafIndexCache()

"""
    invalidate_leaf_indexes!()

Forget every cached index, and the hits last handed to QML. Called alongside
[`invalidate_base_documents!`](@ref).

The hits go too: they name chains in documents that are about to be re-read, and a row applied
after the folders changed would drive the browser to a parameter the new model may not have.
"""
function invalidate_leaf_indexes!()
    global last_search_hits, last_search_total
    empty!(LEAF_INDEXES.entries)
    empty!(LEAF_INDEXES.folders)
    last_search_hits = LeafEntry[]
    last_search_total = 0
    return nothing
end

"""
    leaf_index(location::Symbol)

Every leaf parameter in `location`, built on first use and cached; `LeafEntry[]` when the
location has no readable base document.
"""
function leaf_index(location::Symbol)
    doc = base_document(location)
    isnothing(doc) && return LeafEntry[]
    folder = get(BASE_DOCUMENTS.folders, location, "")
    if haskey(LEAF_INDEXES.entries, location) && get(LEAF_INDEXES.folders, location, "") == folder
        return LEAF_INDEXES.entries[location]
    end

    entries = LeafEntry[]
    unsearchable = Set{String}()
    _collect_leaves!(entries, location, root(doc), String[], unsearchable)
    _warn_unsearchable(location, unsearchable)
    LEAF_INDEXES.entries[location] = entries
    LEAF_INDEXES.folders[location] = folder
    return entries
end

"""
    _collect_leaves!(entries, location, e, chain, unsearchable)

Depth-first walk appending a [`LeafEntry`](@ref) for every leaf below `e`, collecting into
`unsearchable` the names whose subtrees had to be skipped.
"""
function _collect_leaves!(entries::Vector{LeafEntry}, location::Symbol, e::XMLElement,
                          chain::Vector{String}, unsearchable::Set{String})
    next_tokens = get_next_xml_path_elements(e, ID_ATTRIBUTES)
    if isempty(next_tokens)
        isempty(chain) || push!(entries, LeafEntry(location, copy(chain), search_text(chain)))
        return nothing
    end

    for token in next_tokens
        instance = token_name(token)
        if !isempty(instance) && occursin(UNSEARCHABLE_NAME_CHARS, instance)
            push!(unsearchable, instance)
            continue
        end
        #! `_child_for_token` resolves exactly what `retrieveElement` will, so a token it
        #! cannot follow is one the browser could never be driven to -- an ambiguous token
        #! among them, whose `"<tag> (ambiguous)"` spelling matches no tag. Skipping the whole
        #! subtree is what keeps the index free of jumps that land nowhere.
        child = _child_for_token(e, token)
        isnothing(child) && continue
        push!(chain, token)
        _collect_leaves!(entries, location, child, chain, unsearchable)
        pop!(chain)
    end
    return nothing
end

"""
    _child_for_token(e, token)

The child of `e` that `token` names, or `nothing`.

Splits with `limit=3` to match `MM.retrieveElement`, so the index follows the same element the
resolved path will. It needs no `"::"` branch of its own: a name carrying a colon is rejected by
[`UNSEARCHABLE_NAME_CHARS`](@ref) before the walk ever gets here.
"""
function _child_for_token(e::XMLElement, token::AbstractString)
    parts = split(token, ':'; limit=3)
    length(parts) < 3 && return find_element(e, String(token))
    tag, attr, value = parts
    for ce in child_elements(e)
        if name(ce) == tag && has_attribute(ce, attr) && attribute(ce, attr) == value
            return ce
        end
    end
    return nothing
end

#! The only two characters a name cannot carry through the path machinery, measured against
#! `MM.XMLPath` and `MM.columnName`: ":" makes the token four parts and `XMLPath` asserts on it,
#! and "/" is what `columnName` joins on, so the round trip silently returns a different path.
#! Everything else a modeller actually writes survives -- "+", ".", "%", "&", quotes, Greek --
#! and `interactions` ships a cell definition called "CD8+ T cell", so a stricter rule than this
#! would make a sample project's own cell types unsearchable.
const UNSEARCHABLE_NAME_CHARS = r"[:/]"

"""
    _warn_unsearchable(location, names)

Say which names were left out of `location`'s index, once per build.

Skipping them silently is the worse failure: the parameter is in the dropdowns, so the only
signal would be that searching for it never finds it.
"""
function _warn_unsearchable(location::Symbol, names::Set{String})
    isempty(names) && return nothing
    listed = join(sort!(collect(names)), ", ")
    model_manager_studio_warn("""
    Cannot search $(length(names)) name(s) in $(location): $(listed)

    A name carrying ":" or "/" cannot be written as a parameter path -- ModelManager splits a \
    path element on ":" and joins the path on "/". These are still reachable by walking the \
    dropdowns; they just will not turn up in a search.""")
    return nothing
end

#! Separators that carry no meaning to someone typing a parameter's name. Collapsing them lets
#! one query reach both spellings of a name the model uses in two places: the config writes
#! `migration_bias` while a rule writes `migration bias`.
const SEARCH_SEPARATORS = r"[_\-:/]+"

"""
    search_text(parts)

`parts` lowercased and joined into the whitespace-separated text a query is matched against.
"""
function search_text(parts::Vector{<:AbstractString})
    text = replace(lowercase(join(parts, " ")), SEARCH_SEPARATORS => " ")
    return String(strip(replace(text, r"\s+" => " ")))
end

"""
    search_words(query)

`query` reduced to the words a match must contain, normalized the same way the index is.
"""
search_words(query::AbstractString) = String.(split(search_text([String(query)]), ' '; keepempty=false))

"""
    words_in_order(haystack, words)

Whether every word of `words` appears in `haystack`, in order. Each may match mid-word, so
`cd8` finds `CD8+ T cell`.
"""
function words_in_order(haystack::AbstractString, words::Vector{String})
    pos = firstindex(haystack)
    for word in words
        found = findnext(word, haystack, pos)
        isnothing(found) && return false
        pos = nextind(haystack, last(found))
    end
    return true
end

#! Ranks, best first. Tier 0 is a hit whose own tag IS the last word typed; tier 1 only
#! contains it. Order carries meaning here and is worth ranking on -- in `interactions`,
#! `cd8 attack bacteria` and `bacteria attack cd8` are two different parameters -- but someone
#! typing `speed bacteria` means the same thing, so a loose match still places (tier 3) rather
#! than returning nothing.
const RANK_EXACT_TAG = 0
const RANK_TAG_CONTAINS = 1
const RANK_IN_ORDER = 2
const RANK_ANY_ORDER = 3

"""
    match_rank(entry, words)

How well `entry` answers `words`, lower being better, or `nothing` for no match.
"""
function match_rank(entry::LeafEntry, words::Vector{String})
    isempty(words) && return nothing
    all(w -> occursin(w, entry.haystack), words) || return nothing
    words_in_order(entry.haystack, words) || return RANK_ANY_ORDER

    tag = search_text([last(entry.chain)])
    last_word = last(words)
    tag == last_word && return RANK_EXACT_TAG
    return occursin(last_word, tag) ? RANK_TAG_CONTAINS : RANK_IN_ORDER
end

"""
    searchable_locations()

The locations a search covers: those whose folders support variation, in the order the
location dropdown lists them.
"""
searchable_locations() = Symbol.(get_varied_locations())

"""
    search_leaves(query; limit=MAX_SEARCH_RESULTS)

`(hits, total)` — the best `limit` leaves matching `query` across every searchable location,
and how many matched in all.

Ranked by [`match_rank`](@ref), then shallower paths, then shorter ones, so the parameter
actually named outranks a deeper entry that merely repeats the word.
"""
function search_leaves(query::AbstractString; limit::Integer=MAX_SEARCH_RESULTS)
    words = search_words(query)
    isempty(words) && return (LeafEntry[], 0)

    scored = Tuple{Int,LeafEntry}[]
    for location in searchable_locations()
        for entry in leaf_index(location)
            rank = match_rank(entry, words)
            isnothing(rank) || push!(scored, (rank, entry))
        end
    end
    sort!(scored; by=t -> (t[1], length(t[2].chain), length(t[2].haystack), t[2].haystack))
    return ([t[2] for t in first(scored, limit)], length(scored))
end
