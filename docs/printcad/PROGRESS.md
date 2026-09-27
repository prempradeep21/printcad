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
  - Make the heavy-mesh test locale-independent (accept "1,02,749" or format with a fixed locale). Needs Prem's OK (rule 3).
  - Upstream has moved well past what SPEC/ROADMAP assume: parametric feature graph, topological naming,
    OCCT B-rep fillet/booleans and a Catalyst Mac build already exist. Re-scope M1–M2 and the M4 "native Mac UI"
    item against `docs/STATUS_AND_NEXT_STEPS.md` before starting T1.x.
  - Bundle ID is still `com.laan.labs.openshape3d` and team `34FWY7G2HB`; switch to `com.prem.printcad` + Personal Team (SETUP step 5).
  - Run the UI test suite for a full baseline.
