# Product Requirements Document — ModelManagerStudio.jl

> Behavioral specification. Each feature states what it must do, how it must fail, and
> the edge cases that have bitten us. [README.md](README.md) tracks *whether* something is
> built; this file specifies *how it must behave*. [progress.md](progress.md) records why.

---

## Product Overview

ModelManagerStudio is a desktop GUI over ModelManager. Its user is a modeler who knows their model but does not want to look up XML paths, and who needs the resulting campaign to be reproducible without the GUI.

Three commitments shape every feature:

1. **Walk, don't name.** The user reaches a parameter by navigating the model's own structure, never by typing a path.
2. **Everything is recorded.** Every action becomes a line in a replayable `.jl` transcript. A feature that cannot be recorded is not finished.
3. **The GUI is not the source of truth.** ModelManager's database owns committed state. The GUI owns only the uncommitted design.

### Non-goals

- Editing model *files*. Studio selects and varies inputs; it does not author configs. (That is PhysiCell Studio's job, and the reason this package needs a different name.)
- Being the only interface. The transcript exists so a user can graduate to the REPL at any point.
- Live simulation visualization. That is PhysiCellDashboard's job; Studio hands it a folder.

---

## Feature: Project initialization — **implemented**

**Behavior.** `launch()` with zero, one, or two path arguments resolves to a simulator directory and a data directory, initializes ModelManager, and opens the window.

**Acceptance criteria.**
- Zero args → `./PhysiCell` and `./data`. One arg → `<arg>/PhysiCell` and `<arg>/data`. Two args → used as given. All paths normalized and absolutized.
- Initialization failure must not open a window.
- A missing project must produce an actionable message naming the two ways to fix it.

**Edge cases.**
- **Not a project.** MM's `initializeModelManager` returns `false` rather than throwing; PCMM throws `PCMMMissingProject`. Both paths must reach the user.
- **Schema migration.** MM prompts on stdin during a milestone upgrade, which freezes a windowed app. Initialization must pass `auto_upgrade=true` or the app can hang with no visible cause.
- **DB newer than the package.** `initializeModelManager` returns `false`. Surface this as "upgrade the package", not "corrupt project".
- **Diagnostics race.** `initializeModelManager` spawns a background diagnostics task that prints *after* it returns. Anything capturing stdout must fence on `waitForDiagnostics()`.

---

## Feature: Input folder selection — **implemented**

**Behavior.** Required and optional input locations are discovered from the project, each offering the folders present on disk. "Create Inputs" commits the selection to an `InputFolders`.

**Acceptance criteria.**
- Locations come from `projectLocations()`; **no location name is hardcoded** (Fixed Constraint 4).
- Optional locations offer `--NONE--`, which maps to `""`.
- A folder that supports variation is visually distinguished from one that does not (`folderIsVaried`).
- Committing writes an `inputs` block to the transcript.

**Edge cases.**
- **Re-committing.** Creating inputs a second time must invalidate variations built against the old selection. Today it does not — a variation targeting a path that no longer exists survives and fails at run time.
- **Empty location directory.** A required location with no folders must say so, not offer an empty dropdown.
- **Missing basename.** `folderIsVaried` throws `ErrorException` when no basename file exists in the folder. Must be caught and shown, not propagated through a Qt callback.

---

## Feature: Parameter browser — **implemented for PhysiCell; interface pending**

**Behavior.** After choosing a varied location, the user narrows through a chain of dropdowns until the path resolves to a single parameter, whose target path is displayed.

**Children and shortcuts.** A level offers two kinds of entry: **children**, mirroring the
document's own nesting, and **shortcuts**, surfacing a parameter where a user looks for it rather
than where the XML puts it. After choosing `motility`, `speed` belongs in the menu even though the
XML nests it outside `<options>`.

Studio does not hand-curate which shortcuts are valid. It offers both kinds and **filters by
whether the chain resolves** against the base file. A shortcut the backend cannot yet resolve
simply does not appear, and starts appearing once it can — so Studio tracks the simulator instead
of needing a patch each time the backend's path mapping changes. Branch tokens are always kept:
an intermediate chain has no target, so resolvability says nothing about it.

**Acceptance criteria.**
- The chain **terminates**: once the path bottoms out, the next call returns `String[]`.
- Every token offered *to the user* resolves to an element that exists. The raw vocabulary may
  over-offer; the filter is what makes the guarantee.
- Base documents are cached per location and freed when the input folders change. Resolvability
  filtering is per-token, so uncached parsing would make it unaffordable.
- A colon-bearing token has **exactly two** colons (`tag:attr:value`).
- Token ordering is stable across calls — document order, not hash order.
- The resolved target round-trips: `columnName(XMLPath(columnNameToXMLPath(target))) == target`.
- Every varied location is browsable, or says explicitly that it is not.
- The location is derived during the walk and **never asked of the user** — MM does not infer it, so Studio must tag it.

**Edge cases.**
- **Non-terminating chain (fixed).** Config paths bottom out at four tokens. Routing every depth past three to `config_fourth_tokens(t[1:3]...)` ignores later tokens and returns the same list forever, filling all 100 ComboBoxes and never resolving a target. Reachable via `cell_type > cycle > rate > <index>`.
- **Two-part tokens (fixed).** `retrieveElement` splits on `:` with `limit=3` and `getChildByAttribute` destructures three values, so `tag:value` raises `BoundsError` downstream.
- **Locations with no grammar.** The PhysiCell template varies `intracellular` and `ic_ecm`; neither has a token grammar. These must return `String[]` **and warn** — never `nothing`, which QML renders as a silently empty dropdown.
- **Ambiguous siblings.** When no attribute uniquely identifies siblings, the walker emits `"<tag> (ambiguous)"`. This string must never be usable as a path token.
- **Unselected location.** Walker entry points must not be called for a location whose folder is `""`; `prepareBaseFile` throws from deep inside PhysiCellXMLRules.

**Interface (target state).** The browser is defined by a small interface with a generic XML default in the core and curated implementations per backend. The interface belongs in **ModelManager**, with PCMM and BCMM implementing it — parameter metadata is a property of the simulator, not of the GUI:

```julia
struct ParamNode
    token::String     # "cell_definition:name:tumor"
    label::String     # "Tumor"
    is_leaf::Bool
    location::Symbol  # tagged during the walk
end

browsableLocations(sim)                        -> Vector{Symbol}
paramChildren(sim, loc, path::Vector{String})  -> Vector{ParamNode}
paramTarget(sim, loc, path)                    -> XMLPath
paramValue(sim, loc, path)                     -> Any
locationLabel(sim, loc)                        -> String
```

The generic default walks the location's base file and needs nothing from the backend. Curation — friendly labels, semantic grouping, the substrate/cell-type/custom-data distinction — is what a backend adds.

---

## Feature: Variation values — **implemented; parser required**

**Behavior.** The user enters a value specification for the selected target, producing an `AbstractVariation`.

**Acceptance criteria.**
- Accepts: a scalar; a bracketed vector; a range `a:b:c`; a named distribution from an allowlist.
- **Never `eval`s.** Parsing is a whitelisted AST walk. Rejections are shown inline, next to the field.
- One variation per target; re-entering a target **replaces** rather than appends.
- Every variation is deletable individually, and all are clearable.
- Each variation is recorded in the transcript as constructor code.

**Edge cases.**
- **Arbitrary code execution (open).** `Meta.parse |> eval` at module scope with `Distributions` in scope. `(run(`…`); [1.0])` is enough. Benign typos are also destructive: `inputs = nothing` corrupts application state silently.
- **Error strings as data (open).** `get_target_path` returns `"INVALID PATH"` / `"Invalid rule path: …"`. These render in the UI and flow back into variation creation, where `columnNameToXMLPath` is `split(s, "/")` and location inference falls through to `:config` — so a variation is successfully constructed from an error message and fails only at run time.
- **`parseValueFromString` is not sufficient.** MM's exported parser handles a single scalar only; ranges, vectors, and distributions are Studio's own grammar.
- **Type coercion.** `DiscreteVariation{T}` accepts `Float64`, `Int`, `Bool`, `String`. A parameter whose base value is `true` must not silently become `1.0`.

---

## Feature: Covariations — **planned**

**Behavior.** One degree of freedom drives several parameters together.

**Acceptance criteria.**
- Built through the **vector** constructors only, from an explicit `DiscreteVariation[]` or `DistributedVariation[]`.
- Discrete: the UI enforces equal value-vector lengths before calling; the library's only feedback is an `AssertionError`.
- Distributed: per-parameter priors may differ; a per-row "anti-correlated" toggle maps to `flip`.
- The UI states that a covariation costs **one** latent dimension regardless of how many parameters it drives — that is the reason to use it over N separate variations.
- Constituent locations may differ; this must not be blocked.

**Edge cases.**
- Never use the varargs constructor (requires identical concrete types) or the tuple forms.
- A covariation cannot nest — `CoVariation` is a sibling of `ElementaryVariation`, not a subtype.

---

## Feature: Latent variations — **planned**

**Behavior.** K latent dimensions map to M target parameters through user-chosen functions.

**Acceptance criteria.**
- Maps come from a **catalogue** — identity, linear `a·x+b`, exp, log, power, sum, product — not free-text code. The catalogue is what lets Studio emit *named* closures and derive correct `inverse_maps` automatically.
- All K latent parameters must be the same kind: all explicit value vectors, or all distributions. Mixing is not constructible.
- Latent names prefill from `defaultLatentParameterNames`.
- Construction runs off the UI thread: the constructor calls every map to infer types, so a malformed map throws at construction.
- The spec is persisted to a **Studio-owned file**.

**Edge cases.**
- **MM does not persist maps.** Only derived target values reach the database, so a latent design cannot be reconstructed from a project. This is the reason Studio needs its own spec file — without one, "reopen and edit my design" is impossible.
- **Anonymous maps break resume.** Calibration degrades them to `_StrippedLVSource` and cannot resume. The catalogue avoids this by construction.
- **Missing inverse maps** are accepted but silently disable `SimulationBank` reuse — a real performance cliff, so warn.

---

## Feature: Sampling methods — **planned**

**Behavior.** The user picks a design method and sees exactly what will be created before anything is written.

**Acceptance criteria.**
- All four of `GridVariation`, `LHSVariation`, `SobolVariation`, `RBDVariation`.
- A **preview table** built from `ParsedVariations` + the pure CDF generators shows the actual parameter points before any disk write.
- `n_replicates` and `use_previous` are exposed, wired to trial creation.
- `setNumberOfParallelSims` is prominent — it defaults to **1**, which silently serializes large sweeps.
- Incompatible combinations are **disabled with an explanation**, never allowed to throw.

**Edge cases.**
- Grid requires every variation discrete, and is the only method tolerating an empty list.
- LHS/Sobol/RBD error on an empty list (`nLatentDims` is a `mapreduce` with no init).
- RBD's `n` must be within 1 of a power of two when `use_sobol=true`; snap the control or set `use_sobol=false`.
- Do not expose Sobolʼ's `n_matrices` — the A/B slicing assumes exactly 2 and a user value would silently corrupt the design.
- `addVariations` is an **irreversible disk write** that `ALTER`s tables. It belongs behind an explicit button with a progress indicator, never a live form binding.

---

## Feature: Sensitivity analysis — **planned**

**Behavior.** Configure and run a MOAT, Sobolʼ, or RBD design; view indices; add quantities of interest afterwards without re-simulating.

**Acceptance criteria.**
- Live design-size estimate before launching: `n(1+d)` monads for MOAT, `n(2+f)` for Sobolʼ, `n` for RBD.
- Output functions are built against **simulation** ids — `f(simulation_id::Int)`. (MM's docs say monad ids; the code calls `f(simulation_id)` and averages per monad. The code is correct.)
- Estimator dropdowns are restricted to the documented symbols.
- Named top-level functions, never closures — labels come from `nameof(f)`, so anonymous functions render as `#123` with unstable ordering.
- "Add a QoI" calls `calculateGSA!` and does **not** re-simulate.
- Past sweeps are discoverable by the reserved `mm:method` tag.

**Edge cases.**
- **Invalid estimator symbols fail silently** to all-zero indices — the dispatch has no `else` branch. The dropdown is the only guard.
- **Three different result shapes**, no common accessor: MOAT gives row matrices needing `vec`, Sobolʼ gives plain vectors with `nothing` in every confidence slot, RBD gives a bare vector.
- **Column offsets differ per method** — MOAT's design frame has a leading `base` column, Sobolʼ's leads with `A` and `B`, RBD has none. Wrong offset mislabels every bar silently.
- `ignore_indices` is Sobolʼ-only; the other two throw. Gate the control.
- **No reader for a completed GSA.** The scheme CSV is written and never read back, and RBD additionally needs a `num_cycles` not recoverable from it.
- Variation vectors must be narrowed — `Vector{Any}` from GUI widgets is a `MethodError`.

---

## Feature: Calibration — **planned**

**Behavior.** Configure an ABC-SMC calibration, watch it converge, and resume or extend it.

**Acceptance criteria.**
- Per-field validation echoing the library's own error text, checked **before** anything is written — a malformed observed-data container currently throws *after* the calibration row and folder are created.
- Generated summary and distance functions are **named**, so unattended resume works.
- Live monitor: per-generation ε, acceptance rate, and ESS, plus the current posterior.
- The monitor **reconnects after a GUI restart**, by reading on-disk generation files and querying the reserved `mm:calibration` / `mm:generation` tags.
- Resume presented as "extend from generation N+1", where N is the number of completed generations.

**Parameter types.** Calibration currently accepts only distributed variations. **Discrete-parameter support is in flight upstream**, so the UI must treat this as a *capability check*, not a hardcoded rejection: offer discrete parameters, and gate them on whether the installed ModelManager supports them. Do not encode "discrete is impossible" anywhere.

**Edge cases.**
- Overriding the method on resume replaces it **entirely** — reload the saved settings, change one field, pass the whole thing back.
- Resume granularity is per generation; a mid-generation crash loses that generation's particles but not its simulations.
- Generation 1 drops failed particles and renormalizes, so it can hold fewer than the population size — and hard-errors if none survive.
- `progress=:auto` resolves to a progress bar only when stdout is a TTY; in a GUI it silently degrades.
- Distinguish "particles evaluated" from "simulations run" — reuse makes them differ, and only the latter costs compute.

---

## Feature: Run and progress — **implemented (blocking); non-blocking planned**

**Behavior.** Launch the campaign, show progress, allow a stop.

**Acceptance criteria.**
- The window stays responsive for the whole run.
- Progress comes from `run`'s `on_progress(:init|:step|:finish, n)` hook, marshalled through a `Channel` drained by a QML `Timer`. **Never `@emit` across threads.**
- Failure is *visible*: caught, rendered via `sprint(showerror, e)`, and the completion signal always fires.
- While a run is in flight the UI performs **zero** database reads; panes that would read are disabled with a stated reason.
- Stop is honest about its granularity.

**Edge cases.**
- **A failed run currently bricks the app.** No `try`/`catch` means the completion signal never fires and the run button stays disabled forever.
- **The transcript lies about failure.** `record_run()` writes *before* the run, so a crashed run is recorded as having happened.
- **`n_simulation_tasks` counts pending simulations**, not design size — a re-run legitimately reports far fewer.
- **No cancellation API.** Throwing a sentinel from `on_progress` propagates out of `run` (it is called inside the completion loop, whose `finally` only closes the sink DB). In-flight simulations still finish and their results are discarded.
- **Nothing reports GSA failure counts** — the sweep path discards the run's output. Capture `on_progress(:finish, n_success)` and compare against the design size.

---

## Feature: Session transcript — **implemented; ordering bug open**

**Behavior.** Every action is appended to `mms_records/<timestamp>.jl` as runnable ModelManager code.

**Acceptance criteria.**
- The generated file runs standalone in a fresh process and reproduces the same database state.
- Blocks appear in dependency order: inputs, then variations, then run.
- The file lands inside the project, not wherever the process happened to start.

**Edge cases.**
- **Out-of-order actions break reproducibility (open).** Truncation only fires when the incoming record type equals the last one, so `inputs → variation → inputs` appends a second inputs block *after* the variations, and replaying defines `inputs` after the variations built for the old one.
- `mkdir` (not `mkpath`) on a path relative to `pwd()`.
- Distributions are serialized by reflecting over fields; a distribution whose constructor argument order differs from its field order round-trips incorrectly.

---

## Feature: Analysis — **planned**

**Behavior.** Browse, filter, tag, and delete past runs.

**Acceptance criteria.**
- Bind table views by **column name**, never position — folder-column order follows `Dict` iteration.
- Pass `remove_constants=false` for a stable column set; the default drops single-valued columns, so headers change as filters narrow.
- Filter by tag and status via `findSimulationIDs`, with tag inheritance on.
- Delete shows an exact pre-count of affected simulations, monads, samplings, and trials, computed **before** the call.
- Surface provenance (git dirty, interactive) where it affects trust.

**Edge cases.**
- **Two upstream `deleteSimulations` bugs.** An empty matched set throws; passing the ID column straight from `simulationsTable` also throws, because a nullable element type never matches. Work around with `collect(skipmissing(...))` and an empty short-circuit.
- Status and datetime are not in `simulationsTable` — separate query, joined on simulation id.
- Deletion cascades and is irreversible, and DB rows go before files. On HPC, files may only be *staged* for removal.
- Never call the stdin-prompting APIs (`resetDatabase`, `deleteSimulationsByStatus`) without their bypass flags.
- Constituent membership lives in CSV files; a half-deleted project makes the `Sampling`/`Trial` constructors assert. Prefer id-level queries.
- `Monad(id; n_replicates=n)` **creates** simulations when `n` exceeds the current count. A read-only pane must always leave it at 0.

---

## Feature: Visualization — **planned**

**Behavior.** Render results through Montage, behind an extension.

**Acceptance criteria.**
- `montage` / `storyboard` return SVG strings; write them to a **content-addressed** cache file and point a QML `Image` at it. Content addressing dodges QML's URL-keyed image cache and Montage's non-clobber guard at once.
- `tableau` renders PNG for on-screen use — its heatmaps make SVG several times larger.
- A time scrubber is built from `Montage._svgFrame(spec, t)`, which composes one frame with no CairoMakie or FFMPEG.
- CairoMakie stays lazily loaded; the extension must not pull it in at startup.
- Always pass `output` explicitly — every Montage verb otherwise writes into the process's working directory.

**Edge cases.**
- The SVG backend accepts only **paths to SVG files**, never in-memory figures or PNGs.
- `montage` has no `ncols`; the grid is always `ceil(sqrt(n))`.
- Movie frames align **by index**, truncated to the shortest panel — replicates saved at different intervals misalign in time silently.
- Montage's PCMM methods default their output paths from global state; if the user can switch projects, pass paths explicitly.
- Wrap every render in `Base.disable_sigint()` if Studio is ever compiled — a Ctrl-C inside `save` sends FileIO hunting for backends an app does not ship.

---

## Decisions (resolved)

1. **Core depends on ModelManager only**; PhysiCell reaches the GUI through an extension.
2. **The parameter-browser interface belongs in ModelManager**, implemented by the backends. Ship it in Studio first with MM-shaped signatures, then promote as a file move.
3. **Stay on QML.jl** for now; the deciding factor for a browser front end is remote/HPC use, not aesthetics.
4. **Montage plots reach the GUI as files**, not in-memory objects.
5. **Ship through BergmanLabRegistry**; General registration is a stack-wide project.
6. **Value expressions are parsed, never evaluated.**

## Still open

- **Package name.** "Studio" collides with PhysiCell Studio, which PCMM's own `runStudio()` launches. See [progress.md](progress.md).
- **Where the uncommitted design is persisted** — a TOML spec file beside the transcript, or an extension of the transcript itself.
- **Whether the transcript and the design spec are one artifact or two.** One file is simpler; two lets the design be edited without rewriting history.
- **Windows support.** Currently untested and unclaimed.
