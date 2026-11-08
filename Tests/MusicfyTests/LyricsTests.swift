import XCTest
@testable import Musicfy

final class LyricsTests: XCTestCase {
    func testParsesTimedLinesInOrder() {
        let lines = Lyrics.parseLRC("""
            [ar:Someone]
            [00:12.50]Second
            [00:01.00]First
            [01:00.00][02:00.00]Chorus
            """)
        XCTAssertEqual(lines.map(\.text), ["First", "Second", "Chorus", "Chorus"])
        XCTAssertEqual(lines.map(\.time), [1, 12.5, 60, 120])
    }

    func testIgnoresMetadataAndPlainText() {
        XCTAssertTrue(Lyrics.parseLRC("[ti:Title]\n[length:03:20]\nno time here").isEmpty)
    }

    func testIndexFindsTheLineBeingSung() {
        let lyrics = Lyrics(lines: Lyrics.parseLRC("[00:05.00]a\n[00:10.00]b\n[00:20.00]c"), plain: "", instrumental: false)
        XCTAssertNil(lyrics.index(at: 2))
        XCTAssertEqual(lyrics.index(at: 5), 0)
        XCTAssertEqual(lyrics.index(at: 15), 1)
        XCTAssertEqual(lyrics.index(at: 999), 2)
    }

    func testPlainLyricsHaveNoIndex() {
        let lyrics = Lyrics(lines: [], plain: "words", instrumental: false)
        XCTAssertFalse(lyrics.isSynced)
        XCTAssertNil(lyrics.index(at: 10))
    }

    func testEmptyResultIsNotLyrics() {
        XCTAssertNil(LyricsLoader.lyrics(from: ["syncedLyrics": "", "plainLyrics": ""]))
        XCTAssertEqual(LyricsLoader.lyrics(from: ["instrumental": true])?.instrumental, true)
    }

    func testSearchPrefersSyncedWithCloseDuration() {
        let list: [[String: Any]] = [
            ["duration": 300.0, "syncedLyrics": "[00:01.00]too long"],
            ["duration": 181.0, "plainLyrics": "plain only"],
            ["duration": 179.0, "syncedLyrics": "[00:01.00]right one"],
        ]
        XCTAssertEqual(LyricsLoader.best(in: list, duration: 180)?.lines.first?.text, "right one")
    }

    func testSearchFallsBackToPlain() {
        let list: [[String: Any]] = [["duration": 181.0, "plainLyrics": "plain only"]]
        XCTAssertEqual(LyricsLoader.best(in: list, duration: 180)?.plain, "plain only")
        XCTAssertNil(LyricsLoader.best(in: [["duration": 400.0, "plainLyrics": "x"]], duration: 180))
    }
}
