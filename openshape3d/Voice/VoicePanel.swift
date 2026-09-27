//
//  VoicePanel.swift
//  openshape3d
//
//  PrintCAD V1: the bottom-centre voice card. Shows what the microphone is
//  hearing, what you're pointing at, and — after Enter — Jev's decision. The
//  viewport stays interactive underneath so a face or edge can be clicked
//  mid-sentence. The mic button starts/stops listening; nothing listens on its
//  own. Escape is owned by CommandShortcutsView while open.
//

import SwiftUI

struct VoicePanel: View {
    @Bindable var viewModel: EditorViewModel

    private var voice: VoiceSession { viewModel.voice }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            transcript
            outcome
        }
        .padding(16)
        .frame(maxWidth: 560, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("VoicePanel")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                if voice.isListening {
                    voice.pauseListening()
                } else {
                    Task { await voice.start() }
                }
            } label: {
                MicLevelIndicator(level: voice.level, active: voice.isListening)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(voice.isListening ? "Stop listening" : "Speak")
            .accessibilityIdentifier("VoiceMicButton")

            Text(statusText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isUnavailable ? .red : .primary)
                .lineLimit(2)
            Spacer(minLength: 8)
            Text(viewModel.voiceTarget.chipText)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.tint.opacity(0.15), in: Capsule())
                .accessibilityIdentifier("VoiceTargetChip")
            Button {
                viewModel.closeVoice()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Voice Edit")
            .accessibilityIdentifier("VoiceCloseButton")
        }
    }

    private var isUnavailable: Bool {
        if case .unavailable = voice.phase { return true }
        return false
    }

    private var statusText: String {
        switch voice.phase {
        case .starting: return "Starting microphone…"
        case .listening: return "Listening"
        case .unavailable(let message): return message
        case .idle:
            if voice.isAsking { return "Asking Jev…" }
            return voice.transcript.isEmpty ? "Tap the mic to speak" : "Press Enter to send, or tap the mic to add more"
        }
    }

    // MARK: - Transcript + Enter

    private var transcript: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Group {
                if voice.transcript.isEmpty {
                    Text("Click a face or edge, then say what to do — e.g. “drill a 5 mm hole in the centre”.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(voice.transcript)
                        .foregroundStyle(.primary)
                }
            }
            .font(.title3)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .animation(.easeOut(duration: 0.12), value: voice.transcript)
            .accessibilityIdentifier("VoiceTranscript")

            Button {
                viewModel.submitVoice()
            } label: {
                Label("Enter", systemImage: "return")
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!voice.canSubmit)
            .accessibilityIdentifier("VoiceSubmitButton")
        }
    }

    // MARK: - Jev's answer

    @ViewBuilder
    private var outcome: some View {
        switch voice.outcome {
        case .none:
            EmptyView()
        case .asking(let request):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Sending “\(request.transcript)” · \(request.target.chipText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .accessibilityIdentifier("VoiceAsking")
        case .decided(let request, let decision):
            DecisionView(request: request, decision: decision) { voice.choose($0) }
            if let applied = voice.applied {
                Label(applied.message, systemImage: applied.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(applied.ok ? .green : .red)
                    .lineLimit(3)
                    .accessibilityIdentifier("VoiceApplied")
            }
        case .failed(_, let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(3)
                .accessibilityIdentifier("VoiceError")
        }
    }
}

/// Jev's answer: one line per step, and — for an unsure step — options.
private struct DecisionView: View {
    let request: VoiceRequest
    let decision: VoiceDecision
    let choose: (VoiceAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Jev:")
                    .foregroundStyle(.secondary)
                Text(decision.steps.count == 1 ? summary(decision.steps[0]) : "\(decision.steps.count) steps")
                    .fontWeight(.semibold)
                Spacer(minLength: 8)
                Text("\(Int((decision.confidence * 100).rounded()))% · \(String(format: "%.2f", decision.latency)) s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .font(.callout)

            if decision.steps.count > 1 {
                ForEach(Array(decision.steps.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(summary(step))")
                        .font(.caption)
                        .foregroundStyle(step.needsConfirmation ? .orange : .secondary)
                }
            } else if let step = decision.steps.first, !step.numbers.isEmpty {
                Text(step.numbers.map { "\($0.number.phrase) = \($0.role.rawValue)" }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let index = decision.unsureStepIndex {
                let step = decision.steps[index]
                HStack(spacing: 6) {
                    Text(decision.steps.count > 1 ? "Step \(index + 1) — did you mean:" : "Not sure — did you mean:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(step.suggestions, id: \.action) { option in
                        Button("\(option.action.title) \(Int((option.probability * 100).rounded()))%") {
                            choose(option.action)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Text("“\(request.transcript)” · \(request.target.chipText)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("VoiceDecision")
    }

    private func summary(_ step: VoiceStep) -> String {
        var parts = [step.action.title]
        if step.target != .picked && step.target != .nothing {
            parts.append(step.target.rawValue.replacingOccurrences(of: "_", with: " "))
        }
        if step.placement == .clickedPoint { parts.append("where clicked") }
        if step.placement == .corners { parts.append("corners") }
        if step.depth == .throughAll, [.hole, .cornerHoles, .pocket].contains(step.action) { parts.append("through") }
        let numbers = step.numbers.map(\.number.phrase)
        if !numbers.isEmpty { parts.append(numbers.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

/// Mic glyph with a ring that swells with the input level.
private struct MicLevelIndicator: View {
    let level: Float
    let active: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(active ? 0.25 : 0.12))
                .scaleEffect(active ? 1 + CGFloat(level) * 0.6 : 1)
                .animation(.easeOut(duration: 0.08), value: level)
            Image(systemName: active ? "mic.fill" : "mic")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 34, height: 34)
        .contentShape(Circle())
    }
}
