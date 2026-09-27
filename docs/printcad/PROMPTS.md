# Claude Code prompts (copy-paste)

Start Claude Code from the repo root. One task per session.

## Session opener (use before every task prompt)

```
Read CLAUDE.md (including the PrintCAD section) and docs/printcad/PROGRESS.md.
Today's task is below. Before writing code: restate the goal, list files you'll
touch, list tests you'll add, and flag any risk. Wait for my "go".
```

## Session closer (after every task)

```
Run the full test suite and show me the result. If green, update
docs/printcad/PROGRESS.md (what changed, tests added, test count, anything I must
check by hand), then commit with message "<task id>: <summary>". Tell me exactly
what to check manually, in 3 steps or fewer.
```

## P0 — Orientation (tonight, first)

```
Read CLAUDE.md, the README, docs/*.md, and everything in docs/printcad/.
Then give me:
1. A one-screen map of the codebase: key types in Kernel/, Kernel/OCCT/, Model/,
   Editor/, Rendering/ and how an extrude flows from tap to body.
2. Where the parametric FeatureTree from docs/printcad/ARCHITECTURE.md should plug in,
   and which existing types it will replace or wrap.
3. Anything in our docs that conflicts with the actual code. Don't change code.
```

## T0.1 — Baseline

```
Task T0.1 from docs/printcad/ROADMAP.md. Build the app and run the full test suite
on an available iPad simulator. Don't change app code. If something fails, diagnose
and tell me whether it's environment (Xcode, LFS, signing) or code. Create
docs/printcad/PROGRESS.md entries for: Xcode version, simulator used, test count,
pass/fail, build time.
```

## T0.2 — Run on Mac

```
Task T0.2. I will run the app on "My Mac (Designed for iPad)". First, scan the code
for iOS-only assumptions that could break there (UIDevice checks, Pencil-only paths,
touch-only gestures, file pickers, fixed screen sizes). List them, ranked by
likelihood to break. After I run it and report back, fix only what actually breaks.
```

## T0.3 — Printer profile + build volume box

```
Task T0.3. Add a PrinterProfile with the Ender 3 V3 SE constants from CLAUDE.md, as
a static value (no settings UI). Render a ghost wireframe box 220 x 220 x 250 mm at
the origin, toggleable from the display menu, default on. Tests: profile values;
box geometry dimensions. Follow existing renderer patterns.
```

## T0.4 — Export verification

```
Task T0.4. Write tests first: export a 40x30x5 box to 3MF and STL; assert 3MF
declares unit="millimeter", STL bbox equals model bbox within 0.01 mm, min Z = 0,
and the mesh is watertight (each edge shared by exactly 2 triangles). Then fix the
exporter only if a test fails. Tell me where the exported file lands so I can open
it in Creality Print.
```

## T1.1 — Expression evaluator

```
Task T1.1. Implement ExpressionEvaluator and Variable per ARCHITECTURE.md section 3-4,
in pure Swift with no dependencies. Tests first: precedence, parentheses, unary minus,
decimals, variable lookup, unknown variable, divide by zero, circular references,
error messages naming the bad token. No UI yet.
```

## T1.2 — Feature model

```
Task T1.2. Add PrintCADDocument, Variable, Feature, FeatureKind (only primitive,
sketch, extrude cases for now), BooleanOp as Codable types per ARCHITECTURE.md.
Wrap the existing sketch model rather than duplicating it. Tests: JSON round-trip
for each case and a whole document. Don't wire into the editor yet.
```

## T1.3 — Rebuild engine

```
Task T1.3. Implement RebuildEngine for primitive + sketch + extrude on OCCTKernel,
per ARCHITECTURE.md section 4. Tests first: U3 fixture and a plain 40x30x5 plate
built from JSON, asserting bbox and volume from TESTING.md, plus a failing feature
that marks downstream features failed and keeps the last good bodies.
```

## Later tasks

For T1.4 onwards use this template:

```
Task <ID> from docs/printcad/ROADMAP.md. Acceptance criteria are in the roadmap and
fixtures in docs/printcad/TESTING.md. Write the failing tests first, show them to me,
then implement.
```

## When things go wrong

```
Stop. Don't change more code. Summarise: what you tried, what failed, the exact
error, and 2 options with trade-offs. Revert uncommitted changes if I say "revert".
```
