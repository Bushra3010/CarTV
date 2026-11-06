import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Purchases.self) private var purchases
    @AppStorage("openInCarMode") private var openInCarMode = false
    @AppStorage("visualizerStyle") private var visualizerStyle = VisualizerStyle.bars.rawValue
    @State private var confirmClear = false
    @State private var showPaywall = false
    @State private var restoreMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { showPaywall = true } label: {
                        HStack(spacing: 14) {
                            Image(systemName: purchases.isPro ? "checkmark.seal.fill" : "sparkles")
                                .font(.title2).foregroundStyle(.black)
                                .frame(width: 44, height: 44)
                                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(purchases.isPro ? "Backseat Pro is active" : "Upgrade to Backseat Pro").font(.headline)
                                Text(purchases.isPro ? "Thanks for your support" : "Car mode, unlimited playlists and more")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    Button("Restore purchases") {
                        Task {
                            do { try await purchases.restore(); restoreMessage = "Pro restored." }
                            catch { restoreMessage = error.localizedDescription }
                        }
                    }
                } footer: {
                    if let restoreMessage { Text(restoreMessage) }
                }

                Section("Playback") {
                    Toggle(isOn: Binding(get: { openInCarMode }, set: { on in
                        if on, !purchases.isPro, Entitlements.carModeIsPro { showPaywall = true } else { openInCarMode = on }
                    })) {
                        proLabel("Open videos in car mode", pro: Entitlements.carModeIsPro)
                    }
                    Picker(selection: Binding(get: { visualizerStyle }, set: { raw in
                        if VisualizerStyle(rawValue: raw)?.isPro == true, !purchases.isPro { showPaywall = true } else { visualizerStyle = raw }
                    })) {
                        ForEach(VisualizerStyle.allCases) { style in
                            Text(style.isPro && !purchases.isPro ? "\(style.title) (Pro)" : style.title).tag(style.rawValue)
                        }
                    } label: {
                        Text("Audio visualizer")
                    }
                }
                Section {
                    Button("Clear search history") { store.clearSearchHistory() }
                    Button("Clear recently played") { store.clearRecents() }
                    Button("Clear watch progress", role: .destructive) { confirmClear = true }
                } header: { Text("Data") } footer: {
                    Text("Playlists, favourites and progress are stored only on this iPhone. Backseat has no account and no servers of its own.")
                }
                Section("Help") {
                    DisclosureGroup("Why won't a channel play?") {
                        Text("The stream may be offline, geo-blocked, or in a format iPhone can't decode (for example MPEG-2 video or DTS audio). Try refreshing the playlist or ask your provider for an HLS (.m3u8) link.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Casting stopped working") {
                        Text("Make sure the iPhone and the car display are on the same network. Turn the car's wireless adapter off and on, then choose it again from the AirPlay button. Screen Mirroring in Control Center works for every app.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("How do I add a playlist by QR code?") {
                        Text("Open Playlists, tap +, then Scan a QR code. Xtream links that contain a username and password fill in the login form for you.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    Text("Backseat is a media player. It provides no channels, playlists or content. Only add playlists and servers you have the right to use.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("For passengers only. Never watch video while driving.")
                        .font(.footnote.weight(.semibold)).foregroundStyle(.yellow)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Clear watch progress for every video?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear progress", role: .destructive) { store.clearProgress() }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }

    private func proLabel(_ title: String, pro: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title)
            if pro && !purchases.isPro {
                Text("PRO").font(.caption2.bold()).padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Theme.accent, in: Capsule()).foregroundStyle(.black)
            }
        }
    }
}
