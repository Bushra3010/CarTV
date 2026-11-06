import Foundation

enum SourceKind: String, Codable, CaseIterable, Identifiable {
    case m3u, xtream, jellyfin, local
    var id: String { rawValue }

    var title: String {
        switch self {
        case .m3u: "M3U URL"
        case .xtream: "Xtream Codes"
        case .jellyfin: "Jellyfin / Emby"
        case .local: "Local videos"
        }
    }

    var shortTitle: String {
        switch self {
        case .m3u: "M3U"
        case .xtream: "Xtream"
        case .jellyfin: "Server"
        case .local: "Files"
        }
    }

    var symbol: String {
        switch self {
        case .m3u: "list.bullet.rectangle"
        case .xtream: "antenna.radiowaves.left.and.right"
        case .jellyfin: "server.rack"
        case .local: "iphone"
        }
    }
}

/// A playlist or media server the user added. Passwords and tokens live in the Keychain, not here.
struct Source: Identifiable, Codable, Hashable {
    static let sampleURL = "builtin:sample"

    var id = UUID()
    var kind: SourceKind
    var name: String
    var url: String
    var username: String = ""
    var userId: String?
    var addedAt = Date()
    var lastRefreshed: Date?
    var lastError: String?

    var secretKey: String { "source.\(id.uuidString)" }
}

/// One playable entry: a live channel, a movie, an episode or a local file.
struct Channel: Identifiable, Codable, Hashable {
    var key: String
    var sourceId: UUID
    var name: String
    /// http(s) URL, `local://<file>` for imported videos, or `jellyfin://<itemId>`.
    var streamURL: String
    var logoURL: String?
    var group: String

    var id: String { key }

    init(sourceId: UUID, name: String, streamURL: String, logoURL: String? = nil, group: String, key: String? = nil) {
        self.sourceId = sourceId
        self.name = name
        self.streamURL = streamURL
        self.logoURL = logoURL?.isEmpty == true ? nil : logoURL
        self.group = group
        self.key = key ?? "\(sourceId.uuidString)|\(streamURL)"
    }
}

struct PlaybackPosition: Codable, Hashable {
    var seconds: Double
    var duration: Double
    var updatedAt = Date()
    var progress: Double { duration > 0 ? min(1, seconds / duration) : 0 }
}

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let m): m }
    }
}
