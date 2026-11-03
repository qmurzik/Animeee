import SwiftUI
import AVKit

struct Anime: Codable, Identifiable {
    struct Name: Codable { let main: String; let english: String? }
    struct Poster: Codable { let src: String? }
    let id: Int
    let name: Name
    let poster: Poster?
    let description: String?
    let year: Int?
    let episodes: [Episode]?
    var imageURL: URL? { guard let src = poster?.src else { return nil }; return URL(string: src.hasPrefix("http") ? src : "https://anilibria.top" + src) }
}
struct Segment: Codable { let start: Double?; let stop: Double? }
struct Episode: Codable, Identifiable {
    let id: String
    let ordinal: Double
    let name: String?
    let opening: Segment?
    let ending: Segment?
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
        Text("Серии").font(.title2.bold())
        ForEach(anime.episodes ?? []) { episode in NavigationLink { PlayerScreen(anime: anime, episode: episode) } label: { HStack { Image(systemName: "play.circle.fill").font(.title2); Text("Серия \(episode.ordinal.formatted())"); Spacer(); Text(episode.name ?? "").lineLimit(1).foregroundStyle(.secondary) }.padding(12).background(.white.opacity(0.06)).cornerRadius(12) } }
    }.padding() } else if let error { ContentUnavailableView("Источник недоступен", systemImage: "wifi.exclamationmark", description: Text(error)) } else { ProgressView().padding() } }.navigationBarTitleDisplayMode(.inline).task { do { anime = try await Libria().release(id) } catch { self.error = error.localizedDescription } } }
}
struct PlayerScreen: View {
    let anime: Anime
    let episode: Episode
    @State private var player = AVPlayer()
    @State private var quality = ""
    @State private var current: Double = 0
    @State private var timer: Any?
    var key: String { "progress.\(anime.id).\(episode.id)" }
    var body: some View { VStack(spacing: 16) {
        VideoPlayer(player: player).frame(height: 240)
        HStack { Text("Серия \(episode.ordinal.formatted())").font(.headline); Spacer(); Menu(quality.isEmpty ? "Качество" : quality) { ForEach(episode.streams, id: \.0) { item in Button(item.0) { play(item) } } } }
        HStack { if let s = episode.opening, let start = s.start, let stop = s.stop, current >= start, current < stop { Button("Пропустить опенинг") { player.seek(to: CMTime(seconds: stop, preferredTimescale: 600)) } }; if let s = episode.ending, let start = s.start, let stop = s.stop, current >= start, current < stop { Button("Пропустить эндинг") { player.seek(to: CMTime(seconds: stop, preferredTimescale: 600)) } } }
        Text("Озвучка и видео: AniLibria").font(.footnote).foregroundStyle(.secondary)
        Spacer()
    }.padding().navigationTitle(anime.name.main).navigationBarTitleDisplayMode(.inline).onAppear { if let first = episode.streams.first { play(first) }; timer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 2, preferredTimescale: 1), queue: .main) { time in let seconds = time.seconds; if seconds.isFinite && seconds > 0 { current = seconds; UserDefaults.standard.set(seconds, forKey: key); UserDefaults.standard.set(anime.id, forKey: "lastAnime"); UserDefaults.standard.set(anime.name.main, forKey: "lastName") } } }.onDisappear { player.pause(); if let timer { player.removeTimeObserver(timer) } } }
    func play(_ stream: (String, String)) { guard let url = URL(string: stream.1) else { return }; let position = current > 0 ? current : UserDefaults.standard.double(forKey: key); quality = stream.0; player.replaceCurrentItem(with: AVPlayerItem(url: url)); if position > 0 { player.seek(to: CMTime(seconds: position, preferredTimescale: 600)) }; player.play() }
}
struct LibraryView: View {
    @AppStorage("lastAnime") private var lastAnime = 0
    @AppStorage("lastName") private var lastName = ""
    var body: some View { NavigationStack { List { if lastAnime > 0 { NavigationLink(lastName) { DetailView(id: lastAnime) } } else { Text("Здесь появится последний просмотренный тайтл.").foregroundStyle(.secondary) } }.navigationTitle("История") } }
}
