import SwiftUI
import WebKit

struct SourceConfiguration {
    static func api(_ source: CatalogSource) -> String? { UserDefaults.standard.string(forKey: "source.api." + source.rawValue)?.nonEmpty }
    static func sites(_ source: CatalogSource) -> [URL] { MirrorAddress.candidates(primary: UserDefaults.standard.string(forKey: "source.site." + source.rawValue), defaults: source.sites) }
    static func catalog(_ source: CatalogSource) -> ExtraCatalog { ExtraCatalog(source: source, primary: api(source)) }
    static func page(_ title: SourceTitle, episode: SourceEpisode? = nil) -> URL? {
        guard let site = sites(title.source).first, var c = URLComponents(url: site, resolvingAgainstBaseURL: false) else { return nil }
        c.path = title.pagePath
        if let episode, title.source == .anilib { c.path += "/watch"; c.queryItems = [.init(name: "episode", value: episode.id)] }
        return c.url
    }
}
struct SourceSearchView: View {
    @State var query = ""
    @State var source: CatalogSource = .anilib
    @State private var items: [SourceTitle] = []
    @State private var loading = false
    @State private var error: String?
    @State private var revision = 0
    @AppStorage("source.revision") private var configurationRevision = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Источник", selection: $source) { ForEach(CatalogSource.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                Text(source.note).font(.footnote).foregroundStyle(Cinema.muted)
                if loading { ProgressView("Загружаем каталог…").frame(maxWidth: .infinity).padding() }
                if let error { VStack(alignment: .leading, spacing: 12) { Label(error, systemImage: "exclamationmark.icloud"); Button("Повторить") { revision += 1 }; NavigationLink("Адреса и зеркала") { SourceSettingsView(source: source) } }.font(.subheadline).padding(16).background(Cinema.surface, in: RoundedRectangle(cornerRadius: 16)) }
                if !loading && error == nil && !query.isEmpty && items.isEmpty { ContentUnavailableView.search(text: query) }
                if query.isEmpty { Text("Введите название в поиске. Каталоги независимы: совпадение названия не считается совпадением тайтла.").foregroundStyle(Cinema.muted) }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                    ForEach(items) { title in NavigationLink { SourceDetailView(title: title) } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            Artwork(url: title.poster).aspectRatio(0.69, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 17))
                            Text(title.title).font(.subheadline.bold()).lineLimit(2, reservesSpace: true).foregroundStyle(.white)
                            Text(title.source.title).font(.caption).foregroundStyle(Cinema.muted)
                        }
                    }.buttonStyle(.plain) }
                }
            }.padding(20)
        }.background(Cinema.background).navigationTitle("Другие источники")
        .searchable(text: $query, prompt: "Название аниме")
        .toolbar { NavigationLink { SourcesSettingsView() } label: { Image(systemName: "network") }.accessibilityLabel("Зеркала источников") }
        .task(id: source.rawValue + "|" + query + "|" + String(revision) + configurationRevision) { await search() }
    }
    private func search() async {
        items = []; error = nil; loading = false
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        loading = true
        do {
            try await Task.sleep(for: .milliseconds(400))
            let result = try await SourceConfiguration.catalog(source).search(text)
            try Task.checkCancellation(); items = result; loading = false
        } catch { guard !Task.isCancelled else { return }; self.error = error.localizedDescription; loading = false }
    }
}
struct SourceDetailView: View {
    let title: SourceTitle
    @State private var episodes: [SourceEpisode] = []
    @State private var selection: SourceEpisode?
    @State private var players: [SourcePlayer] = []
    @State private var loading = false
    @State private var error: String?
    @State private var match: Anime?
    @State private var browser: SourceBrowserRequest?
    @State private var revision = 0
    @AppStorage("source.revision") private var configurationRevision = ""
    @State private var rememberedEpisode = ""
    private var savedKey: String { "source.last." + title.id }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 18) {
                    Artwork(url: title.poster).frame(width: 108, height: 155).clipShape(RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 10) { Text(title.source.title.uppercased()).font(.caption.bold()).foregroundStyle(Cinema.accent); Text(title.title).font(.title2.bold()).lineLimit(5); if !episodes.isEmpty { Text("\(episodes.count) серий в каталоге").font(.footnote).foregroundStyle(Cinema.muted) } }
                }
                if title.source == .shikimori {
                    if let match { NavigationLink { DetailView(id: match.id) } label: { Label("Смотреть · YummyAnime", systemImage: "play.fill").frame(maxWidth: .infinity).padding().background(Cinema.accent, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(.white) }; Text("Совпадение подтверждено по Shikimori ID. Доступные серии и озвучки зависят от YummyAnime и авторизации.").font(.footnote).foregroundStyle(Cinema.muted) }
                    else if !loading && error == nil { Text("Точное соответствие в YummyAnime не найдено. Публичный API Shikimori не вернул полные серии.").foregroundStyle(Cinema.muted) }
                    if let id = title.shikimoriID { ShikimoriVideosView(animeID: id) }
                } else {
                    if let selection {
                        HStack { Text("Серия \(selection.number)").font(.title3.bold()); Spacer(); if let season = selection.season { Text("Сезон \(season)").font(.caption).foregroundStyle(Cinema.muted) } }
                        if let name = selection.title { Text(name).font(.subheadline).foregroundStyle(Cinema.muted) }
                        if !players.isEmpty {
                            Text("ОЗВУЧКИ И ПЕРЕВОДЫ").font(.caption.bold()).tracking(1.5).foregroundStyle(Cinema.muted)
                            Text("Источник передал страницы плееров, а не прямые потоки. В этом режиме качество, дорожки и полноэкранный просмотр управляются внутри плеера источника. Прогресс, автопереход и пропуск приложения недоступны.").font(.footnote).foregroundStyle(Cinema.muted)
                            ForEach(sortedPlayers) { player in Button { open(player) } label: {
                                HStack(spacing: 12) { Image(systemName: "play.rectangle.fill").font(.title2).foregroundStyle(Cinema.accent); VStack(alignment: .leading, spacing: 5) { Text(player.label).font(.subheadline.bold()).foregroundStyle(.white); Text(player.balancer + " · плеер источника").font(.caption).foregroundStyle(Cinema.muted) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(Cinema.muted) }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Cinema.surface, in: RoundedRectangle(cornerRadius: 15))
                            }.buttonStyle(.plain) }
                        } else if !loading && error == nil { Text("Для выбранной серии источник не вернул доступных плееров. Попробуйте открыть её на сайте и войти в аккаунт.").font(.subheadline).foregroundStyle(Cinema.muted) }
                    }
                    if !episodes.isEmpty {
                        Text("Серии").font(.title3.bold())
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 10)], spacing: 10) {
                            ForEach(episodes) { episode in Button { selection = episode } label: { Text(episode.number).font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 48).background(selection?.id == episode.id ? Cinema.accent : Cinema.surface, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white) }.accessibilityLabel("Серия \(episode.number), сезон \(episode.season ?? "1")") }
                        }
                    }
                }
                if loading { ProgressView("Загружаем…").frame(maxWidth: .infinity).padding() }
                if let error { Text(error).font(.subheadline).foregroundStyle(Cinema.muted); Button("Повторить") { revision += 1 } }
                if let page = SourceConfiguration.page(title, episode: selection) { Button("Открыть на сайте · авторизация") { browser = .init(url: page, referer: nil, title: title.source.title) }.buttonStyle(.bordered) }
                NavigationLink("Адреса и зеркала") { SourceSettingsView(source: title.source) }
            }.padding(20)
        }.background(Cinema.background).navigationBarTitleDisplayMode(.inline)
        .task(id: String(revision) + configurationRevision) { await load() }
        .task(id: selection?.id) { if let selection { await loadPlayers(selection) } }
        .fullScreenCover(item: $browser) { SourceBrowserScreen(request: $0) }
    }
    private var sortedPlayers: [SourcePlayer] {
        let saved = UserDefaults.standard.string(forKey: "source.voice." + title.id)
        return players.sorted { a, b in if (a.studio == saved) != (b.studio == saved) { return a.studio == saved }; return a.label.localizedStandardCompare(b.label) == .orderedAscending }
    }
    private func open(_ player: SourcePlayer) {
        if let selection { UserDefaults.standard.set(selection.id, forKey: savedKey); rememberedEpisode = selection.id }
        UserDefaults.standard.set(player.studio, forKey: "source.voice." + title.id)
        browser = .init(url: player.embed, referer: SourceConfiguration.page(title, episode: selection), title: player.label)
    }
    private func load() async {
        loading = true; error = nil
        do {
            if title.source == .shikimori {
                let response: YaniCatalogResponse = try await YaniAPI.request("/anime", query: [.init(name: "q", value: title.title), .init(name: "limit", value: "50")])
                let found = response.response.filter { $0.remote_ids?.shikimori_id == title.shikimoriID }
                try Task.checkCancellation(); match = found.count == 1 ? found.first?.anime : nil; loading = false
            } else {
                let result = try await SourceConfiguration.catalog(title.source).episodes(title)
                try Task.checkCancellation(); episodes = result
                let saved = UserDefaults.standard.string(forKey: savedKey)
                let chosen = result.first(where: { $0.id == selection?.id }) ?? result.first(where: { $0.id == saved }) ?? result.first
                if selection == chosen { if let chosen { await loadPlayers(chosen) } else { loading = false } }
                else { selection = chosen; if chosen == nil { loading = false } }
            }
        } catch { guard !Task.isCancelled else { return }; self.error = error.localizedDescription; loading = false }
    }
    private func loadPlayers(_ episode: SourceEpisode) async {
        players = []; error = nil; loading = true
        do { let result = try await SourceConfiguration.catalog(title.source).players(episode, title: title); try Task.checkCancellation(); guard selection?.id == episode.id else { return }; players = result; loading = false }
        catch { guard !Task.isCancelled, selection?.id == episode.id else { return }; self.error = error.localizedDescription; loading = false }
    }
}
struct SourcesSettingsView: View {
    var body: some View { List { ForEach(CatalogSource.allCases) { source in NavigationLink { SourceSettingsView(source: source) } label: { VStack(alignment: .leading, spacing: 7) { Text(source.title).font(.headline); Text(source.note).font(.caption).foregroundStyle(.secondary) } } } }.navigationTitle("Источники и зеркала") }
}
struct SourceSettingsView: View {
    let source: CatalogSource
    @State private var site = ""
    @State private var api = ""
    @State private var message: String?
    @State private var checking = false
    var body: some View {
        Form {
            Section(source.title) { Text(source.note).font(.footnote); ForEach(source.sites, id: \.self) { Text($0).font(.caption).textSelection(.enabled) } }
            Section("Свой адрес сайта") { TextField(source.sites[0], text: $site).accessibilityIdentifier("mirror.site").textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL); Text("Только HTTPS-адрес без пути. Используйте зеркало, опубликованное самим сервисом. Пустое поле возвращает стандартный адрес.").font(.footnote).foregroundStyle(.secondary) }
            Section("Адрес API") { TextField(source.api, text: $api).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL); Text("API и сайт настраиваются отдельно. CDN и адреса видео не переписываются. Ключи и токены YummyAnime сюда не отправляются.").font(.footnote).foregroundStyle(.secondary) }
            Section {
                Button("Сохранить") { save() }.accessibilityIdentifier("mirror.save")
                Button("Проверить каталог") { Task { await check() } }.disabled(checking)
                if checking { ProgressView() }
                if let message { Text(message).font(.footnote).textSelection(.enabled) }
            }
            Section("Переключение") { Text("При сетевой ошибке или HTTP 5xx запрос переходит к следующему настроенному адресу API. Ошибки доступа 401/403 и лимит 429 останавливают переключение. Страницы плееров не заменяются зеркалами автоматически; выбранный сайт используется при открытии.").font(.footnote) }
        }.navigationTitle(source.title).onAppear { site = UserDefaults.standard.string(forKey: "source.site." + source.rawValue) ?? ""; api = SourceConfiguration.api(source) ?? "" }
    }
    @discardableResult private func save() -> Bool {
        guard (site.isEmpty || MirrorAddress.parse(site) != nil), (api.isEmpty || MirrorAddress.parse(api) != nil) else { message = "Нужен HTTPS-домен без пути, параметров, логина и пароля."; return false }
        UserDefaults.standard.set(site, forKey: "source.site." + source.rawValue); UserDefaults.standard.set(api, forKey: "source.api." + source.rawValue); UserDefaults.standard.set(UUID().uuidString, forKey: "source.revision"); message = "Адреса сохранены."; return true
    }
    private func check() async {
        guard save() else { return }; checking = true; defer { checking = false }
        do { let results = try await SourceConfiguration.catalog(source).search("Naruto"); message = "Каталог ответил: \(results.count) тайтлов. Это не проверка воспроизведения." }
        catch { message = error.localizedDescription }
    }
}
struct SourceBrowserRequest: Identifiable { let id = UUID(); let url: URL; let referer: URL?; let title: String }
struct SourceBrowserScreen: View {
    let request: SourceBrowserRequest
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var revision = 0
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Плеер источника · его собственные настройки и ограничения").font(.caption2).foregroundStyle(Cinema.muted).padding(8)
                if let error { Text(error).font(.caption).padding(); Button("Повторить") { self.error = nil; revision += 1 } }
                SourceWebView(request: request, failure: $error).id(revision)
            }.background(Cinema.background).navigationTitle(request.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } }; ToolbarItem(placement: .topBarTrailing) { Link(destination: request.url) { Image(systemName: "safari") }.accessibilityLabel("Открыть в браузере") } }
        }
    }
}
struct SourceWebView: UIViewRepresentable {
    let request: SourceBrowserRequest
    @Binding var failure: String?
    func makeCoordinator() -> Coordinator { Coordinator(failure: $failure) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration(); config.allowsInlineMediaPlayback = true; config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        // Official website login stays in WebKit's own store. No token/cookie extraction.
        config.websiteDataStore = .default
        let view = WKWebView(frame: .zero, configuration: config); view.navigationDelegate = context.coordinator
        var req = URLRequest(url: request.url); if let referer = request.referer { req.setValue(referer.absoluteString, forHTTPHeaderField: "Referer") }
        view.load(req); return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) { uiView.stopLoading(); uiView.loadHTMLString("", baseURL: nil); uiView.navigationDelegate = nil }
    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var failure: String?
        init(failure: Binding<String?>) { _failure = failure }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if (error as NSError).code != NSURLErrorCancelled { failure = error.localizedDescription } }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if (error as NSError).code != NSURLErrorCancelled { failure = error.localizedDescription } }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            decisionHandler(["https", "about", "blob"].contains(url.scheme ?? "") && navigationAction.targetFrame != nil ? .allow : .cancel)
        }
    }
}
