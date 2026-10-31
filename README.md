# ModelManagerStudio

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://drbergman-lab.github.io/ModelManagerStudio.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://drbergman-lab.github.io/ModelManagerStudio.jl/dev/)
[![Build Status](https://github.com/drbergman-lab/ModelManagerStudio.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/drbergman-lab/ModelManagerStudio.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/drbergman-lab/ModelManagerStudio.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/drbergman-lab/ModelManagerStudio.jl)

A desktop GUI for [ModelManager.jl](https://github.com/drbergman-lab/ModelManager.jl) — set up parameter variations, launch simulation campaigns, and browse what came back, without writing the script yourself.

> **Naming:** this package is likely to be renamed before 0.1.0. "Studio" already means
> [PhysiCell Studio](https://github.com/PhysiCell-Tools/PhysiCell-Studio) in this ecosystem — and
> PhysiCellModelManager's own `runStudio()` launches *that* tool, not this one. See
> the roadmap below.

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

`PhysiCellModelManager` is a **weak** dependency: Studio installs and loads without it, and the
PhysiCell integration activates when you load both.

```julia
using PhysiCellModelManager   # or another ModelManager backend
using ModelManagerStudio
launch("path/to/project")
```

| Backend | Status |
|---|---|
| [PhysiCellModelManager.jl](https://github.com/drbergman-lab/PhysiCellModelManager.jl) | supported, via `StudioPhysiCellModelManagerExt` |
| Any other `ModelManager.AbstractSimulator` | works on the generic defaults; add an extension for its project layout |

A backend extension supplies three things: where its projects live on disk, what a reproducible
script says to reopen one, and how to point a lost user at its project-creation function. The
parameter browser needs nothing — it walks the location's base XML.

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

## Roadmap

- [ ] Split `assets/ModelManagerStudio.qml` into a component library with a `Theme` singleton; dark mode is currently unreadable
- [ ] Move token-chain and target state into Julia-owned `Observables` so QML holds no snapshots
- [ ] Run campaigns off the UI thread via `run`'s `on_progress` hook — the window currently freezes for the duration
- [ ] Invalidate variations when the input folders change
- [ ] Covariations and latent variations (`CoVariation`, `LatentVariation`)
- [ ] Sampling methods with a pre-commit preview (`GridVariation`, `LHSVariation`, `SobolVariation`, `RBDVariation`)
- [ ] Sensitivity analysis (MOAT, Sobolʼ, RBD) and calibration (ABC-SMC) with live progress
- [ ] Analysis pane over the project database; visualization via [Montage.jl](https://github.com/drbergman-lab/Montage.jl)
- [ ] Rename the package — "Studio" collides with PhysiCell Studio, which PCMM's own `runStudio()` launches

## Related packages

| Package | Role |
|---|---|
| [ModelManager.jl](https://github.com/drbergman-lab/ModelManager.jl) | Simulator-agnostic campaign management: variations, sampling, sensitivity, calibration, provenance |
| [PhysiCellModelManager.jl](https://github.com/drbergman-lab/PhysiCellModelManager.jl) | PhysiCell backend for ModelManager |
| [Montage.jl](https://github.com/drbergman-lab/Montage.jl) | Composite figures and movies — `montage`, `storyboard`, `tableau` |
| [PhysiCellDashboard.jl](https://github.com/drbergman-lab/PhysiCellDashboard.jl) | Live browser-based output viewer for a running simulation |
