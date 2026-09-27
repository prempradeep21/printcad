//
//  VoicePanel.swift
//  openshape3d
//
//  PrintCAD V1.1: the bottom-centre voice card. Shows what the microphone is
//  hearing as you speak, what you're pointing at, and — after Enter — what was
//  sent. The viewport stays interactive underneath so a face or edge can be
//  clicked mid-sentence. Escape is owned by CommandShortcutsView while open.
//

import SwiftUI

struct VoicePanel: View {
    @Bindable var viewModel: EditorViewModel

    private var voice: VoiceSession { viewModel.voice }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            transcript
            if let request = voice.lastRequest {
                sentLine(request)
            }
        }
        .padding(16)
        .frame(maxWidth: 560, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("VoicePanel")
    }

    private var header: some View {
        HStack(spacing: 10) {
            MicLevelIndicator(level: voice.level, active: voice.isListening)
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

    private func sentLine(_ request: VoiceRequest) -> some View {
        // V1.1: nothing is executed yet — say so plainly.
        Text("Would send: “\(request.transcript)” · \(request.target.chipText)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .accessibilityIdentifier("VoiceLastRequest")
    }

    private var isUnavailable: Bool {
        if case .unavailable = voice.phase { return true }
        return false
    }

    private var statusText: String {
        switch voice.phase {
        case .idle: return "Voice Edit"
        case .starting: return "Starting microphone…"
        case .listening: return "Listening"
        case .unavailable(let message): return message
        }
    }
}

/// Mic glyph with a ring that swells with the input level.
private struct MicLevelIndicator: View {
    let level: Float
    let active: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(active ? 0.25 : 0.08))
                .scaleEffect(active ? 1 + CGFloat(level) * 0.6 : 1)
                .animation(.easeOut(duration: 0.08), value: level)
            Image(systemName: active ? "mic.fill" : "mic.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? Color.accentColor : .secondary)
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }
}
