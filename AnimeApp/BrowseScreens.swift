import SwiftUI

struct RootView: View {
    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Cinema.background)
        appearance.shadowColor = UIColor.white.withAlphaComponent(0.06)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
    var body: some View {
        TabView {
            CatalogView().toolbarBackground(Cinema.background, for: .tabBar).toolbarBackground(.visible, for: .tabBar).tabItem { Label("Главная", systemImage: "house.fill") }
            SearchView().toolbarBackground(Cinema.background, for: .tabBar).toolbarBackground(.visible, for: .tabBar).tabItem { Label("Поиск", systemImage: "magnifyingglass") }
            LibraryView().toolbarBackground(Cinema.background, for: .tabBar).toolbarBackground(.visible, for: .tabBar).tabItem { Label("Моё", systemImage: "bookmark.fill") }
            SettingsView().toolbarBackground(Cinema.background, for: .tabBar).toolbarBackground(.visible, for: .tabBar).tabItem { Label("Настройки", systemImage: "slider.horizontal.3") }
        }.tint(Cinema.accent).statusBarHidden(false).toolbarBackground(Cinema.background, for: .tabBar).toolbarBackground(.visible, for: .tabBar)
    }
}
struct CoverCard: View {
    let anime: Anime
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Artwork(url: anime.imageURL).aspectRatio(0.69, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 17))
            Text(anime.name.main).font(.system(size: 14, weight: .semibold)).lineLimit(2, reservesSpace: true).foregroundStyle(.white)
            if let year = anime.year { Text(String(year)).font(.caption).foregroundStyle(Cinema.muted) }
        }.contentShape(Rectangle())
    }
}
struct CatalogView: View {
    @State private var items: [Anime] = []
    @State private var error: String?
    @State private var more = true
    @State private var fetching = false
    @AppStorage("yaniRevision") private var revision = ""
    @AppStorage(HistoryStore.storageKey) private var historyData = Data()
    private var history: [HistoryEntry] { (try? JSONDecoder().decode([HistoryEntry].self, from: historyData)) ?? [] }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack {
                        HStack(spacing: 9) { Image(systemName: "play.square.stack.fill").foregroundStyle(Cinema.accent); Text("ANIME").tracking(3).font(.title3.weight(.black)) }
                        Spacer()
                        NavigationLink { YaniAccountView() } label: { Image(systemName: SessionKeychain.read() == nil ? "person.crop.circle" : "person.crop.circle.fill").font(.title2).foregroundStyle(Cinema.accent).frame(width: 44, height: 44).background(Cinema.surface, in: Circle()) }.accessibilityLabel("Аккаунт YummyAnime")
                    }.padding(.horizontal, 20)
                    if !history.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack { Text("Продолжить смотреть").font(.title3.bold()); Spacer(); Image(systemName: "clock.arrow.circlepath").foregroundStyle(Cinema.muted) }.padding(.horizontal, 20)
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 12) {
                                    ForEach(Array(history.prefix(10))) { entry in
                                        NavigationLink { DetailView(id: entry.id, autoplay: true) } label: { ContinueCard(entry: entry) }.buttonStyle(.plain)
                                    }
                                }.padding(.horizontal, 20)
                            }
                        }
                    }
                    if let hero = items.first { HomeHero(anime: hero).padding(.horizontal, 20) }
                    if let error { VStack(alignment: .leading, spacing: 10) { Text(error).font(.footnote).foregroundStyle(Cinema.muted); Button("Попробовать снова") { Task { await load() } }.buttonStyle(.bordered) }.padding(.horizontal, 20) }
                    if items.isEmpty && error == nil { ProgressView().frame(maxWidth: .infinity).padding(60) }
                    if items.count > 1 {
                        HStack { Text("Выбери свою историю").font(.title3.bold()); Spacer() }.padding(.horizontal, 20)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 22) {
                            ForEach(Array(items.dropFirst())) { anime in NavigationLink { DetailView(id: anime.id) } label: { CoverCard(anime: anime) }.buttonStyle(.plain) }
                        }.padding(.horizontal, 20)
                        if more { Button { Task { await loadMore() } } label: { HStack { if fetching { ProgressView() }; Text(fetching ? "Загружаем…" : "Показать ещё") }.frame(maxWidth: .infinity).padding(16).background(Cinema.surface, in: RoundedRectangle(cornerRadius: 16)) }.disabled(fetching).padding(.horizontal, 20) }
                    }
                }.padding(.top, 8 + max(0, windowTopInset - geometry.frame(in: .global).minY)).padding(.bottom, 28)
            }.background(Cinema.background).toolbar(.hidden, for: .navigationBar).refreshable { await load() }.task(id: revision) { await load() }.statusBarHidden(false)
            }
        }
    }
    private var windowTopInset: CGFloat { UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)?.safeAreaInsets.top ?? 44 }
    private func load() async { do { let page = try await YaniAPI.catalog(); guard !Task.isCancelled else { return }; items = page; more = page.count == 30; error = nil } catch { self.error = "Не удалось загрузить каталог. \(error.localizedDescription)" } }
    private func loadMore() async { guard !fetching else { return }; fetching = true; defer { fetching = false }; do { let page = try await YaniAPI.catalog(offset: items.count); let ids = Set(items.map(\.id)); items.append(contentsOf: page.filter { !ids.contains($0.id) }); more = page.count == 30; error = nil } catch { self.error = error.localizedDescription } }
}
struct HomeHero: View {
    let anime: Anime
    var body: some View {
        NavigationLink { DetailView(id: anime.id) } label: {
            ZStack(alignment: .bottomLeading) {
                Artwork(url: anime.imageURL).frame(height: 370).overlay { LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.1), .black.opacity(0.95)], startPoint: .top, endPoint: .bottom) }
                VStack(alignment: .leading, spacing: 10) {
                    Text("В ЦЕНТРЕ ВНИМАНИЯ").font(.system(size: 10, weight: .heavy)).tracking(2).foregroundStyle(.white.opacity(0.7))
                    Text(anime.name.main).font(.system(size: 27, weight: .bold, design: .rounded)).lineLimit(3).multilineTextAlignment(.leading)
                    HStack { if let year = anime.year { Text(String(year)) }; Text("YummyAnime") }.font(.caption).foregroundStyle(.white.opacity(0.65))
                    HStack { Label("К сериям", systemImage: "play.fill").font(.subheadline.bold()); Spacer(); Image(systemName: "arrow.up.right") }.padding(14).background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 13)).padding(.top, 3)
                }.padding(22).foregroundStyle(.white)
            }.frame(height: 370).clipShape(RoundedRectangle(cornerRadius: 26)).overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.07)))
        }.buttonStyle(.plain)
    }
}
struct ContinueCard: View {
    let entry: HistoryEntry
    var body: some View {
        HStack(spacing: 13) {
            ZStack { Artwork(url: entry.imageURL).frame(width: 72, height: 100).clipped(); Image(systemName: "play.fill").font(.title3).foregroundStyle(.white).padding(10).background(.black.opacity(0.45), in: Circle()) }.clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 7) {
                Text(entry.title).font(.subheadline.bold()).lineLimit(2).foregroundStyle(.white)
                Text("Серия \((entry.episodeNumber ?? 0).formatted()) · \(playbackClock(entry.seconds))").font(.caption).foregroundStyle(Cinema.muted)
                if let duration = entry.duration, duration > 0 { ProgressView(value: min(entry.seconds / duration, 1)).tint(Cinema.accent) }
            }.frame(width: 155, alignment: .leading)
        }.padding(12).background(Cinema.surface, in: RoundedRectangle(cornerRadius: 19))
    }
}
struct SearchView: View {
    @State private var query = ""
    @State private var items: [Anime] = []
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Какую историю\nпосмотрим?").font(.system(size: 32, weight: .bold, design: .rounded))
                            Text("Ищи по русскому, английскому или японскому названию.").font(.subheadline).foregroundStyle(Cinema.muted)
                            Text("БЫСТРЫЙ ПОИСК").font(.caption2.bold()).tracking(2).foregroundStyle(Cinema.muted).padding(.top, 20)
                            ForEach(["Наруто", "Ван-Пис", "Магическая битва", "Провожающая в последний путь Фрирен"], id: \.self) { title in
                                Button { query = title } label: { HStack { Text(title).foregroundStyle(.white); Spacer(); Image(systemName: "arrow.up.left").foregroundStyle(Cinema.accent) }.padding(17).background(Cinema.surface, in: RoundedRectangle(cornerRadius: 15)) }
                            }
                        }
                    } else {
                        if loading { ProgressView().frame(maxWidth: .infinity).padding() }
                        if let error { Text(error).font(.subheadline).foregroundStyle(Cinema.muted) }
                        if !loading && items.isEmpty && error == nil { ContentUnavailableView.search(text: query) }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 22) {
                            ForEach(items) { anime in NavigationLink { DetailView(id: anime.id) } label: { CoverCard(anime: anime) }.buttonStyle(.plain) }
                        }
                    }
                }.padding(20)
            }.background(Cinema.background).navigationTitle("Поиск").searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Название аниме")
            .task(id: query) {
                let requested = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !requested.isEmpty else { items = []; loading = false; error = nil; return }
                loading = true; error = nil
                do { try await Task.sleep(for: .milliseconds(350)); let found = try await YaniAPI.catalog(query: requested); guard !Task.isCancelled else { return }; items = found; loading = false }
                catch { guard !Task.isCancelled else { return }; self.error = error.localizedDescription; loading = false }
            }
        }
    }
}
struct DetailView: View {
    let id: Int
    var autoplay = false
    @State private var anime: Anime?
    @State private var videos: [YaniVideo] = []
    @State private var group = ""
    @State private var error: String?
    @State private var loading = true
    @State private var voiceSheet = false
    @State private var expanded = false
    @State private var request: WatchRequest?
    @State private var didAutoplay = false
    @State private var accountSheet = false
    @AppStorage("yaniRevision") private var sessionRevision = ""
    private var selectedEpisodes: [YaniVideo] { orderedEpisodes(videos.filter { $0.groupKey == group }) }
    private var resume: YaniVideo? {
        let last = HistoryStore.load().first { $0.id == id }
        let remembered = last.flatMap { entry in Int(entry.episodeID.replacingOccurrences(of: "yani-", with: "")) }
        guard let chosen = PlaybackMath.resumeID(selectedEpisodes.map(\.id), remembered: remembered, numbers: selectedEpisodes.map(\.number), episode: last?.episodeNumber.map { String($0) }) else { return nil }
        return selectedEpisodes.first { $0.id == chosen }
    }
    var body: some View {
        ScrollView {
            if let anime {
                VStack(alignment: .leading, spacing: 24) {
                    detailHero(anime)
                    VStack(alignment: .leading, spacing: 23) {
                        if let video = resume {
                            let position = resumePosition(video)
                            PrimaryWatchButton(title: position > 0 ? "Продолжить · серия \(video.number ?? "—")" : "Смотреть · серия \(video.number ?? "—")", subtitle: video.voiceName + (position > 0 ? " · с " + playbackClock(position) : "")) { open(video, anime, transferPosition: true) }
                            Button { voiceSheet = true } label: {
                                HStack(spacing: 12) { Image(systemName: "waveform").foregroundStyle(Cinema.accent).frame(width: 30); VStack(alignment: .leading, spacing: 4) { Text(video.voiceName).font(.subheadline.bold()).foregroundStyle(.white); Text("\(video.playerName) · Озвучек: \(VoicePreferences.sortedGroups(videos).count)").font(.caption).foregroundStyle(Cinema.muted) }; Spacer(); Image(systemName: "chevron.up.chevron.down").foregroundStyle(Cinema.muted) }.padding(16).background(Cinema.surface, in: RoundedRectangle(cornerRadius: 17))
                            }.buttonStyle(.plain)
                            EpisodeGrid(videos: selectedEpisodes, currentID: resume?.id, animeID: anime.id) { open($0, anime) }
                        }
                        if loading { HStack { ProgressView(); Text("Ищем доступные серии…").font(.subheadline).foregroundStyle(Cinema.muted) }.padding(.vertical) }
                        if let error { VStack(alignment: .leading, spacing: 8) { Text(error).font(.subheadline).foregroundStyle(Cinema.muted); Button("Повторить загрузку серий") { Task { await loadVideos(anime) } }; if SessionKeychain.read() == nil { Button("Войти в YummyAnime") { accountSheet = true } } }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Cinema.surface, in: RoundedRectangle(cornerRadius: 16)) }
                        if let episode = anime.episodes?.first(where: { !$0.streams.isEmpty }) { NavigationLink { PlayerScreen(anime: anime, episode: episode) } label: { Label("Смотреть AniLibria", systemImage: "play.fill").font(.headline).padding() } }
                        LibraryControls(anime: anime)
                        if let shikimoriID = anime.shikimoriID, shikimoriID > 0 { ShikimoriVideosView(animeID: shikimoriID) }
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Об аниме").font(.title3.bold())
                            Text(cleanDescription(anime.description)).font(.subheadline).foregroundStyle(Cinema.muted).lineSpacing(5).lineLimit(expanded ? nil : 4)
                            if (anime.description?.count ?? 0) > 180 { Button(expanded ? "Свернуть" : "Читать дальше") { expanded.toggle() }.font(.subheadline.bold()) }
                        }
                    }.padding(.horizontal, 20)
                }.padding(.bottom, 32)
            } else if let error { ContentUnavailableView("Не удалось открыть аниме", systemImage: "wifi.exclamationmark", description: Text(error)); Button("Повторить") { Task { await load() } } }
            else { ProgressView().padding(80) }
        }.background(Cinema.background).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: $voiceSheet) {
            NavigationStack { ScrollView { VoicePicker(videos: videos, selected: group) { group = $0; UserDefaults.standard.set(group, forKey: "voice.\(id)"); voiceSheet = false }.padding(20) }.background(Cinema.background).navigationTitle("Озвучки").navigationBarTitleDisplayMode(.inline).toolbar { Button("Готово") { voiceSheet = false } } }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $accountSheet) { NavigationStack { YaniAccountView().toolbar { Button("Готово") { accountSheet = false } } } }
        .onChange(of: sessionRevision) { _, _ in if let anime { Task { await loadVideos(anime) } } }
        .fullScreenCover(item: $request) { request in MultiSourcePlayerScreen(sourceAnime: request.anime, video: request.video, videos: request.videos) }
        .task { if anime == nil { await load() } }
    }
    private func detailHero(_ anime: Anime) -> some View {
        HStack(alignment: .center, spacing: 20) {
            Artwork(url: anime.imageURL).frame(width: 124, height: 178).clipShape(RoundedRectangle(cornerRadius: 20)).shadow(color: .black.opacity(0.35), radius: 20, y: 10)
            VStack(alignment: .leading, spacing: 12) {
                Text(anime.id < 0 ? "YUMMYANIME" : "ANILIBRIA").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(Cinema.accent)
                Text(anime.name.main).font(.system(size: 23, weight: .bold, design: .rounded)).lineLimit(5).minimumScaleFactor(0.8)
                if let year = anime.year { Text(String(year)).font(.subheadline).foregroundStyle(Cinema.muted) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(LinearGradient(colors: [Cinema.accent.opacity(0.12), Cinema.background], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
    private func resumePosition(_ video: YaniVideo) -> Double {
        let saved = UserDefaults.standard.double(forKey: "progress.\(id).yani-\(video.id)")
        if saved > 0 { return saved }
        guard let last = HistoryStore.load().first(where: { $0.id == id }), last.episodeID != "yani-\(video.id)",
              let number = last.episodeNumber, episodeIdentity(String(number)) == episodeIdentity(video.number),
              last.seconds > 0, last.duration == nil || last.seconds < (last.duration ?? 0) - 10 else { return 0 }
        return last.seconds
    }
    private func open(_ video: YaniVideo, _ anime: Anime, transferPosition: Bool = false) {
        if transferPosition { let position = resumePosition(video); if position > 0 { UserDefaults.standard.set(position, forKey: "progress.\(id).yani-\(video.id)") } }
        request = WatchRequest(anime: anime, video: video, videos: videos)
    }
    private func load() async {
        error = nil; loading = true
        do { let result = id < 0 ? try await YaniAPI.detail(-id) : try await Libria().release(id); anime = result; await loadVideos(result) } catch { self.error = error.localizedDescription; loading = false }
    }
    private func loadVideos(_ anime: Anime) async {
        loading = true; error = nil; defer { loading = false }
        do {
            let all = try await YaniProvider().videos(for: anime)
            videos = all.filter { $0.supportsNativePlayback }
            let groups = VoicePreferences.sortedGroups(videos)
            let saved = UserDefaults.standard.string(forKey: "voice.\(id)") ?? ""
            let last = HistoryStore.load().first { $0.id == id }
            let lastGroup = videos.first { "yani-\($0.id)" == last?.episodeID }?.groupKey
            group = groups.contains(saved) ? saved : lastGroup ?? groups.first ?? ""
            if videos.isEmpty { error = "Источник не вернул совместимых видео Aksor/CVH. Доступность зависит от тайтла и аккаунта." }
            if autoplay && !didAutoplay, let video = resume { didAutoplay = true; open(video, anime, transferPosition: true) }
        } catch { self.error = error.localizedDescription }
    }
    private func cleanDescription(_ text: String?) -> String { (text ?? "Описание пока отсутствует").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&") }
}
