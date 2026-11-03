import XCTest
@testable import WatchCore
final class WatchCoreTests: XCTestCase {
    func testVoiceSwitchMatchesDecimalAndZeroPaddedEpisodes() {
        XCTAssertEqual(EpisodeNumber.canonical("02"), EpisodeNumber.canonical("2"))
        XCTAssertEqual(EpisodeNumber.canonical(" 12,5 "), EpisodeNumber.canonical("12.50"))
        XCTAssertNotEqual(EpisodeNumber.canonical("12.5"), EpisodeNumber.canonical("12"))
    }
    func testNumericEpisodeOrder() {
        let episodes = ["10", "2", "1.5", "1", "100"].sorted { EpisodeNumber.isBefore($0, $1) }
        XCTAssertEqual(episodes, ["1", "1.5", "2", "10", "100"])
    }
    func testSpecialsDoNotCollapseIntoNumberedEpisodes() {
        XCTAssertNotEqual(EpisodeNumber.canonical("OVA"), EpisodeNumber.canonical("0"))
        XCTAssertNotEqual(EpisodeNumber.canonical(nil), EpisodeNumber.canonical("0"))
        XCTAssertEqual(EpisodeNumber.canonical(" Special "), "special")
    }
    func testScrubbingClampsToMediaDurationAndSafeIntegerRange() {
        XCTAssertEqual(PlaybackMath.seekTarget(-20, duration: 1400), 0)
        XCTAssertEqual(PlaybackMath.seekTarget(2000, duration: 1400), 1400)
        XCTAssertEqual(PlaybackMath.seekTarget(15, duration: 1400), 15)
        XCTAssertEqual(PlaybackMath.seekTarget(.infinity, duration: 1400), 0)
        XCTAssertEqual(PlaybackMath.seekTarget(3_000_000, duration: .infinity), 2_000_000)
    }
    func testResumeNeverSelectsUnrelatedIDOutsideChosenVoice() {
        XCTAssertEqual(PlaybackMath.resumeID([17, 23, 30], remembered: 23), 23)
        XCTAssertEqual(PlaybackMath.resumeID([17, 23, 30], remembered: 99), 17)
        XCTAssertNil(PlaybackMath.resumeID([], remembered: 23))
    }
    func testChangingVoiceKeepsEpisodeInsteadOfJumpingToFirst() {
        XCTAssertEqual(PlaybackMath.resumeID([101, 102, 103], remembered: 23, numbers: ["1", "02", "3"], episode: "2.0"), 102)
        XCTAssertEqual(PlaybackMath.resumeID([101, 102], remembered: 101, numbers: ["1", "2"], episode: "2"), 101)
        XCTAssertEqual(PlaybackMath.resumeID([101, 102], remembered: 23, numbers: ["1", "2"], episode: "20"), 101)
        XCTAssertEqual(PlaybackMath.resumeID([101], remembered: nil, numbers: ["1", "2"], episode: "2"), 101)
    }

    func testShikimoriVideoIsAnExternalClipAndRejectsUnsafeLinks() throws {
        let payload = Data(#"{"id":44952,"url":"https://video.sibnet.ru/shell.php?videoid=5237538","name":"OP19v2","kind":"op","hosting":"sibnet"}"#.utf8)
        let clip = try JSONDecoder().decode(ExternalVideo.self, from: payload)
        XCTAssertEqual(clip.kindTitle, "Опенинг")
        XCTAssertEqual(clip.destination?.host, "video.sibnet.ru")
        let unsafe = Data(#"{"id":1,"url":"javascript:alert(1)","name":null,"kind":"pv","hosting":"other"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(ExternalVideo.self, from: unsafe).destination)
    }

}
