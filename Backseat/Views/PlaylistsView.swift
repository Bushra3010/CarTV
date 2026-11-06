import SwiftUI

struct PlaylistsView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(Purchases.self) private var purchases
    @State private var renaming: Source?
    @State private var showPaywall = false
    @State private var newName = ""

    var body: some View {
        @Bindable var router = router
        NavigationStack {
            List {
                ForEach(store.sources) { source in
                    NavigationLink(value: source.id) { SourceRow(source: source) }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) { store.delete(source.id) }
                            Button("Rename", systemImage: "pencil") { startRename(source) }.tint(.indigo)
                        }
                        .swipeActions(edge: .leading) {
                            if canRefresh(source) {
                                Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refresh(source.id) } }.tint(.blue)
                            }
                        }
                        .contextMenu {
                            if canRefresh(source) {
                                Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refresh(source.id) } }
                            }
                            Button("Rename", systemImage: "pencil") { startRename(source) }
                            Button("Delete", systemImage: "trash", role: .destructive) { store.delete(source.id) }
                        }
                }
            }
            .overlay {
                if store.sources.isEmpty {
                    ContentUnavailableView {
                        Label("No playlists yet", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("Backseat comes with no channels. Add a playlist or server you have the right to use.")
                    } actions: {
                        Button("Add a playlist") { router.showAddSource = true }.buttonStyle(.borderedProminent)
            .foregroundStyle(.black)
                    }
                }
            }
            .refreshable { await store.refreshAll() }
            .navigationTitle("Playlists")
            .toolbar {
                Button("Add", systemImage: "plus") {
                    if purchases.canAddPlaylist(store.sources.count) { router.showAddSource = true } else { showPaywall = true }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let source = store.source(id) {
                    if source.kind == .jellyfin {
                        ServerBrowseView(sourceId: id, parent: nil)
                    } else {
                        ChannelBrowserView(sourceId: id)
                    }
                }
            }
            .navigationDestination(for: ServerRoute.self) { route in
                ServerBrowseView(sourceId: route.sourceId, parent: route.item)
            }
            .sheet(isPresented: $router.showAddSource) { AddSourceView() }
            .sheet(isPresented: $showPaywall) {
                PaywallView(reason: "The free version holds \(Entitlements.freePlaylistLimit) playlists. Pro removes the limit.")
            }
            .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Save") { if let r = renaming { store.rename(r.id, to: newName) }; renaming = nil }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
        }
    }

    private func canRefresh(_ s: Source) -> Bool { s.kind == .m3u || s.kind == .xtream }

    private func startRename(_ s: Source) {
        newName = s.name
        renaming = s
    }
}

private struct SourceRow: View {
    @Environment(LibraryStore.self) private var store
    let source: Source

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: source.kind.symbol)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(source.name).font(.headline).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                if let err = source.lastError {
                    Label(err, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red).lineLimit(2)
                }
            }
            Spacer()
            if store.refreshing.contains(source.id) { ProgressView() }
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        var parts = [source.kind.title]
        if source.kind != .jellyfin {
            parts.append("\(store.channels(for: source.id).count.formatted()) entries")
        }
        if let d = source.lastRefreshed { parts.append("updated \(d.relative)") }
        return parts.joined(separator: " · ")
    }
}
