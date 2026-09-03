# ModelManagerStudio

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://drbergman-lab.github.io/ModelManagerStudio.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://drbergman-lab.github.io/ModelManagerStudio.jl/dev/)
[![Build Status](https://github.com/drbergman-lab/ModelManagerStudio.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/drbergman-lab/ModelManagerStudio.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/drbergman-lab/ModelManagerStudio.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/drbergman-lab/ModelManagerStudio.jl)

A desktop GUI for [ModelManager.jl](https://github.com/drbergman-lab/ModelManager.jl) — set up parameter variations, launch simulation campaigns, and browse what came back, without writing the script yourself.

> **Naming:** this package is likely to be renamed before 0.1.0. "Studio" already means
> [PhysiCell Studio](https://github.com/PhysiCell-Tools/PhysiCell-Studio) in this ecosystem — and
> PhysiCellModelManager's own `runStudio()` launches *that* tool, not this one. See
> [progress.md](progress.md), "Open: package name".

## What it does

Every simulation campaign starts the same way: choose input folders, decide which parameters to vary and over what range, then run. Doing that from the REPL means remembering the exact XML path to a parameter you can see perfectly well in a config file. This GUI lets you walk to the parameter instead of naming it, and writes the script for you as you go.

| You want to… | The GUI gives you |
|---|---|
| find a parameter without knowing its XML path | a cascading browser over the model's own structure |
| vary it | a value editor for discrete sets, ranges, and distributions |
| run the campaign | a run button, with the project's parallelism settings honored |
| reproduce the session later | a replayable `.jl` transcript written as you work |

**The transcript is the feature that matters most.** Everything you do in the GUI is recorded to `mms_records/<timestamp>.jl` as ordinary ModelManager code. The GUI is a way to *write* a script, not a replacement for one — so nothing you do in it becomes unreproducible, and there is no lock-in.

## Framework support

ModelManagerStudio targets `ModelManager` itself, so it is not specific to any one simulator. Simulator-specific knowledge — which parameters exist, what they are called, how they are grouped — reaches the GUI through a package extension.

| Backend | Status |
|---|---|
| [PhysiCellModelManager.jl](https://github.com/drbergman-lab/PhysiCellModelManager.jl) (PCMM) | supported |
| Any other `ModelManager.AbstractSimulator` | generic parameter browser only, no curated labels yet |

## Installation

ModelManagerStudio and its dependencies live in **BergmanLabRegistry**, not the General registry. Add the registry once:

```julia
import Pkg
Pkg.Registry.add("General")
Pkg.Registry.add(Pkg.RegistrySpec(url="https://github.com/drbergman-lab/BergmanLabRegistry.git"))
```

Then, from a dedicated project environment:

```julia
import Pkg
Pkg.activate("my-project")
Pkg.add("ModelManagerStudio")
```

Qt comes with the package — QML.jl ships its own Qt6 through `jlqml_jll`, so there is no system Qt to install.

### Running it

```julia
using ModelManagerStudio
launch()                                    # uses ./PhysiCell and ./data
launch("path/to/project")                   # uses <project>/PhysiCell and <project>/data
launch("path/to/PhysiCell", "path/to/data") # explicit
```

You need an existing project. To make one, see PhysiCellModelManager's `createProject()`.

### Environment variables

| Variable | Effect |
|---|---|
| `QT_QUICK_CONTROLS_STYLE` | Qt Quick Controls style. Defaults to `Basic`, which the GUI sets itself — the macOS `NativeStyle` plugin segfaults drawing a ComboBox. Override only if you know you want to. |
| `STUDIO_COLOR_TOKEN` | Pick the color scheme instead of getting a random one. One of `dodgers`, `michigan`, `orioles`, `ravens`, `angels`, `umb`, `hopkins`, `csulb`, `uci`. |
| `MODEL_MANAGER_STUDIO_TESTING` | When `true`, the window closes itself on a timer. For CI; not useful interactively. |

## Implementation Status

### Completed

- **Input folder selection** — required and optional locations discovered generically from the project's `inputs.toml`; no location names hardcoded in the GUI.
- **Parameter browser (PhysiCell)** — cascading token chain over `config`, `rulesets_collection`, and `ic_cell`, with substrate / cell-type / custom-data names read live from the model.
- **Variations** — discrete value sets, ranges, and (via the value expression) distributions. One variation per target, editable in place.
- **Run** — launches the campaign through `ModelManager.run`.
- **Session transcript** — replayable `.jl` script written to `mms_records/`.
- **PCMM 0.3 / ModelManager 0.8** — runs on the split stack, with `ModelManager` as a direct dependency.

### In progress

- **Framework-agnostic core** — moving PhysiCell parameter knowledge behind an extension point so the core depends only on `ModelManager`. Roughly 290 of 619 Julia lines are PhysiCell-specific today.
- **Error surface** — the GUI currently reports failures only to stdout/stderr, so it is usable only when launched from a terminal.
- **Non-blocking run** — `run` is called on the UI thread, so the window freezes for the duration of a campaign. `ModelManager.run`'s `on_progress` hook is the intended fix.

### Planned

- **Covariations and latent variations** — `CoVariation` and `LatentVariation` are fully supported by ModelManager but unreachable from the GUI.
- **Sampling methods** — `GridVariation`, `LHSVariation`, `SobolVariation`, `RBDVariation`, with a preview of the exact parameter points before anything is written to disk.
- **Sensitivity analysis** — MOAT, Sobolʼ, and RBD designs, with results rendered per method.
- **Calibration** — ABC-SMC setup, a live per-generation convergence view, and resume.
- **Analysis** — browse, filter, and tag past runs from the project database.
- **Visualization** — via [Montage.jl](https://github.com/drbergman-lab/Montage.jl), behind an extension.
- **Parameter grammar for every varied location** — `intracellular` and `ic_ecm` are varied by the PhysiCell template but have no browser yet.

See [PRD.md](PRD.md) for the behavioral spec and [progress.md](progress.md) for design rationale.

## Related packages

| Package | Role |
|---|---|
| [ModelManager.jl](https://github.com/drbergman-lab/ModelManager.jl) | Simulator-agnostic campaign management: variations, sampling, sensitivity, calibration, provenance |
| [PhysiCellModelManager.jl](https://github.com/drbergman-lab/PhysiCellModelManager.jl) | PhysiCell backend for ModelManager |
| [Montage.jl](https://github.com/drbergman-lab/Montage.jl) | Composite figures and movies — `montage`, `storyboard`, `tableau` |
| [PhysiCellDashboard.jl](https://github.com/drbergman-lab/PhysiCellDashboard.jl) | Live browser-based output viewer for a running simulation |
