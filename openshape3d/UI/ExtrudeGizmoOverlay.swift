//
//  ExtrudeGizmoOverlay.swift
//  openshape3d
//
//  Shapr3D-style on-arrow controls for extrude / face push-pull / cylinder
//  diameter, projected from world each camera move via `cameraEpoch`.
//  Extrudes and face pulls carry everything here — an options chip (extent,
//  end condition, boolean result, other profile tools), the value, and
//  cancel / commit — laid along the arrow so nothing sits at the bottom of the
//  screen. Tapping the value opens a wide field with the number pad right
//  where it is. The cylinder diameter keeps a plain value pill (its options
//  stay in the bottom bar).
//

import SwiftUI
import simd

struct ExtrudeGizmoOverlay: View {
    @Bindable var viewModel: EditorViewModel

    /// The arrow handle's screen anchor: where the symbol is drawn (and grabbed),
    /// plus the pull direction's on-screen orientation.
    private struct ArrowAnchor {
        var point: CGPoint
        var dir: (x: CGFloat, y: CGFloat, angle: Double)
        var isValid: Bool
    }

    private var arrowAnchor: ArrowAnchor? {
        // `pullArrowState`, NOT `scene.pullArrow`: reading `scene` here made
        // every camera tick re-assemble the whole viewport scene (review S2).
        guard let arrow = viewModel.pullArrowState,
              let cam = viewModel.cameraControl else { return nil }
        let o = SIMD3<Double>(Double(arrow.origin.x), Double(arrow.origin.y), Double(arrow.origin.z))
        let d = simd_normalize(SIMD3<Double>(Double(arrow.direction.x),
                                             Double(arrow.direction.y),
                                             Double(arrow.direction.z)))
        guard let p0 = cam.worldToScreenPoint(o) else { return nil }
        let p1 = cam.worldToScreenPoint(o + d)
        let dir = screenDir(from: p0, to: p1)
        // Float off the cap — shares the grab-region offset so the touch target
        // sits exactly under the drawn symbol.
        let float = ViewportCoordinator.pullHandleScreenOffset
        return ArrowAnchor(
            point: CGPoint(x: p0.x + dir.x * float, y: p0.y + dir.y * float),
            dir: dir, isValid: arrow.isValid
        )
    }

    /// Screen gap the pill sits below the arrow handle — clears the symbol so
    /// the measurement pill never hides the arrow (any face orientation).
    private static let pillDropBelowArrow: CGFloat = 60

    var body: some View {
        let _ = viewModel.cameraEpoch
        GeometryReader { geo in
        ZStack {
            if let anchor = arrowAnchor {
                if !viewModel.editingExtrudeArrow {
                    pullSymbol(anchor)
                }
                if let label = viewModel.extrudeArrowLabel {
                    if label.isDiameter {
                        // Anchor the pill BELOW the arrow (screen-down) so it
                        // never overlaps the handle, whichever way the face
                        // points. While it is a text field, keep it clear of
                        // the on-screen keyboard (bug report 8c98bd3b).
                        let below = CGPoint(x: anchor.point.x,
                                            y: anchor.point.y + Self.pillDropBelowArrow)
                        diameterPill(label)
                            .position(viewModel.editingExtrudeArrow
                                      ? MoveDistanceOverlay.clearOfKeyboard(below, in: geo.size)
                                      : below)
                    } else if let context = viewModel.toolContext {
                        ExtrudeArrowControls(
                            viewModel: viewModel, label: label, context: context,
                            handle: anchor.point, dir: anchor.dir, screen: geo.size
                        )
                    }
                }
            }
        }
        }
        // `worldToScreenPoint` returns full-screen (MTKView) coordinates, so the
        // overlay must span the full screen too — otherwise the safe-area inset
        // shifts every `.position` down and the handle/pill miss the geometry.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        // Helix lives in the arrow's options menu, so its sheet hangs here.
        .sheet(isPresented: $viewModel.showHelixOptions) {
            HelixOptionsSheet { radius, pitch, turns in
                viewModel.commitHelixSweep(radius: radius, pitch: pitch, turns: turns)
            }
        }
    }

    /// The grab handle: the ACTUAL SF Symbol (`arrow.up.and.down`), drawn as an
    /// always-on-top overlay so it stays visible when the moving cap dips below
    /// or behind a surface (the 3D-drawn arrow used to get occluded there). It
    /// rides the pull arrow's world origin, projected each camera move, rotated
    /// so its axis follows the pull direction on screen. Hit-testing is disabled
    /// so drags fall through to the viewport, which grabs it geometrically.
    private func pullSymbol(_ anchor: ArrowAnchor) -> some View {
        ZStack {
            // The visible (rotated) symbol.
            ZStack {
                // Dark backing (a hair larger) → crisp outline like Shapr3D.
                symbolImage.foregroundStyle(Color(white: 0.08))
                    .scaleEffect(1.18)
                symbolImage.foregroundStyle(anchor.isValid ? Color(red: 0.20, green: 0.52, blue: 1.0)
                                                           : Color(red: 0.90, green: 0.26, blue: 0.26))
            }
            .rotationEffect(.radians(anchor.dir.angle + .pi / 2))
            .position(anchor.point)
            .allowsHitTesting(false)
            // A separate, un-rotated invisible marker at the exact grab point —
            // its accessibility frame is what UI tests target (rotation/nested
            // images make the symbol's own frame unreliable).
            Color.clear
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
                .position(anchor.point)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityIdentifier("PullArrowHandle")
        }
    }

    private var symbolImage: some View {
        Image(systemName: "arrow.up.and.down")
            .font(.system(size: 30, weight: .bold))
    }

    /// Unit screen-space direction from `p0` toward `p1` (defaults to straight
    /// up when the axis projects to a point), plus its angle for rotation.
    private func screenDir(from p0: CGPoint, to p1: CGPoint?) -> (x: CGFloat, y: CGFloat, angle: Double) {
        guard let p1 else { return (0, -1, -.pi / 2) }
        let dx = p1.x - p0.x, dy = p1.y - p0.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 0.5 else { return (0, -1, -.pi / 2) }
        return (dx / len, dy / len, atan2(Double(dy), Double(dx)))
    }

    @ViewBuilder
    private func diameterPill(_ label: EditorViewModel.ExtrudeArrowLabel) -> some View {
        if viewModel.editingExtrudeArrow {
            ExtrudeArrowField(viewModel: viewModel)
        } else {
            Button {
                viewModel.beginExtrudeArrowEdit()
            } label: {
                Text(label.text)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.blue, lineWidth: 1.5))
                    .foregroundStyle(Color.blue)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ExtrudeArrowValue")
        }
    }
}

/// The extrude / face-pull controls laid along the arrow (Shapr3D): options
/// chip, value, cancel, commit. The row starts just past the arrow handle and
/// turns with the arrow on screen, flipped so its text never reads upside
/// down; a nearly vertical arrow keeps the row level. While the value is
/// being typed the row stands level (with the pad under it) and stays clear
/// of the screen edges and the keyboard.
///
/// The value is a real `TextField` titled "Distance" in both states — a
/// read-out until tapped — so it is the same element the UI suite has always
/// typed extrude heights into.
private struct ExtrudeArrowControls: View {
    @Bindable var viewModel: EditorViewModel
    let label: EditorViewModel.ExtrudeArrowLabel
    let context: EditorViewModel.ToolContext
    /// The arrow handle's screen point and the pull direction on screen.
    let handle: CGPoint
    let dir: (x: CGFloat, y: CGFloat, angle: Double)
    let screen: CGSize

    @State private var draft = ""
    /// The un-rotated size of the row (plus pad), measured so it can be
    /// placed by its centre and turned about it.
    @State private var size: CGSize = .zero
    @State private var initialValueSelected = true
    @State private var usingSystemKeyboard = AppSettings.prefersSystemKeyboard
    @FocusState private var focused: Bool

    /// Gap from the handle centre to the row: clears the drawn symbol and
    /// most of the handle's grab radius, so a drag on the arrow still starts
    /// on the arrow.
    private static let gapFromHandle: CGFloat = 44
    /// Half the widest editing row, used to keep it on screen.
    private static let editorHalfWidth: CGFloat = 200

    private var editing: Bool { viewModel.editingExtrudeArrow }

    var body: some View {
        VStack(spacing: 6) {
            row
            if editing && !usingSystemKeyboard {
                NumericKeypad(
                    text: $draft,
                    isLocked: nil,
                    initialValueSelected: $initialValueSelected,
                    onCommit: commit,
                    onSwitchToSystemKeyboard: {
                        usingSystemKeyboard = true
                        focused = true
                    }
                )
            }
        }
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        // Turned about its own centre and placed by it. (Pinning an edge with
        // a zero-size frame drew the same, but a rotated zero-size container
        // swallowed every tap: touches outside its bounds were dropped.)
        .rotationEffect(.radians(rotation))
        .position(center)
    }

    // MARK: Layout

    /// Within 60° of horizontal the row follows the arrow, turned half a
    /// turn for a leftward arrow so the text still reads left to right; a
    /// nearly vertical arrow, and the editor, stay level.
    private var followsArrow: Bool { !editing && abs(dir.x) >= 0.5 }

    private var rotation: Double {
        guard followsArrow else { return 0 }
        if dir.x >= 0 { return dir.angle }
        let turned = dir.angle - .pi
        return turned < -.pi ? turned + 2 * .pi : turned
    }

    /// The row's centre: its near end a gap past the handle, the rest
    /// extending away from the arrow along the arrow's direction.
    private var center: CGPoint {
        if editing {
            let top = editorPoint
            return CGPoint(x: top.x, y: top.y + size.height / 2)
        }
        let start = CGPoint(x: handle.x + dir.x * Self.gapFromHandle,
                            y: handle.y + dir.y * Self.gapFromHandle)
        let ideal: CGPoint
        if followsArrow {
            // Either way round, the far end lies further along `dir`.
            ideal = CGPoint(x: start.x + dir.x * size.width / 2,
                            y: start.y + dir.y * size.width / 2)
        } else {
            ideal = CGPoint(x: start.x,
                            y: start.y + (dir.y > 0 ? 1 : -1) * size.height / 2)
        }
        return keptOnScreen(ideal)
    }

    /// Nudge the (turned) row back inside the screen when the arrow sits near
    /// an edge, so every control stays reachable.
    private func keptOnScreen(_ p: CGPoint) -> CGPoint {
        let c = abs(cos(rotation)), s = abs(sin(rotation))
        let halfW = c * size.width / 2 + s * size.height / 2 + 8
        let halfH = s * size.width / 2 + c * size.height / 2 + 8
        func clamp(_ v: CGFloat, _ half: CGFloat, _ extent: CGFloat) -> CGFloat {
            extent > 2 * half ? min(max(v, half), extent - half) : extent / 2
        }
        return CGPoint(x: clamp(p.x, halfW, screen.width), y: clamp(p.y, halfH, screen.height))
    }

    /// Where the level editor hangs: just below the handle, inside the
    /// screen's side margins and in the top part of the screen so the pad or
    /// the keyboard never covers it.
    private var editorPoint: CGPoint {
        let margin = Self.editorHalfWidth + 12
        let x = screen.width > 2 * margin
            ? min(max(handle.x, margin), screen.width - margin)
            : screen.width / 2
        let y = min(max(handle.y + 34, 80), max(80, screen.height * 0.42))
        return CGPoint(x: x, y: y)
    }

    // MARK: Row

    private var row: some View {
        HStack(spacing: 6) {
            optionsMenu
            valueField
            if editing {
                variablesMenu
                keyboardToggle
            }
            iconButton("xmark", label: "Cancel", prominent: false, action: cancel)
            iconButton("checkmark", label: "Extrude", prominent: true, action: commit)
        }
    }

    /// Everything the bottom bar used to hold, one tap away from the value.
    private var optionsMenu: some View {
        Menu {
            Picker("Extent", selection: Binding(
                get: { context.symmetric },
                set: { viewModel.setExtrudeSymmetric($0) }
            )) {
                Text("Total").tag(false)
                Text("Symmetric").tag(true)
            }
            .pickerStyle(.inline)

            // End condition: resolves to a distance from the bodies in the
            // document, which lands on the arrow where it can still change.
            Menu("End") {
                ForEach(ExtrudeEnd.allCases.filter { $0 != .blind }, id: \.self) { end in
                    Button(end.title) { viewModel.resolveExtrudeEnd(end) }
                }
            }

            // Boolean badge: manual result override (spec §4.1).
            Picker("Result", selection: Binding(
                get: { context.booleanOverride },
                set: { viewModel.setBooleanOverride($0) }
            )) {
                ForEach(BooleanOverride.allCases, id: \.self) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.menu)

            // Sketch profiles can revolve about one of their lines, sweep
            // along a path, loft to more profiles, or coil into a helix;
            // face pulls can become an offset construction plane instead.
            if context.sketchID != nil || context.sourceBody != nil {
                Section {
                    if context.sketchID != nil {
                        Button("Revolve") { viewModel.beginRevolveAxisPick() }
                        Button("Sweep") { viewModel.beginSweepPathPick() }
                        Button("Loft") { viewModel.beginLoftProfilePick() }
                        Button("Helix") { viewModel.showHelixOptions = true }
                    }
                    if context.sourceBody != nil {
                        Button("Offset Plane") { viewModel.beginOffsetPlane() }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(label.symmetric ? "Symmetric" : "Total")
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Color.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white, in: Capsule())
        }
        .accessibilityIdentifier("ExtrudeOptionsMenu")
    }

    private var valueField: some View {
        TextField("Distance", text: Binding(
            get: { editing ? draft : label.text },
            set: { if editing { draft = $0 } }
        ))
        .keyboardType(.numbersAndPunctuation)
        .autocorrectionDisabled()
        .multilineTextAlignment(editing ? .leading : .center)
        .font(.system(size: editing ? 16 : 13, weight: .semibold))
        .monospacedDigit()
        .frame(width: fieldWidth)
        .focused($focused)
        // A read-out until tapped, and a display for the pad while it is the
        // input method; only the system keyboard types into it directly.
        .allowsHitTesting(editing && usingSystemKeyboard)
        .submitLabel(.done)
        .onSubmit(commit)
        .padding(.horizontal, 8)
        .padding(.vertical, editing ? 6 : 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color.blue, lineWidth: editing ? 2 : 1.5))
        .foregroundStyle(editing ? Color.primary : Color.blue)
        .contentShape(Rectangle())
        .onTapGesture { if !editing { beginEdit() } }
    }

    /// Shapr3D's fx: mint a variable from what is typed, or use one.
    private var variablesMenu: some View {
        Menu {
            let current = draft
            Button("Create “depth = \(current)”") {
                if let name = viewModel.createVariable(holding: current, preferredName: "depth") {
                    draft = name
                    initialValueSelected = false
                }
            }
            .disabled(current.trimmingCharacters(in: .whitespaces).isEmpty)

            let names = viewModel.variableNames
            if names.isEmpty {
                Text("No available variables")
            } else {
                Section("Variables") {
                    ForEach(names, id: \.self) { name in
                        Button(name) {
                            draft = name
                            initialValueSelected = false
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "function")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityIdentifier("ExtrudeArrowVariables")
    }

    private var keyboardToggle: some View {
        Button {
            if usingSystemKeyboard {
                focused = false
                usingSystemKeyboard = false
            } else {
                usingSystemKeyboard = true
                focused = true
            }
        } label: {
            Image(systemName: usingSystemKeyboard ? "123.rectangle" : "keyboard")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(usingSystemKeyboard ? "Numeric keypad" : "Keyboard")
    }

    private func iconButton(_ symbol: String, label: String, prominent: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                // The row may be turned along the arrow; the glyphs stay upright.
                .rotationEffect(.radians(-rotation))
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .frame(width: 28, height: 28)
                .background(prominent ? AnyShapeStyle(Color.blue) : AnyShapeStyle(.regularMaterial),
                            in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var fieldWidth: CGFloat {
        let text = editing ? draft : label.text
        let font = UIFont.systemFont(ofSize: editing ? 16 : 13, weight: .semibold)
        let measured = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        return editing ? min(280, max(160, measured + 16)) : max(28, measured + 4)
    }

    // MARK: Actions

    private func beginEdit() {
        // Seed with the number on the arrow, unit dropped.
        draft = label.text.replacingOccurrences(
            of: " " + AppSettings.shared.unit.symbol, with: "")
        initialValueSelected = true
        viewModel.beginExtrudeArrowEdit()
        if usingSystemKeyboard { focused = true }
    }

    /// While typing, commits the typed value (which also commits the
    /// feature, like Return); otherwise commits the extrude as it stands.
    private func commit() {
        focused = false
        if editing {
            viewModel.commitExtrudeArrowEdit(draft)
        } else {
            viewModel.commitTool()
        }
    }

    /// While typing, drops the edit and keeps the tool; otherwise cancels
    /// the tool.
    private func cancel() {
        focused = false
        if editing {
            viewModel.cancelExtrudeArrowEdit()
        } else {
            viewModel.cancelTool()
        }
    }
}

private struct ExtrudeArrowField: View {
    @Bindable var viewModel: EditorViewModel
    @State private var text = ""
    @State private var padOpen = false
    @State private var usingSystemKeyboard = AppSettings.prefersSystemKeyboard
    @FocusState private var focused: Bool

    var body: some View {
        // An INLINE card, like the sketch dimension field. A `.popover` works
        // from a bar or a panel but does not reliably present from these
        // canvas-floating overlays, so the pad is stacked under the pill.
        VStack(spacing: 6) {
            pill
            if padOpen && !usingSystemKeyboard {
                NumericKeypad(
                    text: $text,
                    isLocked: nil,
                    onCommit: {
                        padOpen = false
                        viewModel.commitExtrudeArrowEdit(text)
                    },
                    onSwitchToSystemKeyboard: {
                        padOpen = false
                        usingSystemKeyboard = true
                        focused = true
                    }
                )
            }
        }
    }

    private var pill: some View {
        TextField("", text: $text)
            .keyboardType(.numbersAndPunctuation)
            .autocorrectionDisabled()
            .multilineTextAlignment(.center)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .frame(width: 84)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.blue, lineWidth: 1.5))
            .focused($focused)
            .allowsHitTesting(usingSystemKeyboard)
            .submitLabel(.done)
            .onSubmit { viewModel.commitExtrudeArrowEdit(text) }
            .accessibilityIdentifier("ExtrudeArrowField")
            .contentShape(Rectangle())
            .onTapGesture { if !usingSystemKeyboard { padOpen = true } }
            .onAppear {
                // Seed with the numeric part of the current label.
                text = (viewModel.extrudeArrowLabel?.text ?? "")
                    .replacingOccurrences(of: "⌀ ", with: "")
                    .replacingOccurrences(
                        of: " " + AppSettings.shared.unit.symbol, with: "")
                if usingSystemKeyboard { focused = true } else { padOpen = true }
            }
    }
}
