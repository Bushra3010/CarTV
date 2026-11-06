import Foundation
import Observation

@MainActor @Observable
final class LibraryStore {
    private(set) var sources: [Source] = []
    private(set) var channelsBySource: [UUID: [Channel]] = [:]
    private(set) var groupsBySource: [UUID: [String]] = [:]
    private(set) var favorites: [Channel] = []
    private(set) var recents: [Channel] = []
    private(set) var positions: [String: PlaybackPosition] = [:]
    private(set) var searchHistory: [String] = []
    private(set) var refreshing: Set<UUID> = []

    private struct State: Codable {
        var sources: [Source] = []
        var favorites: [Channel] = []
        var recents: [Channel] = []
        var positions: [String: PlaybackPosition] = [:]
        var searchHistory: [String] = []
    }

    init() {
        let state = Persistence.load(State.self, from: "state.json") ?? State()
        sources = state.sources
        favorites = state.favorites
        recents = state.recents
        positions = state.positions
        searchHistory = state.searchHistory
        for source in sources {
            if let list = Persistence.load([Channel].self, from: channelFile(source.id)) { setChannels(list, for: source.id) }
        }
    }

    // MARK: Persistence

    private func channelFile(_ id: UUID) -> String { "channels-\(id.uuidString).json" }

    private func persist() {
        Persistence.save(State(sources: sources, favorites: favorites, recents: recents,
                               positions: positions, searchHistory: searchHistory), to: "state.json")
    }

    private func setChannels(_ list: [Channel], for id: UUID, save: Bool = false) {
        channelsBySource[id] = list
        var seen = Set<String>()
        groupsBySource[id] = list.compactMap { seen.insert($0.group).inserted ? $0.group : nil }
        if save { Persistence.save(list, to: channelFile(id)) }
    }

    // MARK: Queries

    func source(_ id: UUID) -> Source? { sources.first { $0.id == id } }
    func channels(for id: UUID) -> [Channel] { channelsBySource[id] ?? [] }
    func groups(for id: UUID) -> [String] { groupsBySource[id] ?? [] }
    var allChannels: [Channel] { sources.flatMap { channelsBySource[$0.id] ?? [] } }

    func search(_ query: String, limit: Int = 200) -> [Channel] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var out: [Channel] = []
        for source in sources {
            for ch in channelsBySource[source.id] ?? [] where ch.name.localizedCaseInsensitiveContains(q) {
                out.append(ch)
                if out.count >= limit { return out }
            }
        }
        return out
    }

    /// The URL AVPlayer should open. Server tokens are read from the Keychain at play time.
    func playableURL(for channel: Channel) -> URL? {
        if channel.streamURL.hasPrefix("local://") {
            return Persistence.localMediaDirectory.appendingPathComponent(String(channel.streamURL.dropFirst("local://".count)))
        }
        if channel.streamURL.hasPrefix("jellyfin://") {
            guard let client = jellyfinClient(for: channel.sourceId) else { return nil }
            return client.streamURL(String(channel.streamURL.dropFirst("jellyfin://".count)))
        }
        return URL(string: channel.streamURL)
            ?? URL(string: channel.streamURL.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? "")
    }

    func jellyfinClient(for sourceId: UUID) -> JellyfinClient? {
        guard let s = source(sourceId), let url = URL(string: s.url) else { return nil }
        return JellyfinClient(server: url, token: Keychain.get(s.secretKey), userId: s.userId)
    }

    // MARK: Sources

    func addM3U(name: String, url raw: String) async throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == Source.sampleURL || (URL(string: trimmed)?.scheme?.hasPrefix("http") ?? false) else {
            throw AppError.message("Enter a full playlist URL that starts with http:// or https://")
        }
        var source = Source(kind: .m3u, name: name.isEmpty ? (URL(string: trimmed)?.host ?? "Playlist") : name, url: trimmed)
        let list = try await fetchChannels(source)
        source.lastRefreshed = Date()
        insert(source, channels: list)
    }

    func addSample() async {
        guard !sources.contains(where: { $0.url == Source.sampleURL }) else { return }
        try? await addM3U(name: "Sample test streams", url: Source.sampleURL)
    }

    func addXtream(name: String, server raw: String, username: String, password: String) async throws {
        guard let server = Net.normalizeServer(raw, stripping: ["/player_api.php", "/get.php"]) else {
            throw AppError.message("Enter the server address.")
        }
        var source = Source(kind: .xtream, name: name.isEmpty ? (server.host ?? "Xtream") : name,
                            url: server.absoluteString, username: username)
        let list = try await XtreamClient(server: server, username: username, password: password).loadChannels(sourceId: source.id)
        source.lastRefreshed = Date()
        Keychain.set(password, for: source.secretKey)
        insert(source, channels: list)
    }

    func addJellyfin(name: String, server raw: String, username: String, password: String) async throws {
        guard let server = Net.normalizeServer(raw, stripping: ["/web/index.html", "/web"]) else {
            throw AppError.message("Enter the server address.")
        }
        let auth = try await JellyfinClient(server: server).authenticate(username: username, password: password)
        var source = Source(kind: .jellyfin, name: name.isEmpty ? (server.host ?? "Media server") : name,
                            url: server.absoluteString, username: username)
        source.userId = auth.userId
        source.lastRefreshed = Date()
        Keychain.set(auth.token, for: source.secretKey)
        insert(source, channels: [])
    }

    func importLocalFiles(_ urls: [URL]) throws {
        var source = sources.first { $0.kind == .local } ?? Source(kind: .local, name: "On This iPhone", url: "local")
        var list = channels(for: source.id)
        let fm = FileManager.default
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var dest = Persistence.localMediaDirectory.appendingPathComponent(url.lastPathComponent)
            var n = 1
            while fm.fileExists(atPath: dest.path) {
                dest = Persistence.localMediaDirectory.appendingPathComponent(
                    "\(url.deletingPathExtension().lastPathComponent) \(n).\(url.pathExtension)")
                n += 1
            }
            try fm.copyItem(at: url, to: dest)
            list.append(Channel(sourceId: source.id, name: dest.deletingPathExtension().lastPathComponent,
                                streamURL: "local://\(dest.lastPathComponent)", group: "Videos"))
        }
        source.lastRefreshed = Date()
        if sources.contains(where: { $0.id == source.id }) {
            update(source)
            setChannels(list, for: source.id, save: true)
        } else {
            insert(source, channels: list)
        }
    }

    private func insert(_ source: Source, channels list: [Channel]) {
        sources.append(source)
        setChannels(list, for: source.id, save: true)
        persist()
    }

    private func update(_ source: Source) {
        guard let i = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[i] = source
        persist()
    }

    private func fetchChannels(_ source: Source) async throws -> [Channel] {
        switch source.kind {
        case .m3u:
            if source.url == Source.sampleURL { return M3UParser.parse(SamplePlaylist.text, sourceId: source.id) }
            guard let url = URL(string: source.url) else { throw AppError.message("Invalid URL.") }
            let text = try await Net.text(url)
            if M3UParser.isHLSManifest(text) {
                return [Channel(sourceId: source.id, name: source.name, streamURL: source.url, group: "Streams")]
            }
            let id = source.id
            let list = await Task.detached(priority: .userInitiated) { M3UParser.parse(text, sourceId: id) }.value
            if list.isEmpty { throw AppError.message("No channels found. Is this an M3U playlist?") }
            return list
        case .xtream:
            guard let server = URL(string: source.url) else { throw AppError.message("Invalid server.") }
            return try await XtreamClient(server: server, username: source.username,
                                          password: Keychain.get(source.secretKey) ?? "").loadChannels(sourceId: source.id)
        case .jellyfin, .local:
            return channels(for: source.id)
        }
    }

    func refresh(_ id: UUID) async {
        guard var source = source(id), !refreshing.contains(id) else { return }
        refreshing.insert(id)
        defer { refreshing.remove(id) }
        do {
            let list = try await fetchChannels(source)
            setChannels(list, for: id, save: true)
            source.lastRefreshed = Date()
            source.lastError = nil
        } catch {
            source.lastError = error.localizedDescription
        }
        update(source)
    }

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for s in sources where s.kind == .m3u || s.kind == .xtream {
                group.addTask { await self.refresh(s.id) }
            }
        }
    }

    func rename(_ id: UUID, to name: String) {
        guard var s = source(id), !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        s.name = name.trimmingCharacters(in: .whitespaces)
        update(s)
    }

    func delete(_ id: UUID) {
        guard let s = source(id) else { return }
        if s.kind == .local {
            for ch in channels(for: id) { if let url = playableURL(for: ch) { try? FileManager.default.removeItem(at: url) } }
        }
        Keychain.delete(s.secretKey)
        Persistence.remove(channelFile(id))
        sources.removeAll { $0.id == id }
        channelsBySource[id] = nil
        groupsBySource[id] = nil
        favorites.removeAll { $0.sourceId == id }
        recents.removeAll { $0.sourceId == id }
        persist()
    }

    func deleteLocalVideo(_ channel: Channel) {
        guard source(channel.sourceId)?.kind == .local else { return }
        if let url = playableURL(for: channel) { try? FileManager.default.removeItem(at: url) }
        setChannels(channels(for: channel.sourceId).filter { $0.key != channel.key }, for: channel.sourceId, save: true)
        favorites.removeAll { $0.key == channel.key }
        recents.removeAll { $0.key == channel.key }
        persist()
    }

    func renameLocalVideo(_ channel: Channel, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let list = channels(for: channel.sourceId).map { ch -> Channel in
            var c = ch
            if c.key == channel.key { c.name = trimmed }
            return c
        }
        setChannels(list, for: channel.sourceId, save: true)
    }

    // MARK: Favourites, recents, progress

    func isFavorite(_ channel: Channel) -> Bool { favorites.contains { $0.key == channel.key } }

    func toggleFavorite(_ channel: Channel) {
        if isFavorite(channel) { favorites.removeAll { $0.key == channel.key } } else { favorites.append(channel) }
        persist()
    }

    func moveFavorites(from: IndexSet, to: Int) {
        favorites.move(fromOffsets: from, toOffset: to)
        persist()
    }

    func removeFavorites(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        persist()
    }

    func markPlayed(_ channel: Channel) {
        recents.removeAll { $0.key == channel.key }
        recents.insert(channel, at: 0)
        if recents.count > 30 { recents.removeLast(recents.count - 30) }
        persist()
    }

    func position(for channel: Channel) -> PlaybackPosition? { positions[channel.key] }

    func savePosition(_ channel: Channel, seconds: Double, duration: Double) {
        guard duration.isFinite, duration > 30, seconds.isFinite else { return }
        if seconds < 5 || seconds > duration - 15 {
            positions[channel.key] = nil
        } else {
            positions[channel.key] = PlaybackPosition(seconds: seconds, duration: duration)
        }
        persist()
    }

    func clearPosition(_ channel: Channel) {
        positions[channel.key] = nil
        persist()
    }

    var continueWatching: [Channel] {
        recents.filter { positions[$0.key] != nil }
    }

    func addSearch(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        searchHistory.removeAll { $0.caseInsensitiveCompare(t) == .orderedSame }
        searchHistory.insert(t, at: 0)
        if searchHistory.count > 15 { searchHistory.removeLast() }
        persist()
    }

    func clearSearchHistory() { searchHistory = []; persist() }
    func clearRecents() { recents = []; persist() }
    func clearProgress() { positions = [:]; persist() }
}
