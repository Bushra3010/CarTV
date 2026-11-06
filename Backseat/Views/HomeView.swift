import SwiftUI

struct HomeView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(PlayerController.self) private var player
    @Environment(AppRouter.self) private var router
    @State private var query = ""
    @State private var voiceSearch = false

    var body: some View {
        NavigationStack {
            Group {
                if !query.isEmpty {
                    searchResults
                } else if store.sources.isEmpty && store.recents.isEmpty {
                    emptyState
                } else {
                    rails
                }
            }
            .navigationTitle("Backseat")
            .searchable(text: $query, prompt: "Search all channels")
            .searchSuggestions {
                if query.isEmpty {
                    ForEach(store.searchHistory, id: \.self) { term in
                        Label(term, systemImage: "clock.arrow.circlepath").searchCompletion(term)
                    }
                }
            }
            .onSubmit(of: .search) { store.addSearch(query) }
            .toolbar {
                Button("Voice search", systemImage: "mic.fill") { voiceSearch = true }
            }
            .sheet(isPresented: $voiceSearch) {
                VoiceSearchSheet { text in
                    query = text
                    store.addSearch(text)
                }
            }
            .navigationDestination(for: String.self) { route in
                if route == "favorites" { FavoritesView() }
            }
        }
    }

    private var searchResults: some View {
        let results = store.search(query)
        return List(results) { ch in
            Button {
                store.addSearch(query)
                player.play(ch, queue: results)
            } label: { ChannelRow(channel: ch) }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
        .overlay {
            if results.isEmpty { ContentUnavailableView.search(text: query) }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Bring your own playlist", systemImage: "play.tv")
        } description: {
            Text("Add an M3U link, an Xtream login or your Jellyfin server. Then send what you watch to the car screen. Everything stays on this iPhone.")
        } actions: {
            Button("Add a playlist") {
                router.tab = .playlists
                router.showAddSource = true
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(.black)
            Button("Try sample test streams") { Task { await store.addSample() } }
        }
    }

    private var rails: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !store.sources.isEmpty { playlistsRail }
                if !store.continueWatching.isEmpty {
                    Rail(title: "Continue watching", channels: store.continueWatching)
                }
                if !store.recents.isEmpty {
                    Rail(title: "Recently played", channels: store.recents)
                }
                if !store.favorites.isEmpty {
                    Rail(title: "Favourites", channels: store.favorites, destination: "favorites")
                } else {
                    hint("Tap ☆ on any channel to pin it here.")
                }
                if store.recents.isEmpty {
                    hint("Open Playlists and pick a channel to start watching.")
                }
            }
            .padding(.vertical)
        }
    }

    private var playlistsRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(store.sources) { source in
                    Button {
                        router.tab = .playlists
                    } label: {
                        Label(source.name, systemImage: source.kind.symbol)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Theme.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary).padding(.horizontal)
    }
}

private struct Rail: View {
    @Environment(LibraryStore.self) private var store
    @Environment(PlayerController.self) private var player
    let title: String
    let channels: [Channel]
    var destination: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.title3.bold())
                Spacer()
                if let destination {
                    NavigationLink("Edit", value: destination).font(.subheadline)
                }
            }
            .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(channels) { ch in
                        Button { player.play(ch, queue: channels) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ChannelLogo(url: ch.logoURL, name: ch.name, size: 96)
                                if let p = store.position(for: ch) {
                                    ProgressView(value: p.progress).tint(Theme.accent).frame(width: 96)
                                }
                                Text(ch.name).font(.caption.weight(.medium)).lineLimit(2).frame(width: 96, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(store.isFavorite(ch) ? "Remove from favourites" : "Add to favourites",
                                   systemImage: store.isFavorite(ch) ? "star.slash" : "star") { store.toggleFavorite(ch) }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct FavoritesView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(PlayerController.self) private var player

    var body: some View {
        List {
            ForEach(store.favorites) { ch in
                Button { player.play(ch, queue: store.favorites) } label: { ChannelRow(channel: ch) }
                    .buttonStyle(.plain)
            }
            .onMove { store.moveFavorites(from: $0, to: $1) }
            .onDelete { store.removeFavorites(at: $0) }
        }
        .navigationTitle("Favourites")
        .toolbar { EditButton() }
        .overlay {
            if store.favorites.isEmpty { ContentUnavailableView("No favourites", systemImage: "star") }
        }
    }
}
