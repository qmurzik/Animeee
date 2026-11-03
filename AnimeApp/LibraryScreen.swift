import SwiftUI

struct LibraryView: View {
    @AppStorage(HistoryStore.storageKey) private var historyData = Data()
    @AppStorage(LocalLibrary.key) private var libraryData = Data()
    @State private var selection = "История"
    private var history: [HistoryEntry] { (try? JSONDecoder().decode([HistoryEntry].self, from: historyData)) ?? [] }
    private var library: [LibraryEntry] { LocalLibrary.decode(libraryData) }
    private var visible: [LibraryEntry] { selection == "Избранное" ? library.filter(\.favorite) : library.filter { $0.status?.rawValue == selection } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(["История", "Избранное"] + WatchStatus.allCases.map(\.rawValue), id: \.self) { title in
                                Button { selection = title } label: { Text(title).font(.subheadline.bold()).padding(.horizontal, 17).padding(.vertical, 12).background(selection == title ? Cinema.accent : Cinema.surface, in: Capsule()).foregroundStyle(selection == title ? .white : Cinema.muted) }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 20)
                    }
                    if selection == "История" {
                        if history.isEmpty { empty }
                        LazyVStack(spacing: 12) {
                            ForEach(history) { entry in
                                NavigationLink { DetailView(id: entry.id, autoplay: true) } label: {
                                    HStack(spacing: 14) {
                                        Artwork(url: entry.imageURL).frame(width: 62, height: 88).clipShape(RoundedRectangle(cornerRadius: 11))
                                        VStack(alignment: .leading, spacing: 8) { Text(entry.title).font(.subheadline.bold()).lineLimit(2).foregroundStyle(.white); Text("Серия \((entry.episodeNumber ?? 0).formatted()) · \(playbackClock(entry.seconds))").font(.caption).foregroundStyle(Cinema.muted); if let duration = entry.duration, duration > 0 { ProgressView(value: min(entry.seconds / duration, 1)).tint(Cinema.accent) } }
                                        Spacer(minLength: 0); Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(Cinema.accent)
                                    }.padding(12).background(Cinema.surface, in: RoundedRectangle(cornerRadius: 18))
                                }.buttonStyle(.plain).contextMenu { Button("Удалить из истории", role: .destructive) { historyData = (try? JSONEncoder().encode(history.filter { $0.id != entry.id })) ?? Data() } }
                            }
                        }.padding(.horizontal, 20)
                    } else {
                        if visible.isEmpty { empty }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 22) {
                            ForEach(visible) { entry in
                                NavigationLink { DetailView(id: entry.id) } label: {
                                    VStack(alignment: .leading, spacing: 10) { Artwork(url: entry.imageURL).aspectRatio(0.69, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 17)); Text(entry.title).font(.subheadline.bold()).lineLimit(2).foregroundStyle(.white) }
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 20)
                    }
                }.padding(.top, 12).padding(.bottom, 30)
            }.background(Cinema.background).navigationTitle("Моё")
        }
    }
    private var empty: some View {
        VStack(spacing: 16) { Image(systemName: selection == "История" ? "clock" : "bookmark").font(.system(size: 38, weight: .light)).foregroundStyle(Cinema.accent); Text("Здесь будут твои истории").font(.title3.bold()); Text(selection == "История" ? "Начни смотреть — позиция сохранится автоматически." : "Добавляй аниме в список на странице тайтла.").font(.subheadline).foregroundStyle(Cinema.muted).multilineTextAlignment(.center) }.padding(32).frame(maxWidth: .infinity).padding(.top, 60)
    }
}
