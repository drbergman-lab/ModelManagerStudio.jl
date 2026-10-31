using ModelManagerStudio, PhysiCellModelManager, Test, QML, Distributions, LightXML
import ModelManager as MM

#! Testing mode makes the QML side call Qt.exit(0) on a timer. Without it `exec()`
#! never returns and `Pkg.test()` hangs until CI's 60-minute timeout. Set it here
#! rather than relying on the workflow env so the suite is runnable locally.
ENV["MODEL_MANAGER_STUDIO_TESTING"] = "true"

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
