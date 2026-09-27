# PrintCAD — Progress log

Newest first. Claude Code appends an entry at the end of every task.

## Template

### <date> — <task id>: <title>
- Changed:
- Tests added:
- Test count / result:
- Prem checks by hand:
- Found work (not done):

---

### 2026-09-28 — V1.3: Voice holes + undo/redo/views
- Changed: `Voice/VoiceRecipe.swift` (hole size/depth from spoken numbers, default Ø5 through, M-sizes +0.2 mm,
  area centroid of the face outline), `Voice/EditorViewModel+VoiceApply.swift` (face frozen at Enter; hidden circle
  sketch + subtract extrude into the body; failure → undo + message, last valid model kept),
  `DocumentSession.addSketchAndRecord` (new sketch + nodes in ONE undo step via a preview rebuild),
  `VoiceSession.onDecision/applied` (confident answers applied, unsure ones wait for a pick), panel shows ✓/✗ line.
  Voice also does undo, redo, top/front/isometric view, fit view.
- Tests added: `VoiceHoleTests.swift` — sizing 7, centroid 2, real-kernel 8 (Ø5 through removes π·2.5²·2 mm³ as one
  undo step; centre not click point; blind 4×1; click during Jev wait doesn't move hole; non-parametric body refused;
  nothing picked; unsure waits; "undo that"). 68 voice tests pass.
- Test count / result: 68 voice/Jev tests pass; full suite not re-run.
- Prem checks by hand: extrude a plate, click top face, "drill a hole in the centre" → hole appears, ⌘Z removes it.
- Found work (not done): holes at the clicked point; imported meshes can't be cut parametrically.

### 2026-09-28 — V1.2: Enter sends words + selection to Jev
- Changed: `Voice/JevClient.swift` (POST api.typesafe.ai/v1/systemone, Bearer key, clear errors for 401/422/429/529),
  `Voice/VoiceIntent.swift` (action options filtered by selection, placement, depth, one role question per spoken
  number; reply → `VoiceDecision`), `Voice/SpokenNumberParser.swift` ("seven MM", "2.5 millimetres", "M3", cm → mm).
  `VoiceSession`: one utterance at a time — mic stops when the recognizer finishes or on Enter, never restarts by
  itself; tapping the mic adds to unsent words; Enter → "Asking Jev…" → decision (or "Did you mean" buttons under
  60 %). Panel shows action · placement · depth, confidence, latency, number roles. Sketch profiles are a target.
  Key: gitignored `.env.local` → committed `Config/Secrets.xcconfig` (`#include?`) → Debug-only
  `Config/Info-Debug.plist` (`JEVAPIKey`). Outgoing network entitlement added. Decisions are shown, not applied (V1.3).
- Tests added: `JevVoiceTests.swift` (parser 8, request 3, decision 6, HTTP client 5 with stubbed network, key 2);
  `VoiceEditTests` reworked for Enter → Jev and no continuous listening. 52 voice/Jev tests.
- Test count / result: 52 voice/Jev tests pass. Full suite not re-run this task.
- Prem checks by hand: done 2026-09-28 — "I want you to put a hole in this at the centre" on a face →
  Jev: Hole · centre · through all, 100 %, 0.57 s.
- Found work (not done): the chip can change after Enter if the pick changes (shows "Body" while the sent request
  says "Face"); decide whether the chip should freeze to the sent target.

### 2026-09-28 — V1.1: Voice panel + mic (Voice Edit)
- Changed: new `openshape3d/Voice/` — `VoiceSession` (permission → listening → live transcript → Enter),
  `LiveSpeechTranscriber` (AVAudioEngine + on-device SFSpeechRecognizer, CAD vocabulary boosted),
  `VoicePanel` (bottom-centre card: live words, target chip, Enter/Esc), `VoiceTarget` (face/edges/bodies/nothing),
  `EditorViewModel+Voice`. Mic button after Fit View in the toolbar, command `app.voice` (⌘⇧V, also in Command
  Search), Escape closes the panel. Build settings: mic + speech usage strings, `ENABLE_RESOURCE_ACCESS_AUDIO_INPUT`.
  `.gitignore`: `.env.local`, `Config/Secrets.xcconfig` (Jev key lives there, never committed).
  Docs: `docs/printcad/VOICE.md` (plan + action catalog), ROADMAP section V, CLAUDE.md decision row.
  Enter only shows "Would send …" — no Jev call (V1.2) and no geometry change (V1.3) yet.
- Tests added: `VoiceEditTests.swift` — 16 (VoiceTarget 3, VoiceSession 9 with a fake microphone, editor wiring 4:
  ⌘⇧V routable/launchable, toggle starts/stops mic, edge/body/face targets incl. 4 mm² top face, Enter leaves the
  model untouched).
- Test count / result: voice + command tests all pass. Full suite was stopped early at Prem's request:
  1816 passed, 2 failed — `SignatureNamingScaleTests…IsBounded` (timing limit under parallel load) and
  `ConstraintRailUITests.testCoincidentPointOnLineAppliesAndHistoryDeselects`; neither touches voice code, not yet
  re-run in isolation.
- Prem checks by hand: Mac app → 🎤 (or ⌘⇧V) → allow Speech + Microphone → click a face → speak: words appear live,
  chip says "Face · … mm²", Enter shows "Would send …". First Mac try failed with "No microphone input was found"
  (input node touched before the record session was active) — fixed, needs re-check.
- Found work (not done): mic button could move beside the new Recenter button (U1); the two failing tests above
  need an isolated re-run.

### 2026-09-28 — U1: Recenter button + Shapr3D-style extrude controls on the arrow
- Changed:
  - New `UI/RecenterButton.swift`: round button just left of the orientation cube; runs the existing Fit View
    (frames every sketch and body). Toolbar "Fit View" kept.
  - `UI/ExtrudeGizmoOverlay.swift`: sketch extrudes and face pulls now carry all their controls on the arrow —
    options chip (Total/Symmetric, End ▸ Through All / Up To Next, Result ▸ Auto/New Body/Union/Subtract/Intersect,
    Revolve/Sweep/Loft/Helix, Offset Plane), the value, ✕ cancel, ✓ commit. The row turns with the arrow like
    Shapr3D (never upside down; level when the arrow is near vertical; kept on screen). Tapping the value opens a
    wide field there with the number pad, fx (variables) and keyboard toggle.
  - `UI/NumericInputBar.swift`: bottom extrude bar removed (cylinder-diameter bar unchanged).
  - `Editor/EditorViewModel.swift`: on-arrow value now resolves variables and reports unreadable input;
    commit/cancel clear a half-typed arrow edit so the next extrude doesn't open in edit mode.
- Tests added: `RecenterUITests` (button beside cube; recenter puts the model under screen centre),
  `ExtrudeFlowUITests.testExtrudeControlsRideTheArrowNotTheBottom`.
- Tests changed (same checks, new location): UI tests wait for the ✓ "Extrude" button instead of the old bar's
  "Extrude" title, and pick Symmetric / New Body / Revolve / Sweep / Loft / Helix / Offset Plane through the chip
  menu (`tapExtrudeOption`). `FaceFlowUITests` types into the on-arrow Distance field.
  `CompactWidthBarUITests` extrude tests rewritten: they measured the removed bottom bar; they now check the
  on-arrow controls are on screen, hittable and compact, Offset Plane is reachable, and the palette's Delete is
  still reachable.
- Test count / result: unit 1737 run, 0 failed, 1 skipped (opt-in fuzz). UI (verified after the commit, same build):
  186 passed, 2 failed, 4 skipped (compact-width tests, iPad) across three runs (the simulator crashed / was stopped twice;
  each run resumed where the last stopped). Both failures also fail on `786f9307` (before U1), so they predate it:
  `RectangleWorkflowUITests.testGalleryReopenedDesignCanUndoNewRectangle` (gallery card 'Untitled' not hittable after
  relaunch) and `SettingsUITests.testSnappingControlsPersistAcrossLaunch` (snapping toggle value doesn't change).
- Prem checks by hand: on Mac and iPad — tap a profile and check the row sits at the arrow and reads well at a few
  camera angles; open the chip menu; type a value (Mac keyboard too); pan away and tap recenter.
- Found work (not done): the recenter button can sit under the Items panel when that panel is open (both top-right).
  Also: the two pre-existing UI failures above; first full UI-suite baseline, so there was no earlier record of them.

### 2026-09-28 — T0.3: Printer profile + build-volume box
- Changed: new `openshape3d/PrintCAD/PrinterProfile.swift` (Ender 3 V3 SE constants) and
  `openshape3d/PrintCAD/BuildVolume.swift` (12 box edges, Y-up: X ±110, Z ±110, Y 0–250).
  `ViewportScene.buildVolumeLines` (excluded from Zoom-to-Fit bounds), `EditorViewModel.buildVolumeVisible`
  (default on, remembered in UserDefaults `printcad.buildVolumeVisible`), hairline draw pass in `Renderer`
  after the grid (hidden with the grid in "grid off" screenshots), "Build Volume" toggle in the Views menu.
- Tests added: `PrinterProfileTests` (5): profile values, 12 edges at the bed corners, axis-aligned edge
  lengths 220/250/220, fit bounds ignore the box, box alone gives no fit bounds.
- Test count / result: 1737 run, 1736 passed, 1 skipped, 0 failed.
- Prem checks by hand: on the Mac app, pinch out until the grey box appears around the origin; Views →
  Build Volume hides/shows it; relaunch keeps the setting.
- Found work (not done): Mac has no scroll-wheel/⌘± zoom — only trackpad pinch (candidate for T3.4 Mac polish).

### 2026-09-28 — Roadmap re-scope
- Mapped every original task against the fork. M1 (expressions, variables, feature model, rebuild, timeline)
  and most of M2 (fillet, chamfer, shell, booleans, topo naming, edit survival) already exist upstream with tests.
- ROADMAP.md rewritten around the real gaps: build volume, Z-up export, personal-use cleanup, print checks,
  hole clearance, .printcad file, iCloud, fastener tool.
- CLAUDE.md: modeling decision changed from "rebuild from scratch" to upstream's incremental rebuild (Prem approved).
- Found work (not done): ARCHITECTURE.md still sketches `PrintCADDocument` / `RebuildEngine` / `TopoRef`; map them
  onto `FeatureGraph` / `RebuildPlanner` / `FaceRef`+`EdgeRef` or drop them.

### 2026-09-27 — T0.2: Run on Mac
- Changed: nothing in code. Upstream's Mac Catalyst build works as-is (ad-hoc signed, command in T0.1 below).
  Used Catalyst rather than "Designed for iPad", which would need a signing team. Prem approved Catalyst as the Mac strategy (CLAUDE.md updated).
- Tests added: none.
- Test count / result: unchanged from T0.1.
- Prem checked by hand: sketch → extrude → export works on the Mac app.
- Found work (not done): none new.

## Baseline

### 2026-09-27 — T0.1: Build, run tests, record baseline
- Fork: `prempradeep21/printcad` from `laanlabs/openshape3d` @ `be3f2fc8`. Branch `printcad/main`.
- OCCT: `ThirdParty/OCCT.xcframework` 550 MB via LFS, no pointer files. Slices: ios-arm64, ios-arm64-simulator, ios-arm64-maccatalyst.
- Toolchain: Xcode 26.6 (17F113), Apple M5 Pro. Needed `xcodebuild -downloadComponent MetalToolchain` once.
- Build (iPad Pro 13-inch (M5) simulator): succeeded, 11 warnings.
- Unit tests (`-only-testing:openshape3dTests -parallel-testing-enabled NO`): 1732 run, 1730 passed,
  1 skipped (`OCCTFuzzTests.testDeserializeSurvivesHostileInput`, opt-in via `TEST_RUNNER_OS3D_FUZZ=1`),
  1 failed: `HeavyMeshGuardTests.testHeavyMeshBodiesAreNotBooleanCandidates` — locale only. The Mac's
  region is `en_IN`, so 102749 formats as "1,02,749"; the test accepts only "102,749" / "102 749" / "102.749".
  Not a product bug. Test left untouched.
- UI tests (`openshape3dUITests`): not run yet.
- Mac: native Mac Catalyst build also succeeds and launches (ad-hoc signed, no team):
  `xcodebuild build -scheme openshape3d -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath build/DerivedData-mac CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=`
  App: `build/DerivedData-mac/Build/Products/Debug-maccatalyst/openshape3d.app`.
- Prem checks by hand: open the Mac app above; sketch → extrude → export works.
- Found work (not done):
  - ~~Make the heavy-mesh test locale-independent~~ — done 2026-09-27 with Prem's OK: test also accepts "1,02,749". Suite now 1731 passed, 1 skipped, 0 failed.
  - Upstream has moved well past what SPEC/ROADMAP assume: parametric feature graph, topological naming,
    OCCT B-rep fillet/booleans and a Catalyst Mac build already exist. Re-scope M1–M2 and the M4 "native Mac UI"
    item against `docs/STATUS_AND_NEXT_STEPS.md` before starting T1.x.
  - Bundle ID is still `com.laan.labs.openshape3d` and team `34FWY7G2HB`; switch to `com.prem.printcad` + Personal Team (SETUP step 5).
  - Run the UI test suite for a full baseline.
