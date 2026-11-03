import XCTest
@testable import WatchCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
final class SourceMockProtocol: URLProtocol {
    static var respond: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do { let (status, body) = try Self.respond!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class SourceTests: XCTestCase {
    private func session() -> URLSession { let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [SourceMockProtocol.self]; return URLSession(configuration: c) }
    override func tearDown() { SourceMockProtocol.respond = nil; super.tearDown() }
    func testMirrorValidationAndDeduplication() {
        for value in ["http://animego.me", "https://user:pass@animego.me", "https://animego.me/search", "https://animego.me?token=x", "https://127.0.0.1", "https://localhost", "https://animego.me#x"] { XCTAssertNil(MirrorAddress.parse(value), value) }
        XCTAssertEqual(MirrorAddress.candidates(primary: " https://animego.me/ ", defaults: ["https://animego.me", "https://animego.org"]).count, 2)
    }
    func testMirrorFailsOverOnServerErrorWithoutLeakingTokens() async throws {
        var hosts: [String] = []
        SourceMockProtocol.respond = { request in
            hosts.append(request.url!.host!); XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            return request.url!.host == "one.example" ? (503, "") : (200, "[]")
        }
        let result = try await MirrorTransport(session: session()).get(origins: [URL(string: "https://one.example")!, URL(string: "https://two.example")!], path: "/api/animes")
        XCTAssertEqual(hosts, ["one.example", "two.example"]); XCTAssertEqual(result.origin.host, "two.example")
    }
    func testMirrorStopsAtAccessRestriction() async throws {
        var count = 0
        SourceMockProtocol.respond = { _ in count += 1; return (403, "restricted") }
        do { _ = try await MirrorTransport(session: session()).get(origins: [URL(string: "https://one.example")!, URL(string: "https://two.example")!], path: "/api/animes"); XCTFail("403 must not be retried on another host") } catch { XCTAssertTrue(error.localizedDescription.contains("403")) }
        XCTAssertEqual(count, 1)
    }
    func testAnilibUsesCurrentSiteIDAndExplicitShikimoriReference() async throws {
        SourceMockProtocol.respond = { r in
            XCTAssertEqual(r.value(forHTTPHeaderField: "Site-Id"), "5")
            let c = URLComponents(url: r.url!, resolvingAgainstBaseURL: false)!
            XCTAssertEqual(c.queryItems?.first(where: { $0.name == "site_id[]" })?.value, "5")
            return (200, #"{"data":[{"id":11,"name":"Naruto","rus_name":"Наруто","slug_url":"11--naruto-anime","cover":{"default":"https://cover.hentaicdn.org/naruto.jpg"},"shikimori_href":"https://shikimori.io/animes/z20-naruto"}]}"#)
        }
        let result = try await ExtraCatalog(source: .anilib, session: session()).search("Наруто")
        XCTAssertEqual(result.first?.shikimoriID, 20); XCTAssertEqual(result.first?.key, "11--naruto-anime"); XCTAssertEqual(result.first?.title, "Наруто")
    }
    func testAnilibEpisodesAndVoiceIdentity() async throws {
        let title = SourceTitle(source: .anilib, key: "11--naruto-anime", title: "Наруто", poster: nil, pagePath: "/ru/anime/11--naruto-anime", shikimoriID: 20)
        SourceMockProtocol.respond = { r in
            if r.url!.path == "/api/episodes" { return (200, #"{"data":[{"id":457,"number":"10","season":"1"},{"id":455,"number":"1","season":"1"},{"id":456,"number":"2","season":"1"}]}"#) }
            return (200, #"{"data":{"players":[{"id":976,"player":"Kodik","team":{"name":"AniDUB"},"translation_type":{"label":"Озвучка"},"src":"//kodikplayer.com/seria/176463/example/720p"},{"id":3,"player":"Kodik","src":"javascript:alert(1)"}]}}"#)
        }
        let api = ExtraCatalog(source: .anilib, session: session())
        let episodes = try await api.episodes(title)
        XCTAssertEqual(episodes.map(\.number), ["1", "2", "10"])
        let players = try await api.players(episodes[0], title: title)
        XCTAssertEqual(players.count, 1); XCTAssertEqual(players[0].studio, "AniDUB"); XCTAssertEqual(players[0].balancer, "Kodik"); XCTAssertEqual(players[0].embed.scheme, "https")
    }
    func testAnimeGoPublicAttributesAndDuplicateResponsiveEpisodes() {
        let html = #"<a class="ani-grid__item-picture" href="/anime/naruto-11"><img class="image__img" alt="Наруто" src="/image.jpg"></a><a href="/anime/naruto-11">Наруто</a><div data-episode-number="2" data-episode-title="Вторая" data-episode="456"></div><div data-episode="455" data-episode-number="1"></div><div data-episode="455" data-episode-number="1"></div><button data-translation="1"><span>AniDUB</span></button><button data-player="//player.example/video" data-ptranslation="1"><span>Kodik</span></button>"#
        let titles = AnimeGoHTML.search(html, origin: URL(string: "https://animego.me")!)
        XCTAssertEqual(titles.count, 1); XCTAssertEqual(titles[0].key, "naruto-11")
        XCTAssertEqual(AnimeGoHTML.episodes(html).map(\.number), ["1", "2"])
        let players = AnimeGoHTML.players(html); XCTAssertEqual(players.first?.studio, "AniDUB"); XCTAssertEqual(players.first?.balancer, "Kodik")
    }
    func testShikimoriDoesNotTreatClipsAsEpisodes() async throws {
        SourceMockProtocol.respond = { _ in XCTFail("No full episode API exists in this adapter"); return (200, "[]") }
        let title = SourceTitle(source: .shikimori, key: "20", title: "Наруто", poster: nil, pagePath: "/animes/z20-naruto", shikimoriID: 20)
        let episodes = try await ExtraCatalog(source: .shikimori, session: session()).episodes(title)
        XCTAssertTrue(episodes.isEmpty)
    }
}
