# PrintCAD — Architecture

## 1. What the fork already has (from the OpenShape3D README)

| Folder | Contents | PrintCAD stance |
| --- | --- | --- |
| `Kernel/` | Profiles, extrude, booleans, STL, feature edges behind the `KernelOps` facade; `Double`, off main actor, unit-tested | Keep; extend |
| `Kernel/OCCT/` | `OCCTBridge` (Obj-C++, the only place OCCT headers appear) + `OCCTKernel` (Swift API) | Keep the seam; add fillet, chamfer, shell, offset here |
| `Model/` | `DesignDocument` value type, undoable commands, SwiftData persistence, binary mesh format "OS3D" | Add a feature tree beside it (section 3) |
| `Rendering/` | Custom Metal renderer, edges, grid, section clipping, thumbnails | Keep; add build-volume box and print-check overlays |
| `Interaction/` | Gestures, ray-cast picking, gizmo math | Keep |
| `Editor/` | `EditorViewModel`: mode state machine; the viewport never mutates the model | Tools will emit features instead of mutating bodies |
| `UI/` | SwiftUI chrome: gallery, tool palette, numeric input, overlays | Add timeline strip and variables panel |

Known upstream gaps that matter: fillet/shell/chamfer still run on the Euclid mesh (faceted); the OCCT xcframework has iOS slices only;
the `.os3d` archive doesn't carry B-rep; no parametric history. `OCCTKernel.useOCCTAsSourceOfTruth` switches OCCT on/off.

## 2. Target shape

```
UI shells (iPad / Mac "Designed for iPad" / iPhone compact)
        │
EditorViewModel ── tools emit FeatureEdits, never mutate bodies
        │
FeatureTree (Codable) ── Variables ── ExpressionEvaluator
        │
RebuildEngine  ── evaluates features in order, resolves TopoRefs
        │
OCCTKernel / OCCTBridge (exact B-rep)   Euclid (drag previews only)
        │
Bodies (B-rep + render mesh) → Renderer, Print checks, Exporter (3MF/STL)
```

## 3. Data model (Swift sketches — adapt names to the codebase)

```swift
struct PrintCADDocument: Codable {
    var schemaVersion: Int = 1
    var name: String
    var variables: [Variable]          // ordered; later may reference earlier
    var features: [Feature]            // the timeline
    var printer: PrinterProfile = .enderV3SE
}

struct Variable: Codable, Identifiable {
    let id: UUID
    var name: String                   // [a-z_][a-z0-9_]*
    var expression: String             // "2", "wall*2+0.2"
}

/// Every numeric parameter is an expression, so variables flow everywhere.
typealias Expr = String

struct Feature: Codable, Identifiable {
    let id: UUID
    var name: String                   // "Extrude 1"
    var suppressed: Bool = false
    var kind: FeatureKind
}

enum FeatureKind: Codable {
    case sketch(SketchFeature)                         // wraps existing sketch model
    case extrude(sketch: UUID, profiles: [Int], distance: Expr, symmetric: Bool, op: BooleanOp)
    case revolve(sketch: UUID, profiles: [Int], axis: AxisRef, angle: Expr, op: BooleanOp)
    case fillet(edges: [TopoRef], radius: Expr)
    case chamfer(edges: [TopoRef], distance: Expr, angle: Expr?)
    case shell(body: BodyRef, removeFaces: [TopoRef], thickness: Expr)
    case offsetFace(faces: [TopoRef], distance: Expr)
    case boolean(target: BodyRef, tools: [BodyRef], op: BooleanOp)
    case primitive(PrimitiveSpec)                      // box/cylinder/sphere with Expr dims
    case fastener(FastenerSpec)                        // M4
    case pattern(PatternSpec)                          // M4
}

enum BooleanOp: String, Codable { case newBody, union, subtract, intersect }
```

## 4. Rebuild engine

1. Evaluate variables in order with `ExpressionEvaluator` (pure Swift: + − × ÷ ( ), numbers, variable names; errors name the bad token).
2. Walk `features` in order, skipping suppressed ones. Each feature gets the current bodies and returns new bodies or a `FeatureError`.
3. On error: mark that feature and everything downstream as failed, keep bodies from the last good feature, show the reason in the timeline.
4. Rebuild is full, from scratch, on every edit (parts are small; optimise with caching only if a fixture takes > 300 ms).
5. Runs off the main actor; the UI shows the previous result until the new one is ready.

## 5. TopoRef — the hard part

Fillets reference edges, but OCCT creates new edge objects on every rebuild. A `TopoRef` stores a signature, not an object:

```swift
struct TopoRef: Codable, Hashable {
    var createdBy: UUID            // feature that produced the edge/face
    var kind: Kind                 // .edge / .face
    var midpoint: SIMD3<Double>    // at the time of selection
    var direction: SIMD3<Double>   // edge tangent or face normal
    var adjacentNormals: [SIMD3<Double>]   // normals of the 2 faces an edge joins
}
```

Resolution after rebuild: candidates = edges produced by `createdBy`; score by adjacent-normal match first, direction second,
midpoint distance third (normalised by body size). Exactly one clear winner → use it. None or ambiguous → the feature fails
with "Edge lost — reselect", never guesses. Fixture U5 is the acceptance test.

## 6. Mac strategy

| Phase | Approach | Why |
| --- | --- | --- |
| M0–M3 | "Designed for iPad" on Apple Silicon | Zero code; same binary and OCCT slices |
| M4 | Mac Catalyst or native macOS target | Needs OCCT built for that platform (add a slice via `scripts/build_occt_ios.sh`, or evaluate [OCCTSwift](https://github.com/SecondMouseAU/OCCTSwift), which ships macOS + iOS) |

## 7. Files and sync

- New `.printcad` file = JSON `PrintCADDocument` + optional cached mesh, via SwiftUI `DocumentGroup`/`FileDocument`.
- Existing SwiftData gallery stays as the project list.
- iCloud Drive container once the paid developer account exists (M3). Until then: Files app + AirDrop.
