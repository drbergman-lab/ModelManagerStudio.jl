# CLAUDE.md — ModelManagerStudio.jl

## About the User
Assistant professor working on computational modeling of cancer-immune interactions, mechanistic modeling, and agent-based modeling (ABM) frameworks. ModelManagerStudio is the desktop GUI in this ecosystem, alongside [ModelManager.jl](https://github.com/drbergman-lab/ModelManager.jl) (MM), [PhysiCellModelManager.jl](https://github.com/drbergman-lab/PhysiCellModelManager.jl) (PCMM), and [Montage.jl](https://github.com/drbergman-lab/Montage.jl).

## Key Documents — Read These First

| Document | Purpose |
|----------|---------|
| [README.md](README.md) | Project overview + **Implementation Status** (what is built, what remains) |
| [PRD.md](PRD.md) | Behavioral specification for every feature — acceptance criteria and edge cases |
| [progress.md](progress.md) | Session journal: decisions made, approaches rejected, open questions |

Start any feature session by reading the relevant PRD entry and the Implementation Status section of `README.md`.

## Project Overview
ModelManagerStudio is a QML.jl/Qt desktop GUI over ModelManager. It exists to remove one specific friction: setting up a simulation campaign requires naming parameters by their XML path, which is tedious to look up and easy to get wrong. The GUI lets the user *walk* to a parameter through the model's own structure instead.

Three things it does, in order of importance:

1. **Browse to a parameter and vary it** — a cascading token chain resolves to an `XMLPath`, which becomes an `AbstractVariation`.
2. **Record a replayable transcript** — every action is written to `mms_records/<timestamp>.jl` as ordinary ModelManager code. This is the anti-lock-in guarantee: the GUI writes scripts, it does not replace them.
3. **Launch and monitor campaigns** — runs, sweeps, sensitivity analyses, calibrations.

**Status: mid-migration.** The GUI works for the simple case (pick folders → browse → vary → run) but is hardwired to PhysiCell, blocks its own UI during a run, and has no error surface. See [README.md](README.md) Implementation Status.

## Fixed Constraints (decided — do not relitigate)
1. **The core depends on `ModelManager` only.** `PhysiCellModelManager` moves to `[weakdeps]`; PhysiCell knowledge reaches the GUI through a package extension. `ModelManager` is imported as `import ModelManager as MM`, and the `MM.` vs `PhysiCellModelManager.` prefix **is** the boundary marker — anything still qualified with the latter is unfinished extension work and is greppable as such.
2. **The transcript is not optional.** Any feature reachable from the GUI must be expressible in the recorded script. If an action cannot be recorded, the feature is not done.
3. **The GUI never becomes the source of truth.** ModelManager's database and `inputs.toml` own project state. The GUI holds only the in-progress design that has not been committed to disk yet — and that design lives in a Studio-owned spec file, because MM does not persist `LatentVariation` maps.
4. **No location names hardcoded.** Locations come from `projectLocations()` / `inputsDict()`. PCMM has eight; BergiCellModelManager has four with different spellings (`rulesets` vs `rulesets_collection`, `ic_cells` vs `ic_cell`). Any literal `"config"` / `"ic_cell"` outside the extension is a bug.
5. **User input is never `eval`ed.** Value expressions are parsed against a whitelisted AST. `Meta.parse |> eval` at module scope was the original implementation; it is arbitrary code execution and it also blocks any future `juliac` compilation.

## Relationship to MM and PCMM
Both are read-only boundaries from this repo. Do **not** edit files under `~/.julia/dev/ModelManager/` or `~/.julia/dev/PhysiCellModelManager/` in a Studio session — collect the needed changes as bullets for the maintainer instead (see [progress.md](progress.md), "Cross-repo asks").

Two traps worth knowing:
- PCMM `@reexport using ModelManager`, so MM's **exported** names resolve as `PhysiCellModelManager.x`. Unexported ones do not. `variationTarget` and `variationValues` are unexported, so reaching them through PCMM is an `UndefVarError` on PCMM ≥ 0.3 — it compiles fine and fails at runtime.
- PCMM only gained its `ModelManager` dependency at **0.3.0**. Anything pinned to PCMM 0.2 is on the pre-split monolith and has no MM at all.

## Scope
All work stays inside this repository (`~/.julia/dev/ModelManagerStudio/`). MM, PCMM, Montage, BergiCellModelManager, and PhysiCellDashboard are read-only references.

## Git Workflow
Claude Code runs directly on the machine and can run any git operation. The boundaries below keep `main` and anything outward-facing under explicit human control while removing friction from local, reversible work.

**Pre-authorized (no prompt needed):**
- Create and switch feature branches when starting work. Branch from `main` unless told otherwise; name `feature/<short-desc>`.
- Read-only inspection (`git status`/`diff`/`log`/`show`).
- Delete a feature branch once it has been merged into `main`.

**Commit procedure (the gate is *diff review*, not a command confirmation):**
1. When a change is ready, present it for review — a `git diff` and/or a short summary.
2. Wait for the user to confirm they've reviewed it.
3. Once reviewed, write the commit message and commit directly. End messages with the `Co-Authored-By: Claude Opus 5` trailer.
- Never commit before the user has reviewed the diff.

**Requires explicit request:**
- **Merging to `main`** — `main` is the integration gate. Prefer `--ff-only`. Delete the merged branch after.

**Never:**
- Modify `main` directly for feature work.
- Push or publish without an explicit yes.

## Naming Conventions
Consistent with ModelManager.jl / the PhysiCell ecosystem:
- **Functions:** `camelCase` for anything mirroring an MM/PCMM API.
- **QML-facing functions:** `snake_case` (e.g. `get_next_model`, `create_variation`) — these are called from QML as `Julia.get_next_model(...)`, and the existing surface is snake_case. Keep it consistent rather than mixed.
- **Internal helpers:** `_camelCase`.
- **Types / Structs:** `PascalCase`.
- **Files:** `snake_case.jl`.
- **Comments:** `#!` for explanatory comments that should survive (matching MM/PCMM house style); `#` for ordinary ones.

## Required Workflow for Any Change
1. Produce a **design brief** in the assistant response **before any code changes**; wait for human approval.
2. On approval: update [PRD.md](PRD.md) with the new/changed feature, and open a new [progress.md](progress.md) entry.
3. Create the feature branch and implement there.
4. Update the [README.md](README.md) Implementation Status when a feature is complete.
5. Trim PRD.md and progress.md to reflect the final implementation.
6. Present the diff for review; commit once reviewed. Merge to `main` only on explicit request.

**Design brief template:**
```
# Design Brief: [Feature/Refactor Name]
## Motivation      — why this is needed / what it solves
## Scope           — files affected, new files, breaking changes
## Proposed Architecture — current vs proposed, key decisions vs alternatives
## Testing Strategy — unit + integration
## Estimated Effort — LOC, risk level, dependencies
```

## Definition of Done
A feature is complete when **all** are true:
1. **Tests pass:** `julia --project=. -e 'using Pkg; Pkg.test()'` runs green — locally, not only in CI.
2. **Recorded in the transcript:** the action appears in `mms_records/` output as runnable code (Fixed Constraint 2).
3. **Docstrings written:** every exported and every QML-facing function has a docstring.
4. **README updated:** Implementation Status marks the feature complete.
5. **PRD reflects reality.**
6. **No regressions.**

## Studio-Specific Guidance

### Testing a GUI headlessly
The suite calls `launch()`, which blocks in `exec()` until the QML side calls `Qt.exit(0)` on a timer gated by `MODEL_MANAGER_STUDIO_TESTING`. `runtests.jl` sets that variable itself — do not remove it, or `Pkg.test()` hangs until CI's 60-minute timeout.

Prefer **unit tests on pure functions** over tests that drive the GUI through project state. `get_next_xml_path_elements` is tested against a hand-built `XMLDocument`, which is why it cannot be derailed by which optional input folders happen to be selected. Reach for that pattern first.

Set `QT_FATAL_WARNINGS=1` in CI so binding loops, conflicting anchors, unknown properties, and QML JS errors fail the build instead of scrolling past.

### Qt specifics
- **The style is pinned to `Basic`** in `init_model_manager_gui`. The macOS `NativeStyle` plugin segfaults inside `QMacStyle::drawComplexControl` drawing a ComboBox. `QT_QPA_PLATFORM=offscreen` does **not** protect against this — the platform plugin and the controls style are chosen independently.
- QML.jl ships **Qt6** via `jlqml_jll`. Any `apt-get install qtbase5-dev …` in CI is wrong-version dead weight.
- The QML file is resolved as `joinpath(@__DIR__, "..", "assets", …)`, which does not exist under PackageCompiler `create_app`. Making this relocatable is a prerequisite for any app bundle.

### Token chains
A token chain must **terminate**. `get_tokens` returns `String[]` when the path bottoms out; returning a non-empty list at every depth makes the QML repeater fill all 100 ComboBoxes with the same values and never resolve a target. Config paths bottom out at four tokens.

Tokens carrying a colon must have **exactly two** colons (`tag:attr:value`). MM's `retrieveElement` splits on `:` with `limit=3` and `getChildByAttribute` destructures three values, so a two-part token raises a `BoundsError` once the path is resolved.

### XML documents
`parse_file` allocates a libxml2 document that must be `free`d. MM's own `xml_utilities.jl` does this; Studio historically did not, and the QML delegate re-parsed the config once per item binding. Cache model vocabulary in Julia per `inputs` change; never read XML from a QML property binding.

## Julia Environment Rules
- Always run Julia with `--project=.`
- Preferred test command: `julia --project=. -e 'using Pkg; Pkg.test()'`
- Do not edit `Manifest.toml` or add dependencies without explicit approval. `PhysiCellModelManager` belongs in `[weakdeps]` with a matching `[extensions]` entry once the migration lands — not `[deps]`.

## Environment Facts
- Julia 1.12.7 in the dev env; template `[compat] julia = "1.10"`.
- **`src/main.jl` is gated on `VERSION >= v"1.11"`**, so on the LTS the package claims to support there is no `main` entrypoint at all.
- QML.jl v0.11.0 → `jlqml_jll` 0.8.0 (Qt6). Newer QML.jl exists (0.13.x); bumping is a separate commit.
- MM v0.8.4, PCMM v0.3.3, Montage v0.2.0.
- The package is registered in **BergmanLabRegistry**, not General — and neither is PCMM or MM, so General registration is a stack-wide project, not a Studio one.
- Sibling repos for reference: `~/.julia/dev/{ModelManager,PhysiCellModelManager,Montage,BergiCellModelManager,PhysiCellDashboard}`.

## To-dos
See [README.md](README.md) Implementation Status for the feature-by-feature record and [progress.md](progress.md) for open decisions. The near-term sequence:

1. **Framework-agnostic core** — define the parameter-browser interface, implement the generic XML default, move PhysiCell knowledge into `ext/`. Target: `grep -ri physicell src/ assets/` returns nothing outside `ext/`.
2. **Error surface + non-blocking run** — a log pane fed by a captured logger, `run` on a worker task with `on_progress` marshalled through a `Channel` drained by a QML `Timer`. Never `@emit` across threads.
3. **Typed value editor** — replace `Meta.parse |> eval` with a whitelisted AST parser, and add per-row variation delete (today variations can only accumulate).
4. **Component library + view models** — split the 1044-line QML file; move token-chain and target-resolution state into Julia-owned `Observables` so QML holds no snapshots.
5. **Variations completeness** → **analysis/visualization** → **sensitivity/calibration**.

### Decided against (do not relitigate)
- **Rewriting on a browser front end now.** QML.jl already supports the whole reactive redesign (`JuliaPropertyMap` connects `Observables`, `JuliaItemModel` exposes mutation, `exec_async()` exists), and it ships its own Qt so users install nothing. The current imperative-JS design is a choice, not a constraint. Revisit only if remote/HPC-login use becomes a real requirement, where a browser UI needs a port-forward and Qt over X11 does not work well. The view-model extraction pays off under either outcome, so it comes first regardless.
- **Depending on PhysiCellDashboard.** It drags Makie/CairoMakie into Studio's dependency graph and requires `julia = "1.12"` while QML.jl pins Studio to 1.10. Integrate by handing it an output folder (or spawning its binary), not by adding a dependency.
- **A `:makie` backend for Montage's `montage`/`storyboard`.** Declined upstream; those verbs are SVG-only. Get SVG strings and hand them to a QML `Image`.
- **PackageCompiler as the primary distribution route.** Blocked by the non-relocatable QML path, and on macOS needs a signed and notarized `.app` before anyone else can open it. Keep it possible; do not make it the plan.
