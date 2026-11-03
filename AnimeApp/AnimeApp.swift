import SwiftUI
import AVKit

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
            LibraryView().tabItem { Label("История", systemImage: "clock") }
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
struct CatalogView: View {
    @State private var items: [Anime] = []
    @State private var error: String?
    var body: some View { NavigationStack { List { if let error { Text(error).foregroundStyle(.secondary) }; Section("Новые релизы · AniLibria") { ForEach(items) { item in NavigationLink { DetailView(id: item.id) } label: { PosterView(anime: item) } } } }.navigationTitle("Открывайте аниме").task { await load() }.refreshable { await load() } } }
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
    var body: some View { ScrollView { if let anime { VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .top) { AsyncImage(url: anime.imageURL) { $0.resizable().scaledToFill() } placeholder: { Color.purple.opacity(0.2) }.frame(width: 130, height: 190).clipped().cornerRadius(14); VStack(alignment: .leading, spacing: 10) { Text(anime.name.main).font(.title2.bold()); Text(anime.name.english ?? "").foregroundStyle(.secondary); Text("AniLibria · \(anime.episodes?.count ?? 0) серий").font(.caption).foregroundStyle(.purple) } }
        Text(anime.description ?? "Описание отсутствует").font(.body).foregroundStyle(.secondary)
        if let last = HistoryStore.load().first(where: { $0.id == anime.id }), let episode = anime.episodes?.first(where: { $0.id == last.episodeID }) {
            NavigationLink { PlayerScreen(anime: anime, episode: episode) } label: { Label("Продолжить: серия \((episode.ordinal ?? 0).formatted())", systemImage: "play.fill").frame(maxWidth: .infinity).padding().background(.purple).foregroundStyle(.white).cornerRadius(12) }
        }
        Text("Серии").font(.title2.bold())
        ForEach(anime.episodes ?? []) { episode in NavigationLink { PlayerScreen(anime: anime, episode: episode) } label: { HStack { Image(systemName: "play.circle.fill").font(.title2); Text("Серия \((episode.ordinal ?? 0).formatted())"); Spacer(); Text(episode.name ?? "").lineLimit(1).foregroundStyle(.secondary) }.padding(12).background(.white.opacity(0.06)).cornerRadius(12) } }
    }.padding() } else if let error { ContentUnavailableView("Источник недоступен", systemImage: "wifi.exclamationmark", description: Text(error)) } else { ProgressView().padding() } }.navigationBarTitleDisplayMode(.inline).task { do { anime = try await Libria().release(id) } catch { self.error = error.localizedDescription } } }
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
struct LibraryView: View {
    @AppStorage(HistoryStore.storageKey) private var data = Data()
    var entries: [HistoryEntry] { (try? JSONDecoder().decode([HistoryEntry].self, from: data)) ?? [] }
    var body: some View { NavigationStack { List { if entries.isEmpty { Text("Здесь появятся просмотренные тайтлы.").foregroundStyle(.secondary) }; ForEach(entries) { entry in NavigationLink { DetailView(id: entry.id) } label: { VStack(alignment: .leading) { Text(entry.title); Text("Серия \((entry.episodeNumber ?? 0).formatted()) · \(Int(entry.seconds / 60)) мин.").font(.caption).foregroundStyle(.secondary) } } }.onDelete { offsets in var all = entries; all.remove(atOffsets: offsets); data = (try? JSONEncoder().encode(all)) ?? Data() } }.navigationTitle("История") } }
}

struct SettingsView: View {
    @AppStorage("autoSkipOpening") private var opening = false
    @AppStorage("autoSkipEnding") private var ending = false
    @AppStorage("autoNext") private var autoNext = true
    var body: some View { NavigationStack { Form { Section("Воспроизведение") { Toggle("Следующая серия автоматически", isOn: $autoNext) }; Section("Пропуск") { Toggle("Автоматически пропускать опенинг", isOn: $opening); Toggle("Автоматически пропускать эндинг", isOn: $ending); Text("Используются точные метки источника; данные AniSkip применяются только при совпадении длительности.").font(.footnote).foregroundStyle(.secondary) }; Section("Источник") { Text("AniLibria"); Text("Доступность зависит от источника и сети.").font(.footnote).foregroundStyle(.secondary) } }.navigationTitle("Настройки") } }
}
