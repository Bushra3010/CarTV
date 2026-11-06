import SwiftUI

struct VoiceSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerController.self) private var player
    @State private var voice = VoiceSearch()
    @State private var resumePlayback = false
    let onResult: (String) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text(voice.isListening ? "Listening…" : (voice.error == nil ? "Say a channel name" : "Voice search"))
                .font(.headline).foregroundStyle(.secondary)
            Text(voice.transcript.isEmpty ? " " : voice.transcript)
                .font(.title.bold()).multilineTextAlignment(.center).frame(minHeight: 80)
            if let error = voice.error {
                Text(error).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Button {
                if voice.isListening { finish() } else { Task { await voice.start() } }
            } label: {
                Image(systemName: voice.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 88, height: 88)
                    .background(Theme.accent, in: Circle())
                    .symbolEffect(.pulse, isActive: voice.isListening)
            }
            .accessibilityLabel(voice.isListening ? "Stop listening" : "Start listening")
            HStack {
                Button("Cancel") { voice.stop(); dismiss() }
                Spacer()
                Button("Search") { finish() }.bold().disabled(voice.transcript.isEmpty)
            }
        }
        .padding(24)
        .presentationDetents([.medium])
        .task {
            resumePlayback = player.isPlaying
            player.player.pause()
            await voice.start()
        }
        .onDisappear {
            voice.stop()
            if resumePlayback { player.player.play() }
        }
        .onChange(of: voice.isListening) { was, now in
            if was, !now, !voice.transcript.isEmpty, voice.error == nil { finish() }
        }
    }

    private func finish() {
        voice.stop()
        let text = voice.transcript.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { onResult(text) }
        dismiss()
    }
}
