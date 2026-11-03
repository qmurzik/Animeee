import SwiftUI
import AVKit
import UniformTypeIdentifiers

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
    var body: some Scene { WindowGroup { RootView().preferredColorScheme(.dark).tint(.purple) } }
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
            Text(anime.name.main).font(.subheadline.weight(.semibold)).lineLimit(2).frame(width: 140, alignment: .leading)
            if let year = anime.year { Text(String(year)).font(.caption).foregroundStyle(.secondary) }
        }.frame(width: 140, alignment: .topLeading)
    }
}
struct CatalogView: View {
    @State private var items: [Anime] = []
    @State private var error: String?
    @AppStorage(HistoryStore.storageKey) private var historyData = Data()
    var history: [HistoryEntry] { (try? JSONDecoder().decode([HistoryEntry].self, from: historyData)) ?? [] }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) { Text("ANIME / APP").font(.caption.weight(.bold)).tracking(2).foregroundStyle(.purple); Text("Хорошо, что ты здесь").font(.title2.bold()) }
                        Spacer(); Image(systemName: "sparkles").font(.title2).foregroundStyle(.purple)
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
                            HStack { VStack(alignment: .leading, spacing: 3) { Text("Свежие релизы").font(.title2.bold()); Text("Обновления AniLibria").font(.caption).foregroundStyle(.secondary) }; Spacer() }.padding(.horizontal)
                            ScrollView(.horizontal, showsIndicators: false) { LazyHStack(alignment: .top, spacing: 12) { ForEach(items) { anime in NavigationLink { DetailView(id: anime.id) } label: { CoverCard(anime: anime) }.buttonStyle(.plain) } }.padding(.horizontal) }
                        }
                        Text("Каталог").font(.title2.bold()).padding(.horizontal)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                            ForEach(items) { anime in NavigationLink { DetailView(id: anime.id) } label: { CoverCard(anime: anime) }.buttonStyle(.plain) }
                        }.padding(.horizontal)
                    }
                }.padding(.top, 12).padding(.bottom, 30)
            }.background(Color(red: 0.045, green: 0.04, blue: 0.075)).toolbar(.hidden, for: .navigationBar).task { await load() }.refreshable { await load() }
        }
    }
    func load() async { do { items = try await Libria().latest(); error = nil } catch { self.error = "Не удалось загрузить каталог: \(error.localizedDescription)" } }
}
struct SearchView: View {
    @State private var query = ""
    @State private var items: [Anime] = []
    @State private var error: String?
    var body: some View { NavigationStack { List { if let error { Text(error) }; ForEach(items) { item in NavigationLink { DetailView(id: item.id) } label: { PosterView(anime: item) } } }.navigationTitle("Поиск").searchable(text: $query, prompt: "Название аниме").task(id: query) { guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { items = []; return }; do { try await Task.sleep(for: .milliseconds(400)); let found = try await Libria().search(query); guard !Task.isCancelled else { return }; items = found; error = nil } catch is CancellationError {} catch { self.error = error.localizedDescription } } } }
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
                        VStack(alignment: .leading, spacing: 6) { Text("ANILIBRIA").font(.caption.bold()).tracking(2).foregroundStyle(.purple); Text(anime.name.main).font(.largeTitle.bold()).lineLimit(3); if let year = anime.year { Text("\(String(year))  •  \(anime.episodes?.count ?? 0) серий").font(.subheadline).foregroundStyle(.secondary) } }.padding(20)
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
                        HStack { Text("Серии").font(.title2.bold()); Spacer(); Text("AniLibria").font(.caption).foregroundStyle(.purple) }
                        ForEach(anime.episodes ?? []) { episode in
                            NavigationLink { PlayerScreen(anime: anime, episode: episode) } label: {
                                HStack(spacing: 14) { Image(systemName: "play.fill").frame(width: 42, height: 42).background(.purple.opacity(0.24), in: RoundedRectangle(cornerRadius: 12)); VStack(alignment: .leading, spacing: 4) { Text("Серия \((episode.ordinal ?? 0).formatted())").font(.subheadline.bold()); if let name = episode.name { Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1) } }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }.padding(12).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 20)
                }.padding(.bottom, 30)
            } else if let error { ContentUnavailableView("Источник недоступен", systemImage: "wifi.exclamationmark", description: Text(error)) } else { ProgressView().padding() }
        }.background(Color(red: 0.045, green: 0.04, blue: 0.075)).navigationBarTitleDisplayMode(.inline).task { do { anime = try await Libria().release(id) } catch { self.error = error.localizedDescription } }
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
        let grouped = Dictionary(grouping: videos, by: \.groupKey)
        return grouped.map { (key: $0.key, count: $0.value.count) }.sorted { a, b in
            if (a.key == preferred) != (b.key == preferred) { return a.key == preferred }
            return a.key.localizedStandardCompare(b.key) == .orderedAscending
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Другие озвучки").font(.title2.bold()); Spacer(); if loading { ProgressView() } }
            Text("Каталог YummyAnime · нативное воспроизведение").font(.caption).foregroundStyle(.secondary)
            if !loaded && !loading { Button("Найти озвучки") { Task { await load() } }.buttonStyle(.bordered) }
            if let error { Text(error).font(.footnote).foregroundStyle(.secondary); Button("Повторить") { Task { await load() } }.font(.footnote) }
            ForEach(groups, id: \.key) { group in
                NavigationLink {
                    YaniEpisodesView(name: group.key, videos: videos.filter { $0.groupKey == group.key })
                } label: { HStack { VStack(alignment: .leading) { Text(group.key); Text("\(group.count) записей серий").font(.caption).foregroundStyle(.secondary) }; Spacer(); if preferred == group.key { Image(systemName: "star.fill").foregroundStyle(.yellow) } }.padding(10).background(.white.opacity(0.06)).cornerRadius(10) }
            }
        }
    }
    func load() async {
        loading = true; error = nil
        do { videos = try await YaniProvider().videos(for: anime); loaded = true; if videos.isEmpty { error = "Источник не вернул доступных страниц плеера." } }
        catch { self.error = "YummyAnime: \(error.localizedDescription)" }
        loading = false
    }
}
struct YaniEpisodesView: View {
    let name: String
    let videos: [YaniVideo]
    @AppStorage("preferredYaniVoice") private var preferred = ""
    var sorted: [YaniVideo] { videos.sorted { ($0.number ?? "").localizedStandardCompare($1.number ?? "") == .orderedAscending } }
    var body: some View {
        List {
            Section { Button(preferred == name ? "Убрать из предпочтений" : "Предпочитать эту озвучку и плеер") { preferred = preferred == name ? "" : name } }
            Section("Серии") {
                ForEach(sorted) { video in
                    if video.page != nil { NavigationLink("Серия \(video.number ?? "—")") { AksorNativeScreen(video: video) } }
                }
            }
        }.navigationTitle(name).navigationBarTitleDisplayMode(.inline)
    }
}
struct AksorResponse: Decodable { let qualities: [String: String?] }
struct AksorNativeScreen: View {
    let video: YaniVideo
    @State private var anime: Anime?
    @State private var episode: Episode?
    @State private var error: String?
    var body: some View {
        Group {
            if let anime, let episode { PlayerScreen(anime: anime, episode: episode) }
            else if let error { ContentUnavailableView("Поток недоступен", systemImage: "play.slash", description: Text(error)) }
            else { ProgressView("Получаем видеопоток…") }
        }.task { await resolve() }
    }
    func resolve() async {
        guard let page = video.page, page.host?.lowercased() == "player.aksor.tv", page.pathComponents.count == 3, page.pathComponents[1] == "video" else { error = "Для этого балансера прямой поток пока не поддерживается."; return }
        let hash = page.lastPathComponent
        guard hash.range(of: "^[a-zA-Z0-9_-]{1,128}$", options: .regularExpression) != nil,
              let api = URL(string: "https://player.aksor.tv/api/video/\(hash)") else { error = "Некорректный адрес плеера."; return }
        do {
            var req = URLRequest(url: api); req.setValue(page.absoluteString, forHTTPHeaderField: "Referer"); req.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            let payload = try JSONDecoder().decode(AksorResponse.self, from: data)
            func compatible(_ key: String) -> String? {
                guard let raw = payload.qualities[key] ?? nil, let url = URL(string: raw.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? raw), url.scheme == "https", ["m3u8", "mp4"].contains(url.pathExtension.lowercased()) else { return nil }
                return url.absoluteString
            }
            let q480 = compatible("q480"), q720 = compatible("q720"), q1080 = compatible("q1080")
            guard q480 != nil || q720 != nil || q1080 != nil else { error = "Aksor вернул MPEG-DASH или другой формат, который встроенный AVPlayer не поддерживает. Выберите AniLibria."; return }
            let item = Episode(id: "yani-\(video.id)", ordinal: Double(video.number ?? ""), name: nil, opening: nil, ending: nil, duration: nil, hls_480: q480, hls_720: q720, hls_1080: q1080)
            // Keep the YummyAnime video identity separate from AniLibria IDs.
            anime = Anime(id: -video.id, mal: nil, name: Anime.Name(main: video.voiceName, english: video.playerName), poster: nil, description: nil, year: nil, episodes: [item]); episode = item
        } catch { self.error = "Aksor: \(error.localizedDescription)" }
    }
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
                Section("Источник") { Text("AniLibria"); Text("Доступность зависит от источника и сети.").font(.footnote).foregroundStyle(.secondary) }
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
