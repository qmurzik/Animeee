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
}
