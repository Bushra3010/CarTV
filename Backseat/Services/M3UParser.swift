import Foundation

enum M3UParser {
    private static let attributeRegex = try! Regex(#"([A-Za-z0-9_\-]+)="([^"]*)""#)

    /// True when the text is an HLS stream manifest rather than a channel list.
    static func isHLSManifest(_ text: String) -> Bool {
        text.contains("#EXT-X-TARGETDURATION") || text.contains("#EXT-X-STREAM-INF") || text.contains("#EXT-X-MEDIA-SEQUENCE")
    }

    static func parse(_ text: String, sourceId: UUID) -> [Channel] {
        var channels: [Channel] = []
        var name: String?
        var logo: String?
        var group: String?
        var seen = Set<String>()

        text.enumerateLines { raw, _ in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return }
            if line.hasPrefix("#EXTINF") {
                let info = parseExtInf(Substring(line))
                name = info.name.isEmpty ? info.attributes["tvg-name"] : info.name
                logo = info.attributes["tvg-logo"]
                group = info.attributes["group-title"]
            } else if line.hasPrefix("#EXTGRP:") {
                group = String(line.dropFirst("#EXTGRP:".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("#") {
                return
            } else {
                let url = line
                let finalName = (name?.isEmpty == false ? name! : URL(string: url)?.lastPathComponent) ?? url
                let finalGroup = (group?.isEmpty == false) ? group! : "Ungrouped"
                let channel = Channel(sourceId: sourceId, name: finalName, streamURL: url, logoURL: logo, group: finalGroup)
                if seen.insert(channel.key).inserted { channels.append(channel) }
                name = nil; logo = nil; group = nil
            }
        }
        return channels
    }

    static func parseExtInf(_ line: Substring) -> (attributes: [String: String], name: String) {
        var inQuotes = false
        var comma: Substring.Index?
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if c == "\"" { inQuotes.toggle() } else if c == ",", !inQuotes { comma = i; break }
            i = line.index(after: i)
        }
        let head = comma.map { line[..<$0] } ?? line
        let name = comma.map { String(line[line.index(after: $0)...]).trimmingCharacters(in: .whitespaces) } ?? ""
        var attributes: [String: String] = [:]
        for match in head.matches(of: attributeRegex) {
            if let key = match.output[1].substring, let value = match.output[2].substring {
                attributes[key.lowercased()] = String(value)
            }
        }
        return (attributes, name)
    }
}

enum SamplePlaylist {
    /// Public test streams for trying the app without a playlist of your own.
    static let text = """
    #EXTM3U
    #EXTINF:-1 group-title="Test streams (HLS)",Apple Bipbop (fMP4, multi-audio)
    https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8
    #EXTINF:-1 group-title="Test streams (HLS)",Apple Bipbop 16x9
    https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8
    #EXTINF:-1 group-title="Test streams (HLS)",Big Buck Bunny (Mux)
    https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8
    #EXTINF:-1 group-title="Test streams (HLS)",Tears of Steel (Unified Streaming)
    https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8
    #EXTINF:-1 group-title="Test streams (HLS)",Apple Bipbop (audio only)
    https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/gear0/prog_index.m3u8
    #EXTINF:-1 group-title="Sample movies (MP4)",Sintel (trailer)
    https://download.blender.org/durian/trailer/sintel_trailer-480p.mp4
    #EXTINF:-1 group-title="Sample movies (MP4)",Big Buck Bunny (10s clip)
    https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4
    #EXTINF:-1 group-title="Sample movies (MP4)",Jellyfish (10s clip)
    https://test-videos.co.uk/vids/jellyfish/mp4/h264/720/Jellyfish_720_10s_1MB.mp4
    #EXTINF:-1 group-title="Sample movies (MP4)",Flower (MDN, CC0)
    https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4
    """
}
