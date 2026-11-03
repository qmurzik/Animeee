import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum CatalogSource: String, CaseIterable, Identifiable, Codable {
    case shikimori, anilib, animego
    var id: String { rawValue }
    var title: String { switch self { case .shikimori: return "Shikimori"; case .anilib: return "AnimeLIB"; case .animego: return "AnimeGO" } }
    var sites: [String] { switch self {
    case .shikimori: return ["https://shikimori.io"]
    case .anilib: return ["https://animelib.org", "https://anilib.me"]
    case .animego: return ["https://animego.me", "https://animego.org"]
    } }
    var api: String { self == .anilib ? "https://hapi.hentaicdn.org" : sites[0] }
    var note: String { switch self {
    case .shikimori: return "Каталог и клипы. Серии ищутся в YummyAnime по подтверждённому Shikimori ID."
    case .anilib: return "Серии и команды перевода из AnimeLIB. Для Kodik используется отдельный плеер источника."
    case .animego: return "Экспериментальный адаптер. При HTTP 500 серии недоступны; остальные источники продолжают работать."
    } }
}
struct SourceTitle: Identifiable, Hashable {
    let source: CatalogSource
    let key: String
    let title: String
    let poster: URL?
    let pagePath: String
    let shikimoriID: Int?
    var id: String { source.rawValue + ":" + key }
}
struct SourceEpisode: Identifiable, Hashable {
    let id: String
    let number: String
    let title: String?
    let season: String?
}
struct SourcePlayer: Identifiable, Hashable {
    let id: String
    let studio: String
    let translation: String
    let balancer: String
    let embed: URL
    var label: String { studio + " · " + translation }
}
struct SourceFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
enum MirrorAddress {
    // Only HTTPS origins; paths, credentials and query strings must never become a mirror.
    static func parse(_ raw: String) -> URL? {
        guard let c = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              c.scheme == "https", let host = c.host, host.contains("."), c.user == nil, c.password == nil,
              c.port == nil || c.port == 443, c.query == nil, c.fragment == nil,
              c.path.isEmpty || c.path == "/", !host.contains(":"), host != "localhost",
              host.split(separator: ".").contains(where: { Int($0) == nil }),
              let url = URL(string: "https://" + host.lowercased()) else { return nil }
        return url
    }
    static func candidates(primary: String?, defaults: [String]) -> [URL] {
        var seen = Set<String>()
        return ([primary].compactMap { $0 } + defaults).compactMap(parse).filter { seen.insert($0.absoluteString).inserted }
    }
}
struct MirrorResponse { let data: Data; let origin: URL }
final class MirrorRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // There are no tokens/cookies in API requests. Never downgrade a redirected request.
        completionHandler(request.url?.scheme == "https" ? request : nil)
    }
}
struct MirrorTransport {
    let session: URLSession
    // Reuse a bounded connection pool during searches instead of retaining a new delegate session per query.
    private static let publicSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config, delegate: MirrorRedirects(), delegateQueue: nil)
    }()
    init(session: URLSession? = nil) { self.session = session ?? Self.publicSession }
    func get(origins: [URL], path: String, query: [URLQueryItem] = [], anilib: Bool = false) async throws -> MirrorResponse {
        var failures: [String] = []
        for origin in origins {
            try Task.checkCancellation()
            guard var c = URLComponents(url: origin, resolvingAgainstBaseURL: false), path.hasPrefix("/"), !path.hasPrefix("//") else { throw URLError(.badURL) }
            c.path = path; c.queryItems = query.isEmpty ? nil : query
            guard let url = c.url else { throw URLError(.badURL) }
            var request = URLRequest(url: url, timeoutInterval: 12)
            request.setValue("application/json, text/html;q=0.9", forHTTPHeaderField: "Accept")
            request.setValue("AnimeApp/0.8 (iOS client)", forHTTPHeaderField: "User-Agent")
            if anilib { request.setValue("5", forHTTPHeaderField: "Site-Id") }
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                guard !(200..<300).contains(http.statusCode) else {
                    guard data.count <= 12_000_000 else { throw SourceFailure(message: "Ответ источника слишком большой") }
                    var actual = URLComponents(url: http.url ?? origin, resolvingAgainstBaseURL: false)
                    actual?.path = ""; actual?.query = nil; actual?.fragment = nil
                    return MirrorResponse(data: data, origin: actual?.url ?? origin)
                }
                let message = "\(origin.host ?? "Источник"): HTTP \(http.statusCode)"
                // Authentication, access restrictions and rate limits are not mirror failures.
                if [401, 403, 429].contains(http.statusCode) { throw SourceFailure(message: message + ". Требуется доступ на стороне сервиса; переключение зеркал остановлено.") }
                if http.statusCode < 500 { throw SourceFailure(message: message) }
                failures.append(message)
            } catch let error as URLError {
                if error.code == .cancelled { throw error }
                failures.append("\(origin.host ?? "Источник"): \(error.localizedDescription)")
            }
        }
        throw SourceFailure(message: failures.isEmpty ? "Нет настроенного адреса источника" : failures.joined(separator: "\n"))
    }
}
protocol EpisodeCatalog {
    func search(_ query: String) async throws -> [SourceTitle]
    func episodes(_ title: SourceTitle) async throws -> [SourceEpisode]
    func players(_ episode: SourceEpisode, title: SourceTitle) async throws -> [SourcePlayer]
}
