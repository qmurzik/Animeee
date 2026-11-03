import SwiftUI
import ImageIO

// Shared visual language, bounded image decoding, and reusable viewing controls.
enum Cinema {
    static let background = Color(red: 0.035, green: 0.039, blue: 0.062)
    static let surface = Color(red: 0.075, green: 0.08, blue: 0.115)
    static let accent = Color(red: 0.64, green: 0.46, blue: 1)
    static let muted = Color(red: 0.61, green: 0.64, blue: 0.72)
}
actor ArtworkCache {
    static let shared = ArtworkCache()
    private let cache = NSCache<NSURL, UIImage>()
    private let session: URLSession
    init() {
        cache.totalCostLimit = 32 * 1024 * 1024
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 64 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }
    func clear() { cache.removeAllObjects(); session.configuration.urlCache?.removeAllCachedResponses() }
    func image(_ url: URL) async throws -> UIImage? {
        if let image = cache.object(forKey: url as NSURL) { return image }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 12_000_000, !Task.isCancelled else { return nil }
        let image: UIImage? = autoreleasepool {
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 650, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
            return UIImage(cgImage: decoded)
        }
        if let image, let cg = image.cgImage { cache.setObject(image, forKey: url as NSURL, cost: cg.bytesPerRow * cg.height) }
        return image
    }
}
struct Artwork: View {
    let url: URL?
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            Cinema.surface
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: "sparkles.tv").font(.title).foregroundStyle(Cinema.accent.opacity(0.35)) }
        }.clipped().task(id: url) { image = nil; guard let url else { return }; let loaded = try? await ArtworkCache.shared.image(url); guard !Task.isCancelled else { return }; image = loaded }
    }
}
struct PrimaryWatchButton: View {
    let title: String
    let subtitle: String?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "play.fill").font(.title3)
                VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline); if let subtitle { Text(subtitle).font(.caption).opacity(0.8) } }
                Spacer(); Image(systemName: "arrow.right").font(.subheadline.bold())
            }.foregroundStyle(.white).padding(17).frame(maxWidth: .infinity).background(LinearGradient(colors: [Cinema.accent, Color(red: 0.42, green: 0.28, blue: 0.85)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }
}
func playbackClock(_ value: Double) -> String {
    guard value.isFinite else { return "0:00" }; let s = Int(max(0, value))
    if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) }
    return String(format: "%d:%02d", s / 60, s % 60)
}
func orderedEpisodes(_ videos: [YaniVideo]) -> [YaniVideo] {
    var seen = Set<String>()
    return videos.sorted { a, b in
        if episodeIdentity(a.number) == episodeIdentity(b.number) { return a.id < b.id }
        return EpisodeNumber.isBefore(a.number, b.number)
    }.filter { seen.insert(episodeIdentity($0.number)).inserted }
}
enum VoicePreferences {
    static var favorites: Set<String> { Set(UserDefaults.standard.stringArray(forKey: "favoriteVoiceStudios") ?? []) }
    static func sortedGroups(_ videos: [YaniVideo]) -> [String] {
        let favorites = favorites, preferred = UserDefaults.standard.string(forKey: "preferredYaniVoice") ?? ""
        let grouped = Dictionary(grouping: videos, by: \.groupKey)
        return grouped.keys.sorted { a, b in
            if (a == preferred) != (b == preferred) { return a == preferred }
            let av = favorites.contains(grouped[a]?.first?.voiceName ?? ""), bv = favorites.contains(grouped[b]?.first?.voiceName ?? "")
            if av != bv { return av }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }
}
struct WatchRequest: Identifiable {
    let id = UUID()
    let anime: Anime
    let video: YaniVideo
    let videos: [YaniVideo]
}
struct VoicePicker: View {
    let videos: [YaniVideo]
    let selected: String
    var episode: String? = nil
    let choose: (String) -> Void
    @State private var query = ""
    @State private var favorites = VoicePreferences.favorites
    private var groups: [String] { VoicePreferences.sortedGroups(videos).filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(spacing: 14) {
            HStack { Image(systemName: "magnifyingglass").foregroundStyle(Cinema.muted); TextField("Студия или источник", text: $query).autocorrectionDisabled() }.padding(13).background(Cinema.surface, in: RoundedRectangle(cornerRadius: 12))
            ForEach(groups, id: \.self) { group in
                let entries = videos.filter { $0.groupKey == group }
                if let first = entries.first {
                    let available = episode == nil || entries.contains { episodeIdentity($0.number) == episodeIdentity(episode) }
                    HStack(spacing: 12) {
                        Button { choose(group) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected == group ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(selected == group ? Cinema.accent : Cinema.muted)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(first.voiceName).font(.subheadline.bold()).foregroundStyle(.white)
                                    Text("\(first.playerName) · \(orderedEpisodes(entries).count) серий" + (available ? "" : " · этой серии нет")).font(.caption).foregroundStyle(Cinema.muted)
                                }; Spacer(minLength: 0)
                            }.padding(.vertical, 12).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(!available).opacity(available ? 1 : 0.4)
                        Button {
                            if favorites.contains(first.voiceName) { favorites.remove(first.voiceName) } else { favorites.insert(first.voiceName) }
                            UserDefaults.standard.set(Array(favorites), forKey: "favoriteVoiceStudios")
                        } label: { Image(systemName: favorites.contains(first.voiceName) ? "star.fill" : "star").foregroundStyle(favorites.contains(first.voiceName) ? .yellow : Cinema.muted).frame(width: 44, height: 44) }.buttonStyle(.plain).accessibilityLabel("Предпочитать студию \(first.voiceName)")
                    }
                    Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
                }
            }
            if groups.isEmpty { Text("Подходящих озвучек нет").foregroundStyle(Cinema.muted).padding() }
        }
    }
}
struct EpisodeGrid: View {
    let videos: [YaniVideo]
    let currentID: Int?
    let animeID: Int
    let choose: (YaniVideo) -> Void
    @State private var page = 0
    @State private var query = ""
    private var episodes: [YaniVideo] { orderedEpisodes(videos) }
    private var visible: [YaniVideo] {
        if !query.isEmpty { return episodes.filter { ($0.number ?? "").localizedCaseInsensitiveContains(query) } }
        return Array(episodes.dropFirst(page * 50).prefix(50))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Серии").font(.title3.bold()); Text("\(episodes.count)").font(.caption.bold()).foregroundStyle(Cinema.muted)
                Spacer()
                HStack { Image(systemName: "magnifyingglass"); TextField("№ серии", text: $query).keyboardType(.numbersAndPunctuation).frame(width: 76) }.font(.subheadline).foregroundStyle(Cinema.muted).padding(10).background(Cinema.surface, in: Capsule())
            }
            if episodes.count > 50 && query.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<((episodes.count + 49) / 50), id: \.self) { index in
                            Button("\(episodes[index * 50].number ?? "—")–\(episodes[min(episodes.count - 1, index * 50 + 49)].number ?? "—")") { page = index }
                                .font(.caption.bold()).padding(.horizontal, 14).padding(.vertical, 10).background(page == index ? Cinema.accent.opacity(0.22) : Cinema.surface, in: Capsule()).foregroundStyle(page == index ? Cinema.accent : Cinema.muted)
                        }
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 10)], spacing: 10) {
                ForEach(visible) { video in
                    let current = video.id == currentID
                    let progress = UserDefaults.standard.double(forKey: "progress.\(animeID).yani-\(video.id)")
                    Button { choose(video) } label: {
                        VStack(spacing: 5) {
                            HStack(spacing: 4) { if current { Image(systemName: "play.fill").font(.caption2) }; Text(video.number ?? "—").font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.65) }
                            Text(current ? "Сейчас" : progress > 0 ? playbackClock(progress) : "Серия").font(.system(size: 10, weight: .medium)).foregroundStyle(current ? .white.opacity(0.8) : Cinema.muted)
                        }.frame(maxWidth: .infinity).frame(height: 66).foregroundStyle(.white).background(current ? Cinema.accent : Cinema.surface, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(current ? .white.opacity(0.25) : .white.opacity(0.04)))
                    }.buttonStyle(.plain).accessibilityLabel("Серия \(video.number ?? "—")" + (current ? ", воспроизводится" : ""))
                }
            }
            if visible.isEmpty { Text("Серия не найдена в этой озвучке").font(.subheadline).foregroundStyle(Cinema.muted).padding(.vertical) }
        }.onAppear { focusCurrent() }.onChange(of: currentID) { _, _ in focusCurrent() }.onChange(of: videos.count) { _, _ in page = 0; focusCurrent() }
    }
    private func focusCurrent() { if let index = episodes.firstIndex(where: { $0.id == currentID }) { page = index / 50 } else { page = 0 } }
}
