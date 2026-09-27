# PrintCAD — Roadmap

Rewritten 2026-09-28 after mapping the original plan against what OpenShape3D already ships.
Policy: reuse what upstream has when it fits; replace it when it would block something we want.
Pace: 2–4 hrs/week ≈ one task per session. Each milestone ends with a real print.

## What upstream already covers (no task needed)

Verified by existing tests; see the 2026-09-28 mapping in `PROGRESS.md`.

| Original task | Covered by |
| --- | --- |
| T1.1 expressions + variables | `Kernel/ExpressionEvaluator.swift`, `Model/Variables.swift` |
| T1.2 Codable feature model | `FeatureGraph` / `FeatureNode` / `FeatureKind`, persisted per feature |
| T1.3 rebuild engine | `FeatureGraph.evaluate` + `RebuildPlanner` + `EvalCache` (incremental; same result as a full rebuild) |
| T1.4 extrude as a feature | `EditorViewModel` commits `.extrude` / `.revolve` / `.sweep` / `.boolean` nodes |
| T1.5 timeline | `UI/HistoryPanelView.swift` (edit, suppress, rollback, error badge) |
| T1.6 variables panel + expressions in fields | `VariablesPanelView`, `ExpressionValueField` |
| T2.1–T2.4, T2.6 fillet, chamfer, shell, booleans | OCCT via `OCCTBridge.mm`; `.fillet` / `.chamfer` / `.shell` / `.boolean` features |
| T2.2 topological naming | `FaceRef` / `EdgeRef`, `TopoNaming.swift`, `ElementNaming.swift` |
| T2.7 edit survival | `FeatureGraphEvalTests` edit-and-resolve tests |
| M4 patterns, mirror, revolve, Mac, AI input | `.pattern` / `.mirror` / `.revolve`; Mac Catalyst build; `Agent/*` |

Conventions to respect: the app is **Y-up** (printer Z = app Y); geometry tests are pure values
(never `DocumentSession` / `ModelContainer` in XCTest); mutations go through `DocumentCommand`;
new numeric inputs store `Expr` so they follow variables; new code in new files, not `EditorViewModel.swift`.

## M0 — Baseline (done: T0.1, T0.2)

| ID | Task | Acceptance |
| --- | --- | --- |
| T0.3 | `PrinterProfile` (Ender 3 V3 SE constants) + toggleable 220×220×250 build-volume box in the viewport | Box visible on Mac and iPad, toggle works; unit test on profile values and box geometry |
| T0.4 | Print-ready export: STL/3MF rotated to Z-up and dropped onto Z=0, on by default | Export tests: Z-up, min Z = 0, bbox matches model; 3MF declares mm. Prem opens a 40×30×5 box in Creality Print, lying flat |
| T0.5 | Manual: print the box | Photo in PROGRESS.md |

## M1 — Make it mine (2–3 sessions)

| ID | Task | Acceptance |
| --- | --- | --- |
| T1.1 | Personal-use cleanup: bundle ID `com.prem.printcad`, remove bug-report upload entry points, pin units to mm and hide the unit picker, AI control server off by default | Builds and tests green; no Firebase entry points reachable; Settings shows no unit toggle |
| T1.2 | Fixture check: build TESTING.md U1–U5 with the existing features as tests (exact volumes/bboxes) | U1–U5 pass, or each failure logged as found work |
| T1.3 | Manual: print U3 spacer and a U4 variable-driven variant | Photos |

## M2 — Print-ready (4–5 sessions)

| ID | Task | Acceptance |
| --- | --- | --- |
| T2.1 | Print checks: fits build volume, watertight (reuse `ShapeHealth`), thin wall < 0.8 mm, overhang > 45° heatmap | Tests on deliberately bad fixtures |
| T2.2 | Hole clearance: +0.2 mm default on hole diameters, driven by a variable | Tests: hole diameter = nominal + clearance; variable change updates it |
| T2.3 | `.printcad` file: wrap the existing `.os3d` `ProjectArchive` with a Files-app document type | Save, close, reopen U1–U5 identical |
| T2.4 | iCloud Drive container (needs the paid developer account) | Edit on iPad, open on Mac |
| T2.5 | Manual: print U1 designed entirely on iPad | Photo |

## M3 — Features I want (ongoing)

| ID | Task |
| --- | --- |
| T3.1 | Fastener tool: clearance/tap holes, counterbores, printable threads using `thread_clearance` (builds on the helix tool) |
| T3.2 | Fix upstream revolve bug: valid closed profile refused (`STATUS_AND_NEXT_STEPS.md`, sheet 7.2) |
| T3.3 | iPhone: view and edit dimensions/variables comfortably |
| T3.4 | Mac polish: menus, shortcuts, window sizing |
| T3.5 | AI "describe the part" on top of the existing `Agent/*` control surface |
