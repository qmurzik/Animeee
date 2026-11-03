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
    var body: some Scene { WindowGroup { AppRoute().preferredColorScheme(.dark).tint(.purple).task { _ = try? await YaniAPI.restore() } } }
}
struct AppRoute: View {
    var body: some View {
        #if DEBUG
        if let probe = ProcessInfo.processInfo.environment["ANIMEAPP_PROBE"], ["aksor", "cvh"].contains(probe) {
            PlaybackProbeView(mode: probe)
        } else { RootView() }
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
    var body: some View {
        let anime = Anime(id: -100, mal: nil, name: .init(main: "Проверка потока \(mode.uppercased())", english: nil), poster: nil, description: nil, year: nil, episodes: nil)
        NavigationStack { MultiSourcePlayerScreen(sourceAnime: anime, video: video, videos: [video]) }
    }
}
#endif
// YummyAnime is an independent catalog. Negative local IDs namespace its IDs
// separately from the existing positive AniLibria IDs in saved data.
struct YaniCatalogItem: Decodable {
    struct Image: Decodable { let fullsize: String?; let big: String? }
    struct IDs: Decodable { let myanimelist_id: Int? }
    let anime_id: Int
    let title: String
    let description: String?
    let year: Int?
    let poster: Image?
    let remote_ids: IDs?
    var anime: Anime {
        let image = poster?.big ?? poster?.fullsize
        return Anime(id: -anime_id, mal: remote_ids?.myanimelist_id.map { .init(id: $0) }, name: .init(main: title, english: nil), poster: image.map { .init(src: $0.hasPrefix("//") ? "https:" + $0 : $0) }, description: description, year: year, episodes: nil)
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
struct RootView: View {
    var body: some View {
        TabView {
            CatalogView().tabItem { Label("Главная", systemImage: "sparkles.tv") }
            SearchView().tabItem { Label("Поиск", systemImage: "magnifyingglass") }
            LibraryView().tabItem { Label("Библиотека", systemImage: "books.vertical") }
            SettingsView().tabItem { Label("Настройки", systemImage: "gearshape") }
        }
    }
}
struct PosterView: View {
    let anime: Anime
    var body: some View { HStack(spacing: 14) {
        AsyncImage(url: anime.imageURL) { image in image.resizable().scaledToFill() } placeholder: { Color.purple.opacity(0.2) }.frame(width: 72, height: 100).clipped().cornerRadius(10)
        VStack(alignment: .leading, spacing: 7) { Text(anime.name.main).font(.headline); Text(anime.name.english ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(2); if let year = anime.year { Text(String(year)).font(.caption).foregroundStyle(.purple) } }
    }.padding(.vertical, 3) }
}
struct CoverCard: View {
    let anime: Anime
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: anime.imageURL) { $0.resizable().scaledToFill() } placeholder: { Rectangle().fill(.white.opacity(0.06)).overlay { Image(systemName: "sparkles.tv").foregroundStyle(.white.opacity(0.3)) } }
                .frame(width: 140, height: 200).clipped().clipShape(RoundedRectangle(cornerRadius: 14))
            Text(anime.name.main).font(.subheadline.weight(.semibold)).lineLimit(2, reservesSpace: true).frame(width: 140, alignment: .leading)
            if let year = anime.year { Text(String(year)).font(.caption).foregroundStyle(.secondary) }
        }.frame(width: 140, alignment: .topLeading)
    }
}
struct CatalogView: View {
    @State private var offset = 0
    @State private var more = true
    @State private var fetchingMore = false
    @AppStorage("yaniRevision") private var sessionRevision = ""
    @State private var items: [Anime] = []
    @State private var error: String?
    @AppStorage(HistoryStore.storageKey) private var historyData = Data()
    var history: [HistoryEntry] { (try? JSONDecoder().decode([HistoryEntry].self, from: historyData)) ?? [] }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) { Text("ANIME / APP").font(.caption.weight(.bold)).tracking(2).foregroundStyle(.purple); Text("Сегодня в кадре").font(.title2.bold()) }
                        Spacer(); NavigationLink { YaniAccountView() } label: { Image(systemName: "person.crop.circle").font(.title2).foregroundStyle(.purple) }
                    }.padding(.horizontal)
                    if let last = history.first {
                        NavigationLink { DetailView(id: last.id) } label: {
                            HStack(spacing: 14) { Image(systemName: "play.fill").font(.title3).frame(width: 46, height: 46).background(.purple, in: RoundedRectangle(cornerRadius: 14)); VStack(alignment: .leading, spacing: 4) { Text("ПРОДОЛЖИТЬ").font(.caption2.bold()).tracking(1).foregroundStyle(.purple); Text(last.title).font(.headline).lineLimit(1); Text("Серия \((last.episodeNumber ?? 0).formatted()) · \(Int(last.seconds / 60)) мин").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary) }.padding(16).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal)
                        }.buttonStyle(.plain)
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.secondary).padding(.horizontal); Button("Повторить") { Task { await load() } }.padding(.horizontal) }
                    if items.isEmpty && error == nil { ProgressView().frame(maxWidth: .infinity).padding() }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { VStack(alignment: .leading, spacing: 3) { Text("Открывайте аниме").font(.title2.bold()); Text("Каталог YummyAnime").font(.caption).foregroundStyle(.secondary) }; Spacer() }.padding(.horizontal)
                            ScrollView(.horizontal, showsIndicators: false) { LazyHStack(alignment: .top, spacing: 12) { ForEach(Array(items.prefix(8))) { anime in NavigationLink { DetailView(id: anime.id) } label: { CoverCard(anime: anime) }.buttonStyle(.plain) } }.padding(.horizontal) }
                        }
                        Text("Ещё в каталоге").font(.title2.bold()).padding(.horizontal)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .center, spacing: 18) {
                            ForEach(Array(items.dropFirst(8))) { anime in NavigationLink { DetailView(id: anime.id) } label: { CoverCard(anime: anime) }.buttonStyle(.plain) }
                        }.padding(.horizontal)
                        if more { Button(fetchingMore ? "Загрузка…" : "Загрузить ещё") { Task { await loadMore() } }.disabled(fetchingMore).buttonStyle(.bordered).frame(maxWidth: .infinity) }
                    }
                }.padding(.top, 12).padding(.bottom, 30)
            }.background(Color(red: 0.045, green: 0.04, blue: 0.075)).toolbar(.hidden, for: .navigationBar).task(id: sessionRevision) { await load() }.refreshable { await load() }
        }
    }
    func loadMore() async { fetchingMore = true; defer { fetchingMore = false }; do { let page = try await YaniAPI.catalog(offset: offset); offset += page.count; more = page.count == 30; let ids = Set(items.map(\.id)); items.append(contentsOf: page.filter { !ids.contains($0.id) }); error = nil } catch { self.error = error.localizedDescription } }
    func load() async { do { items = try await YaniAPI.catalog(); offset = items.count; more = items.count == 30; error = nil } catch { self.error = "Не удалось загрузить каталог: \(error.localizedDescription)" } }
}
struct SearchView: View {
    @State private var query = ""
    @State private var items: [Anime] = []
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        NavigationStack {
            ScrollView {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("Найди свою историю", systemImage: "sparkle.magnifyingglass", description: Text("Ищи по русскому или оригинальному названию"))
                } else {
                    if loading { ProgressView().padding() }
                    if let error { Text(error).foregroundStyle(.secondary).padding() }
                    if !loading && items.isEmpty && error == nil { ContentUnavailableView.search(text: query) }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .center, spacing: 20) {
                        ForEach(items) { item in NavigationLink { DetailView(id: item.id) } label: { CoverCard(anime: item) }.buttonStyle(.plain) }
                    }.padding()
                }
            }.background(Color(red: 0.045, green: 0.04, blue: 0.075)).navigationTitle("Поиск")
             .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Название аниме")
             .task(id: query) {
                 guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { items = []; loading = false; error = nil; return }
                 loading = true
                 do { try await Task.sleep(for: .milliseconds(400)); let found = try await YaniAPI.catalog(query: query); guard !Task.isCancelled else { return }; items = found; error = nil; loading = false }
                 catch { guard !Task.isCancelled else { return }; self.error = error.localizedDescription; loading = false }
             }
        }
    }
}
struct DetailView: View {
    let id: Int
    @State private var anime: Anime?
    @State private var error: String?
    @AppStorage(HistoryStore.storageKey) private var historyData = Data()
    var history: [HistoryEntry] { (try? JSONDecoder().decode([HistoryEntry].self, from: historyData)) ?? [] }
    var body: some View {
        ScrollView {
            if let anime {
                VStack(alignment: .leading, spacing: 20) {
                    ZStack(alignment: .bottomLeading) {
                        AsyncImage(url: anime.imageURL) { $0.resizable().scaledToFill() } placeholder: { Color.purple.opacity(0.2) }.frame(maxWidth: .infinity).frame(height: 330).clipped()
                        LinearGradient(colors: [.clear, .black.opacity(0.35), Color(red: 0.045, green: 0.04, blue: 0.075)], startPoint: .top, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 6) { Text(anime.id < 0 ? "YUMMYANIME" : "ANILIBRIA").font(.caption.bold()).tracking(2).foregroundStyle(.purple); Text(anime.name.main).font(.largeTitle.bold()).lineLimit(3); if let year = anime.year { Text(anime.id < 0 ? "\(String(year))  •  YummyAnime" : "\(String(year))  •  \(anime.episodes?.count ?? 0) серий").font(.subheadline).foregroundStyle(.secondary) } }.padding(20)
                    }.frame(height: 330).clipped()
                    VStack(alignment: .leading, spacing: 20) {
                        if let last = history.first(where: { $0.id == anime.id }), let episode = anime.episodes?.first(where: { $0.id == last.episodeID }) {
                            NavigationLink { PlayerScreen(anime: anime, episode: episode) } label: { Label("Продолжить · серия \((episode.ordinal ?? 0).formatted())", systemImage: "play.fill").frame(maxWidth: .infinity).padding().background(.purple, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.white) }
                        } else if let episode = anime.episodes?.first(where: { !$0.streams.isEmpty }) {
                            NavigationLink { PlayerScreen(anime: anime, episode: episode) } label: { Label("Смотреть", systemImage: "play.fill").frame(maxWidth: .infinity).padding().background(.purple, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.white) }
                        }
                        LibraryControls(anime: anime)
                        Text(anime.description ?? "Описание отсутствует").font(.subheadline).foregroundStyle(.secondary)
                        YaniSourcesView(anime: anime)
                        if !(anime.episodes ?? []).isEmpty { HStack { Text("Серии").font(.title2.bold()); Spacer(); Text("AniLibria").font(.caption).foregroundStyle(.purple) } }
                        ForEach(anime.episodes ?? []) { episode in
                            NavigationLink { PlayerScreen(anime: anime, episode: episode) } label: {
                                HStack(spacing: 14) { Image(systemName: "play.fill").frame(width: 42, height: 42).background(.purple.opacity(0.24), in: RoundedRectangle(cornerRadius: 12)); VStack(alignment: .leading, spacing: 4) { Text("Серия \((episode.ordinal ?? 0).formatted())").font(.subheadline.bold()); if let name = episode.name { Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1) } }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }.padding(12).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 20)
                }.padding(.bottom, 30)
            } else if let error { ContentUnavailableView("Источник недоступен", systemImage: "wifi.exclamationmark", description: Text(error)) } else { ProgressView().padding() }
        }.background(Color(red: 0.045, green: 0.04, blue: 0.075)).toolbar(.visible, for: .navigationBar).navigationBarTitleDisplayMode(.inline).task { do { anime = id < 0 ? try await YaniAPI.detail(-id) : try await Libria().release(id) } catch { self.error = error.localizedDescription } }
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
struct YaniSourcesView: View {
    let anime: Anime
    @State private var videos: [YaniVideo] = []
    @State private var error: String?
    @State private var loading = false
    @State private var loaded = false
    @AppStorage("preferredYaniVoice") private var preferred = ""
    var groups: [(key: String, count: Int)] {
        let grouped = Dictionary(grouping: videos.filter { $0.supportsNativePlayback }, by: \.groupKey)
        return grouped.map { (key: $0.key, count: $0.value.count) }.sorted { a, b in
            if (a.key == preferred) != (b.key == preferred) { return a.key == preferred }
            return a.key.localizedStandardCompare(b.key) == .orderedAscending
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(anime.id < 0 ? "Озвучки и серии" : "Другие озвучки").font(.title2.bold()); Spacer(); if loading { ProgressView() } }
            Text("Озвучки · Aksor и CVH").font(.caption).foregroundStyle(.secondary)
            if !loaded && !loading { Button("Найти озвучки") { Task { await load() } }.buttonStyle(.bordered) }
            if let error { Text(error).font(.footnote).foregroundStyle(.secondary); Button("Повторить") { Task { await load() } }.font(.footnote) }
            if let last = HistoryStore.load().first(where: { $0.id == anime.id }), let video = videos.first(where: { "yani-\($0.id)" == last.episodeID && $0.supportsNativePlayback }) {
                NavigationLink { MultiSourcePlayerScreen(sourceAnime: anime, video: video, videos: videos.filter { $0.supportsNativePlayback }) } label: { Label("Продолжить · \(video.voiceName) · серия \(video.number ?? "—")", systemImage: "play.fill").font(.subheadline.bold()).padding().frame(maxWidth: .infinity, alignment: .leading).background(.purple, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.white) }
            }
            if anime.id < 0, let first = videos.filter({ $0.supportsNativePlayback }).sorted(by: { ($0.number ?? "").localizedStandardCompare($1.number ?? "") == .orderedAscending }).first(where: { preferred.isEmpty || $0.groupKey == preferred }) ?? videos.first(where: { $0.supportsNativePlayback }) {
                NavigationLink { MultiSourcePlayerScreen(sourceAnime: anime, video: first, videos: videos.filter { $0.supportsNativePlayback }) } label: { Label("Смотреть · \(first.voiceName)", systemImage: "play.fill").font(.headline).padding().frame(maxWidth: .infinity, alignment: .leading).background(.purple, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.white) }
            }
            DisclosureGroup("Выбрать озвучку · \(groups.count)") {
            ForEach(groups, id: \.key) { group in
                NavigationLink {
                    YaniEpisodesView(anime: anime, name: group.key, videos: videos.filter { $0.supportsNativePlayback })
                } label: { HStack { VStack(alignment: .leading) { Text(group.key); Text("\(group.count) серий · выбрать озвучку").font(.caption).foregroundStyle(.secondary) }; Spacer(); if preferred == group.key { Image(systemName: "star.fill").foregroundStyle(.yellow) } }.padding(10).background(.white.opacity(0.06)).cornerRadius(10) }
            }
            }
        }.task { if !loaded && !loading { await load() } }
    }
    func load() async {
        loading = true; error = nil
        do { videos = try await YaniProvider().videos(for: anime); loaded = true; if !videos.contains(where: { $0.supportsNativePlayback }) { error = anime.id < 0 ? "YummyAnime не вернул потоков Aksor или CVH. Для остальных балансеров нативный адаптер пока не подключён." : "Для этого тайтла пока нет поддерживаемых дополнительных потоков. Выберите серии AniLibria ниже." } }
        catch { self.error = "YummyAnime: \(error.localizedDescription)" }
        loading = false
    }
}
struct YaniEpisodesView: View {
    let anime: Anime
    let name: String
    let videos: [YaniVideo]
    @AppStorage("preferredYaniVoice") private var preferred = ""
    var sorted: [YaniVideo] { videos.filter { $0.groupKey == name }.sorted { ($0.number ?? "").localizedStandardCompare($1.number ?? "") == .orderedAscending } }
    var body: some View {
        List {
            Section { Button(preferred == name ? "Убрать из предпочтений" : "Предпочитать эту озвучку и плеер") { preferred = preferred == name ? "" : name } }
            Section("Серии") {
                ForEach(sorted) { video in
                    if video.page != nil { NavigationLink("Серия \(video.number ?? "—")") { MultiSourcePlayerScreen(sourceAnime: anime, video: video, videos: videos) } }
                }
            }
        }.scrollContentBackground(.hidden).background(Color(red: 0.045, green: 0.04, blue: 0.075)).navigationTitle(name).navigationBarTitleDisplayMode(.inline)
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
    var voices: [String] { Array(Set(videos.map(\.groupKey))).sorted() }
    var hasNext: Bool { guard let index = episodes.firstIndex(where: { $0.id == selected.id }) else { return false }; return episodes.indices.contains(index + 1) }
    var audioTracks: [(id: Int32, name: String)] { tracks(player.audioTrackIndexes as? [NSNumber] ?? [], player.audioTrackNames as? [String] ?? []) }
    var subtitleTracks: [(id: Int32, name: String)] { tracks(player.videoSubTitlesIndexes as? [NSNumber] ?? [], player.videoSubTitlesNames as? [String] ?? []) }
    private func tracks(_ ids: [NSNumber], _ names: [String]) -> [(id: Int32, name: String)] { ids.enumerated().compactMap { index, id in names.indices.contains(index) ? (id.int32Value, id.int32Value == -1 ? "Выключено" : names[index]) : nil } }
    var episodes: [YaniVideo] { videos.filter { $0.groupKey == selected.groupKey }.sorted { ($0.number ?? "").localizedStandardCompare($1.number ?? "") == .orderedAscending } }
    init(anime: Anime, videos: [YaniVideo], video: YaniVideo) { self.anime = anime; self.videos = videos; selected = video }
    func start() {
        guard poll == nil else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        select(selected)
    }
    func stop() { save(); task?.cancel(); poll?.invalidate(); poll = nil; player.stop(); player.drawable = nil; UIApplication.shared.isIdleTimerDisabled = false }
    func save() {
        guard !finished, seconds > 0, seconds.isFinite else { return }
        UserDefaults.standard.set(seconds, forKey: key)
        HistoryStore.save(HistoryEntry(id: anime.id, title: anime.name.main, episodeID: "yani-\(selected.id)", episodeNumber: Double(selected.number ?? ""), seconds: seconds, updated: Date()))
    }
    func select(_ video: YaniVideo, preservePosition: Bool = false) {
        save(); let prior = preservePosition ? seconds : UserDefaults.standard.double(forKey: "progress.\(anime.id).yani-\(video.id)")
        task?.cancel(); player.stop(); selected = video; seconds = prior; pendingSeek = prior; error = nil; notice = nil; choices = []; duration = 0; seekable = false; finished = false; loading = true
        UserDefaults.standard.set(video.groupKey, forKey: "preferredYaniVoice")
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
        guard let video = videos.first(where: { $0.groupKey == name && episodeIdentity($0.number) == episodeIdentity(selected.number) }) else { error = "В этой озвучке нет текущей серии. Выберите другую серию."; return }
        select(video, preservePosition: true)
    }
    func next() {
        guard let index = episodes.firstIndex(where: { $0.id == selected.id }), episodes.indices.contains(index + 1) else { return }
        select(episodes[index + 1])
    }
    func seek(_ value: Double) { guard value.isFinite, player.isSeekable else { return }; let target = max(0, min(value, duration > 0 ? duration : 2_000_000)); player.time = VLCTime(int: Int32(target * 1000)); seconds = target }
    func toggle() { if finished { select(selected); return }; if player.isPlaying { player.pause() } else { player.play(); player.rate = rate } }
    func tick() {
        playing = player.isPlaying; seekable = player.isSeekable
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
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.player.pause()
                    try? await Task.sleep(for: .seconds(1))
                    let frozen = self.player.time.intValue
                    try? await Task.sleep(for: .seconds(1))
                    guard !self.player.isPlaying, abs(self.player.time.intValue - frozen) < 1000, self.player.isSeekable else { NSLog("ANIMEAPP_CONTROLS_%@ failed pause/seekability", probe); return }
                    self.seek(15); self.toggle()
                    for _ in 0..<10 {
                        try? await Task.sleep(for: .seconds(1))
                        if self.player.isPlaying && self.player.time.intValue >= 10000 { NSLog("ANIMEAPP_CONTROLS_%@ passed", probe); return }
                    }
                    NSLog("ANIMEAPP_CONTROLS_%@ failed resume/seek", probe)
                }
            }
            #endif
            tickCount += 1; if tickCount % 10 == 0 && pendingSeek == nil { save() }
        }
        if player.state == .ended && !finished {
            save(); finished = true; UserDefaults.standard.set(0, forKey: key)
            if UserDefaults.standard.object(forKey: "autoNext") as? Bool ?? true { next() }
        }
    }
}
struct VLCSurface: UIViewRepresentable {
    let player: VLCMediaPlayer
    func makeUIView(context: Context) -> UIView { let view = UIView(); view.backgroundColor = .black; player.drawable = view; return view }
    func updateUIView(_ view: UIView, context: Context) { if player.drawable == nil { player.drawable = view } }
}
struct MultiSourcePlayerScreen: View {
    @StateObject private var model: MultiSourcePlayback
    @Environment(\.dismiss) private var dismiss
    @State private var controls = true
    @State private var locked = false
    @State private var panel: PlayerPanel?
    @State private var scrub: Double?
    @State private var feedback: String?
    enum PlayerPanel: String, Identifiable { case episodes, voices, settings; var id: String { rawValue } }
    init(sourceAnime: Anime, video: YaniVideo, videos: [YaniVideo]) { _model = StateObject(wrappedValue: MultiSourcePlayback(anime: sourceAnime, videos: videos, video: video)) }
    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            let windowInsets = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)?.safeAreaInsets ?? .zero
            ZStack {
                Color.black
                VLCSurface(player: model.player).ignoresSafeArea()
                HStack(spacing: 0) {
                    Color.clear.contentShape(Rectangle()).onTapGesture(count: 2) { jump(-10) }.onTapGesture { reveal() }
                    Color.clear.contentShape(Rectangle()).onTapGesture(count: 2) { jump(10) }.onTapGesture { reveal() }
                }
                if controls && !locked {
                    LinearGradient(colors: [.black.opacity(0.85), .clear, .clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
                    VStack(spacing: 0) {
                        header(landscape: landscape)
                        Spacer()
                        timeline
                        actions
                    }.padding(.horizontal, max(20, max(windowInsets.left, windowInsets.right) + 12))
                     .padding(.top, max(16, max(geometry.safeAreaInsets.top, windowInsets.top) + 8))
                     .padding(.bottom, max(16, max(geometry.safeAreaInsets.bottom, windowInsets.bottom) + 8))
                     .transition(.opacity)
                    if model.error == nil { transport }
                }
                if model.loading && model.error == nil { ProgressView("Подключаем видео…").tint(.white).foregroundStyle(.white).padding(18).background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 14)).allowsHitTesting(false) }
                if let error = model.error {
                    VStack(spacing: 14) {
                        Image(systemName: "wifi.exclamationmark").font(.largeTitle)
                        Text("Не удалось продолжить просмотр").font(.headline)
                        Text(error).font(.footnote).multilineTextAlignment(.center).lineLimit(4).foregroundStyle(.white.opacity(0.7))
                        HStack { Button("Повторить") { model.select(model.selected, preservePosition: true) }.buttonStyle(.borderedProminent); Button("Озвучки") { panel = .voices }.buttonStyle(.bordered) }
                    }.padding(24).frame(maxWidth: 380).background(.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 20)).padding(24)
                }
                if locked {
                    VStack { Spacer(); Button { locked = false; controls = true } label: { Label("Разблокировать", systemImage: "lock.open.fill").font(.subheadline.bold()).padding(14).background(.black.opacity(0.7), in: Capsule()) }.padding(.bottom, max(24, geometry.safeAreaInsets.bottom + 12)) }
                }
                if let feedback { Text(feedback).font(.headline.monospacedDigit()).padding(16).background(.black.opacity(0.75), in: Capsule()).allowsHitTesting(false) }
            }.foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.ignoresSafeArea().background(.black)
        .toolbar(.hidden, for: .navigationBar).toolbar(.hidden, for: .tabBar)
        .sheet(item: $panel) { selection in selectionSheet(selection) }
        .statusBarHidden(true)
        .task(id: "\(controls)-\(model.playing)-\(panel?.id ?? "none")-\(scrub != nil)") {
            #if DEBUG
            if ProcessInfo.processInfo.environment["ANIMEAPP_PROBE"] != nil { return }
            #endif
            guard controls else { return }; do { try await Task.sleep(for: .seconds(5)); if model.playing && panel == nil && scrub == nil && model.error == nil { withAnimation { controls = false } } } catch {} }
        .onChange(of: model.playing) { _, playing in if !playing { controls = true } }
        .onChange(of: panel) { _, value in if value != nil { controls = true } }
        .onAppear {
            model.start()
            #if DEBUG
            if ProcessInfo.processInfo.environment["ANIMEAPP_LANDSCAPE"] == "1" { Task { try? await Task.sleep(for: .seconds(1)); rotate(.landscapeRight) } }
            #endif
        }.onDisappear { model.stop() }
    }
    private func header(landscape: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Button { rotate(.portrait); dismiss() } label: { Image(systemName: "chevron.left").font(.title3.bold()).frame(width: 44, height: 44).background(.white.opacity(0.12), in: Circle()) }.accessibilityLabel("Закрыть плеер")
            VStack(alignment: .leading, spacing: 5) {
                Text(model.anime.name.main).font(.headline).lineLimit(landscape ? 1 : 2)
                Text("Серия \(model.selected.number ?? "—") · \(model.selected.voiceName)").font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }.padding(.top, 4)
            Spacer(minLength: 0)
            Button { locked = true; controls = false } label: { Image(systemName: "lock.open").frame(width: 40, height: 44) }.accessibilityLabel("Заблокировать управление")
            Button { rotate(landscape ? .portrait : .landscapeRight) } label: { Image(systemName: landscape ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").frame(width: 40, height: 44) }.accessibilityLabel(landscape ? "Портретный режим" : "Полный экран")
        }
    }
    private var transport: some View {
        HStack(spacing: 42) {
            Button { jump(-10) } label: { Image(systemName: "gobackward.10").font(.system(size: 30)).frame(width: 52, height: 64) }.disabled(!model.seekable)
            Button { model.toggle(); controls = true } label: { Image(systemName: model.playing ? "pause.fill" : "play.fill").font(.system(size: 36)).frame(width: 76, height: 76).background(.black.opacity(0.4), in: Circle()) }.disabled(model.loading)
            Button { jump(10) } label: { Image(systemName: "goforward.10").font(.system(size: 30)).frame(width: 52, height: 64) }.disabled(!model.seekable)
        }.opacity(model.loading ? 0 : 1)
    }
    private var timeline: some View {
        VStack(spacing: 0) {
            if let notice = model.notice { Text(notice).font(.caption).foregroundStyle(.white.opacity(0.75)).lineLimit(2) }
            if model.duration > 0 {
                Slider(value: Binding(get: { min(scrub ?? model.seconds, model.duration) }, set: { scrub = $0 }), in: 0...max(1, model.duration), onEditingChanged: { editing in if !editing { if let scrub { model.seek(scrub) }; scrub = nil; controls = true } }).tint(.purple).disabled(!model.seekable || model.loading)
                HStack { Text(clock(scrub ?? model.seconds)); Spacer(); Text(clock(model.duration)) }.font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.8))
            } else { Text("Серия \(model.selected.number ?? "—")").font(.caption).foregroundStyle(.white.opacity(0.7)) }
        }
    }
    private var actions: some View {
        HStack(spacing: 12) {
            Button { panel = .episodes } label: { Label("Серии", systemImage: "list.bullet.rectangle") }
            Spacer()
            Button { panel = .voices } label: { Label("Озвучка", systemImage: "waveform") }
            Spacer()
            Button { panel = .settings } label: { Image(systemName: "gearshape") }.accessibilityLabel("Настройки плеера")
            if model.hasNext { Button { model.next(); controls = true } label: { Image(systemName: "forward.end.fill") }.accessibilityLabel("Следующая серия") }
        }.font(.subheadline.weight(.semibold)).buttonStyle(.plain).frame(minHeight: 50).padding(.top, 8)
    }
    private func selectionSheet(_ selection: PlayerPanel) -> some View {
        NavigationStack {
            List {
                switch selection {
                case .episodes:
                    Section(model.selected.voiceName) {
                        ForEach(model.episodes) { video in
                            Button { model.select(video); panel = nil } label: {
                                HStack {
                                    Label("Серия \(video.number ?? "—")", systemImage: video.id == model.selected.id ? "play.circle.fill" : "play.circle")
                                    Spacer()
                                    if video.id == model.selected.id { Image(systemName: "checkmark") }
                                }.padding(.vertical, 7)
                            }
                        }
                    }
                case .voices:
                    Section("Серия \(model.selected.number ?? "—")") {
                        ForEach(model.voices, id: \.self) { voice in
                            let available = model.videos.contains { $0.groupKey == voice && episodeIdentity($0.number) == episodeIdentity(model.selected.number) }
                            Button { model.chooseVoice(voice); panel = nil } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(voice); Spacer()
                                        if voice == model.selected.groupKey { Image(systemName: "checkmark") }
                                    }
                                    if !available { Text("Эта серия ещё недоступна").font(.caption).foregroundStyle(.secondary) }
                                }
                            }.disabled(!available)
                        }
                    }
                case .settings:
                    Section("Качество") {
                        ForEach(model.choices) { choice in
                            Button { model.changeQuality(choice); panel = nil } label: {
                                HStack { Text(choice.label); Spacer(); if choice.label == model.quality { Image(systemName: "checkmark") } }
                            }
                        }
                    }
                    Section("Скорость") {
                        Picker("Скорость просмотра", selection: Binding(get: { model.rate }, set: { model.rate = $0; model.player.rate = $0 })) {
                            ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 1.75, 2], id: \.self) { value in Text("\(value.formatted())×").tag(value) }
                        }
                    }
                    Section("Звук") {
                        ForEach(model.audioTracks, id: \.id) { track in
                            Button { model.player.currentAudioTrackIndex = track.id; model.objectWillChange.send() } label: {
                                HStack { Text(track.name); Spacer(); if model.player.currentAudioTrackIndex == track.id { Image(systemName: "checkmark") } }
                            }
                        }
                    }
                    Section("Субтитры") {
                        if model.subtitleTracks.isEmpty { Text("Источник не предоставил отдельные субтитры").foregroundStyle(.secondary) }
                        ForEach(model.subtitleTracks, id: \.id) { track in
                            Button { model.player.currentVideoSubTitleIndex = track.id; model.objectWillChange.send() } label: {
                                HStack { Text(track.name); Spacer(); if model.player.currentVideoSubTitleIndex == track.id { Image(systemName: "checkmark") } }
                            }
                        }
                    }
                }
            }.navigationTitle(selection == .episodes ? "Серии" : selection == .voices ? "Озвучки и источники" : "Настройки плеера")
             .navigationBarTitleDisplayMode(.inline).toolbar { Button("Готово") { panel = nil } }
        }.preferredColorScheme(.dark).tint(.purple).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
    private func reveal() { guard !locked else { return }; withAnimation(.easeInOut(duration: 0.2)) { controls.toggle() } }
    private func jump(_ delta: Double) {
        guard !locked, model.seekable else { return }; model.seek(model.seconds + delta); feedback = delta > 0 ? "+10 сек" : "−10 сек"
        Task { try? await Task.sleep(for: .seconds(0.8)); feedback = nil }
    }
    private func rotate(_ orientation: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) else { return }
        scene.windows.first(where: \.isKeyWindow)?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { error in
            model.notice = "Поворот недоступен: \(error.localizedDescription)"
        }
    }
    private func clock(_ value: Double) -> String { let s = Int(max(0, value)); return String(format: "%d:%02d", s / 60, s % 60) }
}
func episodeIdentity(_ number: String?) -> String {
    let value = (number ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if let numeric = Double(value.replacingOccurrences(of: ",", with: ".")), numeric.isFinite, numeric >= 0 { return String(numeric) }
    return value.lowercased()
}
struct HistoryEntry: Codable, Identifiable {
    let id: Int
    let title: String
    let episodeID: String
    let episodeNumber: Double?
    let seconds: Double
    let updated: Date
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
        HistoryStore.save(HistoryEntry(id: anime.id, title: anime.name.main, episodeID: episode.id, episodeNumber: episode.ordinal, seconds: current, updated: Date()))
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
        HStack {
            Menu {
                ForEach(WatchStatus.allCases) { status in Button(status.rawValue) { var entry = current; entry.status = status; update(entry) } }
                if current.status != nil { Button("Убрать из списка", role: .destructive) { var entry = current; entry.status = nil; update(entry) } }
            } label: { Label(current.status?.rawValue ?? "Добавить в библиотеку", systemImage: "bookmark") }
            Spacer()
            Button { var entry = current; entry.favorite.toggle(); update(entry) } label: { Label(current.favorite ? "В избранном" : "В избранное", systemImage: current.favorite ? "heart.fill" : "heart") }
        }.font(.subheadline).buttonStyle(.bordered)
    }
}
struct LibraryView: View {
    @AppStorage(HistoryStore.storageKey) private var historyData = Data()
    @AppStorage(LocalLibrary.key) private var libraryData = Data()
    @State private var selection = "История"
    var history: [HistoryEntry] { (try? JSONDecoder().decode([HistoryEntry].self, from: historyData)) ?? [] }
    var library: [LibraryEntry] { LocalLibrary.decode(libraryData) }
    var visible: [LibraryEntry] { selection == "Избранное" ? library.filter(\.favorite) : library.filter { $0.status?.rawValue == selection } }
    var body: some View {
        NavigationStack {
            List {
                if selection == "История" {
                    if history.isEmpty { Text("Просмотренные тайтлы появятся здесь.").foregroundStyle(.secondary) }
                    ForEach(history) { entry in NavigationLink { DetailView(id: entry.id) } label: { VStack(alignment: .leading) { Text(entry.title); Text("Серия \((entry.episodeNumber ?? 0).formatted()) · \(Int(entry.seconds / 60)) мин.").font(.caption).foregroundStyle(.secondary) } } }
                    .onDelete { offsets in var all = history; all.remove(atOffsets: offsets); historyData = (try? JSONEncoder().encode(all)) ?? Data() }
                } else {
                    if visible.isEmpty { Text("В этом разделе пока нет тайтлов.").foregroundStyle(.secondary) }
                    ForEach(visible) { entry in NavigationLink { DetailView(id: entry.id) } label: {
                        HStack { AsyncImage(url: entry.imageURL) { image in image.resizable().scaledToFill() } placeholder: { Color.purple.opacity(0.2) }.frame(width: 54, height: 75).clipped().cornerRadius(8); Text(entry.title); Spacer(); if entry.favorite { Image(systemName: "heart.fill").foregroundStyle(.purple) } }
                    } }
                }
            }.navigationTitle("Библиотека")
             .toolbar { ToolbarItem(placement: .topBarTrailing) { Menu(selection) { Button("История") { selection = "История" }; Button("Избранное") { selection = "Избранное" }; ForEach(WatchStatus.allCases) { status in Button(status.rawValue) { selection = status.rawValue } } } } }
        }
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
    @State private var exporting = false
    @State private var importing = false
    @State private var exportDocument: BackupDocument?
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Воспроизведение") { Toggle("Следующая серия автоматически", isOn: $autoNext) }
                Section("Пропуск") { Toggle("Автоматически пропускать опенинг", isOn: $opening); Toggle("Автоматически пропускать эндинг", isOn: $ending); Text("Используются метки источника; данные AniSkip применяются только при близкой длительности. Различия монтажа всё равно возможны.").font(.footnote).foregroundStyle(.secondary) }
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
