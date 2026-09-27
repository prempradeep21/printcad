//
//  RecenterButton.swift
//  openshape3d
//
//  A one-tap "bring everything back" control beside the orientation cube:
//  frames every sketch and body in view (the same fit as Fit View), so a
//  model panned or zoomed off screen is one tap away wherever the eye already
//  is — the cube's corner — rather than up in the toolbar.
//

import SwiftUI

struct RecenterButton: View {
    @Bindable var viewModel: EditorViewModel

    /// Gap between the button and the cube's left edge.
    private static let gap: CGFloat = 8
    private static let size: CGFloat = 36

    var body: some View {
        GeometryReader { geo in
            let cube = OrientationCube.rect(in: geo.size)
            Button {
                viewModel.fitView()
            } label: {
                Image(systemName: "viewfinder")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: Self.size, height: Self.size)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().stroke(.quaternary, lineWidth: 0.5))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Recenter")
            .accessibilityIdentifier("RecenterButton")
            .position(x: cube.minX - Self.gap - Self.size / 2, y: cube.midY)
        }
        // The cube is placed in the full-bleed Metal view's coordinates; a
        // safe-area-inset overlay would sit ~85pt below it.
        .ignoresSafeArea()
    }
}
