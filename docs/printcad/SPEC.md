# PrintCAD — Product Spec (v1)

## Goal

Design a 40 × 30 × 5 mm bracket with two M3 holes and 2 mm fillets in under 3 minutes on iPad or Mac,
change any dimension later, and export a file that Creality Print opens with zero repair warnings.

## Non-goals (v1)

Freeform surfaces, sculpting, lofts/sweeps as priorities, assemblies/joints, 2D drawings, GD&T,
built-in slicer, STL import/editing, STEP, App Store release, AI part generation.

## Use cases (acceptance fixtures in TESTING.md)

| ID | Job |
| --- | --- |
| U1 | Flat bracket with M3 clearance holes and filleted corners |
| U2 | Open-top enclosure made with shell |
| U3 | Spacer / standoff (tube) |
| U4 | Part driven by variables; change a variable, everything updates |
| U5 | Edit an early dimension of U1; fillets and holes survive |

## Features

| ID | Feature | Behaviour | Pri | Milestone |
| --- | --- | --- | --- | --- |
| F1 | Units & grid | mm, 0.1 mm snap | P0 | exists |
| F2 | Primitives | Box, cylinder, sphere with typed dimensions | P0 | exists → M1 as features |
| F3 | Sketch | Line, rect, circle, arc, polygon on plane/face | P0 | exists |
| F4 | Constraints | Coincident, H/V, parallel, perpendicular, equal, tangent, concentric, symmetric | P0 | exists |
| F5 | Driving dimensions | Tap a dimension, type a value or expression | P0 | exists → M1 expressions |
| F6 | Variables | Named parameters with math (`wall*2+0.2`) in any field | P0 | M1 |
| F7 | Extrude | Blind, symmetric; new / add / cut | P0 | M1 as feature |
| F8 | Revolve | Axis + angle | P1 | M4 |
| F9 | Fillet | Constant radius on selected edges, OCCT-exact | P0 | M2 |
| F10 | Chamfer | Distance, or distance + angle | P0 | M2 |
| F11 | Offset | Sketch offset; face offset | P0 | M2 |
| F12 | Shell | Hollow a body, remove chosen faces | P0 | M2 |
| F13 | Booleans | Union, subtract, intersect as features | P0 | M2 |
| F16 | Feature timeline | Ordered list; edit any step; downstream rebuilds | P0 | M1 |
| F17 | Measure | Distance, angle, bbox | P1 | exists |
| F19 | Export | 3MF (default) and binary STL, mm, Z-up, on the bed | P0 | M0 verify, M3 defaults |
| F20 | Print checks | Build volume fit, thin walls, overhangs, watertight | P1 | M3 |
| F21 | Fastener tool | See table below | P1 | M4 |
| F15 | Patterns & mirror | As features | P1 | M4 |

## F21 Fastener tool

Small metric threads do not print reliably on a 0.4 mm nozzle, so the tool picks the joint by size.
All values are variables so Prem can tune after one test print.

| Size | Joint options | Defaults (mm) |
| --- | --- | --- |
| Clearance holes | Through hole | M2 2.4 · M3 3.4 · M4 4.5 · M5 5.5 · M6 6.6 · M8 9.0 |
| M2–M5 | Heat-set insert hole (default) | Hole Ø: M2 3.2 · M3 4.0 · M4 5.6 · M5 6.4 — tune to the inserts Prem buys |
| M2–M5 | Hex nut trap | Across flats + 0.3: M3 5.8 · M4 7.3 · M5 8.3 |
| M2–M5 | Self-tap hole | Ø = nominal − 0.5 (M3 → 2.5) |
| M6–M12 | Modelled ISO thread, internal or external | Pitch M6 1.0 · M8 1.25 · M10 1.5 · M12 1.75; `thread_clearance` 0.2 |
| Caps/jars | Coarse custom thread | Pitch 3.0, trapezoid profile |

## UX rules

| Rule | Behaviour |
| --- | --- |
| Type-to-create | Every tool opens a numeric field first; dragging just previews it |
| Tap-to-edit | Tap a dimension on the model → edit → rebuild |
| Expressions | Any field accepts `25.4/2`, `wall*2`, variable names |
| Timeline | Horizontal strip of feature chips; tap to edit; failed features show red with the reason |
| Print mode | Toggle shows build box, overhang heatmap, thin-wall warnings |
| iPhone | View, edit dimensions and variables, export. No new sketches in v1 |

## Export rules

| Setting | Default |
| --- | --- |
| Format | 3MF with `unit="millimeter"`; binary STL optional |
| Placement | Lowest point at Z = 0, centred on the 220 × 220 bed, Z-up |
| Tessellation | Fine: 0.01 mm chord, 5° angle. Draft: 0.05 mm, 15° |
| Validation | Watertight (every edge shared by exactly 2 triangles), consistent normals; refuse to export otherwise |
| Filename | `<document>-<yyyyMMdd-HHmm>.3mf` |
| Hand-off | Mac: open in Creality Print; iPad: share sheet / AirDrop / Files |
