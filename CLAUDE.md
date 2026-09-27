# openshape3d

Open-source iOS direct-modeling CAD app: SwiftUI + custom Metal renderer +
Euclid mesh-CSG kernel + parametric feature graph (topological naming).

**Start here: `docs/STATUS_AND_NEXT_STEPS.md`** — current phase status, the
prioritized next missions, dev workflow (simulator UDID, test commands,
UI-test helpers), and the gotchas list (SwiftData-in-XCTest crash, a11y
container collapse, bottom-overlay stacking, nonisolated defaults, …).
Update it at the end of each mission.

Spec/design companions: `docs/PARITY_SPEC.md`,
`docs/IMPLEMENTATION_PLAN.md`, `docs/PHASE_D_DESIGN.md`.
AI assistants (Claude Desktop / MCP) driving the app: `docs/AI_MODELING_SETUP.md`
(user tutorial `docs/CLAUDE_DESKTOP_TUTORIAL.md`, protocol `docs/AGENT_CONTROL.md`).
Modeling-core roadmap (sketch + solid parity, ordered with acceptance
criteria): `docs/MODELING_PARITY_GOALS.md`. Kernel strategy:
`docs/OCCT_BREP_PORT_DESIGN.md`.

Architecture seams (never bypass): geometry ops via `KernelOps`, mutations via
`DocumentCommand` (undoable), all state through `EditorViewModel`. Run tests
with `-parallel-testing-enabled NO`; unit-test geometry as pure values —
never instantiate `DocumentSession`/`ModelContainer` in tests.


<!-- Append this whole file to the repo's CLAUDE.md. Keep the upstream content above it. -->

# PrintCAD fork — rules for Claude Code

## Context

- This repo is **PrintCAD**, a personal hard fork of OpenShape3D. The owner is Prem, a single user.
- Purpose: design simple, dimension-driven parts and export STL/3MF for an **Ender 3 V3 SE**, sliced in **Creality Print**.
- Owner codes with AI assistance and cannot review Swift/C++ line by line. **Tests are the review.**
- Read before any task: `docs/printcad/SPEC.md`, `docs/printcad/ARCHITECTURE.md`, `docs/printcad/ROADMAP.md`, `docs/printcad/PROGRESS.md`.

## Decisions (do not revisit without asking)

| Topic | Decision |
| --- | --- |
| Modeling | Parametric history: upstream's `FeatureGraph`, rebuilt incrementally via `RebuildPlanner` / `EvalCache` (decided 2026-09-28). Reuse upstream features that fit; replace any that block planned work |
| Devices | Mac and iPad equally; iPhone for viewing and editing dimensions |
| Mac strategy | Native Mac Catalyst build (upstream's, already working), ad-hoc signed for local use. Mac-specific UI polish stays in M4 |
| Kernel | OCCT through the existing `OCCTBridge` / `OCCTKernel` seam. Euclid only for live previews |
| Units | Millimetres everywhere. No inches, no unit toggle |
| Distribution | Personal use only. No App Store work |
| Deferred | STL import/editing, AI "describe the part", STEP, assemblies |

## Hard rules

1. **Plan first.** For every task: restate the goal, list files you will touch, list tests you will add, then wait for "go".
2. **Tests first for geometry.** Any change under `Kernel/`, `Model/` or the rebuild engine starts with a failing test from `docs/printcad/TESTING.md`.
3. **Green before commit.** Run the full test suite; never commit on red. Never delete or weaken a test to get green; ask instead.
4. Keep upstream seams: OCCT C++ headers only inside `OCCTBridge`. Kernel math in `Double`. The viewport never mutates the model.
5. **No new dependencies** (SPM, CocoaPods, binaries) without asking. Never link GPL code (e.g. SolveSpace).
6. Never edit or regenerate `ThirdParty/` binaries unless the task says so.
7. Small commits, message format: `T1.3: rebuild engine for extrude`.
8. One task ID per session. If you discover extra work, add it to `PROGRESS.md` under "Found work"; don't do it.
9. When OCCT fails (fillet too large, boolean error), surface a clear message and keep the last valid model. Never silently fall back to a faceted mesh.
10. End of task: update `docs/printcad/PROGRESS.md` (what changed, tests added, test count, anything Prem must check by hand).

## Printer profile (constants)

| Name | Value |
| --- | --- |
| Build volume | 220 × 220 × 250 mm |
| Nozzle | 0.4 mm |
| Min wall warning | < 0.8 mm |
| Overhang warning | > 45° from vertical |
| Default hole clearance | +0.2 mm on diameter |
| Default thread clearance | 0.2 mm (variable `thread_clearance`) |

## Test command

```bash
xcodebuild test -project openshape3d.xcodeproj -scheme openshape3d \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'
```
(Use any available iPad simulator if that name doesn't exist: `xcrun simctl list devices available`.)
