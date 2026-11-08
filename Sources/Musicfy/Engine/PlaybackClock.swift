import Foundation

/// The beat for whatever shows the time: the elapsed and remaining seconds, and the line of
/// lyrics being sung. The bar and the ring don't need it (Core Animation moves them).
///
/// It only ticks while a song plays with the player on screen, once a second, right after
/// the song's second changes; with lyrics open, four times a second. Paused or hidden, it
/// stays still, and with it everything that reads it.
@MainActor
final class PlaybackClock: ObservableObject {
    @Published private(set) var now = Date()

    private var timer: Timer?

    /// `position`: the song's position right now, to line the ticks up with its seconds.
    func sync(running: Bool, fine: Bool, position: Double) {
        timer?.invalidate()
        timer = nil
        now = Date()
        guard running else { return }
        let interval: TimeInterval = fine ? 0.25 : 1
        let fractional = position - position.rounded(.down)
        let untilNext = (interval - fractional.truncatingRemainder(dividingBy: interval)) + 0.02
        let timer = Timer(fire: Date().addingTimeInterval(untilNext), interval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date() }
        }
        timer.tolerance = fine ? 0.03 : 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
