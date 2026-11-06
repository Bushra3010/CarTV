import AVFoundation
import SwiftUI

struct CastView: View {
    @Environment(PlayerController.self) private var player
    @Environment(Purchases.self) private var purchases
    @State private var routeName: String?
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statusCard
                    VStack(spacing: 10) {
                        AirPlayButton().frame(width: 90, height: 90)
                            .background(Theme.card, in: Circle())
                        Text("Choose a car screen or TV").font(.headline)
                    }
                    .padding(.vertical, 8)

                    if let current = player.current {
                        nowPlaying(current)
                    }

                    StepCard(title: "Cast what you're watching", symbol: "airplayvideo", steps: [
                        "Connect this iPhone to the car's display, to a wireless adapter that supports AirPlay, or to the same Wi-Fi as the receiver.",
                        "Tap the AirPlay button above or in the player, then pick the screen.",
                        "Play any channel. The video moves to the car screen and the iPhone becomes the remote.",
                    ])
                    StepCard(title: "Mirror your whole screen", symbol: "rectangle.on.rectangle", steps: [
                        "Open Control Center by swiping down from the top-right corner.",
                        "Tap Screen Mirroring and choose the car display.",
                        "Everything on the iPhone now shows on the car screen, from any app.",
                    ])
                    Label("For passengers only. Never watch video or use this app while driving.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.yellow)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding()
            }
            .navigationTitle("Cast to Car")
            .onAppear(perform: updateRoute)
            .sheet(isPresented: $showPaywall) { PaywallView(reason: "Car mode is part of Backseat Pro.") }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
                DispatchQueue.main.async(execute: updateRoute)
            }
        }
    }

    private var connected: Bool { routeName != nil || player.externalPlaybackActive }

    private var statusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: connected ? "checkmark.circle.fill" : "car.side")
                .font(.largeTitle)
                .foregroundStyle(connected ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(connected ? "Connected" : "Not connected").font(.headline)
                Text(routeName.map { "Sending to \($0)" } ?? (connected ? "Sending to the external screen" : "No car screen or TV selected yet"))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func nowPlaying(_ ch: Channel) -> some View {
        HStack(spacing: 12) {
            ChannelLogo(url: ch.logoURL, name: ch.name, size: 52)
            VStack(alignment: .leading) {
                Text("Now playing").font(.caption).foregroundStyle(.secondary)
                Text(ch.name).font(.headline).lineLimit(1)
            }
            Spacer()
            Button {
                if purchases.isPro || !Entitlements.carModeIsPro {
                    player.carMode = true
                    player.isPresented = true
                } else {
                    showPaywall = true
                }
            } label: {
                Label("Car mode", systemImage: "car.fill").lineLimit(1).fixedSize()
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(.black)
        }
        .padding()
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func updateRoute() {
        routeName = AVAudioSession.sharedInstance().currentRoute.outputs
            .first { $0.portType == .airPlay || $0.portType == .HDMI || $0.portType == .carAudio }?.portName
    }
}

private struct StepCard: View {
    let title: String
    let symbol: String
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(Theme.accent)
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)").font(.caption.bold()).frame(width: 22, height: 22)
                        .background(Theme.card, in: Circle())
                    Text(step).font(.subheadline)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
