# PrintCAD — Roadmap

Pace: 2–4 hrs/week ≈ one task per session. Expect ~5–6 months to M3.
Each milestone ends with a real print.

## M0 — Baseline (2–3 sessions)

| ID | Task | Acceptance |
| --- | --- | --- |
| T0.1 | Build, run tests, record baseline | All upstream tests pass; count logged in PROGRESS.md |
| T0.2 | Run on Mac (Mac Catalyst); fix anything iOS-only that breaks | Sketch → extrude → export works on Mac |
| T0.3 | Printer profile constant + ghost build-volume box 220×220×250 in viewport | Box visible, toggleable; unit test on profile values |
| T0.4 | Export check: 3MF declares millimetres; STL bbox equals model bbox; part sits on Z=0 | New export tests pass; Prem opens a 40×30×5 box in Creality Print |
| T0.5 | Manual: print the box | Photo in PROGRESS.md |

## M1 — Parametric core (6–8 sessions)

| ID | Task | Acceptance |
| --- | --- | --- |
| T1.1 | `ExpressionEvaluator` + `Variable` (pure Swift) | Unit tests: precedence, parentheses, unknown name, divide by zero, cycles |
| T1.2 | `PrintCADDocument` / `Feature` Codable model | JSON round-trip tests for every FeatureKind implemented so far |
| T1.3 | `RebuildEngine` for primitive + sketch + extrude | U3 and plain-plate fixtures rebuild from JSON |
| T1.4 | Extrude tool emits a feature instead of mutating bodies | UI test: extrude, change distance in timeline, body updates |
| T1.5 | Timeline strip UI (tap to edit, failed = red) | Manual check on iPad + Mac |
| T1.6 | Variables panel + expressions in all numeric fields | U4 fixture passes |
| T1.7 | Manual: print U3 spacer and a U4 variant | Photos in PROGRESS.md |

## M2 — Solid features on OCCT (8–10 sessions, the risky one)

| ID | Task | Acceptance |
| --- | --- | --- |
| T2.1 | OCCT fillet + chamfer in `OCCTBridge` (`BRepFilletAPI_MakeFillet`, `BRepFilletAPI_MakeChamfer`) | Kernel tests: exact cylindrical fillet faces; too-large radius returns an error, not a crash |
| T2.2 | `TopoRef` capture + resolution | Unit tests for match, ambiguous, lost |
| T2.3 | Fillet/chamfer as features | U1 passes |
| T2.4 | Shell on OCCT (`BRepOffsetAPI_MakeThickSolid`) as feature | U2 passes |
| T2.5 | Face offset + sketch offset | Tests on plate thicken |
| T2.6 | Booleans as features | Subtract/union fixture tests |
| T2.7 | Edit-survival | U5 passes |
| T2.8 | Manual: print U1 and U2 | Photos |

## M3 — Print-ready (4–5 sessions)

| ID | Task | Acceptance |
| --- | --- | --- |
| T3.1 | Print checks: fit, thin wall, overhang heatmap, watertight | Tests on deliberately bad fixtures |
| T3.2 | `.printcad` file format via DocumentGroup | Save, close, reopen U1–U5 identical |
| T3.3 | Export defaults, filenames, Mac hand-off to Creality Print | Manual |
| T3.4 | iCloud Drive container (needs paid account) | Edit on iPad, open on Mac |
| T3.5 | Manual: print U1 designed entirely on iPad | Photo |

## M4 — Polish (ongoing)

Fastener tool (F21, first), patterns & mirror, revolve as feature, iPhone compact editing, native Mac UI, AI part input (later).
