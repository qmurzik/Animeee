import SwiftUI
import AVKit
import MediaPlayer
import VLCKitSPM

struct MultiSourcePlayerScreen: View {
    @StateObject private var model: MultiSourcePlayback
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var controls = true
    @State private var locked = false
    @State private var panel: PlayerPanel?
    @State private var section = 0
    @State private var scrub: Double?
    @State private var feedback: String?
    @State private var interaction = 0
    @State private var dragMode: String?
    @State private var dragStart: Double = 0
    @State private var brightnessStart: CGFloat = 0.5
    @State private var volumeStart: Int32 = 100
    @State private var zoom: CGFloat = 1
    @State private var zoomStart: CGFloat = 1
    @State private var originalBrightness: CGFloat?
    @AppStorage("autoNext") private var autoNext = true
    @AppStorage("openPlayerLandscape") private var openLandscape = false
    enum PlayerPanel: String, Identifiable { case episodes, voices, settings; var id: String { rawValue } }
    init(sourceAnime: Anime, video: YaniVideo, videos: [YaniVideo]) { _model = StateObject(wrappedValue: MultiSourcePlayback(anime: sourceAnime, videos: videos, video: video)) }
    private var scene: UIWindowScene? { UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive } }
    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            let insets = scene?.windows.first(where: \.isKeyWindow)?.safeAreaInsets ?? .zero
            VStack(spacing: 0) {
                Color.black.frame(height: landscape ? 0 : insets.top)
                videoCanvas(landscape: landscape, insets: insets)
                    .frame(height: landscape ? geometry.size.height : geometry.size.width * 9 / 16)
                if !landscape {
                    portraitTimeline.allowsHitTesting(!locked)
                    portraitRoom.allowsHitTesting(!locked).padding(.bottom, max(12, insets.bottom))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(Cinema.background)
            #if DEBUG
            .task(id: landscape) { await captureLandscape(landscape) }
            #endif
        }.ignoresSafeArea().background(Cinema.background).foregroundStyle(.white).tint(Cinema.accent)
        .toolbar(.hidden, for: .navigationBar).toolbar(.hidden, for: .tabBar).statusBarHidden(true)
        .sheet(item: $panel) { selection in playerSheet(selection) }
        .task(id: "\(controls)-\(model.playing)-\(panel?.id ?? "none")-\(scrub != nil)-\(interaction)") {
            #if DEBUG
            if ProcessInfo.processInfo.environment["ANIMEAPP_PROBE"] != nil { return }
            #endif
            guard controls, model.playing, panel == nil, scrub == nil, model.error == nil else { return }
            do { try await Task.sleep(for: .seconds(4)); withAnimation(.easeOut(duration: 0.2)) { controls = false } } catch {}
        }
        .task(id: feedback) { guard feedback != nil, dragMode == nil else { return }; do { try await Task.sleep(for: .seconds(1)); feedback = nil } catch {} }
        .onChange(of: model.playing) { _, playing in if !playing { controls = true } }
        .sensoryFeedback(.selection, trigger: model.selected.id)
        .onChange(of: model.selected.id) { _, _ in scrub = nil; controls = true; interaction += 1 }
        .onChange(of: scenePhase) { _, phase in if phase == .background { model.save(); model.player.pause() } }
        .onAppear {
            model.start()
            #if DEBUG
            if ProcessInfo.processInfo.environment["ANIMEAPP_PANEL"] == "voices" { section = 1 }
            #endif
            #if DEBUG
            let probe = ProcessInfo.processInfo.environment["ANIMEAPP_LANDSCAPE"]
            let rotateOnStart = probe == "1" || (probe == nil && openLandscape)
            #else
            let rotateOnStart = openLandscape
            #endif
            if rotateOnStart { Task { try? await Task.sleep(for: .milliseconds(500)); rotate(.landscapeRight) } }
        }
        .onDisappear { model.stop(); if let originalBrightness { scene?.screen.brightness = originalBrightness } }
    }
    #if DEBUG
    private func captureLandscape(_ landscape: Bool) async {
    guard landscape, ProcessInfo.processInfo.environment["ANIMEAPP_LANDSCAPE"] == "1" else { return }
    for _ in 0..<20 {
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
        if model.player.hasVideoOut && model.playing && model.seconds >= 15 { break }
    }
    guard let scene, scene.interfaceOrientation.isLandscape, let window = scene.windows.first(where: \.isKeyWindow), window.bounds.width > window.bounds.height else { NSLog("ANIMEAPP_LANDSCAPE failed scene orientation"); return }
    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("player-landscape.png")
    do { try image.pngData()?.write(to: url); NSLog("ANIMEAPP_LANDSCAPE verified %.0fx%.0f", window.bounds.width, window.bounds.height) } catch { NSLog("ANIMEAPP_LANDSCAPE failed capture") }
    }
    #endif
    private func videoCanvas(landscape: Bool, insets: UIEdgeInsets) -> some View {
        GeometryReader { video in
            ZStack {
                Color.black
                VLCSurface(player: model.player).scaleEffect(zoom)
                HStack(spacing: 0) {
                    tapZone(-10)
                    tapZone(10)
                }.gesture(DragGesture(minimumDistance: 18).onChanged { value in drag(value, size: video.size) }.onEnded { _ in endDrag() })
                if controls && !locked {
                    LinearGradient(colors: [.black.opacity(0.75), .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
                    VStack(spacing: 0) {
                        videoHeader(landscape: landscape)
                        Spacer(minLength: 0)
                        if landscape { timeline; landscapeActions }
                        else { HStack { Spacer(); iconButton("arrow.up.left.and.arrow.down.right", label: "На весь экран") { rotate(.landscapeRight) } } }
                    }.padding(.horizontal, landscape ? max(24, max(insets.left, insets.right) + 12) : 12)
                     .padding(.top, landscape ? 12 : 4).padding(.bottom, landscape ? max(12, insets.bottom) : 4)
                    if model.error == nil && !model.loading { transport(landscape: landscape) }
                }
                if model.loading && model.error == nil { ProgressView().controlSize(.large).tint(.white).padding(18).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16)).allowsHitTesting(false) }
                if model.error != nil {
                    VStack(spacing: 9) {
                        Text("Видео недоступно").font(.headline)
                        HStack { Button("Повторить") { model.select(model.selected, preservePosition: true) }; Button("Сменить озвучку") { panel = .voices } }.font(.subheadline.bold()).buttonStyle(.bordered)
                    }.padding(16).background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
                }
                if locked { VStack { Spacer(); Button { locked = false; touch() } label: { Label("Разблокировать", systemImage: "lock.fill").font(.subheadline.bold()).padding(13).background(.black.opacity(0.75), in: Capsule()) }.padding(.bottom, 20) } }
                if let feedback { Text(feedback).font(.headline.monospacedDigit()).padding(15).background(.black.opacity(0.75), in: Capsule()).allowsHitTesting(false) }
            }.clipped().simultaneousGesture(MagnificationGesture().onChanged { value in
                guard !locked else { return }; zoom = max(1, min(2, zoomStart * value)); feedback = "Масштаб " + Double(zoom).formatted(.number.precision(.fractionLength(1))) + "×"
            }.onEnded { _ in zoomStart = zoom; feedback = nil; touch() })
        }
    }
    private func tapZone(_ delta: Double) -> some View {
        Color.clear.contentShape(Rectangle()).onTapGesture(count: 2) { jump(delta) }.onTapGesture { guard !locked else { return }; withAnimation(.easeOut(duration: 0.15)) { controls.toggle() }; interaction += 1 }
    }
    private func videoHeader(landscape: Bool) -> some View {
        HStack(spacing: 12) {
            iconButton("chevron.left", label: "Закрыть просмотр") { rotate(.portrait); dismiss() }
            if landscape {
                VStack(alignment: .leading, spacing: 4) { Text(model.anime.name.main).font(.subheadline.bold()).lineLimit(1); Text("Серия \(model.selected.number ?? "—") · \(model.selected.voiceName)").font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(1) }
            } else { Text("Серия \(model.selected.number ?? "—")").font(.subheadline.bold()) }
            Spacer(minLength: 0)
            if zoom > 1 { Button("1:1") { zoom = 1; zoomStart = 1; touch() }.font(.caption.bold()).frame(width: 44, height: 44).accessibilityLabel("Сбросить увеличение видео") }
            if landscape { iconButton("lock.open", label: "Заблокировать касания") { locked = true; controls = false } }
            iconButton("ellipsis", label: "Настройки просмотра") { panel = .settings }
        }
    }
    private func transport(landscape: Bool) -> some View {
        HStack(spacing: landscape ? 50 : 35) {
            Button { jump(-10) } label: { Image(systemName: "gobackward.10").font(.system(size: landscape ? 31 : 26, weight: .medium)).frame(width: 52, height: 54) }.disabled(!model.seekable).accessibilityLabel("Назад на 10 секунд")
            Button { model.toggle(); touch() } label: { Image(systemName: model.playing ? "pause.fill" : "play.fill").font(.system(size: landscape ? 36 : 28, weight: .semibold)).frame(width: landscape ? 78 : 64, height: landscape ? 78 : 64).background(.black.opacity(0.4), in: Circle()) }.accessibilityLabel(model.playing ? "Пауза" : "Продолжить")
            Button { jump(10) } label: { Image(systemName: "goforward.10").font(.system(size: landscape ? 31 : 26, weight: .medium)).frame(width: 52, height: 54) }.disabled(!model.seekable).accessibilityLabel("Вперёд на 10 секунд")
        }.buttonStyle(.plain)
    }
    private var portraitTimeline: some View { timeline.padding(.horizontal, 20).padding(.top, 3).padding(.bottom, 12).background(Color.black) }
    private var timeline: some View {
        VStack(spacing: 0) {
            Slider(value: Binding(get: { min(scrub ?? model.seconds, max(1, model.duration)) }, set: { scrub = $0 }), in: 0...max(1, model.duration), onEditingChanged: { editing in
                if editing { interaction += 1; controls = true } else { if let scrub { model.seek(scrub) }; scrub = nil; touch() }
            }).tint(Cinema.accent).disabled(!model.seekable || model.loading).accessibilityLabel("Позиция воспроизведения")
            HStack {
                Text(playbackClock(scrub ?? model.seconds)); Spacer()
                if scrub != nil { Text("Перемотка").foregroundStyle(Cinema.accent); Spacer() }
                Text(model.duration > 0 ? "−" + playbackClock(max(0, model.duration - (scrub ?? model.seconds))) : "—")
            }.font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.6))
        }
    }
    private var portraitRoom: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.anime.name.main).font(.title3.bold()).lineLimit(3)
                    HStack(spacing: 8) { Text("Серия \(model.selected.number ?? "—")").foregroundStyle(Cinema.accent); Text("·"); Text(model.selected.voiceName).lineLimit(1) }.font(.subheadline).foregroundStyle(Cinema.muted)
                }
                HStack(spacing: 10) {
                    Button { model.previous(); touch() } label: { Image(systemName: "backward.end.fill").frame(width: 44, height: 48).background(Cinema.surface, in: RoundedRectangle(cornerRadius: 13)) }.disabled(!model.hasPrevious).opacity(model.hasPrevious ? 1 : 0.35).accessibilityLabel("Предыдущая серия")
                    Button { model.next(); touch() } label: { HStack { Text("Следующая серия").font(.subheadline.bold()); Spacer(); Image(systemName: "forward.end.fill") }.padding(.horizontal, 14).frame(height: 48).background(Cinema.surface, in: RoundedRectangle(cornerRadius: 13)) }.disabled(!model.hasNext).opacity(model.hasNext ? 1 : 0.35)
                    Button { panel = .settings } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 48).background(Cinema.surface, in: RoundedRectangle(cornerRadius: 13)) }.accessibilityLabel("Качество и настройки")
                }.buttonStyle(.plain)
                if let error = model.error { Text(error).font(.caption).foregroundStyle(Cinema.muted) }
                if let notice = model.notice { Text(notice).font(.caption).foregroundStyle(Cinema.muted) }
                HStack(spacing: 0) {
                    roomTab("Серии", value: 0)
                    roomTab("Озвучки", value: 1)
                }.padding(4).background(Cinema.surface, in: RoundedRectangle(cornerRadius: 14))
                if section == 0 { EpisodeGrid(videos: model.episodes, currentID: model.selected.id, animeID: model.anime.id) { model.select($0); touch() }.equatable() }
                else { VoicePicker(videos: model.videos, selected: model.selected.groupKey, episode: model.selected.number) { model.chooseVoice($0); touch() }.equatable() }
            }.padding(20)
        }.scrollIndicators(.hidden)
    }
    private func roomTab(_ title: String, value: Int) -> some View {
        Button { section = value } label: { Text(title).font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 12).background(section == value ? Cinema.accent.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 11)).foregroundStyle(section == value ? Cinema.accent : Cinema.muted) }.buttonStyle(.plain)
    }
    private var landscapeActions: some View {
        HStack(spacing: 18) {
            Button { panel = .episodes } label: { Label("Серии", systemImage: "rectangle.grid.2x2") }
            Button { panel = .voices } label: { Label(model.selected.voiceName, systemImage: "waveform").lineLimit(1) }
            Spacer(minLength: 0)
            Button(model.quality + " · " + model.rate.formatted() + "×") { panel = .settings }
            iconButton("backward.end.fill", label: "Предыдущая серия") { model.previous(); touch() }.disabled(!model.hasPrevious)
            iconButton("forward.end.fill", label: "Следующая серия") { model.next(); touch() }.disabled(!model.hasNext)
            iconButton("arrow.down.right.and.arrow.up.left", label: "Вернуться к списку серий") { rotate(.portrait) }
        }.font(.system(size: 13, weight: .semibold)).buttonStyle(.plain).padding(.top, 4)
    }
    private func iconButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel(label)
    }
    private func playerSheet(_ selection: PlayerPanel) -> some View {
        NavigationStack {
            Group {
                if selection == .settings { settings }
                else {
                    ScrollView {
                        if selection == .episodes { EpisodeGrid(videos: model.episodes, currentID: model.selected.id, animeID: model.anime.id) { model.select($0); panel = nil; touch() }.padding(20) }
                        else { VoicePicker(videos: model.videos, selected: model.selected.groupKey, episode: model.selected.number) { model.chooseVoice($0); panel = nil; touch() }.padding(20) }
                    }.background(Cinema.background)
                }
            }.navigationTitle(selection == .episodes ? "Выбрать серию" : selection == .voices ? "Озвучки" : "Настройки просмотра").navigationBarTitleDisplayMode(.inline).toolbar { Button("Готово") { panel = nil; touch() } }
        }.preferredColorScheme(.dark).tint(Cinema.accent).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
    private var settings: some View {
        Form {
            Section("Качество видео") {
                if model.choices.isEmpty { Text("Получаем варианты от источника…").foregroundStyle(.secondary) }
                ForEach(model.choices) { choice in Button { model.changeQuality(choice); panel = nil; touch() } label: { HStack { Text(choice.label); Spacer(); if choice.label == model.quality { Image(systemName: "checkmark") } } } }
            }
            Section("Скорость") {
                Picker("Скорость просмотра", selection: Binding(get: { model.rate }, set: { model.setRate($0) })) { ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 1.75, 2], id: \.self) { value in Text("\(value.formatted())×").tag(value) } }
            }
            Section("Просмотр") { Toggle("Следующая серия автоматически", isOn: $autoNext); Toggle("Открывать на весь экран", isOn: $openLandscape) }
            Section("Громкость плеера") {
                Slider(value: Binding(get: { Double(model.player.audio?.volume ?? 100) }, set: { model.player.audio?.volume = Int32($0); model.objectWillChange.send() }), in: 0...100).accessibilityLabel("Громкость плеера")
            }
            Section("Громкость устройства") { SystemVolumeControl().frame(height: 36).listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 0, trailing: 20)) }
            Section("Аудиодорожки") {
                ForEach(model.audioTracks, id: \.id) { track in Button { model.player.currentAudioTrackIndex = track.id; model.objectWillChange.send() } label: { HStack { Text(track.name); Spacer(); if model.player.currentAudioTrackIndex == track.id { Image(systemName: "checkmark") } } } }
            }
            Section("Субтитры") {
                if model.subtitleTracks.isEmpty { Text("В этом потоке нет отдельных субтитров").foregroundStyle(.secondary) }
                ForEach(model.subtitleTracks, id: \.id) { track in Button { model.player.currentVideoSubTitleIndex = track.id; model.objectWillChange.send() } label: { HStack { Text(track.name); Spacer(); if model.player.currentVideoSubTitleIndex == track.id { Image(systemName: "checkmark") } } } }
            }
            Section("Жесты на видео") {
                Text("Двойное касание слева или справа — ±10 секунд. Горизонтальный свайп — перемотка с предпросмотром времени. Вертикальный свайп слева — яркость, справа — громкость плеера. Разведите два пальца для увеличения видео; кнопка 1:1 возвращает исходный размер.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
    private func touch() { controls = true; interaction += 1 }
    private func jump(_ delta: Double) { guard !locked, model.seekable else { return }; model.seek(model.seconds + delta); feedback = delta > 0 ? "+10 сек" : "−10 сек"; interaction += 1 }
    private func drag(_ value: DragGesture.Value, size: CGSize) {
        guard !locked, model.error == nil else { return }
        if dragMode == nil {
            dragStart = model.seconds
            brightnessStart = scene?.screen.brightness ?? 0.5
            volumeStart = model.player.audio?.volume ?? 100
            if abs(value.translation.width) > abs(value.translation.height) { guard model.seekable else { return }; dragMode = "seek" }
            else { dragMode = value.startLocation.x < size.width / 2 ? "brightness" : "volume" }
        }
        switch dragMode {
        case "seek":
            scrub = PlaybackMath.seekTarget(dragStart + Double(value.translation.width / max(1, size.width)) * 120, duration: model.duration)
            feedback = playbackClock(scrub ?? 0)
        case "brightness":
            if originalBrightness == nil { originalBrightness = brightnessStart }
            let next = max(0.05, min(1, brightnessStart - value.translation.height / max(1, size.height)))
            scene?.screen.brightness = next; feedback = "Яркость \(Int(next * 100))%"
        case "volume":
            let next = max(0, min(100, volumeStart - Int32(value.translation.height / max(1, size.height) * 100)))
            model.player.audio?.volume = next; feedback = "Звук плеера \(next)%"
        default: break
        }
        controls = false; interaction += 1
    }
    private func endDrag() { if dragMode == "seek", let scrub { model.seek(scrub) }; scrub = nil; dragMode = nil; feedback = nil; touch() }
    private func rotate(_ orientation: UIInterfaceOrientationMask) {
        guard let scene else { return }
        scene.windows.first(where: \.isKeyWindow)?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { error in model.notice = "Не удалось повернуть экран: \(error.localizedDescription)" }
    }
}
struct SystemVolumeControl: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView { let view = MPVolumeView(); view.showsRouteButton = false; view.showsVolumeSlider = true; return view }
    func updateUIView(_ view: MPVolumeView, context: Context) {}
}
