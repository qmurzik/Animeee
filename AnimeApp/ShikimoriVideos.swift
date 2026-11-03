import SwiftUI

protocol ClipCatalog {
    func videos(animeID: Int) async throws -> [ExternalVideo]
}
struct ShikimoriCatalog: ClipCatalog {
    func videos(animeID: Int) async throws -> [ExternalVideo] {
        guard animeID > 0 else { throw URLError(.badURL) }
        let url = URL(string: "https://shikimori.io/api/animes/\(animeID)/videos")!
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AnimeApp/0.7 (native iOS client)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode([ExternalVideo].self, from: data).filter { $0.destination != nil }
    }
}
struct ShikimoriVideosView: View {
    let animeID: Int
    @State private var expanded = false
    @State private var clips: [ExternalVideo] = []
    @State private var loading = false
    @State private var loaded = false
    @State private var error: String?
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Видео из Shikimori открываются на платформе источника. Это трейлеры и клипы; они не заменяют серии.").font(.caption).foregroundStyle(Cinema.muted)
                if loading { ProgressView().padding() }
                if let error { Text(error).font(.caption).foregroundStyle(Cinema.muted); Button("Повторить") { Task { await load() } } }
                if loaded && clips.isEmpty { Text("Для этого тайтла нет доступных клипов").font(.subheadline).foregroundStyle(Cinema.muted) }
                LazyVStack(spacing: 0) {
                    ForEach(clips) { clip in
                        if let destination = clip.destination {
                            Link(destination: destination) {
                                HStack(spacing: 12) {
                                    Image(systemName: "play.rectangle").font(.title3).foregroundStyle(Cinema.accent)
                                    VStack(alignment: .leading, spacing: 5) { Text(clip.name?.isEmpty == false ? clip.name! : clip.kindTitle).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(2); Text("\(clip.kindTitle) · \(clip.hosting)").font(.caption).foregroundStyle(Cinema.muted) }
                                    Spacer(minLength: 0); Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Cinema.muted)
                                }.padding(.vertical, 13).contentShape(Rectangle())
                            }
                            Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
                        }
                    }
                }
            }.padding(.top, 14)
        } label: {
            VStack(alignment: .leading, spacing: 5) { Text("Видео Shikimori").font(.title3.bold()).foregroundStyle(.white); Text("Трейлеры, опенинги и клипы").font(.caption).foregroundStyle(Cinema.muted) }
        }.task(id: expanded) { if expanded && !loaded && !loading { await load() } }
    }
    private func load() async {
        loading = true; error = nil; defer { loading = false }
        do { let result = try await ShikimoriCatalog().videos(animeID: animeID); guard !Task.isCancelled else { return }; clips = result; loaded = true }
        catch { if !Task.isCancelled { self.error = "Shikimori недоступен: \(error.localizedDescription)" } }
    }
}
