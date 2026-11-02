using ModelManagerStudio, PhysiCellModelManager, Test, QML, Distributions, LightXML
import ModelManager as MM

#! Testing mode makes the QML side call Qt.exit(0) on a timer. Without it `exec()`
#! never returns and `Pkg.test()` hangs until CI's 60-minute timeout. Set it here
#! rather than relying on the workflow env so the suite is runnable locally.
ENV["MODEL_MANAGER_STUDIO_TESTING"] = "true"

#! A stand-in backend whose colour hook returns whatever it is told to, so the core's handling
#! of a backend's return value can be tested without a backend that misbehaves on purpose.
struct ColorProbe <: MM.AbstractSimulator
    answer::Any
end

function ModelManagerStudio.studio_token_color(probe::ColorProbe, ::Symbol,
                                               ::Vector{String}, ::AbstractString)
    probe.answer === :throw && error("backend blew up")
    return probe.answer
end

createProject()

@testset "ModelManagerStudio.jl" begin
    @testset "GUI initialization" begin
        @test begin
            ModelManagerStudio.launch()
            true
        end

        for args in [["."], [joinpath(".", "PhysiCell"), joinpath(".", "data")]]
            physicell_dir, data_dir = Base.get_extension(ModelManagerStudio, :StudioPhysiCellModelManagerExt).physicell_project_paths(args...)
            @test isdir(data_dir)
            @test isdir(physicell_dir)
            @test abspath(physicell_dir) == abspath(joinpath(".", "PhysiCell"))
            @test abspath(data_dir) == abspath(joinpath(".", "data"))
        end
    end

    @testset "Creating inputs" begin
        ModelManagerStudio.set_input_folders()
        inputs = ModelManagerStudio.inputs
        @test inputs[:config].folder == "0_template"
        @test inputs[:custom_code].folder == "0_template"
    end

    @testset "Colors" begin
        for scheme in ModelManagerStudio.random_color_scheme_list()
            withenv("STUDIO_COLOR_TOKEN" => scheme) do
                colors = ModelManagerStudio.color_scheme()
                for color in values(colors)
                    @test occursin(r"^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$", color)
                end
            end
        end
    end

    #! Regression guard for the PCMM 0.3 split. `variationTarget`/`variationValues` live in
    #! ModelManager and are not exported, so reaching them as `PhysiCellModelManager.x`
    #! throws UndefVarError. Nothing in the suite used to touch create_variation or the
    #! record transcript, so that break was invisible.
    @testset "Creating variations" begin
        target = ModelManagerStudio.get_target_path("config", "overall", "max_time")
        @test target isa AbstractString
        @test ModelManagerStudio.is_resolvable_target(target)
        @test target == "overall/max_time"
        @test !ModelManagerStudio.variation_exists(target)

        ModelManagerStudio.create_variation(target, "[100.0, 200.0]")
        @test ModelManagerStudio.variation_exists(target)

        current = ModelManagerStudio.get_current_variations()
        @test length(current) == 1

        #! Editing the same target must replace, not append.
        ModelManagerStudio.create_variation(target, "[300.0]")
        @test length(ModelManagerStudio.get_current_variations()) == 1

        #! The transcript is the package's reproducibility promise; exercise the
        #! MM.variationTarget / MM.variationValues calls inside it.
        @test isfile(ModelManagerStudio.path_to_record)
        @test occursin("ElementaryVariation", read(ModelManagerStudio.path_to_record, String))
    end

    @testset "Browser walks the document" begin
        #! The browser is a plain XML walk now: tokens ARE path elements. The top level of
        #! config is therefore the config root's own children, not a curated vocabulary.
        top = ModelManagerStudio.get_next_model("config")
        @test !isempty(top)
        @test "domain" in top
        @test "overall" in top
        #! Curated semantic tokens are gone -- `max_time` is reached as overall > max_time.
        @test !("max_time" in top)
        @test !("user_parameter" in top)

        #! Same-tag siblings are distinguished by attribute, with exactly two colons so that
        #! retrieveElement's limit=3 split and getChildByAttribute's 3-way destructure work.
        defs = ModelManagerStudio.get_next_model("config", "cell_definitions")
        @test !isempty(defs)
        @test all(t -> count(==(':'), t) in (0, 2), defs)
        @test any(t -> startswith(t, "cell_definition:name:"), defs)

        #! Every varied location is browsable now, including the two that had no grammar
        #! under the curated cascade and returned nothing.
        for loc in ModelManagerStudio.get_varied_locations()
            toks = ModelManagerStudio.get_next_model(loc)
            @test toks isa Vector{String}
        end

        #! An unknown location yields an empty model rather than throwing or returning nothing.
        @test ModelManagerStudio.get_next_model("not_a_location") == String[]
    end

    @testset "Chain terminates at a leaf" begin
        #! Structural, not curated: a finite document, one token per level, nothing below a
        #! leaf. Walk to a known scalar and one step past it.
        @test !isempty(ModelManagerStudio.get_next_model("config", "overall"))
        @test ModelManagerStudio.get_next_model("config", "overall", "max_time") == String[]
        @test ModelManagerStudio.get_next_model("config", "overall", "max_time", "junk") == String[]
    end

    @testset "Target is the path itself" begin
        t = ModelManagerStudio.get_target_path("config", "overall", "max_time")
        @test ModelManagerStudio.is_resolvable_target(t)
        @test t == "overall/max_time"
        #! Round trips through ModelManager's own column-name encoding.
        @test MM.columnName(MM.XMLPath(MM.columnNameToXMLPath(t))) == t

        #! An interior node is not a parameter, and says so rather than producing a path.
        @test !ModelManagerStudio.is_resolvable_target(ModelManagerStudio.get_target_path("config", "overall"))
        #! Neither is a path that is not in the document.
        @test !ModelManagerStudio.is_resolvable_target(ModelManagerStudio.get_target_path("config", "nope"))
        @test !ModelManagerStudio.is_resolvable_target(ModelManagerStudio.get_target_path("config"))
    end

    @testset "Every offered chain resolves" begin
        #! Tokens are read FROM the document, so this holds by construction rather than by a
        #! filter -- but assert it, because it is the property the curated cascade kept
        #! breaking. Walk the whole config tree to a bounded depth.
        doc = ModelManagerStudio.base_document(:config)
        @test doc !== nothing
        bad = String[]
        leaves = Ref(0)
        function walk(chain, depth)
            depth > 6 && return
            for t in ModelManagerStudio.get_next_model("config", chain...)
                next = [chain; t]
                kids = ModelManagerStudio.get_next_model("config", next...)
                if isempty(kids)
                    leaves[] += 1
                    tgt = ModelManagerStudio.get_target_path("config", next...)
                    ModelManagerStudio.is_resolvable_target(tgt) || push!(bad, join(next, "/"))
                else
                    walk(next, depth + 1)
                end
            end
        end
        walk(String[], 1)
        for b in bad
            @info "unresolvable: $b"
        end
        @test isempty(bad)
        @test leaves[] > 50     # the walk actually covered the document
    end

    @testset "Menus render" begin
        #! Rendered into the log so the walked menus can be eyeballed from a test run.
        function render(chain)
            toks  = ModelManagerStudio.get_next_model("config", chain...)
            kinds = ModelManagerStudio.get_token_kinds("config", chain...)
            io = IOBuffer()
            for (t, k) in zip(toks, kinds)
                println(io, "     ", rpad(t, 42), k == "branch" ? "\u203a" : "")
            end
            @info "config" * (isempty(chain) ? "" : " > " * join(chain, " > ")) * "\n" * String(take!(io))
        end
        render(String[])
        render(["cell_definitions"])
        render(["cell_definitions", "cell_definition:name:default", "phenotype", "motility"])

        #! The deep path the walk produces for a parameter the curated cascade reached in two
        #! steps. Longer, but it is the document's own structure.
        deep = ModelManagerStudio.get_target_path("config", "cell_definitions",
            "cell_definition:name:default", "phenotype", "motility", "speed")
        @test ModelManagerStudio.is_resolvable_target(deep)
        @test deep == "cell_definitions/cell_definition:name:default/phenotype/motility/speed"
    end

    @testset "Backend colour hook" begin
        sim = ModelManagerStudio.studio_backend()
        ext = Base.get_extension(ModelManagerStudio, :StudioPhysiCellModelManagerExt)
        @test !isnothing(ext)

        N = ModelManagerStudio.token_name
        @test N("cell_definition:name:default") == "default"
        @test N("variable:name:substrate") == "substrate"
        @test N("phenotype") == ""
        @test N("") == ""
        #! limit=3 matches retrieveElement, so a name containing a colon survives intact.
        @test N("tag:attr:a:b") == "a:b"

        #! PhysiCell's own schema is not coloured -- only names from the user's model are.
        @test all(isempty, ModelManagerStudio.get_token_colors("config", "overall"))

        cell_color = ext.CELL_DEFINITION_COLOR
        substrate_color = ext.SUBSTRATE_COLOR
        custom_color = ext.CUSTOM_DATA_COLOR
        #! Three categories, three appearances. If two collapsed, the colour would stop
        #! distinguishing the thing it exists to distinguish.
        @test length(unique([cell_color, substrate_color, custom_color])) == 3

        #! Every cell definition draws the same colour -- as a group, not as instances.
        defs = ModelManagerStudio.get_next_model("config", "cell_definitions")
        def_colors = ModelManagerStudio.get_token_colors("config", "cell_definitions")
        @test length(def_colors) == length(defs)
        @test !isempty(defs)
        @test all(==(cell_color), def_colors)

        #! ...including where it appears under a different tag entirely. Adhesion affinities
        #! are per cell type, so the same names recur deep inside the phenotype.
        aff_chain = ["cell_definitions", "cell_definition:name:default", "phenotype",
                     "mechanics", "cell_adhesion_affinities"]
        aff = ModelManagerStudio.get_next_model("config", aff_chain...)
        if !isempty(aff)
            @test all(==(cell_color), ModelManagerStudio.get_token_colors("config", aff_chain...))
        end

        #! Substrates are a different group, so a different colour -- and they sit beside
        #! <options>, which is schema and must stay uncoloured.
        micro = ModelManagerStudio.get_next_model("config", "microenvironment_setup")
        micro_colors = ModelManagerStudio.get_token_colors("config", "microenvironment_setup")
        by_token = Dict(zip(micro, micro_colors))
        substrate_tokens = [t for t in micro if startswith(t, "variable:")]
        @test !isempty(substrate_tokens)
        @test all(t -> by_token[t] == substrate_color, substrate_tokens)
        @test all(t -> by_token[t] == "", [t for t in micro if !startswith(t, "variable:")])

        #! Custom data has no name attribute to look up -- its children ARE the parameters --
        #! so the tag is the key, drawn from every cell definition's block unioned together.
        #! PhysiCell requires those blocks to agree and writes out the first one's set, so the
        #! union is the model's vocabulary however a hand-edited config has drifted.
        custom_chain = ["cell_definitions", "cell_definition:name:default", "custom_data"]
        custom = ModelManagerStudio.get_next_model("config", custom_chain...)
        custom_colors = ModelManagerStudio.get_token_colors("config", custom_chain...)
        @test length(custom_colors) == length(custom)
        @test !isempty(custom)
        @test all(==(custom_color), custom_colors)

        @test ext.custom_data_names(ModelManagerStudio.base_document(:config)) == Set(custom)

        #! Unioned across cell definitions, because PhysiCell inherits a definition's custom
        #! data from its parent and appends -- a later definition can declare tags no earlier
        #! one has.
        doc = XMLDocument()
        root = create_root(doc, "PhysiCell_settings")
        defs = new_child(root, "cell_definitions")
        for (cell, entries) in [("default", ["alpha", "beta"]), ("other", ["alpha", "gamma"])]
            cd = new_child(defs, "cell_definition")
            set_attribute(cd, "name", cell)
            block = new_child(cd, "custom_data")
            for entry in entries
                new_child(block, entry)
            end
        end
        @test ext.custom_data_names(doc) == Set(["alpha", "beta", "gamma"])
        free(doc)

        #! A rule names a custom-data entry as a signal or behavior, in either of the two
        #! spellings PhysiCell_signal_behavior.cpp registers for the NAME. It also accepts
        #! "custom <index>", which is deliberately not resolved.
        K(name) = ext.custom_data_key(name, Set(["damage_rate", "oncoprotein"]))
        @test K("custom:damage_rate") == "damage_rate"
        @test K("custom: damage_rate") == "damage_rate"
        @test K("custom 0") == ""
        @test K("custom 1") == ""
        #! Undeclared and unprefixed both decline rather than guess.
        @test K("custom:not_declared") == ""
        @test K("damage_rate") == ""
        @test K("oxygen") == ""
        @test K("custom:") == ""

        for entry in custom
            for spelling in ["custom:" * entry, "custom: " * entry]
                @test ModelManagerStudio.studio_token_color(sim, :rulesets_collection,
                    ["behavior_ruleset:name:default"], "behavior:name:" * spelling) == custom_color
            end
            #! The positional form stays uncoloured even when it would resolve.
            @test isnothing(ModelManagerStudio.studio_token_color(sim, :rulesets_collection,
                ["behavior_ruleset:name:default"], "behavior:name:custom 0"))
        end
        #! An undeclared name is not coloured just for carrying the prefix.
        @test isnothing(ModelManagerStudio.studio_token_color(sim, :rulesets_collection,
            ["behavior_ruleset:name:default"], "behavior:name:custom:not_declared"))

        #! Unprefixed, the name is not unique, so a bare tag counts only inside <custom_data>.
        #! sample_projects/cancer_biorobots ships `damage_rate` as custom data AND as
        #! PhysiCell's own cell_integrity/damage_rate in the same cell definitions.
        for entry in custom
            @test ModelManagerStudio.studio_token_color(sim, :config, ["custom_data"], entry) == custom_color
            @test isnothing(ModelManagerStudio.studio_token_color(sim, :config,
                ["phenotype", "cell_integrity"], entry))
            @test isnothing(ModelManagerStudio.studio_token_color(sim, :config, String[], entry))
        end
        #! An element PhysiCell declares itself is not any of the three.
        @test isnothing(ModelManagerStudio.studio_token_color(sim, :config, ["custom_data"], "custom_data"))
        @test isnothing(ModelManagerStudio.studio_token_color(sim, :config, String[], "anything"))

        #! The generic default colours nothing, so a backend that ignores the hook still works.
        @test hasmethod(ModelManagerStudio.studio_token_color,
                        Tuple{MM.AbstractSimulator,Symbol,Vector{String},AbstractString})
        @test isnothing(invoke(ModelManagerStudio.studio_token_color,
                               Tuple{MM.AbstractSimulator,Symbol,Vector{String},AbstractString},
                               sim, :config, String[], "cell_definitions"))
    end

    @testset "Mixed value lists narrow to a concrete type" begin
        #! DiscreteVariation wants a concrete Vector{T}. Broadcasting alone joins rather than
        #! promotes, so [1, 2.0] used to land on the non-concrete Vector{Real}.
        for (spec, T) in [("[1.0, 2.0]", Float64), ("[1, 2]", Int), ("[1, 2.0]", Float64),
                          ("[1, true]", Int), ("0.1:0.1:0.3", Float64)]
            vals = ModelManagerStudio.parse_value_spec(spec)
            @test vals isa AbstractVector
            @test isconcretetype(eltype(vals))
            @test eltype(vals) == T
        end
    end

    @testset "Backend colours are sanitized" begin
        #! Reached from a QML property binding, so a backend returning something QML cannot
        #! draw has to dull the token rather than break the row it is on.
        tc(answer) = ModelManagerStudio.token_color(ColorProbe(answer), :config, String[], "t")

        @test tc(nothing) == ""
        @test tc(missing) == ""
        @test tc("#A0B0C0") == "#A0B0C0"
        @test tc("#abc") == "#abc"
        @test tc("#80A0B0C0") == "#80A0B0C0"
        @test tc("red") == ""
        @test tc("#12345") == ""
        @test tc(42) == ""
        #! A throwing backend is a dull token, not a stack trace out of a binding.
        @test tc(:throw) == ""
    end

    @testset "Branch and leaf kinds" begin
        top   = ModelManagerStudio.get_next_model("config")
        kinds = ModelManagerStudio.get_token_kinds("config")
        @test length(kinds) == length(top)
        @test all(k -> k in ("branch", "leaf"), kinds)
        k = Dict(zip(top, kinds))
        @test k["domain"] == "branch"
        @test k["overall"] == "branch"

        inner = ModelManagerStudio.get_next_model("config", "overall")
        ik = Dict(zip(inner, ModelManagerStudio.get_token_kinds("config", "overall")))
        @test ik["max_time"] == "leaf"
    end


    @testset "Leaf index enumerates every reachable parameter" begin
        #! Hand-built, so the index is tested against a known document rather than against
        #! whichever optional input folders happen to be selected.
        doc = XMLDocument()
        r = create_root(doc, "root")
        set_content(new_child(r, "scalar"), "1")
        grp = new_child(r, "group")
        for nm in ("x", "y")
            c = new_child(grp, "item")
            set_attribute(c, "name", nm)
            set_content(c, "0")
        end
        #! Two same-tag siblings that no attribute tells apart. `retrieveElement` cannot
        #! follow the token the walk emits for them, so nothing below may be indexed.
        amb = new_child(r, "ambiguous_parent")
        set_content(new_child(amb, "same"), "1")
        set_content(new_child(amb, "same"), "2")

        #! `retrieveElement` tests for "::" BEFORE splitting on ":", and routes such a path
        #! element to `getChildByChildContent`, which reads a child's content rather than an
        #! attribute. An attribute value carrying "::" therefore names an element the index
        #! could follow but the resolved path could not.
        dc = new_child(r, "double_colon")
        set_attribute(dc, "name", "Wnt::bcat")
        set_content(new_child(dc, "rate"), "1")
        #! " (ambiguous)" is the walker's marker for same-tag siblings no attribute tells
        #! apart, but it is also something a modeller may legally name a cell type. The marker
        #! must not be recovered from text that came out of the model file.
        named = new_child(r, "named")
        set_attribute(named, "name", "tumor (ambiguous)")
        set_content(new_child(named, "size"), "1")

        entries = ModelManagerStudio.LeafEntry[]
        ModelManagerStudio._collect_leaves!(entries, :config, root(doc), String[])
        chains = [e.chain for e in entries]

        @test ["scalar"] in chains
        @test ["group", "item:name:x"] in chains
        @test ["group", "item:name:y"] in chains
        @test !any(c -> "ambiguous_parent" in c, chains)
        @test !any(c -> any(t -> contains(t, "::"), c), chains)
        @test ["named:name:tumor (ambiguous)", "size"] in chains
        @test all(e -> e.location === :config, entries)
        #! Every indexed chain must resolve, or a hit would drive the browser nowhere.
        @test all(c -> !isnothing(MM.retrieveElement(doc, c; required=false)), chains)

        free(doc)
    end

    @testset "Search normalizes the separators a model spells names with" begin
        #! The config writes `migration_bias`; a PhysiCell rule writes `migration bias`. One
        #! query has to reach both, so the index and the query are flattened the same way.
        @test ModelManagerStudio.search_text(["a_b", "c-d"]) == "a b c d"
        @test ModelManagerStudio.search_text(["cell_definition:name:CD8+ T cell"]) ==
              "cell definition name cd8+ t cell"
        @test ModelManagerStudio.search_words("  migration_bias ") == ["migration", "bias"]
        @test ModelManagerStudio.search_words("") == String[]
        @test ModelManagerStudio.search_words("migration_bias") ==
              ModelManagerStudio.search_words("migration bias")
    end

    @testset "Search ranks the parameter named over one that repeats the word" begin
        entry(chain) = ModelManagerStudio.LeafEntry(:config, chain,
                                                    ModelManagerStudio.search_text(chain))
        speed = entry(["cell_definition:name:bacteria", "phenotype", "motility", "speed"])
        halfmax = entry(["cell_definition:name:bacteria", "custom_data", "migration_speed_halfmax"])
        words = ModelManagerStudio.search_words("bacteria speed")

        @test ModelManagerStudio.match_rank(speed, words) == ModelManagerStudio.RANK_EXACT_TAG
        @test ModelManagerStudio.match_rank(halfmax, words) == ModelManagerStudio.RANK_TAG_CONTAINS
        @test ModelManagerStudio.match_rank(speed, words) <
              ModelManagerStudio.match_rank(halfmax, words)

        #! Order carries meaning -- "cd8 attack bacteria" and "bacteria attack cd8" are two
        #! different parameters -- but a loose query still places rather than finding nothing.
        loose = ModelManagerStudio.search_words("speed bacteria")
        @test ModelManagerStudio.match_rank(speed, loose) == ModelManagerStudio.RANK_ANY_ORDER
        @test isnothing(ModelManagerStudio.match_rank(speed, ModelManagerStudio.search_words("zzz")))
        @test isnothing(ModelManagerStudio.match_rank(speed, String[]))
    end

    @testset "A search hit drives the browser to a real target" begin
        labels = ModelManagerStudio.search_parameters("max time")
        @test !isempty(labels)
        @test any(l -> occursin("overall/max_time", l), labels)
        @test ModelManagerStudio.search_result_count() >= length(labels)
        @test length(labels) <= ModelManagerStudio.MAX_SEARCH_RESULTS

        #! QML counts rows from zero and addresses the result by row.
        row = findfirst(l -> occursin("overall/max_time", l), labels) - 1
        toks = ModelManagerStudio.search_result_tokens(row)
        @test toks == ["config", "overall", "max_time"]

        #! The whole point: the chain a hit returns is one the existing resolver accepts.
        target = ModelManagerStudio.get_target_path(toks[1], toks[2:end]...)
        @test ModelManagerStudio.is_resolvable_target(target)

        #! Each token must be offered by the level above it, or the ComboBoxes cannot be set.
        @test toks[2] in ModelManagerStudio.get_next_model(toks[1])
        @test toks[3] in ModelManagerStudio.get_next_model(toks[1], toks[2])

        #! Out-of-range rows and empty queries are answered, not thrown.
        @test ModelManagerStudio.search_result_tokens(10_000) == String[]
        @test ModelManagerStudio.search_result_tokens(-1) == String[]
        @test ModelManagerStudio.search_parameters("") == String[]
        @test ModelManagerStudio.search_result_count() == 0
        @test ModelManagerStudio.search_parameters("zzzz no such parameter") == String[]
    end

    @testset "Results come back in rank order, not document order" begin
        #! Ranking is only observable through `search_parameters`, so assert it there: without
        #! the sort, hits arrive in document order and a deeper entry that merely repeats the
        #! word can outrank the parameter actually named.
        ranks = Int[]
        words = ModelManagerStudio.search_words("rate")
        for label in ModelManagerStudio.search_parameters("rate")
            location, path = split(label, ": "; limit=2)
            chain = String.(split(path, "/"))
            entry = ModelManagerStudio.LeafEntry(Symbol(location), chain,
                                                 ModelManagerStudio.search_text(chain))
            push!(ranks, ModelManagerStudio.match_rank(entry, words))
        end
        @test length(ranks) > 1
        @test issorted(ranks)
        @test first(ranks) == minimum(ranks)
    end

    @testset "A truncated result list reports how many actually matched" begin
        #! `search_result_count` is the whole basis for the "Showing N of M" footer, so it has
        #! to be the match total and not the length of the capped list.
        broad = ModelManagerStudio.search_parameters("a")
        @test length(broad) == ModelManagerStudio.MAX_SEARCH_RESULTS
        @test ModelManagerStudio.search_result_count() > ModelManagerStudio.MAX_SEARCH_RESULTS
    end

    @testset "Search spans every varied location, not just the one on screen" begin
        #! The headline promise: a model's parameters and the rules acting on them live in two
        #! locations, and one query has to reach both. The suite's default selection varies
        #! only `config`, so a second varied folder is selected here on purpose.
        saved = ModelManagerStudio.inputs
        try
            ModelManagerStudio.inputs = PhysiCellModelManager.InputFolders(config="0_template",
                                                                           custom_code="0_template",
                                                                           rulesets_collection="0_template")
            ModelManagerStudio.invalidate_base_documents!()

            locations = ModelManagerStudio.searchable_locations()
            @test :config in locations
            @test :rulesets_collection in locations

            indexed = filter(l -> !isempty(ModelManagerStudio.leaf_index(l)), locations)
            @test length(indexed) >= 2

            #! One query, hits from more than one location -- the thing a per-location search
            #! cannot do. "max" appears in the config's intervals and in a ruleset's half_max.
            found = Set(Symbol(first(split(l, ": "; limit=2)))
                        for l in ModelManagerStudio.search_parameters("max"))
            @test length(found) >= 2
            @test issubset(found, Set(locations))

            #! And a hit from the non-config location still resolves.
            rules = [l for l in ModelManagerStudio.search_parameters("max")
                     if startswith(l, "rulesets_collection: ")]
            @test !isempty(rules)
            row = findfirst(==(first(rules)), ModelManagerStudio.search_parameters("max")) - 1
            toks = ModelManagerStudio.search_result_tokens(row)
            @test toks[1] == "rulesets_collection"
            @test ModelManagerStudio.is_resolvable_target(
                      ModelManagerStudio.get_target_path(toks[1], toks[2:end]...))
        finally
            ModelManagerStudio.inputs = saved
            ModelManagerStudio.invalidate_base_documents!()
        end
    end

    @testset "Searchable locations are the varied ones, and every hit resolves" begin
        @test ModelManagerStudio.searchable_locations() ==
              Symbol.(ModelManagerStudio.get_varied_locations())

        for location in ModelManagerStudio.searchable_locations()
            index = ModelManagerStudio.leaf_index(location)
            @test all(e -> e.location === location, index)
            @test all(e -> !isempty(e.chain), index)
            #! A location with a document indexes something; one without indexes nothing.
            @test isnothing(ModelManagerStudio.base_document(location)) == isempty(index)
            #! Every indexed chain has to resolve, or a hit drives the browser nowhere.
            @test all(e -> ModelManagerStudio.is_resolvable_target(
                               ModelManagerStudio.get_target_path(String(location), e.chain...)), index)
        end
    end

    @testset "Leaf indexes are cached and invalidated with the documents" begin
        first_build = ModelManagerStudio.leaf_index(:config)
        @test !isempty(first_build)
        #! Cached by identity: a second call must not rebuild.
        @test ModelManagerStudio.leaf_index(:config) === first_build

        #! Hits name chains in documents that are about to be re-read, so they go too: a row
        #! applied after the folders changed would drive the browser to a parameter the new
        #! model may not have.
        @test !isempty(ModelManagerStudio.search_parameters("max time"))
        ModelManagerStudio.invalidate_base_documents!()
        @test isempty(ModelManagerStudio.LEAF_INDEXES.entries)
        @test ModelManagerStudio.search_result_tokens(0) == String[]
        @test ModelManagerStudio.search_result_count() == 0
        rebuilt = ModelManagerStudio.leaf_index(:config)
        @test rebuilt !== first_build
        @test [e.chain for e in rebuilt] == [e.chain for e in first_build]
    end

    @testset "No-folder sentinel is shared with QML" begin
        #! The sentinel used to be a literal on both sides of the Julia/QML boundary. QML now
        #! reads it from project_configuration_properties, so it must actually be published
        #! there -- a missing key would silently make every optional tile read as "in use".
        props = ModelManagerStudio.create_project_configuration_properties()
        @test props["no_folder_sentinel"] == ModelManagerStudio.NO_FOLDER_SENTINEL

        #! And the round trip an optional location makes: offered in the dropdown, stored as "".
        @test ModelManagerStudio.NO_FOLDER_SENTINEL in
              ModelManagerStudio.get_folders(String(first(MM.projectLocations().required)), false)
        @test !ModelManagerStudio.is_varied_location("config", ModelManagerStudio.NO_FOLDER_SENTINEL)
    end

    @testset "Base documents are cached and invalidated" begin
        #! Thirteen helpers each used to parse the config afresh, and none freed it. The cache
        #! makes repeated vocabulary lookups cheap enough for the resolvability filter to run
        #! on every menu.
        d1 = ModelManagerStudio.base_document(:config)
        d2 = ModelManagerStudio.base_document(:config)
        @test d1 !== nothing
        @test d1 === d2                      # same document, not re-parsed

        #! Unknown or unselected locations yield nothing rather than throwing out of a
        #! QML callback -- prepareBaseFile asserts from inside the simulator's dependencies.
        @test ModelManagerStudio.base_document(:not_a_location) === nothing
        @test ModelManagerStudio.base_element(:not_a_location, ["anything"]) === nothing
        @test ModelManagerStudio.base_element(:config, ["no", "such", "path"]) === nothing
        @test ModelManagerStudio.base_element(:config, ["overall"]) !== nothing

        ModelManagerStudio.invalidate_base_documents!()
        d3 = ModelManagerStudio.base_document(:config)
        @test d3 !== nothing
        @test ModelManagerStudio.base_element(:config, ["overall"]) !== nothing
    end

    @testset "Zero-arg launch adopts an existing project" begin
        #! By this point the suite has an initialized project. A 0-arg initialization must
        #! adopt it rather than re-deriving paths from pwd() -- otherwise launching from any
        #! directory other than the project root silently retargets or fails, even though the
        #! session already has a perfectly good project open.
        @test ModelManagerStudio.studio_project_is_open()
        data_before = MM.dataDir()

        elsewhere = mktempdir()
        cd(elsewhere) do
            @test ModelManagerStudio.studio_initialize_model_manager()
            @test MM.dataDir() == data_before
        end

        #! Explicit arguments still win over the adopted project; the PhysiCell layout now
        #! lives in the extension.
        ext = Base.get_extension(ModelManagerStudio, :StudioPhysiCellModelManagerExt)
        @test ext.physicell_project_paths(".") ==
              (abspath(normpath(joinpath(".", "PhysiCell"))), abspath(normpath(joinpath(".", "data"))))
    end

    @testset "PhysiCell support arrives as an extension" begin
        ext = Base.get_extension(ModelManagerStudio, :StudioPhysiCellModelManagerExt)
        @test ext !== nothing

        sim = ModelManagerStudio.studio_backend()
        @test sim isa PhysiCellModelManager.PhysiCellSimulator

        #! Each seam function must reach the PhysiCell method, not the generic fallback.
        @test occursin("PhysiCell", ModelManagerStudio.studio_no_project_message(sim))
        @test occursin("createProject", ModelManagerStudio.studio_no_project_message(sim))

        #! The transcript must reopen a PhysiCell project, which takes both directories --
        #! the generic one-argument form would produce a script that does not run.
        pre = ModelManagerStudio.studio_transcript_preamble(sim)
        @test occursin("using PhysiCellModelManager", pre)
        @test occursin(PhysiCellModelManager.physicellDir(), pre)
        @test occursin(MM.dataDir(), pre)

        #! The PhysiCell project layout lives in the extension now, not in core.
        @test !isdefined(ModelManagerStudio, :get_pcmm_paths)
        pc, dat = ext.physicell_project_paths("someproj")
        @test endswith(pc, joinpath("someproj", "PhysiCell"))
        @test endswith(dat, joinpath("someproj", "data"))
        @test ext.physicell_project_paths() |> first |> isabspath

        #! Core carries no PhysiCell dependency.
        @test !(:PhysiCellModelManager in names(ModelManagerStudio; all=true, imported=true))
    end

    @testset "Transcript preamble actually reopens the project" begin
        #! The preamble is the one seam function whose failure is silent and late: a wrong one
        #! still writes a transcript, and you find out when someone runs the script. So execute
        #! it rather than pattern-matching it. Evaluated in a throwaway module; it reopens the
        #! same project, so the suite's state is unchanged.
        pre = ModelManagerStudio.studio_transcript_preamble(ModelManagerStudio.studio_backend())
        sandbox = Module(:PreambleCheck)
        Core.eval(sandbox, :(using Test))
        @test try
            include_string(sandbox, pre)
            true
        catch e
            @info "preamble failed to run" exception = (e, catch_backtrace())
            false
        end
        #! And it must leave a project open, not merely run without error.
        @test ModelManagerStudio.studio_project_is_open()
        @test MM.dataDir() == dirname(MM.centralDB().file)
    end

    @testset "Documented API is reachable" begin
        #! The README tells users to write `using ModelManagerStudio; launch()`. That only
        #! works if `launch` is exported -- it was `@compat public`, which is not the same
        #! thing, so the documented invocation raised UndefVarError.
        @test :launch in names(ModelManagerStudio)
        @test :main in names(ModelManagerStudio)
        #! Reachable unqualified, which is what the docs promise.
        @test isdefined(@__MODULE__, :launch)
    end

    @testset "Entrypoint exists and reports failure" begin
        #! `main` is exported, but main.jl used to be included only on 1.11+, so on the LTS
        #! the package claims compat with the exported name did not exist.
        @test isdefined(ModelManagerStudio, :main)

        #! Failure must be reported, not swallowed into a 0 exit status. Point it at a
        #! directory that is definitely not a project.
        empty_dir = mktempdir()
        code = mktemp() do path, io
            redirect_stderr(io) do
                ModelManagerStudio._studio_main((empty_dir,))
            end
        end
        @test code == 1
    end

    @testset "Value spec parser" begin
        P = ModelManagerStudio.parse_value_spec
        E = ModelManagerStudio.ValueSpecError

        #! Scalars
        @test P("2.5") == 2.5
        @test P("-3") == -3
        @test P("1e-4") == 1e-4
        @test P("true") === true
        @test P("false") === false
        @test P("\"tumor\"") == "tumor"

        #! Lists, bracketed and bare
        @test P("[1.0, 2.0, 3.0]") == [1.0, 2.0, 3.0]
        @test P("1.0, 2.0") == [1.0, 2.0]
        @test P("[1.0, 2.0]") isa Vector{Float64}

        #! Ranges are materialized to a Vector, since DiscreteVariation wants Vector{T}
        @test P("1:5") == [1, 2, 3, 4, 5]
        @test P("0.0:0.5:1.0") == [0.0, 0.5, 1.0]
        @test P("0.0:0.5:1.0") isa Vector

        #! Whitelisted distributions
        d = P("Normal(1.0, 0.2)")
        @test d isa Normal
        @test mean(d) == 1.0
        @test P("Uniform(0, 1)") isa Uniform

        #! The allowlist is derived from Distributions.jl, not hand-listed.
        allowed = ModelManagerStudio.allowed_distribution_names()
        @test length(allowed) > 40
        for expected in ("Normal", "Uniform", "LogNormal", "Gamma", "Beta", "Weibull",
                         "Poisson", "Binomial", "Geometric", "DiscreteUniform", "Pareto")
            @test expected in allowed
        end

        #! Wrappers are concrete univariate distributions but cannot be built from numeric
        #! literals, so they must not be advertised — listing them would offer choices that
        #! always fail.
        for wrapper in ("Truncated", "Censored", "MixtureModel", "AffineDistribution",
                        "OrderStatistic", "UnivariateGMM", "Kolmogorov")
            @test !(wrapper in allowed)
            @test_throws E P("$(wrapper)(1.0, 2.0)")
        end

        #! Multivariate stays out: DistributedVariation samples with quantile(dist, u).
        for mv in ("MvNormal", "Dirichlet", "Wishart", "Multinomial")
            @test !(mv in allowed)
        end

        #! Every advertised name must come from Distributions.jl itself. `subtypes` walks all
        #! loaded modules, and Copulas.jl arrives transitively through ModelManager — without
        #! the parentmodule filter it contributed Logarithmic, PStable and Sibuya, which would
        #! make the accepted set depend on the transitive dependency graph and break the
        #! guarantee that a recorded transcript stays runnable.
        @test all(n -> isdefined(Distributions, Symbol(n)), allowed)
        for leaked in ("Logarithmic", "PStable", "Sibuya")
            @test !(leaked in allowed)
        end

        #! A newly-reachable distribution that was never in the hand-written list.
        @test P("Pareto(1.0, 2.0)") isa Pareto
        @test P("Arcsine(0.0, 1.0)") isa Arcsine

        #! Unknown names get a short message with suggestions, not a dump of all 60+.
        msg = try; P("Norml(1.0, 2.0)"); catch e; sprint(showerror, e); end
        @test occursin("Norml", msg)
        @test length(msg) < 400

        #! --- the whole point: user input is never executed ---
        #! A side-effecting expression must be rejected at parse time, not run. If `eval`
        #! were still in place, this would create the file.
        probe = joinpath(mktempdir(), "must_not_exist.txt")
        @test_throws E P("(write(\"$(escape_string(probe))\", \"x\"); [1.0])")
        @test !isfile(probe)

        #! Assignment must not reach module scope and corrupt application state.
        @test_throws E P("inputs = nothing")
        @test_throws E P("tokens_avs = []")

        #! Arbitrary calls, arithmetic, variables, indexing are all out.
        for bad in ("run(`ls`)", "rm(\"/tmp\")", "1 + 1", "2 * 3", "sqrt(4)",
                    "foo", "[1,2][1]", "Main.inputs", "exit()", "MvNormal([1.0],[1.0;;])",
                    "Normal(1.0, 0.2) * 2", "[Normal(1,2)]", "()", "[]", "",
                    "Normal(a, b)", "Normal(1.0, 0.2; check_args=false)")
            @test_throws E P(bad)
        end

        #! Two AST shapes that Meta.parse does NOT throw on, verified against Julia 1.12:
        #! semicolon-separated input becomes Expr(:toplevel, ...) and truncated input becomes
        #! Expr(:incomplete, ...). The first is the shape that would smuggle a command past a
        #! naive check, so it gets its own probe file assertion.
        probe2 = joinpath(mktempdir(), "toplevel_must_not_exist.txt")
        @test_throws E P("[1.0] ; write(\"$(escape_string(probe2))\", \"x\")")
        @test !isfile(probe2)
        @test_throws E P("1.0; 2.0")
        @test_throws E P("[1,2")
        @test_throws E P("\"unterminated")

        #! Distributions' own domain validation is surfaced, not swallowed.
        @test_throws E P("Normal(1.0, -1.0)")

        #! An empty range is a user error worth naming rather than a silent zero-run sweep.
        @test_throws E P("1.0:-0.5:2.0")

        #! Errors carry a displayable message for the GUI.
        err = try; P("wat"); catch e; e; end
        @test err isa E
        @test !isempty(sprint(showerror, err))
    end

    @testset "Unresolvable targets are refused" begin
        @test ModelManagerStudio.is_resolvable_target("config/overall/max_time")
        @test !ModelManagerStudio.is_resolvable_target("")
        @test !ModelManagerStudio.is_resolvable_target("   ")

        #! Every failure path in get_target_path must be flagged, so nothing can be mistaken
        #! for a real path downstream.
        bad = ModelManagerStudio.get_target_path("rulesets_collection", "only_one_token")
        @test !ModelManagerStudio.is_resolvable_target(bad)
        @test !ModelManagerStudio.variation_exists(bad)

        #! A nonsense config chain must also come back flagged rather than as a path.
        nonsense = ModelManagerStudio.get_target_path("config", "definitely_not_a_parameter")
        @test !ModelManagerStudio.is_resolvable_target(nonsense)

        #! And it must not be possible to build a variation from one.
        n_before = length(ModelManagerStudio.get_current_variations())
        ModelManagerStudio.create_variation(bad, "[1.0]")
        @test length(ModelManagerStudio.get_current_variations()) == n_before
    end

    @testset "Variation blocker reports why" begin
        V = ModelManagerStudio.value_spec_error
        B = ModelManagerStudio.variation_blocker

        #! Valid input is not an error.
        @test V("[1.0, 2.0]") == ""
        @test V("Normal(1.0, 0.2)") == ""
        #! Empty is incomplete, not wrong — no error before the user has typed.
        @test V("") == ""
        @test V("   ") == ""

        #! The incomplete expression from the bug report: `Cauchy(0.2,` used to be silently
        #! swallowed to stderr when the button was clicked.
        @test V("Cauchy(0.2,") != ""
        @test V("Normal(1.0, -1.0)") != ""
        @test V("run(`ls`)") != ""
        #! Never throws, whatever it is handed.
        for junk in ("", ")", "@#\$%", "1 2", "[1,2", "\"x", ";;;", "Normal(")
            @test V(junk) isa String
        end

        good = ModelManagerStudio.get_target_path("config", "overall", "max_time")
        @test B(good, "[1.0]") == ""
        #! Each blocked case names its own reason.
        @test occursin("parameter", B("", "[1.0]"))
        @test occursin("Enter a value", B(good, ""))
        @test B(good, "Cauchy(0.2,") != ""

        #! The button predicate must agree with what create_variation actually does: if the
        #! blocker is empty, creation must succeed; if not, it must refuse.
        ModelManagerStudio.clear_variations()
        @test ModelManagerStudio.create_variation(good, "[1.0]") == ""
        @test length(ModelManagerStudio.get_current_variations()) == 1

        n = length(ModelManagerStudio.get_current_variations())
        @test ModelManagerStudio.create_variation(good, "Cauchy(0.2,") != ""
        @test length(ModelManagerStudio.get_current_variations()) == n
        ModelManagerStudio.clear_variations()
    end

    @testset "Variation delete and clear" begin
        ModelManagerStudio.clear_variations()
        @test isempty(ModelManagerStudio.get_current_variations())

        t1 = ModelManagerStudio.get_target_path("config", "overall", "max_time")
        t2 = ModelManagerStudio.get_target_path("config", "overall", "dt_diffusion")
        @test ModelManagerStudio.is_resolvable_target(t1)
        @test ModelManagerStudio.is_resolvable_target(t2)

        ModelManagerStudio.create_variation(t1, "[1.0, 2.0]")
        ModelManagerStudio.create_variation(t2, "[0.01]")
        @test length(ModelManagerStudio.get_current_variations()) == 2

        @test ModelManagerStudio.delete_variation(1)
        @test length(ModelManagerStudio.get_current_variations()) == 1

        #! Out-of-range deletes are refused, not fatal — QML indices can lag the model.
        @test !ModelManagerStudio.delete_variation(99)
        @test !ModelManagerStudio.delete_variation(0)
        @test length(ModelManagerStudio.get_current_variations()) == 1

        @test ModelManagerStudio.clear_variations()
        @test isempty(ModelManagerStudio.get_current_variations())
    end

    @testset "Color scheme is never fatal" begin
        #! An unknown token used to leave `colors` undefined and throw before the window
        #! opened. It must now warn and fall back.
        withenv("STUDIO_COLOR_TOKEN" => "not-a-real-scheme") do
            colors = ModelManagerStudio.color_scheme()
            for c in values(colors)
                @test occursin(r"^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$", c)
            end
        end
        #! Unset must still work (random choice).
        withenv("STUDIO_COLOR_TOKEN" => nothing) do
            @test ModelManagerStudio.color_scheme() !== nothing
        end
        @test ModelManagerStudio.DEFAULT_COLOR_SCHEME in ModelManagerStudio.random_color_scheme_list()
    end

    @testset "Distributed variation values" begin
        #! value_string(::DistributedVariation) is the other MM.-qualified call site.
        dv = MM.DistributedVariation(:config, MM.XMLPath(["overall", "max_time"]), Normal(1.0, 2.0))
        @test ModelManagerStudio.value_string(dv) == "Normal{Float64}(1.0, 2.0)"
    end

end

#__PROBE_START__
let S = ModelManagerStudio
    function raw_order(query)
        words = S.search_words(query)
        scored = Tuple{Int,S.LeafEntry}[]
        for location in S.searchable_locations()
            for entry in S.leaf_index(location)
                rank = S.match_rank(entry, words)
                isnothing(rank) || push!(scored, (rank, entry))
            end
        end
        return scored
    end
    for query in ["default speed", "max time", "speed", "default migration", "default bias"]
        raw = raw_order(query)
        sorted = S.search_parameters(query)
        println("PROBE === query: ", repr(query), "  (", length(raw), " matches)")
        println("PROBE -- RAW (sort! deleted), first 5 --")
        for (rank, e) in first(raw, 5)
            println("PROBE    rank=", rank, "  ", e.location, ": ", join(e.chain, "/"))
        end
        println("PROBE -- SORTED (current code), first 5 --")
        for (i, l) in enumerate(first(sorted, 5))
            println("PROBE    rank=", S.match_rank(S.last_search_hits[i], S.search_words(query)), "  ", l)
        end
        if !isempty(raw)
            fr = raw[1][1]; best = minimum(t -> t[1], raw)
            println("PROBE -- raw-first-rank=", fr, " best-rank=", best, fr > best ? "   <<<< INVERSION" : "")
        end
    end
end
#__PROBE_END__
