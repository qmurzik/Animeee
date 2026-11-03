import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct ExtraCatalog: EpisodeCatalog {
    let source: CatalogSource
    let transport: MirrorTransport
    let origins: [URL]
    init(source: CatalogSource, session: URLSession? = nil, primary: String? = nil) {
        self.source = source; transport = MirrorTransport(session: session)
        origins = MirrorAddress.candidates(primary: primary, defaults: source == .animego ? source.sites : [source.api])
    }
    private func get(_ path: String, _ query: [URLQueryItem] = []) async throws -> MirrorResponse {
        try await transport.get(origins: origins, path: path, query: query, anilib: source == .anilib)
    }
    func search(_ query: String) async throws -> [SourceTitle] {
        switch source {
        case .shikimori:
            let response = try await get("/api/animes", [.init(name: "search", value: query), .init(name: "limit", value: "30")])
            return try JSONDecoder().decode([ShikiTitle].self, from: response.data).map { $0.normalized(origin: response.origin) }
        case .anilib:
            let response = try await get("/api/anime", [.init(name: "q", value: query), .init(name: "site_id[]", value: "5")])
            return try JSONDecoder().decode(LibEnvelope<[LibTitle]>.self, from: response.data).data.map(\.normalized)
        case .animego:
            let response = try await get("/search/anime", [.init(name: "q", value: query)])
            return AnimeGoHTML.search(String(decoding: response.data, as: UTF8.self), origin: response.origin)
        }
    }
    func episodes(_ title: SourceTitle) async throws -> [SourceEpisode] {
        switch source {
        case .shikimori: return [] // Shikimori's public videos endpoint is clips, not episodes.
        case .anilib:
            let response = try await get("/api/episodes", [.init(name: "anime_id", value: title.key)])
            let episodes = try JSONDecoder().decode(LibEnvelope<[LibEpisode]>.self, from: response.data).data
            return episodes.map { .init(id: String($0.id), number: $0.number, title: $0.name, season: $0.season) }.sorted {
                if $0.season != $1.season { return EpisodeNumber.isBefore($0.season, $1.season) }
                return EpisodeNumber.isBefore($0.number, $1.number)
            }
        case .animego:
            guard let id = title.key.split(separator: "-").last, Int(id) != nil else { throw URLError(.badURL) }
            let response = try await get("/player/\(id)")
            let html = try JSONDecoder().decode(GoEnvelope.self, from: response.data).data.content
            let episodes = AnimeGoHTML.episodes(html)
            if episodes.isEmpty { throw SourceFailure(message: "Источник не вернул список серий в поддерживаемом формате.") }
            return episodes
        }
    }
    func players(_ episode: SourceEpisode, title: SourceTitle) async throws -> [SourcePlayer] {
        guard Int(episode.id) != nil else { throw URLError(.badURL) }
        switch source {
        case .shikimori: return []
        case .anilib:
            let response = try await get("/api/episodes/\(episode.id)")
            let detail = try JSONDecoder().decode(LibEnvelope<LibEpisodeDetail>.self, from: response.data).data
            return detail.players.compactMap { player in
                guard let embed = SourceURL.https(player.src) else { return nil }
                return SourcePlayer(id: String(player.id), studio: player.team?.name ?? "Без команды", translation: player.translation_type?.label ?? "Перевод не указан", balancer: player.player, embed: embed)
            }
        case .animego:
            let response = try await get("/player/videos/\(episode.id)")
            let html = try JSONDecoder().decode(GoEnvelope.self, from: response.data).data.content
            return AnimeGoHTML.players(html)
        }
    }
}
enum SourceURL {
    static func https(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw.hasPrefix("//") ? "https:" + raw : raw), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
}
struct ShikiTitle: Decodable {
    struct Image: Decodable { let original: String? }
    let id: Int; let name: String; let russian: String?; let image: Image?; let url: String
    func normalized(origin: URL) -> SourceTitle {
        SourceTitle(source: .shikimori, key: String(id), title: russian?.isEmpty == false ? russian! : name,
                    poster: image?.original.flatMap { URL(string: $0, relativeTo: origin)?.absoluteURL }, pagePath: url, shikimoriID: id)
    }
}
struct LibEnvelope<T: Decodable>: Decodable { let data: T }
struct LibTitle: Decodable {
    struct Cover: Decodable { let `default`: String? }
    let id: Int; let slug_url: String; let name: String; let rus_name: String?; let cover: Cover?; let shikimori_href: String?
    var normalized: SourceTitle {
        let shiki = shikimori_href.flatMap(URL.init(string:)).flatMap { url -> Int? in
            guard ["shikimori.io", "shikimori.one", "shikimori.me"].contains(url.host ?? ""), url.path.hasPrefix("/animes/") else { return nil }
            let component = url.lastPathComponent
            return Int(component.drop(while: { !$0.isNumber }).prefix(while: \.isNumber))
        }
        return SourceTitle(source: .anilib, key: slug_url, title: rus_name?.isEmpty == false ? rus_name! : name, poster: SourceURL.https(cover?.default), pagePath: "/ru/anime/" + slug_url, shikimoriID: shiki)
    }
}
struct LibEpisode: Decodable { let id: Int; let number: String; let name: String?; let season: String? }
struct LibEpisodeDetail: Decodable {
    struct Player: Decodable {
        struct Team: Decodable { let name: String }
        struct Translation: Decodable { let label: String }
        let id: Int; let player: String; let team: Team?; let translation_type: Translation?; let src: String?
    }
    let players: [Player]
}
struct GoEnvelope: Decodable { struct Content: Decodable { let content: String }; let data: Content }
// Small bounded parser for public attributes. Never executes a player script or decodes protected URLs.
enum AnimeGoHTML {
    static func matches(_ pattern: String, _ value: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let s = value as NSString
        return regex.matches(in: value, range: NSRange(location: 0, length: s.length)).map { match in
            (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : s.substring(with: match.range(at: $0)) }
        }
    }
    static func attr(_ name: String, _ tag: String) -> String? {
        matches("(?:^|\\s)" + NSRegularExpression.escapedPattern(for: name) + "\\s*=\\s*([\"'])(.*?)\\1", tag).first.map { unescape($0[2]) }
    }
    static func unescape(_ s: String) -> String { s.replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#039;", with: "'").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&") }
    static func text(_ s: String) -> String { unescape(s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)).trimmingCharacters(in: .whitespacesAndNewlines) }
    static func search(_ html: String, origin: URL) -> [SourceTitle] {
        var seen = Set<String>()
        return matches("<a\\b([^>]*href\\s*=\\s*[\"'][^\"']*/anime/[^\"']+[\"'][^>]*)>(.*?)</a>", html).compactMap { match in
            guard let href = attr("href", match[1]), let url = URL(string: href, relativeTo: origin)?.absoluteURL, url.host == origin.host, url.path.hasPrefix("/anime/") else { return nil }
            let name = matches("<img\\b([^>]*)>", match[2]).first.flatMap { attr("alt", $0[1]) } ?? text(match[2])
            guard !name.isEmpty, seen.insert(url.path).inserted else { return nil }
            let poster = matches("<img\\b([^>]*)>", match[2]).first.flatMap { attr("src", $0[1]) }.flatMap { URL(string: $0, relativeTo: origin)?.absoluteURL }
            return SourceTitle(source: .animego, key: url.lastPathComponent, title: name, poster: poster, pagePath: url.path, shikimoriID: nil)
        }
    }
    static func episodes(_ html: String) -> [SourceEpisode] {
        var seen = Set<String>()
        return matches("<[^>]+\\bdata-episode=[^>]+>", html).compactMap { match in
            guard let id = attr("data-episode", match[0]), Int(id) != nil, let number = attr("data-episode-number", match[0]), seen.insert(id).inserted else { return nil }
            return SourceEpisode(id: id, number: number, title: attr("data-episode-title", match[0]), season: nil)
        }.sorted { EpisodeNumber.isBefore($0.number, $1.number) }
    }
    static func players(_ html: String) -> [SourcePlayer] {
        var seen = Set<String>()
        let labels = Dictionary(matches("<button\\b([^>]*data-translation=[^>]*)>(.*?)</button>", html).compactMap { m -> (String, String)? in
            guard let id = attr("data-translation", m[1]) else { return nil }; return (id, text(m[2]))
        }, uniquingKeysWith: { first, _ in first })
        return matches("<button\\b([^>]*data-player=[^>]*)>(.*?)</button>", html).compactMap { m in
            guard let url = SourceURL.https(attr("data-player", m[1])), seen.insert(url.absoluteString).inserted else { return nil }
            let voiceID = attr("data-ptranslation", m[1]) ?? ""
            return SourcePlayer(id: url.absoluteString, studio: attr("data-translation-title", m[1]) ?? labels[voiceID] ?? "Перевод не указан", translation: "Перевод источника", balancer: text(m[2]), embed: url)
        }
    }
}
