import AppKit
import XCTest
@testable import Musicfy

final class EngineTests: XCTestCase {
    private func state(_ change: (inout PlayerState) -> Void = { _ in }) -> PlayerState {
        var state = PlayerState(
            source: .music, isPlaying: true, title: "Song", artist: "Artist", album: "Album",
            duration: 200, position: 10, trackID: "ABC", volume: 50, shuffle: false,
            repeatMode: .off, favorited: false, artworkURL: nil
        )
        change(&state)
        return state
    }

    func testTrackKeyUsesTheIDWhenThereIsOne() {
        XCTAssertEqual(state().trackKey, "music|ABC")
        XCTAssertEqual(state { $0.trackID = "" }.trackKey, "music|Song|Artist|Album")
    }

    func testSubtitleDropsAnAlbumNamedLikeTheArtist() {
        XCTAssertEqual(state().subtitle, "Artist — Album")
        XCTAssertEqual(state { $0.album = "artist" }.subtitle, "Artist")
        XCTAssertEqual(state { $0.artist = "" }.subtitle, "Album")
    }

    func testAppleScriptNumbersUseADecimalPoint() {
        XCTAssertEqual(MusicSource.number(83.456), "83.46")
        XCTAssertEqual(MusicSource.number(0), "0.00")
    }

    func testDescriptorItemsTolerateMissingValues() {
        let list = NSAppleEventDescriptor.list()
        list.insert(NSAppleEventDescriptor(string: "x"), at: 1)
        list.insert(NSAppleEventDescriptor.null(), at: 2)
        XCTAssertEqual(list.string(1), "x")
        XCTAssertNil(list.item(2))
        XCTAssertEqual(list.string(2), "")
        XCTAssertEqual(list.double(9), 0)
        XCTAssertFalse(list.bool(9))
    }

    func testParsesTheStateScriptAnswer() {
        let values: [NSAppleEventDescriptor] = [
            .init(string: "playing"), .init(string: "Song"), .init(string: "Artist"), .init(string: "Album"),
            .init(double: 200.5), .init(double: 12.25), .init(string: "ID1"), .init(int32: 70),
            .init(boolean: true), .init(string: "one"), .init(boolean: true),
            .init(string: "https://example.com/a.jpg"),
        ]
        let list = NSAppleEventDescriptor.list()
        for (offset, value) in values.enumerated() { list.insert(value, at: offset + 1) }
        let parsed = MusicSource().parse(list)
        XCTAssertEqual(parsed?.isPlaying, true)
        XCTAssertEqual(parsed?.title, "Song")
        XCTAssertEqual(parsed?.duration, 200.5)
        XCTAssertEqual(parsed?.position, 12.25)
        XCTAssertEqual(parsed?.volume, 70)
        XCTAssertEqual(parsed?.shuffle, true)
        XCTAssertEqual(parsed?.repeatMode, .one)
        XCTAssertEqual(parsed?.favorited, true)
        XCTAssertEqual(parsed?.artworkURL?.absoluteString, "https://example.com/a.jpg")
    }

    func testStoppedMeansNothingPlaying() {
        let list = NSAppleEventDescriptor.list()
        list.insert(NSAppleEventDescriptor(string: "stopped"), at: 1)
        XCTAssertNil(MusicSource().parse(list))
    }

    func testPodcastPositionMovesOnlyWhilePlaying() {
        let start = Date()
        var info = NowPlayingBridge.Info(
            bundle: "com.apple.podcasts", parent: "", playing: true, title: "Episode", artist: "Show",
            album: "", duration: 100, position: 40, readAt: start, identifier: "1", artworkTag: ""
        )
        XCTAssertEqual(info.position(at: start.addingTimeInterval(5)), 45, accuracy: 0.001)
        XCTAssertEqual(info.position(at: start.addingTimeInterval(500)), 100) // never past the end
        info.playing = false
        XCTAssertEqual(info.position(at: start.addingTimeInterval(5)), 40)
        XCTAssertTrue(info.belongs(to: "com.apple.Podcasts"))
        XCTAssertFalse(info.belongs(to: "com.apple.Music"))
    }

    /// The timeout wrapper must keep scripts that return early (every state script does).
    func testTimeoutWrapperKeepsEarlyReturns() {
        let runner = AppleScriptRunner.shared
        let result = runner.queue.sync {
            runner.run("if true then return {\"stopped\"}\nreturn {\"never\"}", cache: false)
        }
        guard case .success(let list) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(list.string(1), "stopped")
    }

    func testTimeoutWrapperText() {
        XCTAssertEqual(AppleScriptRunner.withTimeout("beep", seconds: 3), "with timeout of 3 seconds\nbeep\nend timeout")
    }
}
