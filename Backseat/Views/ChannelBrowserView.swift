import SwiftUI

struct ChannelBrowserView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(PlayerController.self) private var player
    let sourceId: UUID
    @State private var group: String?
    @State private var favouritesOnly = false
    @State private var query = ""
    @State private var renaming: Channel?
    @State private var newName = ""

    private var source: Source? { store.source(sourceId) }

    private var filtered: [Channel] {
        var list = store.channels(for: sourceId)
        if favouritesOnly { list = list.filter { store.isFavorite($0) } }
        if let group { list = list.filter { $0.group == group } }
        if !query.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(query) } }
        return list
    }

    var body: some View {
        let list = filtered
        VStack(spacing: 0) {
            groupChips
            List(list) { ch in
                Button { player.play(ch, queue: list) } label: { ChannelRow(channel: ch, showGroup: group == nil) }
                    .buttonStyle(.plain)
                    .swipeActions {
                        if source?.kind == .local {
                            Button("Delete", systemImage: "trash", role: .destructive) { store.deleteLocalVideo(ch) }
                            Button("Rename", systemImage: "pencil") { newName = ch.name; renaming = ch }.tint(.indigo)
                        }
                    }
            }
            .listStyle(.plain)
            .overlay {
                if list.isEmpty {
                    if !query.isEmpty { ContentUnavailableView.search(text: query) }
                    else { ContentUnavailableView("Nothing here", systemImage: "tv", description: Text(favouritesOnly ? "No favourites in this playlist yet." : "This group is empty.")) }
                }
            }
        }
        .navigationTitle(source?.name ?? "Channels")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search \(store.channels(for: sourceId).count.formatted()) entries")
        .toolbar {
            if source?.kind == .m3u || source?.kind == .xtream {
                if store.refreshing.contains(sourceId) {
                    ProgressView()
                } else {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refresh(sourceId) } }
                }
            }
        }
        .alert("Rename video", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Save") { if let r = renaming { store.renameLocalVideo(r, to: newName) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private var groupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: group == nil && !favouritesOnly) { group = nil; favouritesOnly = false }
                chip("★ Favourites", selected: favouritesOnly) { favouritesOnly.toggle() }
                ForEach(store.groups(for: sourceId), id: \.self) { g in
                    chip(g, selected: group == g) { group = (group == g ? nil : g) }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(selected ? Theme.accent : Theme.card, in: Capsule())
                .foregroundStyle(selected ? Color.black : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
