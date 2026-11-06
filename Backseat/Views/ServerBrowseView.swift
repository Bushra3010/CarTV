import SwiftUI

struct ServerRoute: Hashable {
    let sourceId: UUID
    let item: JFItem
}

struct ServerBrowseView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(PlayerController.self) private var player
    let sourceId: UUID
    let parent: JFItem?

    @State private var items: [JFItem] = []
    @State private var loading = true
    @State private var error: String?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    var body: some View {
        ScrollView {
            if parent?.type == "Season" {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        Button { play(item) } label: { episodeRow(item) }.buttonStyle(.plain)
                        Divider().padding(.leading)
                    }
                }
            } else {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(items) { item in
                        if item.isBrowsable {
                            NavigationLink(value: ServerRoute(sourceId: sourceId, item: item)) { tile(item) }.buttonStyle(.plain)
                        } else {
                            Button { play(item) } label: { tile(item) }.buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
        }
        .overlay {
            if loading { ProgressView() }
            else if let error {
                ContentUnavailableView {
                    Label("Could not load", systemImage: "wifi.exclamationmark")
                } description: { Text(error) } actions: {
                    Button("Try again") { Task { await load() } }
                }
            } else if items.isEmpty {
                ContentUnavailableView("Empty", systemImage: "film.stack")
            }
        }
        .navigationTitle(parent?.name ?? store.source(sourceId)?.name ?? "Library")
        .task { await load() }
        .refreshable { await load() }
    }

    private var client: JellyfinClient? { store.jellyfinClient(for: sourceId) }

    private func load() async {
        guard let client else { error = "Server details are missing. Remove and add the server again."; loading = false; return }
        loading = items.isEmpty
        error = nil
        do {
            if let parent { items = try await client.children(of: parent) } else { items = try await client.libraries() }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func channel(_ item: JFItem) -> Channel {
        let group = item.seriesName ?? parent?.name ?? store.source(sourceId)?.name ?? "Library"
        let name = item.type == "Episode" ? "\(item.subtitle.map { "\($0) · " } ?? "")\(item.name)" : item.name
        return Channel(sourceId: sourceId, name: name, streamURL: "jellyfin://\(item.id)",
                       logoURL: client?.imageURL(item.id)?.absoluteString, group: group, key: "\(sourceId.uuidString)|jf:\(item.id)")
    }

    private func play(_ item: JFItem) {
        let queue = items.filter { !$0.isBrowsable }.map(channel)
        player.play(channel(item), queue: queue)
    }

    private func tile(_ item: JFItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: client?.imageURL(item.id)) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { Theme.card.overlay(Image(systemName: item.isBrowsable ? "folder" : "film").foregroundStyle(.secondary)) }
            }
            .frame(height: 160)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(item.name).font(.caption.weight(.medium)).lineLimit(2)
            if let s = item.subtitle { Text(s).font(.caption2).foregroundStyle(.secondary) }
        }
    }

    private func episodeRow(_ item: JFItem) -> some View {
        let ch = channel(item)
        return HStack(spacing: 12) {
            AsyncImage(url: client?.imageURL(item.id)) { phase in
                if let image = phase.image { image.resizable().scaledToFill() } else { Theme.card }
            }
            .frame(width: 120, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.subtitle ?? "").font(.caption).foregroundStyle(.secondary)
                Text(item.name).font(.subheadline.weight(.medium)).lineLimit(2)
                if let p = store.position(for: ch) { ProgressView(value: p.progress).tint(Theme.accent) }
            }
            Spacer()
            Image(systemName: "play.circle").font(.title2).foregroundStyle(Theme.accent)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
