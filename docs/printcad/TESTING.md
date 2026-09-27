# PrintCAD — Test Fixtures

Each fixture is built **from a `PrintCADDocument` JSON** (not UI calls), rebuilt by `RebuildEngine`, then asserted.
Volumes are exact analytic values; allow ±0.5% for OCCT volume properties (`BRepGProp`) and ±1% for tessellated meshes.
Bounding boxes ±0.01 mm. Every fixture also exports STL and must pass the watertight check.

## Shared assertions (every fixture)

| Check | Rule |
| --- | --- |
| Watertight | Every mesh edge shared by exactly 2 triangles, consistent winding |
| On the bed | Min Z = 0 after export placement |
| Fits printer | Bbox ≤ 220 × 220 × 250 |
| Round-trip | JSON → rebuild → JSON is identical |
| Determinism | Two rebuilds give the same volume and bbox |

## U1 — Bracket plate

Variables: none. Features: box 40 × 30 × 5 · two Ø3.4 through-holes at (8, 15) and (32, 15) · fillet r = 2 on the 4 vertical corner edges.

| Assert | Expected |
| --- | --- |
| Bbox | 40 × 30 × 5 |
| Volume | 5892.04 mm³ (6000 − 90.79 holes − 17.17 fillets) |
| Cylindrical faces | 6 (2 holes + 4 fillets), all analytic (not faceted) |

## U2 — Open-top enclosure

Features: box 60 × 40 × 30 · shell thickness 2, remove top face.

| Assert | Expected |
| --- | --- |
| Bbox | 60 × 40 × 30 |
| Volume | 15552 mm³ (72000 − 56 × 36 × 28) |
| Faces | 11 planar (5 outer, 5 inner, 1 rim) |

## U3 — Spacer

Features: cylinder Ø10 × 8 · subtract cylinder Ø3.4 × 8 (coaxial).

| Assert | Expected |
| --- | --- |
| Bbox | 10 × 10 × 8 |
| Volume | 555.68 mm³ |

## U4 — Variable-driven plate

Variables: `w = 40`, `d = 30`, `t = 5`, `hole = 3.4`, `edge = 8`.
Features: box `w` × `d` × `t` · holes Ø`hole` at (`edge`, `d/2`) and (`w-edge`, `d/2`).

| Step | Assert |
| --- | --- |
| As defined | Bbox 40 × 30 × 5; volume 5909.21 mm³ |
| Set `w = 50` | Bbox 50 × 30 × 5; volume 7409.21 mm³; second hole centre at x = 42 |
| Set `w = 10` | Holes overlap/leave the part → clear error on the hole feature, no crash |
| `w = t*` (bad expression) | Evaluator error names the problem; last good model kept |

## U5 — Edit survival

Start from U1. Change the box height 5 → 10.

| Assert | Expected |
| --- | --- |
| Fillet feature status | OK (edges re-resolved via TopoRef, not lost) |
| Holes | Still through (length 10) |
| Volume | 11784.08 mm³ |
| Then delete fillet edge's source face (e.g. replace box with cylinder) | Fillet fails with "Edge lost — reselect", no crash |

## Bad-geometry fixtures (M3 print checks)

| Fixture | Expected warning |
| --- | --- |
| Box 230 × 50 × 10 | Exceeds build volume in X |
| Shell thickness 0.5 | Thin wall < 0.8 mm |
| Horizontal 20 mm overhang with no support | Overhang > 45° region flagged |
