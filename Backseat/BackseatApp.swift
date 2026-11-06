import SwiftUI

enum AppTab: Hashable { case home, playlists, cast, settings }

@MainActor @Observable
final class AppRouter {
    var tab: AppTab = .home
    var showAddSource = false
}

@main
struct BackseatApp: App {
    @State private var store: LibraryStore
    @State private var player: PlayerController
    @State private var router = AppRouter()
    @State private var purchases = Purchases()

    init() {
        URLCache.shared = URLCache(memoryCapacity: 40_000_000, diskCapacity: 300_000_000)
        let store = LibraryStore()
        let player = PlayerController()
        player.store = store
        _store = State(initialValue: store)
        _player = State(initialValue: player)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(player)
                .environment(router)
                .environment(purchases)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @Environment(PlayerController.self) private var player
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        @Bindable var player = player
        TabView(selection: $router.tab) {
            Tab("Home", systemImage: "play.tv", value: AppTab.home) { HomeView().miniPlayerInset() }
            Tab("Playlists", systemImage: "list.bullet.rectangle.portrait", value: AppTab.playlists) { PlaylistsView().miniPlayerInset() }
            Tab("Cast to Car", systemImage: "car.rear.and.tire.marks", value: AppTab.cast) { CastView().miniPlayerInset() }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) { SettingsView().miniPlayerInset() }
        }
        .fullScreenCover(isPresented: $player.isPresented) {
            PlayerScreen()
        }
    }
}
