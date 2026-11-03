import SwiftUI
import AVKit
import VLCKitSPM
import UniformTypeIdentifiers
import Security
import WebKit

struct Anime: Codable, Identifiable {
    struct Name: Codable { let main: String; let english: String? }
    struct Poster: Codable { let src: String? }
    struct ExternalID: Codable { let id: Int? }
    let id: Int
    let mal: ExternalID?
    let name: Name
    let poster: Poster?
    let description: String?
    let year: Int?
    let episodes: [Episode]?
    var shikimoriID: Int? = nil
    var imageURL: URL? { guard let src = poster?.src else { return nil }; return URL(string: src.hasPrefix("http") ? src : "https://anilibria.top" + src) }
}
struct Segment: Codable { let start: Double?; let stop: Double?
    var valid: Bool { guard let start, let stop else { return false }; return start >= 0 && stop > start }
}
struct Episode: Codable, Identifiable {
    let id: String
    let ordinal: Double?
    let name: String?
    let opening: Segment?
    let ending: Segment?
    let duration: Double?
    let hls_480: String?
    let hls_720: String?
    let hls_1080: String?
    var streams: [(String, String)] { [("1080p", hls_1080), ("720p", hls_720), ("480p", hls_480)].compactMap { label, value in value.map { (label, $0) } } }
}
protocol AnimeProvider {
    func latest() async throws -> [Anime]
    func search(_ text: String) async throws -> [Anime]
    func release(_ id: Int) async throws -> Anime
}
struct Libria: AnimeProvider {
    private func fetch<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: "https://anilibria.top/api/v1/" + path) else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }
    func latest() async throws -> [Anime] { try await fetch("anime/releases/latest?limit=30") }
    func search(_ text: String) async throws -> [Anime] { var c = URLComponents(); c.queryItems = [URLQueryItem(name: "query", value: text)]; return try await fetch("app/search/releases" + (c.percentEncodedQuery.map { "?" + $0 } ?? "")) }
    func release(_ id: Int) async throws -> Anime { try await fetch("anime/releases/\(id)") }
}
@main struct AnimeApp: App {
    var body: some Scene { WindowGroup { AppRoute().preferredColorScheme(.dark).tint(Cinema.accent).task { _ = try? await YaniAPI.restore() } } }
}
struct AppRoute: View {
    var body: some View {
        #if DEBUG
        if let probe = ProcessInfo.processInfo.environment["ANIMEAPP_PROBE"], ["aksor", "cvh"].contains(probe) {
            PlaybackProbeView(mode: probe)
        } else if ProcessInfo.processInfo.environment["ANIMEAPP_SCREEN"] == "detail" { NavigationStack { DetailView(id: -119) } } else { RootView() }
        #else
        RootView()
        #endif
    }
}
#if DEBUG
// CI-only launch route; excluded from the release IPA.
struct PlaybackProbeView: View {
    let mode: String
    var video: YaniVideo {
        if mode == "aksor" { return YaniVideo(video_id: 709233, data: .init(player: "Aksor", dubbing: "SHIZA Project"), number: "1", iframe_url: "https://player.aksor.tv/video/8d4b9ff83b37b94e542c49fa3a8d2286") }
        return YaniVideo(video_id: 1310106, data: .init(player: "CVH", dubbing: "FumoDub"), number: "1", iframe_url: "https://ru.yummyani.me/iframeCVH.html?dubbing_code=FumoDub&anime_id=51404&episode=1")
    }
    @State private var context: WatchRequest?
    var body: some View {
        Group {
            if ProcessInfo.processInfo.environment["ANIMEAPP_UI_TEST"] == "1" {
                RootView().fullScreenCover(item: $context) { request in MultiSourcePlayerScreen(sourceAnime: request.anime, video: request.video, videos: request.videos) }
            } else {
                NavigationStack {
                    if let context { MultiSourcePlayerScreen(sourceAnime: context.anime, video: context.video, videos: context.videos) }
                    else { ProgressView("Загружаем тестовый тайтл…") }
                }
            }
        }.task {
            guard context == nil else { return }
            if mode == "aksor", let anime = try? await YaniAPI.detail(119), let all = try? await YaniAPI.videos(119), let actual = all.first(where: { $0.id == video.id }) {
                context = WatchRequest(anime: anime, video: actual, videos: all.filter { $0.supportsNativePlayback })
            } else {
                let anime = Anime(id: -100, mal: nil, name: .init(main: "Проверка потока \(mode.uppercased())", english: nil), poster: nil, description: nil, year: nil, episodes: nil)
                context = WatchRequest(anime: anime, video: video, videos: [video])
            }
        }
    }
}
#endif
// YummyAnime is an independent catalog. Negative local IDs namespace its IDs
// separately from the existing positive AniLibria IDs in saved data.
struct YaniCatalogItem: Decodable {
    struct Image: Decodable { let fullsize: String?; let big: String? }
    struct IDs: Decodable { let myanimelist_id: Int?; let shikimori_id: Int? }
    let anime_id: Int
    let title: String
    let description: String?
    let year: Int?
    let poster: Image?
    let remote_ids: IDs?
    var anime: Anime {
        let image = poster?.big ?? poster?.fullsize
        return Anime(id: -anime_id, mal: remote_ids?.myanimelist_id.map { .init(id: $0) }, name: .init(main: title, english: nil), poster: image.map { .init(src: $0.hasPrefix("//") ? "https:" + $0 : $0) }, description: description, year: year, episodes: nil, shikimoriID: remote_ids?.shikimori_id)
    }
}
struct YaniCatalogResponse: Decodable { let response: [YaniCatalogItem] }
struct YaniDetailResponse: Decodable { let response: YaniCatalogItem }
struct YaniProfileResponse: Decodable {
    struct Profile: Decodable { let id: Int; let nickname: String? }
    let response: Profile
}
struct YaniDiscardResponse: Decodable {}
struct YaniTokenResponse: Decodable {
    struct Token: Decodable { let token: String }
    let response: Token
}
enum SessionKeychain {
    private static let service = "com.animeapp.viewer.yani"
    static func read() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "session", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func write(_ token: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "session"]
        let values: [String: Any] = [kSecValueData as String: Data(token.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let result = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if result == errSecItemNotFound {
            var added = query; values.forEach { added[$0.key] = $0.value }
            guard SecItemAdd(added as CFDictionary, nil) == errSecSuccess else { throw CocoaError(.fileWriteUnknown) }
        } else if result != errSecSuccess { throw CocoaError(.fileWriteUnknown) }
    }
    static func clear() { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "session"] as CFDictionary) }
}
struct YaniAPIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}
final class YaniHTTP: NSObject, URLSessionTaskDelegate {
    static let session = URLSession(configuration: .ephemeral, delegate: YaniHTTP(), delegateQueue: nil)
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.host == "api.yani.tv" && request.url?.scheme == "https" ? request : nil)
    }
}
enum YaniAPI {
    static func request<T: Decodable>(_ path: String, query: [URLQueryItem] = [], method: String = "GET", body: Data? = nil, token: String? = nil) async throws -> T {
        var parts = URLComponents(); parts.scheme = "https"; parts.host = "api.yani.tv"; parts.path = path; if !query.isEmpty { parts.queryItems = query }
        guard let url = parts.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 25); request.httpMethod = method; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept"); request.setValue("ru", forHTTPHeaderField: "Lang")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let bearer = token ?? SessionKeychain.read(), !bearer.isEmpty { request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization") }
        let (data, response) = try await YaniHTTP.session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw YaniAPIError(status: response.statusCode, message: json?["error"] as? String ?? "YummyAnime: HTTP \(response.statusCode)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    static func catalog(query: String? = nil, offset: Int = 0) async throws -> [Anime] {
        var params = [URLQueryItem(name: "limit", value: "30"), URLQueryItem(name: "offset", value: String(offset))]
        if let query, !query.isEmpty { params.append(.init(name: "q", value: query)) }
        let result: YaniCatalogResponse = try await request("/anime", query: params)
        return result.response.map(\.anime)
    }
    static func detail(_ id: Int) async throws -> Anime { let result: YaniDetailResponse = try await request("/anime/\(id)"); return result.response.anime }
    static func videos(_ id: Int) async throws -> [YaniVideo] { let result: YaniVideosResponse = try await request("/anime/\(id)/videos"); return result.response.filter { $0.page != nil } }
    @MainActor static func accept(_ token: String, expectedToken: String? = nil) async throws -> YaniProfileResponse.Profile {
        let generation = UserDefaults.standard.string(forKey: "yaniRevision") ?? ""
        if let expectedToken, SessionKeychain.read() != expectedToken { throw CancellationError() }
        guard !token.isEmpty, token.utf8.count <= 16384 else { throw URLError(.userAuthenticationRequired) }
        let profile: YaniProfileResponse = try await request("/profile", token: token)
        guard profile.response.id > 0 else { throw URLError(.userAuthenticationRequired) }
        guard (UserDefaults.standard.string(forKey: "yaniRevision") ?? "") == generation else { throw CancellationError() }
        if let expectedToken, SessionKeychain.read() != expectedToken { throw CancellationError() }
        try SessionKeychain.write(token)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "yaniTokenRefreshed")
        UserDefaults.standard.set(profile.response.nickname ?? "YummyAnime", forKey: "yaniNickname")
        UserDefaults.standard.set(UUID().uuidString, forKey: "yaniRevision")
        return profile.response
    }
    @MainActor static func restore() async throws -> YaniProfileResponse.Profile? {
        guard let token = SessionKeychain.read() else { return nil }
        do {
            if Date().timeIntervalSince1970 - UserDefaults.standard.double(forKey: "yaniTokenRefreshed") > 172800 {
                let renewed: YaniTokenResponse = try await request("/profile/token", token: token)
                return try await accept(renewed.response.token, expectedToken: token)
            }
            let response: YaniProfileResponse = try await request("/profile", token: token)
            guard SessionKeychain.read() == token else { return nil }
            return response.response
        } catch let error as YaniAPIError where error.status == 401 { if SessionKeychain.read() == token { clearSession(); throw error }; return nil }
    }
    @MainActor static func logout() async { let token = SessionKeychain.read(); clearSession(); if let token { let _: YaniDiscardResponse? = try? await request("/profile/logout", method: "POST", token: token) } }
    @MainActor static func clearSession() { SessionKeychain.clear(); UserDefaults.standard.removeObject(forKey: "yaniNickname"); UserDefaults.standard.set(UUID().uuidString, forKey: "yaniRevision") }
}
struct YaniAccountView: View {
    @State private var login = ""
    @State private var password = ""
    @State private var busy = false
    @State private var message: String?
    @State private var web = false
    @AppStorage("yaniNickname") private var nickname = ""
    @State private var authorized = SessionKeychain.read() != nil
    var body: some View {
        Form {
            Section("Аккаунт YummyAnime") {
                if authorized {
                    Label(nickname.isEmpty ? "YummyAnime" : nickname, systemImage: "person.crop.circle.fill")
                    Button("Выйти", role: .destructive) { Task { busy = true; await YaniAPI.logout(); authorized = false; busy = false } }.disabled(busy)
                } else {
                    Text("Используется тот же аккаунт, что на сайте YummyAnime. Сессия сохраняется в Keychain.").font(.footnote).foregroundStyle(.secondary)
                    Button("Войти через сайт YummyAnime") { web = true }
                    TextField("Логин или email", text: $login).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username)
                    SecureField("Пароль", text: $password).textContentType(.password)
                    Button("Войти по логину и паролю") { Task { await signIn() } }.disabled(busy || login.isEmpty || password.isEmpty)
                }
                if busy { ProgressView() }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
            Section { Link("Открыть официальный сайт", destination: URL(string: "https://ru.yummyani.me/")!) }
        }.navigationTitle("YummyAnime").sheet(isPresented: $web) {
            NavigationStack {
                YaniSiteLogin { token in
                    guard !busy else { return }; busy = true
                    Task { do { let profile = try await YaniAPI.accept(token); nickname = profile.nickname ?? "YummyAnime"; authorized = true; web = false; message = nil } catch { message = error.localizedDescription }; busy = false }
                }.safeAreaInset(edge: .top) { Text(message ?? "Войдите на официальном сайте. После успешного входа приложение проверит сессию через API и сохранит её в Keychain.").font(.footnote).padding().background(.ultraThinMaterial) }
                .navigationTitle("Вход на сайте").navigationBarTitleDisplayMode(.inline).toolbar { Button("Закрыть") { web = false } }
            }
        }.task { do { if let profile = try await YaniAPI.restore() { nickname = profile.nickname ?? "YummyAnime"; authorized = true } else { authorized = SessionKeychain.read() != nil } } catch { authorized = SessionKeychain.read() != nil; message = error.localizedDescription } }.onDisappear { password = "" }
    }
    func signIn() async {
        busy = true; message = nil
        defer { busy = false }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["login": login, "password": password, "need_json": true])
            let result: YaniTokenResponse = try await YaniAPI.request("/profile/login", method: "POST", body: body)
            let profile = try await YaniAPI.accept(result.response.token)
            nickname = profile.nickname ?? login; password = ""; authorized = true
        } catch { message = "\(error.localizedDescription). Если сайт требует капчу, используйте вход через сайт." }
    }
}
struct YaniSiteLogin: UIViewRepresentable {
    let accept: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(accept: accept) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "yaniSignIn")
        // Observe only successful authentication responses from the service in the
        // user-requested login window. Passwords/cookies/localStorage are never read.
        let script = #"""
        (() => {
          if (!['ru.yummyani.me','yummyani.me','api.yani.tv'].includes(location.hostname)) return;
          function authenticationURL(raw) { try { const u = new URL(raw, location.href); return u.protocol === 'https:' && u.hostname === 'api.yani.tv' && ['/profile/login','/profile/token'].includes(u.pathname); } catch (_) { return false; } }
          function receive(data) { const value = data && data.response && data.response.token; if (typeof value === 'string' && value.length > 0 && value.length <= 16384) window.webkit.messageHandlers.yaniSignIn.postMessage(value); }
          const original = window.fetch;
          window.fetch = async function(...args) { const response = await original.apply(this,args); if (response.ok && authenticationURL(response.url)) response.clone().json().then(receive).catch(()=>{}); return response; };
          const open = XMLHttpRequest.prototype.open;
          XMLHttpRequest.prototype.open = function(...args) { this.addEventListener('load',function() { if (this.status >= 200 && this.status < 300 && authenticationURL(this.responseURL)) { try { receive(this.responseType === 'json' ? this.response : JSON.parse(this.responseText)); } catch (_) {} } }); return open.apply(this,args); };
        })();
        """#
        configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: configuration); view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: URL(string: "https://ru.yummyani.me/")!)); return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) { view.stopLoading(); view.configuration.userContentController.removeScriptMessageHandler(forName: "yaniSignIn") }
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let accept: (String) -> Void
        init(accept: @escaping (String) -> Void) { self.accept = accept }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, ["ru.yummyani.me", "yummyani.me", "api.yani.tv"].contains(message.frameInfo.securityOrigin.host), let token = message.body as? String, !token.isEmpty, token.utf8.count <= 16384 else { return }
            accept(token)
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) { decisionHandler(navigationAction.request.url?.scheme == "https" || navigationAction.request.url?.scheme == "about" ? .allow : .cancel) }
    }
}
struct YaniSearchResponse: Decodable {
    struct Item: Decodable {
        struct RemoteIDs: Decodable { let myanimelist_id: Int? }
        let anime_id: Int
        let remote_ids: RemoteIDs?
    }
    let response: [Item]
}
struct YaniVideosResponse: Decodable { let response: [YaniVideo] }
struct YaniVideo: Decodable, Identifiable {
    struct Info: Decodable { let player: String?; let dubbing: String? }
    let video_id: Int
    let data: Info?
    let number: String?
    let iframe_url: String?
    var id: Int { video_id }
    var playerName: String { data?.player?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Неизвестный плеер" }
    var voiceName: String { data?.dubbing?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Неизвестный перевод" }
    var groupKey: String { playerName + " · " + voiceName }
    var page: URL? {
        guard let raw = iframe_url?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let url = URL(string: raw.hasPrefix("//") ? "https:" + raw : raw), url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }
}
extension String { var nonEmpty: String? { isEmpty ? nil : self } }
struct YaniProvider {
    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url); request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }
    func videos(for anime: Anime) async throws -> [YaniVideo] {
        if anime.id < 0 { return try await YaniAPI.videos(-anime.id) }
        guard let malID = anime.mal?.id, malID > 0 else { throw YaniError.noIdentifier }
        var components = URLComponents(string: "https://api.yani.tv/anime")!
        components.queryItems = [URLQueryItem(name: "q", value: anime.name.main), URLQueryItem(name: "limit", value: "50")]
        guard let url = components.url else { throw URLError(.badURL) }
        let candidates: YaniSearchResponse = try await fetch(url)
        let matches = candidates.response.filter { $0.remote_ids?.myanimelist_id == malID }
        guard matches.count == 1, let match = matches.first else { throw YaniError.noMatch }
        guard let videosURL = URL(string: "https://api.yani.tv/anime/\(match.anime_id)/videos") else { throw URLError(.badURL) }
        let result: YaniVideosResponse = try await fetch(videosURL)
        return result.response.filter { $0.page != nil }
    }
}
enum YaniError: LocalizedError {
    case noIdentifier, noMatch
    var errorDescription: String? {
        switch self {
        case .noIdentifier: return "Для безопасного сопоставления отсутствует MAL ID."
        case .noMatch: return "Однозначное совпадение по MAL ID не найдено."
        }
    }
}
struct CVHPlaylist: Decodable {
    struct Item: Decodable { let vkId: String?; let voiceStudio: String?; let episode: Int? }
    let isSerial: Bool?
    let items: [Item]?
    let tags: [Int]?
}
struct CVHMedia: Decodable { let sources: [String: String?]? }
struct CVHResolver {
    func resolve(_ video: YaniVideo) async throws -> [StreamChoice] {
        guard let page = video.page, let parts = URLComponents(url: page, resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        let query = parts.queryItems ?? []
        func value(_ key: String) -> String? { query.first { $0.name == key }?.value }
        guard let animeID = value("anime_id"), Int(animeID) != nil, let studio = value("dubbing_code"), !studio.isEmpty,
              let url = URL(string: "https://plapi.cdnvideohub.com/api/v1/player/sv/playlist?pub=745&id=\(animeID)&aggr=mali") else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let playlist = try JSONDecoder().decode(CVHPlaylist.self, from: data)
        let items = playlist.items ?? []
        guard !(items.isEmpty && (playlist.tags ?? []).contains(5)) else { throw URLError(.noPermissionsToReadFile) }
        let episode = Int(value("episode") ?? "1")
        let matches = items.filter { ($0.voiceStudio ?? "").caseInsensitiveCompare(studio) == .orderedSame && (playlist.isSerial == false || $0.episode == episode) }
        guard matches.count == 1, let identifier = matches.first?.vkId, identifier.range(of: "^[0-9_-]{1,100}$", options: .regularExpression) != nil,
              let mediaURL = URL(string: "https://plapi.cdnvideohub.com/api/v1/player/sv/video/\(identifier)") else { throw URLError(.resourceUnavailable) }
        let (mediaData, mediaResponse) = try await URLSession.shared.data(from: mediaURL)
        guard (mediaResponse as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let media = try JSONDecoder().decode(CVHMedia.self, from: mediaData)
        return [("480p", "mpegMediumUrl"), ("720p", "mpegHighUrl"), ("1080p", "mpegFullHdUrl"), ("360p", "mpegLowUrl")].compactMap { label, key in
            guard let raw = media.sources?[key] ?? nil, let url = URL(string: raw), url.scheme == "https" else { return nil }
            return StreamChoice(label: label, url: url)
        }
    }
}
extension YaniVideo {
    var supportsNativePlayback: Bool {
        guard let page else { return false }
        return page.host == "player.aksor.tv" || (["ru.yummyani.me", "yummyani.me", "yani.tv"].contains(page.host ?? "") && page.lastPathComponent == "iframeCVH.html")
    }
}
struct AksorResponse: Decodable { let qualities: [String: String?] }
struct StreamChoice: Identifiable { let label: String; let url: URL; var id: String { label } }
struct AksorResolver {
    func resolve(_ video: YaniVideo) async throws -> [StreamChoice] {
        guard let page = video.page, page.host?.lowercased() == "player.aksor.tv", page.pathComponents.count == 3, page.pathComponents[1] == "video",
              page.lastPathComponent.range(of: "^[a-zA-Z0-9_-]{1,128}$", options: .regularExpression) != nil,
              let api = URL(string: "https://player.aksor.tv/api/video/\(page.lastPathComponent)") else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: api); request.setValue(page.absoluteString, forHTTPHeaderField: "Referer")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let payload = try JSONDecoder().decode(AksorResponse.self, from: data)
        let choices = ["q480", "q720", "q1080", "q360"].compactMap { key -> StreamChoice? in
            guard let raw = payload.qualities[key] ?? nil, let url = URL(string: raw.replacingOccurrences(of: " ", with: "%20")), url.scheme == "https", ["m3u8", "mp4", "mpd"].contains(url.pathExtension.lowercased()) else { return nil }
            return StreamChoice(label: key.dropFirst() + "p", url: url)
        }
        guard !choices.isEmpty else { throw URLError(.resourceUnavailable) }
        return choices
    }
}
@MainActor final class MultiSourcePlayback: ObservableObject {
    let anime: Anime
    let videos: [YaniVideo]
    private let queues: [String: [YaniVideo]]
    let player = VLCMediaPlayer()
    @Published var selected: YaniVideo
    @Published var choices: [StreamChoice] = []
    @Published var quality = ""
    @Published var loading = false
    @Published var error: String?
    @Published var seconds: Double = 0
    @Published var duration: Double = 0
    @Published var playing = false
    @Published var rate: Float = 1
    @Published var seekable = false
    @Published var notice: String?
    private var finished = false
    private var seekStarted = Date()
    private var poll: Timer?
    private var task: Task<Void, Never>?
    private var pendingSeek: Double?
    private var tickCount = 0
    private var reportedFrame = false
    var key: String { "progress.\(anime.id).yani-\(selected.id)" }
    var voices: [String] { VoicePreferences.sortedGroups(videos) }
    var hasNext: Bool { guard let index = episodes.firstIndex(where: { $0.id == selected.id }) else { return false }; return episodes.indices.contains(index + 1) }
    var audioTracks: [(id: Int32, name: String)] { tracks(player.audioTrackIndexes as? [NSNumber] ?? [], player.audioTrackNames as? [String] ?? []) }
    var subtitleTracks: [(id: Int32, name: String)] { tracks(player.videoSubTitlesIndexes as? [NSNumber] ?? [], player.videoSubTitlesNames as? [String] ?? []) }
    private func tracks(_ ids: [NSNumber], _ names: [String]) -> [(id: Int32, name: String)] { ids.enumerated().compactMap { index, id in names.indices.contains(index) ? (id.int32Value, id.int32Value == -1 ? "Выключено" : names[index]) : nil } }
    var episodes: [YaniVideo] { queues[selected.groupKey] ?? [] }
    init(anime: Anime, videos: [YaniVideo], video: YaniVideo) { self.anime = anime; self.videos = videos; queues = Dictionary(grouping: videos, by: \.groupKey).mapValues { orderedEpisodes($0) }; selected = video; quality = UserDefaults.standard.string(forKey: "defaultQuality") ?? "720p"; let saved = UserDefaults.standard.float(forKey: "playbackRate"); rate = (0.5...2).contains(saved) ? saved : 1 }
    func start() {
        guard poll == nil else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        select(selected)
    }
    func stop() { save(); task?.cancel(); poll?.invalidate(); poll = nil; player.stop(); player.drawable = nil; UIApplication.shared.isIdleTimerDisabled = false; try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    func save() {
        guard !finished, pendingSeek == nil, seconds > 0, seconds.isFinite else { return }
        UserDefaults.standard.set(seconds, forKey: key)
        HistoryStore.save(HistoryEntry(id: anime.id, title: anime.name.main, episodeID: "yani-\(selected.id)", episodeNumber: Double(selected.number ?? ""), seconds: seconds, updated: Date(), imageURL: anime.imageURL, duration: duration))
    }
    func select(_ video: YaniVideo, preservePosition: Bool = false) {
        save(); let prior = preservePosition ? seconds : UserDefaults.standard.double(forKey: "progress.\(anime.id).yani-\(video.id)")
        task?.cancel(); player.stop(); selected = video; seconds = prior; pendingSeek = prior; error = nil; notice = nil; choices = []; duration = 0; seekable = false; finished = false; loading = true
        UserDefaults.standard.set(video.groupKey, forKey: "preferredYaniVoice")
        UserDefaults.standard.set(video.groupKey, forKey: "voice.\(anime.id)")
        task = Task {
            do {
                let result = try await (video.page?.host == "player.aksor.tv" ? AksorResolver().resolve(video) : CVHResolver().resolve(video))
                guard !result.isEmpty else { throw URLError(.resourceUnavailable) }
                guard !Task.isCancelled else { return }; choices = result
                let stream = result.first { $0.label == quality } ?? result[0]
                try await open(stream, position: prior)
            } catch { if !Task.isCancelled { self.error = "Источник недоступен: \(error.localizedDescription)"; loading = false } }
        }
    }
    func open(_ stream: StreamChoice, position: Double) async throws {
        if stream.url.pathExtension.lowercased() == "mpd" {
            let (data, response) = try await URLSession.shared.data(from: stream.url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            guard let xml = String(data: data, encoding: .utf8), xml.contains("<MPD"), !xml.contains("ContentProtection") else { throw URLError(.cannotDecodeContentData) }
        }
        guard !Task.isCancelled else { return }
        player.stop(); quality = stream.label; pendingSeek = position > 0 ? position : nil; seekStarted = Date()
        let media = VLCMedia(url: stream.url)
        media.addOption(":network-caching=1500")
        player.media = media; player.play(); player.rate = rate
        UIApplication.shared.isIdleTimerDisabled = true
    }
    func changeQuality(_ stream: StreamChoice) {
        let position = seconds; task?.cancel(); loading = true; error = nil
        task = Task { do { try await open(stream, position: position) } catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } } }
    }
    func chooseVoice(_ name: String) {
        guard let video = queues[name]?.first(where: { episodeIdentity($0.number) == episodeIdentity(selected.number) }) else { error = "В этой озвучке нет текущей серии. Выберите другую серию."; return }
        select(video, preservePosition: true)
    }
    var hasPrevious: Bool { guard let index = episodes.firstIndex(where: { $0.id == selected.id }) else { return false }; return index > 0 }
    func previous() { guard let index = episodes.firstIndex(where: { $0.id == selected.id }), index > 0 else { return }; select(episodes[index - 1]) }
    func next() {
        guard let index = episodes.firstIndex(where: { $0.id == selected.id }), episodes.indices.contains(index + 1) else { return }
        select(episodes[index + 1])
    }
    func seek(_ value: Double) { guard value.isFinite, player.isSeekable else { return }; let target = PlaybackMath.seekTarget(value, duration: duration); player.time = VLCTime(int: Int32(target * 1000)); seconds = target }
    func setRate(_ value: Float) { guard (0.5...2).contains(value) else { return }; rate = value; player.rate = value; UserDefaults.standard.set(value, forKey: "playbackRate") }
    func toggle() { if finished { select(selected); return }; if player.isPlaying { player.pause() } else { player.play(); player.rate = rate } }
    func tick() {
        if playing != player.isPlaying { playing = player.isPlaying; UIApplication.shared.isIdleTimerDisabled = playing }; if seekable != player.isSeekable { seekable = player.isSeekable }
        if player.state == .buffering && !playing { loading = true }
        if player.state == .paused { loading = false }
        if player.state == .error { error = "Не удалось воспроизвести поток. Попробуйте повторить или выбрать другой источник."; loading = false }
        if playing {
            loading = false
            if let position = pendingSeek { if player.isSeekable { pendingSeek = nil; seek(position); return }; if Date().timeIntervalSince(seekStarted) > 12 { pendingSeek = nil; notice = "Источник не разрешает восстановить позицию." } }
            seconds = max(0, Double(player.time.intValue) / 1000)
            duration = max(0, Double(player.media?.length.intValue ?? 0) / 1000)
            #if DEBUG
            if !reportedFrame, seconds > 2, player.hasVideoOut, let probe = ProcessInfo.processInfo.environment["ANIMEAPP_PROBE"] {
                reportedFrame = true
                NSLog("ANIMEAPP_FRAME_%@ seconds=%.2f", probe, seconds)
                if ProcessInfo.processInfo.environment["ANIMEAPP_UI_TEST"] != "1" { Task { @MainActor [weak self] in await self?.probeControls(probe) } }
            }
            #endif
            tickCount += 1; if tickCount % 10 == 0 && pendingSeek == nil { save() }
        }
        if player.state == .ended && !finished {
            save(); finished = true; UserDefaults.standard.set(0, forKey: key)
            if UserDefaults.standard.object(forKey: "autoNext") as? Bool ?? true { next() }
        }
    }
    #if DEBUG
    private func probeWait(_ condition: () -> Bool, attempts: Int = 50) async -> Bool {
        for _ in 0..<attempts {
            if condition() { return true }
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return false }
        }
        return condition()
    }
    private func probeControls(_ probe: String) async {
        let firstClock = player.time.intValue
        guard await probeWait({ self.player.isPlaying && self.player.isSeekable && self.player.canPause && self.player.time.intValue >= firstClock + 1000 && (self.player.media?.length.intValue ?? 0) > 0 }, attempts: 100) else {
            NSLog("ANIMEAPP_CONTROLS_%@ failed readiness state=%@ playing=%d seekable=%d canPause=%d", probe, String(describing: player.state), player.isPlaying ? 1 : 0, player.isSeekable ? 1 : 0, player.canPause ? 1 : 0); return
        }
        NSLog("ANIMEAPP_READY_%@ seekable=1 canPause=1 advancing=1 cachedState=%@", probe, String(describing: player.state))
        player.pause()
        guard await probeWait({ !self.player.isPlaying }) else {
            NSLog("ANIMEAPP_CONTROLS_%@ failed pause state=%@ playing=%d", probe, String(describing: player.state), player.isPlaying ? 1 : 0); return
        }
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
        let frozen = player.time.intValue
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
        guard !player.isPlaying, abs(player.time.intValue - frozen) < 500, player.isSeekable else {
            NSLog("ANIMEAPP_CONTROLS_%@ failed frozen clock delta=%d playing=%d seekable=%d", probe, player.time.intValue - frozen, player.isPlaying ? 1 : 0, player.isSeekable ? 1 : 0); return
        }
        seek(15); toggle()
        guard await probeWait({ self.player.isPlaying && (13000...23000).contains(self.player.time.intValue) }) else {
            NSLog("ANIMEAPP_CONTROLS_%@ failed resume time=%.2f state=%@", probe, Double(player.time.intValue) / 1000, String(describing: player.state)); return
        }
        NSLog("ANIMEAPP_CONTROLS_%@ passed target=15 actual=%.2f", probe, Double(player.time.intValue) / 1000)
    }
    #endif

}
struct VLCSurface: UIViewRepresentable {
    let player: VLCMediaPlayer
    func makeUIView(context: Context) -> UIView { let view = UIView(); view.backgroundColor = .black; view.isUserInteractionEnabled = false; player.drawable = view; return view }
    func updateUIView(_ view: UIView, context: Context) { if player.drawable == nil { player.drawable = view } }
}
struct HistoryEntry: Codable, Identifiable {
    let id: Int
    let title: String
    let episodeID: String
    let episodeNumber: Double?
    let seconds: Double
    let updated: Date
    var imageURL: URL? = nil
    var duration: Double? = nil
}
enum HistoryStore {
    static let storageKey = "viewingHistory.v1"
    static func load() -> [HistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([HistoryEntry].self, from: data)) ?? []
    }
    static func save(_ entry: HistoryEntry) {
        var all = load().filter { $0.id != entry.id }
        all.insert(entry, at: 0)
        if let data = try? JSONEncoder().encode(Array(all.prefix(100))) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
@MainActor final class PlaybackController: ObservableObject {
    let anime: Anime
    let player = AVPlayer()
    @Published var episode: Episode
    @Published var quality = ""
    @Published var current: Double = 0
    @Published var error: String?
    @Published var remoteSegments: [String: Segment] = [:]
    @Published var rate: Float = 1
    private var timer: Any?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var skipTask: Task<Void, Never>?
    private var lastSave: Double = -10
    var episodes: [Episode] { (anime.episodes ?? []).filter { !$0.streams.isEmpty }.sorted { ($0.ordinal ?? 0) < ($1.ordinal ?? 0) } }
    var key: String { "progress.\(anime.id).\(episode.id)" }
    var opening: Segment? { if let segment = episode.opening, segment.valid { return segment }; return remoteSegments["op"] }
    var ending: Segment? { if let segment = episode.ending, segment.valid { return segment }; return remoteSegments["ed"] }
    init(anime: Anime, episode: Episode) { self.anime = anime; self.episode = episode }
    func start() {
        guard timer == nil else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        timer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in self?.tick(time.seconds) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self, let item = note.object as? AVPlayerItem, item === self.player.currentItem else { return }
                UserDefaults.standard.set(0, forKey: self.key)
                if UserDefaults.standard.object(forKey: "autoNext") as? Bool ?? true { self.next() }
            }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self, let item = note.object as? AVPlayerItem, item === self.player.currentItem else { return }
                self.error = "Воспроизведение прервано. Проверьте сеть и повторите попытку."
            }
        }
        select(episode, saveCurrent: false)
    }
    func stop() {
        saveProgress()
        skipTask?.cancel(); skipTask = nil
        player.pause()
        if let timer { player.removeTimeObserver(timer); self.timer = nil }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver); self.endObserver = nil }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver); self.failureObserver = nil }
        statusObservation = nil
    }
    func tick(_ seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        current = seconds
        if seconds - lastSave >= 5 { saveProgress(); lastSave = seconds }
        let options = [(UserDefaults.standard.bool(forKey: "autoSkipOpening"), opening), (UserDefaults.standard.bool(forKey: "autoSkipEnding"), ending)]
        for (enabled, segment) in options {
            if enabled, let segment, segment.valid, let start = segment.start, let end = segment.stop, seconds >= start, seconds < end { seek(end); break }
        }
    }
    func saveProgress() {
        guard current.isFinite, current > 0 else { return }
        UserDefaults.standard.set(current, forKey: key)
        HistoryStore.save(HistoryEntry(id: anime.id, title: anime.name.main, episodeID: episode.id, episodeNumber: episode.ordinal, seconds: current, updated: Date(), imageURL: anime.imageURL, duration: episode.duration))
    }
    func seek(_ seconds: Double) { player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) }
    func select(_ selected: Episode, saveCurrent: Bool = true) {
        if saveCurrent { saveProgress() }
        skipTask?.cancel(); remoteSegments = [:]; episode = selected; current = UserDefaults.standard.double(forKey: key); lastSave = -10
        let preferred = selected.streams.first { $0.0 == quality } ?? selected.streams.first
        guard let preferred else { error = "Для этой серии нет доступного потока."; return }
        play(preferred, position: current)
        let requestedID = selected.id
        skipTask = Task { await loadSkipTimes(for: selected, requestedID: requestedID) }
    }
    func next() {
        guard let index = episodes.firstIndex(where: { $0.id == episode.id }), episodes.indices.contains(index + 1) else { return }
        select(episodes[index + 1], saveCurrent: false)
    }
    func play(_ stream: (String, String), position: Double? = nil) {
        guard let url = URL(string: stream.1), url.scheme == "https" else { error = "Некорректный адрес потока."; return }
        let resume = position ?? current
        quality = stream.0; error = nil
        let item = AVPlayerItem(url: url)
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "Не удалось открыть видео."
            Task { @MainActor [weak self] in self?.error = message }
        }
        player.replaceCurrentItem(with: item)
        if resume > 0 { seek(resume) }
        player.playImmediately(atRate: rate)
    }
    func retry() { if let stream = episode.streams.first(where: { $0.0 == quality }) ?? episode.streams.first { play(stream) } }
    func changeRate(_ value: Float) { rate = value; if player.timeControlStatus != .paused { player.rate = value } }
    func loadSkipTimes(for selected: Episode, requestedID: String) async {
        guard let mal = anime.mal?.id, let number = selected.ordinal, number > 0, number.rounded() == number,
              let duration = selected.duration, duration.isFinite, duration > 0,
              let url = URL(string: "https://api.aniskip.com/v2/skip-times/\(mal)/\(Int(number))?types=op&types=ed&episodeLength=0") else { return }
        do {
            var request = URLRequest(url: url); request.setValue("AnimeApp/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled, requestedID == episode.id, (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let result = try JSONDecoder().decode(SkipResponse.self, from: data)
            for entry in result.results where abs(entry.episodeLength - duration) <= 3 {
                let segment = Segment(start: entry.interval.startTime, stop: entry.interval.endTime)
                if segment.valid { remoteSegments[entry.skipType] = segment }
            }
        } catch { return }
    }
}
struct PlayerScreen: View {
    @StateObject private var controller: PlaybackController
    init(anime: Anime, episode: Episode) { _controller = StateObject(wrappedValue: PlaybackController(anime: anime, episode: episode)) }
    var body: some View {
        VStack(spacing: 16) {
            VideoPlayer(player: controller.player).frame(height: 240)
            HStack {
                Menu("Серия \((controller.episode.ordinal ?? 0).formatted())") {
                    ForEach(controller.episodes) { episode in Button("Серия \((episode.ordinal ?? 0).formatted())") { controller.select(episode) } }
                }
                Spacer()
                Menu(controller.quality.isEmpty ? "Качество" : controller.quality) {
                    ForEach(controller.episode.streams, id: \.0) { stream in Button(stream.0) { controller.play(stream) } }
                }
                Menu("\(controller.rate.formatted())×") {
                    ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 1.75, 2], id: \.self) { rate in Button("\(rate.formatted())×") { controller.changeRate(rate) } }
                }
            }
            HStack {
                if let s = controller.opening, s.valid, let start = s.start, let stop = s.stop, controller.current >= start, controller.current < stop { Button("Пропустить опенинг") { controller.seek(stop) } }
                if let s = controller.ending, s.valid, let start = s.start, let stop = s.stop, controller.current >= start, controller.current < stop { Button("Пропустить эндинг") { controller.seek(stop) } }
            }
            if let error = controller.error { VStack(spacing: 8) { Text(error).foregroundStyle(.secondary); Button("Повторить") { controller.retry() } } }
            Text("Озвучка и видео: AniLibria").font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }.padding().navigationTitle(controller.anime.name.main).navigationBarTitleDisplayMode(.inline)
            .onAppear { controller.start() }.onDisappear { controller.stop() }
    }
}
struct SkipResponse: Decodable {
    struct Entry: Decodable {
        struct Interval: Decodable { let startTime: Double; let endTime: Double }
        let interval: Interval
        let skipType: String
        let episodeLength: Double
    }
    let results: [Entry]
}
enum WatchStatus: String, Codable, CaseIterable, Identifiable {
    case watching = "Смотрю", planned = "В планах", completed = "Просмотрено", paused = "Отложено", dropped = "Брошено"
    var id: String { rawValue }
}
struct LibraryEntry: Codable, Identifiable {
    let id: Int
    let title: String
    let imageURL: URL?
    var status: WatchStatus?
    var favorite: Bool
}
enum LocalLibrary {
    static let key = "localLibrary.v1"
    static func decode(_ data: Data) -> [LibraryEntry] { (try? JSONDecoder().decode([LibraryEntry].self, from: data)) ?? [] }
    static func encode(_ entries: [LibraryEntry]) -> Data { (try? JSONEncoder().encode(entries)) ?? Data() }
}
struct LibraryControls: View {
    let anime: Anime
    @AppStorage(LocalLibrary.key) private var data = Data()
    var current: LibraryEntry { LocalLibrary.decode(data).first { $0.id == anime.id } ?? LibraryEntry(id: anime.id, title: anime.name.main, imageURL: anime.imageURL, status: nil, favorite: false) }
    func update(_ entry: LibraryEntry) {
        var items = LocalLibrary.decode(data).filter { $0.id != anime.id }
        if entry.status != nil || entry.favorite { items.insert(entry, at: 0) }
        data = LocalLibrary.encode(items)
    }
    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(WatchStatus.allCases) { status in Button(status.rawValue) { var entry = current; entry.status = status; update(entry) } }
                if current.status != nil { Button("Убрать из списка", role: .destructive) { var entry = current; entry.status = nil; update(entry) } }
            } label: { Label(current.status?.rawValue ?? "В список", systemImage: current.status == nil ? "plus" : "bookmark.fill").font(.subheadline.bold()).frame(maxWidth: .infinity).padding(14).background(Cinema.surface, in: RoundedRectangle(cornerRadius: 14)) }
            Button { var entry = current; entry.favorite.toggle(); update(entry) } label: { Image(systemName: current.favorite ? "heart.fill" : "heart").foregroundStyle(current.favorite ? Cinema.accent : .white).frame(width: 52, height: 48).background(Cinema.surface, in: RoundedRectangle(cornerRadius: 14)) }.accessibilityLabel(current.favorite ? "Убрать из избранного" : "В избранное")
        }.buttonStyle(.plain)
    }
}

struct LibraryBackup: Codable {
    let version: Int
    let library: [LibraryEntry]
    let history: [HistoryEntry]
    let progress: [String: Double]
    static func make() -> LibraryBackup {
        let defaults = UserDefaults.standard
        let progress = defaults.dictionaryRepresentation().reduce(into: [String: Double]()) { result, item in
            if item.key.hasPrefix("progress."), let value = item.value as? Double, value.isFinite, value >= 0 { result[item.key] = value }
        }
        return LibraryBackup(version: 1, library: LocalLibrary.decode(defaults.data(forKey: LocalLibrary.key) ?? Data()), history: HistoryStore.load(), progress: progress)
    }
    func restore() throws {
        guard version == 1, library.count <= 10000, history.count <= 10000, progress.count <= 100000,
              Set(library.map(\.id)).count == library.count, Set(history.map(\.id)).count == history.count,
              progress.allSatisfy({ $0.key.hasPrefix("progress.") && $0.key.count < 200 && $0.value.isFinite && $0.value >= 0 }) else { throw CocoaError(.fileReadCorruptFile) }
        let libraryData = try JSONEncoder().encode(library)
        let historyData = try JSONEncoder().encode(history)
        let defaults = UserDefaults.standard
        defaults.set(libraryData, forKey: LocalLibrary.key)
        defaults.set(historyData, forKey: HistoryStore.storageKey)
        // Restore replaces saved progress as well as the library and history.
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("progress.") { defaults.removeObject(forKey: key) }
        for (key, value) in progress { defaults.set(value, forKey: key) }
    }
}
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var backup: LibraryBackup
    init(backup: LibraryBackup) { self.backup = backup }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count <= 10_000_000 else { throw CocoaError(.fileReadCorruptFile) }
        backup = try JSONDecoder().decode(LibraryBackup.self, from: data)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: try JSONEncoder().encode(backup)) }
}

struct SettingsView: View {
    @AppStorage("autoSkipOpening") private var opening = false
    @AppStorage("autoSkipEnding") private var ending = false
    @AppStorage("autoNext") private var autoNext = true
    @AppStorage("openPlayerLandscape") private var landscape = false
    @AppStorage("defaultQuality") private var defaultQuality = "720p"
    @State private var exporting = false
    @State private var importing = false
    @State private var exportDocument: BackupDocument?
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Просмотр") {
                    Toggle("Следующая серия автоматически", isOn: $autoNext)
                    Toggle("Открывать плеер на весь экран", isOn: $landscape)
                    Picker("Предпочитаемое качество", selection: $defaultQuality) { ForEach(["360p", "480p", "720p", "1080p"], id: \.self) { Text($0) } }
                    Text("Если выбранного качества нет, используется вариант, доступный у источника.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Пропуск · AniLibria") { Toggle("Автоматически пропускать опенинг", isOn: $opening); Toggle("Автоматически пропускать эндинг", isOn: $ending); Text("Используются метки источника; данные AniSkip применяются только при близкой длительности. Различия монтажа всё равно возможны.").font(.footnote).foregroundStyle(.secondary) }
                Section("Библиотека") {
                    Button("Экспортировать JSON") { exportDocument = BackupDocument(backup: LibraryBackup.make()); exporting = true }
                    Button("Импортировать JSON") { importing = true }
                    Text("Импорт заменяет библиотеку, историю и сохранённые позиции.").font(.footnote).foregroundStyle(.secondary)
                    if let message { Text(message).font(.footnote) }
                }
                Section("Источник") { NavigationLink("Аккаунт YummyAnime") { YaniAccountView() }; Text("Каталог: YummyAnime · видео: Aksor, CVH, AniLibria"); Text("Доступность зависит от источника и сети.").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("Настройки")
            .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: "AnimeApp-backup") { result in
                switch result { case .success: message = "Экспорт завершён."; case .failure(let error): message = "Ошибка экспорта: \(error.localizedDescription)" }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    guard data.count <= 10_000_000 else { throw CocoaError(.fileReadCorruptFile) }
                    let backup = try JSONDecoder().decode(LibraryBackup.self, from: data)
                    try backup.restore(); message = "Импорт завершён."
                } catch { message = "Ошибка импорта: \(error.localizedDescription)" }
            }
        }
    }
}
