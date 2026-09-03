# progress.md — ModelManagerStudio Session Journal

> **Purpose:** Session-level decisions, rejected approaches, and open questions.
> Unlike [PRD.md](PRD.md) (specification) and [README.md](README.md) (completion status), this
> file captures the *reasoning* behind decisions — things that would otherwise exist only in
> ended chat history.

---

## 2026-08-24 — Migration onto the split stack; deploy-readiness audit

### Context

Studio was written before ModelManager existed, against a much earlier PhysiCellModelManager. The goal of this session was to scope making it framework-agnostic (built on MM, with PCMM arriving via an extension) and deploy-ready, and to fix whatever was cheap and verifiable along the way.

Read in full: MM 0.8.4 (`variations.jl`, `sensitivity.jl`, `calibration/*`, `database.jl`, `tags.jl`, `classes.jl`, `runner.jl`, `globals.jl`, `project_configuration.jl`, `abstract_simulator.jl`), PCMM 0.3.3, Montage 0.2.0, BergiCellModelManager 0.1.0, PhysiCellDashboard 0.2.0, and Studio's own 619 Julia + 1044 QML lines.

Created: CLAUDE.md, PRD.md, progress.md (this file). Rewrote README.md.

---

### Finding: Studio was never on ModelManager at all

`Project.toml` pinned `PhysiCellModelManager = "0.2"`. Checking the registry's `Deps.toml`, `ModelManager` appears only in the `["0.3-0"]` block — **PCMM gained its MM dependency at 0.3.0**. So Studio was sitting on the pre-split monolith, and "make it framework-agnostic" started one step earlier than expected.

Bumping to `PhysiCellModelManager = "0.3"` resolves to PCMM 0.3.3 + MM 0.8.4 and precompiles cleanly. That looked free.

---

### Key decision: `import ModelManager as MM` rather than reaching through PCMM

**The problem the bump exposed.** With PCMM 0.3, `PhysiCellModelManager.variationTarget` is an `UndefVarError`. PCMM does `@reexport using ModelManager`, which forwards **exported** names only — and `variationTarget` / `variationValues` are not exported by MM. Studio called them in three places.

It compiles fine, because the call sites are inside function bodies. Nothing in the then-38-test suite ever executed the variation path, so the break was invisible. Verified directly:

```
variationTarget    PCMM.false  MM.true   MM-exported:false
variationValues    PCMM.false  MM.true   MM-exported:false
columnName         PCMM.true   MM.true   MM-exported:true
```

**Options considered.**

1. **Qualify as `PhysiCellModelManager.ModelManager.variationTarget`.** Works on 0.3, but reaches through a re-export chain and would break again on any PCMM restructure.
2. **Ask MM to export them.** Correct long-term, but gates Studio on an MM release.
3. **Add `ModelManager` as a direct dependency (chosen).** One line in `Project.toml`, no upstream coordination.

**Decision:** option 3, with `import ModelManager as MM`. The unexpected benefit is that the **prefix becomes the boundary marker**: everything reached as `MM.` is generic, everything still reached as `PhysiCellModelManager.` is PhysiCell-specific and therefore unfinished extension work. That makes migration progress `grep`-able, which is now the Phase 1 exit criterion in CLAUDE.md.

Still worth asking upstream to promote both names to public — a GUI depending on unexported symbols is a standing hazard, as this demonstrated.

---

### Key decision: pin the Qt Quick Controls style to `Basic`

**The bug.** Running the suite against PCMM 0.3.3 on macOS got through `createProject()`, the PhysiCell clone, and PCMM init, then died:

```
[12298] signal 11 (2): Segmentation fault: 11
objc_msgSend                                → libobjc.A.dylib
QQC2::QMacStylePrivate::drawNSViewInRect(…)  → libqtquickcontrols2nativestyleplugin
QQC2::QMacStyle::drawComplexControl(…)
```

Qt Quick Controls selects the macOS **NativeStyle** plugin and crashes inside it drawing a ComboBox. Two things worth recording:

- **`QT_QPA_PLATFORM=offscreen` does not protect against this.** The platform plugin and the controls style are chosen independently. CI sets the former and would still have crashed — if CI ran on macOS.
- **CI is `ubuntu-latest` only**, so a desktop GUI whose likeliest user platform is macOS had zero coverage of it. This is the class of defect a single-platform matrix cannot catch, and it was live in `main`.

**Options considered.** A `qtquickcontrols2.conf` beside the QML (the Qt-native route, but resolution depends on the executable's location — fragile under an app bundle); documenting an env var (puts a segfault on the user); or setting it in `launch()`.

**Decision:** `get!(ENV, "QT_QUICK_CONTROLS_STYLE", "Basic")` in `init_model_manager_gui`, before `loadqml`. `get!` so an explicit user choice still wins. `Basic` also happens to be the style that honors the custom `background` Rectangles this GUI already defines, so appearance is unchanged — the native style was never being respected visually anyway.

---

### Key decision: fix the token-chain non-termination by returning empty, not by deepening the cascade

**The bug.** `get_tokens` routed every `config` case with more than two prior tokens to `config_fourth_tokens(previous_tokens[1:3]...)`, ignoring everything past the third. So after selecting `cell_type > cycle > rate > 0`, the next call passed the *same* three tokens and returned the same phase-index list — forever. The QML cascade filled all 100 ComboBoxes with identical lists, ran the repeater off its end, and never set the flag that resolves the target. Fully reachable from the UI, and the same for `initial_parameter_distribution`.

**Options considered.**

1. **Extend the cascade to a fifth/sixth token function.** Treats the symptom, and the cascade is exactly the hardcoded PhysiCell vocabulary we are trying to delete.
2. **Replace the cascade with a generic XML walk (chosen shape, deferred).** The right end state, but config tokens are *semantic* (`max_time`, a cell-type name), not XML tags — the walk has to run from `configPath(tokens...)`, not from the tokens directly. That belongs with the parameter-browser interface work.
3. **Return `String[]` past the known depth (chosen now).** Config paths bottom out at four tokens; every depth past that is terminal.

**Decision:** option 3 now, option 2 as the interface work. Verified that depth 4 really is terminal for both reachable branches, and that the non-`cycle` branches already terminated correctly (they fall through to an empty list).

While there, the `else` for unknown locations now returns `String[]` **and warns**, instead of returning `nothing`. That does not make `intracellular` or `ic_ecm` browsable — they need a grammar — but it converts a silent empty dropdown into a diagnosable one.

---

### Key decision: three-part tokens, and unit-test the walker directly

`get_next_xml_path_elements` emitted `"tag:value"` in its multi-child branch while the single-child branch above it emitted `"tag:attr:value"`. MM's `retrieveElement` splits a token on `:` with `limit=3` and `getChildByAttribute` destructures exactly three values, so the two-part form raises a `BoundsError` once the path is resolved. Fixed to three parts.

Also replaced the untyped `Dict()` with an ordered grouping — Dict iteration order is unspecified, so ComboBox ordering varied between runs.

**Testing note worth generalizing.** My first attempt tested this through `get_ruled_behaviors`, which failed — not because the fix was wrong, but because the template project has no rulesets folder selected, so `prepareBaseFile` threw from inside PhysiCellXMLRules. `get_next_xml_path_elements` is a **pure function**, so it is now unit-tested against a hand-built `XMLDocument`. That cannot be derailed by which optional folders happen to be selected, and it tests the actual invariant. This is now the recommended pattern in CLAUDE.md: prefer unit tests on pure functions over tests that drive the GUI through project state.

---

### Finding: the test suite could not run locally, and the gaps were exactly where the coupling was

`runtests.jl` calls `launch()` but never set `MODEL_MANAGER_STUDIO_TESTING` — it relied on a step `env:` in `CI.yml`. Locally, the QML exit timer never fires, `exec()` never returns, and `Pkg.test()` hangs until CI's 60-minute timeout. Now set in the test file itself.

The colors testset also assigned `ENV["STUDIO_COLOR_TOKEN"]` without restoring it, leaking into everything after. Now `withenv`.

The deeper point: the untested regions were not random. `create_variation`, `find_variation_index`, `record_variations`, `record_run`, and both `value_string` methods had **zero** coverage — and those are precisely the functions that reached into PCMM internals. Test count went 38 → 67, and the new cases are the ones that would have caught this session's breaks.

---

### Key decision: the parameter-browser interface belongs in ModelManager

**The question.** Does the interface live in Studio (with a Studio extension holding PhysiCell knowledge), or in MM (with PCMM implementing it)?

**What made this decidable.** I expected a generic browser to *require* each backend publishing a curated token tree, which would have made the extension a prerequisite. It does not. MM's `recurseToGetParameterValues!` already walks a base XML generically, using the same `tag:attr:value` disambiguation the browser needs, and `getAllParameterValues` returns a frame whose column names *are* `columnName(xp)`. Walking each varied location's base file yields a complete tree with no backend cooperation at all.

BergiCellModelManager confirmed the XML assumption generalizes: it is a second MM backend and also XML-driven, reusing MM's `XMLPath`/`columnName` verbatim. What differs is only the **location names** — four (`config`, `custom_code`, `rulesets`, `ic_cells`) against PCMM's eight, with different spellings for shared concepts (`rulesets` vs `rulesets_collection`, `ic_cells` vs `ic_cell`). Studio hardcodes PCMM's spellings today, which is exactly the bug the interface removes. (BCMM is stale against MM 0.8 — it calls `markSimulationComplete`, which no longer exists, and has an arity mismatch on `resolveSimulatorVersionID` — so treat it as a design specimen, not a runtime target.)

**Decision:** the interface belongs in **ModelManager**, implemented by the backends, because what parameters exist and what they are called is simulator metadata, not GUI code — and there it serves any front end, not just Studio. But shipping it there first would gate progress on coordinated MM and PCMM releases. So: define and implement it in Studio now, with signatures written exactly as they should appear in MM, and promote later as a file move rather than a redesign.

---

### Decision: design for discrete calibration parameters, don't preclude them

Calibration's parameter layer currently accepts only distributed variations and throws `ArgumentError` on discrete ones. The obvious UI move — hardcode "discrete not allowed" — would have to be undone, because **discrete-parameter support is in flight upstream**.

**Decision:** treat parameter-type support as a **capability check** rather than a fixed rule. Offer discrete parameters in the calibration UI and gate them on what the installed ModelManager supports. Nothing in Studio should assert that discrete is impossible.

---

### Finding: cancellation can be masked in Studio; no MM change needed

The roadmap initially listed a cooperative `should_stop` kwarg on `run(::AbstractTrial)` as a cross-repo ask. Reading `runner.jl` more carefully, that turns out to be avoidable.

`on_progress(:step, 1)` is called from inside the completion loop, and that loop's `try` has a `finally` that only closes the sink DB — it does not swallow exceptions. So **throwing a sentinel from `on_progress` propagates straight out of `run`**. Studio can implement Stop entirely on its own side: pass an `on_progress` that checks a flag and throws `StudioCancelled()`, then catch it.

Limits to be honest about in the UI:
- In-flight simulations still run to completion; their results are discarded (the code comments say so explicitly).
- It cancels *between* simulations, not during one.
- The same trick via `post_processor` would only fire after *successful* simulations, so `on_progress` is the better hook.

`should_stop` would still be cleaner — a cooperative flag rather than an exception used for control flow — but it is a nicety, not a blocker. Downgraded from "ask" to "suggestion".

---

### Decision: Montage plots reach the GUI as files

Settled by prior art rather than argument. PhysiCellDashboard already does exactly this: one `Montage.tableau(snap; size, output=path, overwrite=true)` call writing a PNG into a `mktempdir()`, with `if !isfile(path)` as the entire cache lookup and the filename keyed by `(index, width, height)`.

The in-memory route exists and was deliberately **not** taken — `tableau(…; output=nothing)` returns a live Makie `Figure`, and `montage`/`storyboard` return SVG strings directly. The file route bought the size-keyed cache for free.

For QML this translates almost unchanged: swap the HTTP response for `Image { source: "file:///…" }`. Two refinements for Studio's case: **content-address** the filenames, which dodges QML's URL-keyed image cache and Montage's non-clobber guard in one move; and build any scrubber from `Montage._svgFrame(spec, t)`, which composes one frame's SVG with no CairoMakie, Rsvg, Cairo, or FFMPEG involved.

**Not merging with PhysiCellDashboard.** It would drag Makie into Studio's graph (its own build notes measure hundreds of MB and a CI link step that OOM-killed on Linux runners), and it requires `julia = "1.12"` while QML.jl pins Studio to 1.10. Integrate by handing it an output folder or spawning its binary.

---

### Open: package name

**The problem.** "Studio" already means [PhysiCell Studio](https://github.com/PhysiCell-Tools/PhysiCell-Studio) in this ecosystem, and PCMM's own public API has `runStudio()` — which launches *that* tool. So within one ecosystem, `runStudio` and `ModelManagerStudio` refer to unrelated things. Also, the GUI's window title is currently hardcoded `"PhysiCellModelManager.jl GUI"`, which is wrong on both counts already.

**Why now.** Renaming means a new name and UUID in BergmanLabRegistry regardless of when it happens. Pre-0.1.0, in a private registry, with no external users, is the cheapest moment there will ever be.

**Candidates.** House naming runs two ways: descriptive compounds (`PhysiCellModelManager`, `BergiCellModelManager`) and single evocative nouns (`Montage`, `Smore`). `Montage` is the strongest name in the set because it names what the thing does, which argues for the second mode.

- **`Cockpit.jl`** — the place you launch from, watch instruments, and steer a long campaign. Plain-English noun, pairs with `Montage`, no collision found in Julia or the ecosystem, and it survives the framework-agnostic goal (nothing in it says PhysiCell or even ModelManager).
- `Vernier.jl` — the precision-adjustment scale on an instrument; right register, mild collision with Vernier Software.
- `ModelManagerGUI.jl` — zero ambiguity, self-documenting, boring, and ages badly if a browser front end lands.

**Status:** maintainer's call. Docs are written under the current name, so a rename is a find-and-replace plus a registry entry.

---

### Cross-repo asks

Collected here rather than acted on — MM and PCMM are read-only boundaries from this repo.

**ModelManager**
- Fix `deleteSimulations` with an empty matched set — throws `MethodError` on `_deletePostProcessingRows` because an empty SQLite result gives a `Union{Missing,Int64}` element type.
- Fix `deleteSimulations(df.SimID)` — the documented call, straight from `simulationsTable`, throws for the same nullable-eltype reason. `filter!` does not narrow the element type.
- Promote `variationTarget`, `variationValues`, and `variationLocation` to public.
- Promote the GSA plot-data builders (`_moatBarData` and friends) and the `_GSA*Data` structs to public — they are exactly right for a Makie renderer, being plain names plus `Float64` vectors with no Plots dependency.
- Add a reader for a completed GSA. The scheme CSV is written and never read back, and `RBDSampling` needs a `num_cycles` not recoverable from it.
- Correct the sensitivity docs: output functions are called as `f(simulation_id)`, not `f(monad_id)`.
- Correct the sensitivity docs' claim that the plot recipes work with Makie backends — RecipesBase is consumed by Plots.
- Consider a cooperative `should_stop` kwarg on `run(::AbstractTrial)`. Not blocking; Studio can throw from `on_progress`.
- Guard against invalid `sobol_index_methods` symbols — the dispatch has no `else`, so a typo yields all-zero indices silently.

**PhysiCellModelManager**
- Implement the parameter-browser interface once it lands in MM, moving the curated vocabulary out of Studio's extension.
- Consider renaming `runStudio` — it launches PhysiCell Studio, which will read as this package's own launcher to anyone using both.
- `prepareBaseFile` on an unselected (`""`) input folder throws an `AssertionError` from deep inside PhysiCellXMLRules. A typed, catchable error naming the location would be friendlier to any GUI.

---

### Session summary

Changed: `Project.toml`, `src/ModelManagerStudio.jl`, `src/record.jl`, `test/runtests.jl`; added `CLAUDE.md`, `PRD.md`, `progress.md`; rewrote `README.md`.

Verified on Julia 1.12.7 / macOS arm64: resolves to PCMM 0.3.3 + MM 0.8.4, precompiles clean, **67/67 tests pass** (was 38), no segfault, no external environment variables required.

Not addressed, and still the top blockers: the `eval` of user input, the absent error surface, the blocking run, and error strings flowing into variation targets. See [README.md](README.md) Implementation Status.
