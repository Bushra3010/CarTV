import Foundation

enum Net {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = ["User-Agent": "Backseat/1.0"]
        return URLSession(configuration: config)
    }()

    static func data(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw AppError.message("The server refused the login (HTTP \(http.statusCode)). Check the username and password.")
            }
            throw AppError.message("The server answered with HTTP \(http.statusCode).")
        }
        return data
    }

    static func text(_ url: URL) async throws -> String {
        let data = try await data(URLRequest(url: url))
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    /// Accepts "host:port", "http://host/", and similar, and returns a clean base URL.
    static func normalizeServer(_ raw: String, stripping suffixes: [String] = []) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "http://" + s }
        if let q = s.firstIndex(of: "?") { s = String(s[..<q]) }
        for suffix in suffixes where s.hasSuffix(suffix) { s = String(s.dropLast(suffix.count)) }
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }
}

/// Values in Xtream JSON can be strings or numbers, depending on the panel.
private func xs(_ any: Any?) -> String? {
    switch any {
    case let s as String: s
    case let n as NSNumber: n.stringValue
    default: nil
    }
}

struct XtreamClient {
    let server: URL
    let username: String
    let password: String

    private func call(_ action: String?) async throws -> Any {
        var comps = URLComponents(url: server.appendingPathComponent("player_api.php"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "username", value: username), URLQueryItem(name: "password", value: password)]
        if let action { comps.queryItems?.append(URLQueryItem(name: "action", value: action)) }
        let data = try await Net.data(URLRequest(url: comps.url!))
        return try JSONSerialization.jsonObject(with: data)
    }

    private func categories(_ action: String) async throws -> [String: String] {
        let list = (try await call(action) as? [[String: Any]]) ?? []
        var map: [String: String] = [:]
        for c in list { if let id = xs(c["category_id"]), let name = xs(c["category_name"]) { map[id] = name } }
        return map
    }

    func loadChannels(sourceId: UUID) async throws -> [Channel] {
        let auth = try await call(nil) as? [String: Any]
        guard let info = auth?["user_info"] as? [String: Any], xs(info["auth"]) == "1" else {
            throw AppError.message("Login failed. Check the server, username and password.")
        }
        let base = server.absoluteString
        let u = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let p = password.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? password

        var channels: [Channel] = []
        let liveCats = try await categories("get_live_categories")
        let live = (try await call("get_live_streams") as? [[String: Any]]) ?? []
        for s in live {
            guard let id = xs(s["stream_id"]) else { continue }
            channels.append(Channel(sourceId: sourceId, name: xs(s["name"]) ?? "Channel \(id)",
                                    streamURL: "\(base)/live/\(u)/\(p)/\(id).m3u8", logoURL: xs(s["stream_icon"]),
                                    group: liveCats[xs(s["category_id"]) ?? ""] ?? "Live"))
        }
        // Movies are optional; some panels have none or disable the endpoint.
        if let vodCats = try? await categories("get_vod_categories"),
           let vod = try? await call("get_vod_streams") as? [[String: Any]] {
            for s in vod {
                guard let id = xs(s["stream_id"]) else { continue }
                let ext = xs(s["container_extension"]) ?? "mp4"
                channels.append(Channel(sourceId: sourceId, name: xs(s["name"]) ?? "Movie \(id)",
                                        streamURL: "\(base)/movie/\(u)/\(p)/\(id).\(ext)", logoURL: xs(s["stream_icon"]),
                                        group: "Movies · " + (vodCats[xs(s["category_id"]) ?? ""] ?? "Other")))
            }
        }
        if channels.isEmpty { throw AppError.message("This account has no channels.") }
        return channels
    }
}

struct JFItem: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: String?
    let isFolder: Bool?
    let productionYear: Int?
    let indexNumber: Int?
    let parentIndexNumber: Int?
    let seriesId: String?
    let seriesName: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", type = "Type", isFolder = "IsFolder", productionYear = "ProductionYear"
        case indexNumber = "IndexNumber", parentIndexNumber = "ParentIndexNumber", seriesId = "SeriesId", seriesName = "SeriesName"
    }

    var isBrowsable: Bool {
        if isFolder == true { return true }
        return ["CollectionFolder", "Series", "Season", "BoxSet", "Folder", "UserView"].contains(type ?? "")
    }

    var subtitle: String? {
        if type == "Episode", let s = parentIndexNumber, let e = indexNumber { return "S\(s) · E\(e)" }
        if let y = productionYear { return String(y) }
        return nil
    }
}

private struct JFItemsResponse: Decodable {
    let items: [JFItem]
    enum CodingKeys: String, CodingKey { case items = "Items" }
}

struct JellyfinClient {
    let server: URL
    var token: String?
    var userId: String?

    static var deviceId: String {
        if let id = UserDefaults.standard.string(forKey: "deviceId") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "deviceId")
        return id
    }

    private var authHeader: String {
        var h = #"MediaBrowser Client="Backseat", Device="iPhone", DeviceId="\#(Self.deviceId)", Version="1.0""#
        if let token { h += #", Token="\#(token)""# }
        return h
    }

    private func request(_ path: String, query: [String: String] = [:], method: String = "GET", body: Data? = nil) -> URLRequest {
        var comps = URLComponents(url: server.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.httpBody = body
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue(authHeader, forHTTPHeaderField: "X-Emby-Authorization")
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return req
    }

    func authenticate(username: String, password: String) async throws -> (token: String, userId: String) {
        let body = try JSONSerialization.data(withJSONObject: ["Username": username, "Pw": password])
        let data = try await Net.data(request("Users/AuthenticateByName", method: "POST", body: body))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["AccessToken"] as? String,
              let user = json["User"] as? [String: Any], let uid = user["Id"] as? String else {
            throw AppError.message("This does not look like a Jellyfin or Emby server.")
        }
        return (token, uid)
    }

    private func items(_ req: URLRequest) async throws -> [JFItem] {
        try JSONDecoder().decode(JFItemsResponse.self, from: try await Net.data(req)).items
    }

    func libraries() async throws -> [JFItem] {
        try await items(request("Users/\(userId ?? "")/Views"))
    }

    func children(of item: JFItem) async throws -> [JFItem] {
        switch item.type {
        case "Series":
            return try await items(request("Shows/\(item.id)/Seasons", query: ["userId": userId ?? ""]))
        case "Season":
            return try await items(request("Shows/\(item.seriesId ?? item.id)/Episodes",
                                           query: ["userId": userId ?? "", "seasonId": item.id]))
        default:
            return try await items(request("Users/\(userId ?? "")/Items",
                                           query: ["ParentId": item.id, "SortBy": "SortName", "SortOrder": "Ascending",
                                                   "Fields": "ProductionYear"]))
        }
    }

    func imageURL(_ itemId: String) -> URL? {
        var c = URLComponents(url: server.appendingPathComponent("Items/\(itemId)/Images/Primary"), resolvingAgainstBaseURL: false)
        c?.queryItems = [URLQueryItem(name: "maxHeight", value: "300")]
        return c?.url
    }

    func streamURL(_ itemId: String) -> URL? {
        var c = URLComponents(url: server.appendingPathComponent("Videos/\(itemId)/master.m3u8"), resolvingAgainstBaseURL: false)
        c?.queryItems = [
            URLQueryItem(name: "MediaSourceId", value: itemId),
            URLQueryItem(name: "DeviceId", value: Self.deviceId),
            URLQueryItem(name: "api_key", value: token),
            URLQueryItem(name: "VideoCodec", value: "h264,hevc"),
            URLQueryItem(name: "AudioCodec", value: "aac,mp3,ac3,eac3"),
            URLQueryItem(name: "SegmentContainer", value: "mp4"),
            URLQueryItem(name: "TranscodingMaxAudioChannels", value: "6"),
        ]
        return c?.url
    }
}
