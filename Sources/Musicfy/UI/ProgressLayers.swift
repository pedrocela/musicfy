import AppKit
import SwiftUI

/// The song's progress, moved by Core Animation instead of being redrawn.
///
/// The bar and the ring used to be redrawn by SwiftUI on every frame while a song played
/// (a 0.25 s linear animation chained to the next one, forever). Here the app says once
/// "from here to the end, at this speed" and the window server moves it; the app only
/// speaks again when something changes (a seek, a pause, a fresh reading).
struct ProgressMotion {
    /// Where the fill is now (0 to 1).
    var fraction: Double
    /// How much it grows per second (0 = still).
    var rate: Double

    /// The keyframes from `current` (what's on screen) to the end of the song: an optional
    /// 0.25 s glide to where it should be, then a straight run at `rate`.
    func animation(keyPath: String, from current: Double, glide: Bool) -> CAAnimation? {
        let glideTime = glide ? 0.25 : 0
        let afterGlide = min(1, fraction + rate * glideTime)
        guard rate > 0 else {
            guard glide, abs(current - fraction) > 0.0005 else { return nil }
            let move = CABasicAnimation(keyPath: keyPath)
            move.fromValue = current
            move.toValue = fraction
            move.duration = glideTime
            move.timingFunction = CAMediaTimingFunction(name: .linear)
            return move
        }
        let runTime = max(0, (1 - afterGlide) / rate)
        let total = glideTime + runTime
        guard total > 0 else { return nil }
        let keyframes = CAKeyframeAnimation(keyPath: keyPath)
        keyframes.values = [glide ? current : fraction, afterGlide, 1]
        keyframes.keyTimes = [0, NSNumber(value: glideTime / total), 1]
        keyframes.calculationMode = .linear
        keyframes.duration = total
        keyframes.fillMode = .forwards
        keyframes.isRemovedOnCompletion = false
        return keyframes
    }
}

/// Keeps track of what was asked last, to tell a real change from the same motion
/// asked again on the next render.
struct MotionTracker {
    private var fraction = -1.0
    private var rate = 0.0
    private var since = CACurrentMediaTime()

    /// Where the last motion has the fill right now.
    var expected: Double {
        min(1, fraction + rate * (CACurrentMediaTime() - since))
    }

    /// Nothing shown yet: the first value appears in place, without gliding in.
    var isFresh: Bool { fraction < 0 }

    /// True if `motion` is the one already running (within a pixel or so).
    func matches(_ motion: ProgressMotion) -> Bool {
        fraction >= 0 && rate == motion.rate && abs(expected - motion.fraction) < 0.002
    }

    mutating func record(_ motion: ProgressMotion) {
        fraction = motion.fraction
        rate = motion.rate
        since = CACurrentMediaTime()
    }
}

// MARK: - Bar

/// Track and fill of `ScrubBar`, in one rounded layer.
struct ProgressBarLayer: NSViewRepresentable {
    let fraction: Double
    /// Fraction per second while the song plays; 0 when it's still.
    var rate: Double = 0
    /// Glide to new values (the time bar) or jump (volume, dragging).
    var smooth = true
    let fill: Color
    let track: Color

    func makeNSView(context: Context) -> ProgressBarView { ProgressBarView() }

    func updateNSView(_ view: ProgressBarView, context: Context) {
        view.setColors(fill: NSColor(fill).cgColor, track: NSColor(track).cgColor)
        view.show(ProgressMotion(fraction: max(0, min(1, fraction)), rate: max(0, rate)), smooth: smooth)
    }
}

final class ProgressBarView: NSView {
    private let fillLayer = CALayer()
    private var tracker = MotionTracker()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        guard let layer else { return }
        layer.masksToBounds = true
        layer.cornerCurve = .circular
        fillLayer.anchorPoint = CGPoint(x: 0, y: 0.5)
        fillLayer.setAffineTransform(CGAffineTransform(scaleX: 0, y: 1))
        layer.addSublayer(fillLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.cornerRadius = bounds.height / 2
        fillLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        fillLayer.position = CGPoint(x: 0, y: bounds.midY)
        CATransaction.commit()
    }

    func setColors(fill: CGColor, track: CGColor) {
        if fillLayer.backgroundColor != fill {
            // The same short fade the bar had when touched.
            CATransaction.begin()
            CATransaction.setAnimationDuration(fillLayer.backgroundColor == nil ? 0 : 0.2)
            fillLayer.backgroundColor = fill
            CATransaction.commit()
        }
        if layer?.backgroundColor != track {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.backgroundColor = track
            CATransaction.commit()
        }
    }

    func show(_ motion: ProgressMotion, smooth: Bool) {
        guard !tracker.matches(motion) else { return }
        let current = (fillLayer.presentation()?.value(forKeyPath: "transform.scale.x") as? Double) ?? tracker.expected
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.removeAnimation(forKey: "progress")
        fillLayer.setValue(motion.fraction, forKeyPath: "transform.scale.x")
        if let animation = motion.animation(keyPath: "transform.scale.x", from: current, glide: smooth && !tracker.isFresh) {
            fillLayer.add(animation, forKey: "progress")
        }
        CATransaction.commit()
        tracker.record(motion)
    }
}

// MARK: - Ring

/// The Island's progress ring: from twelve o'clock, clockwise.
struct ProgressRingLayer: NSViewRepresentable {
    let fraction: Double
    var rate: Double = 0
    let color: Color
    var lineWidth: CGFloat = 2

    func makeNSView(context: Context) -> ProgressRingView { ProgressRingView() }

    func updateNSView(_ view: ProgressRingView, context: Context) {
        view.lineWidth = lineWidth
        view.setColor(NSColor(color).cgColor)
        view.show(ProgressMotion(fraction: max(0, min(1, fraction)), rate: max(0, rate)))
    }
}

final class ProgressRingView: NSView {
    private let ring = CAShapeLayer()
    private var tracker = MotionTracker()

    var lineWidth: CGFloat = 2 {
        didSet { if lineWidth != oldValue { needsLayout = true } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        ring.fillColor = nil
        ring.lineCap = .round
        ring.strokeEnd = 0
        layer?.addSublayer(ring)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.frame = bounds
        ring.lineWidth = lineWidth
        let path = CGMutablePath()
        let radius = min(bounds.width, bounds.height) / 2
        // Not flipped: y grows upward, so twelve o'clock is π/2 and clockwise goes down from there.
        path.addArc(
            center: CGPoint(x: bounds.midX, y: bounds.midY),
            radius: radius,
            startAngle: .pi / 2,
            endAngle: .pi / 2 - 2 * .pi,
            clockwise: true
        )
        ring.path = path
        CATransaction.commit()
    }

    func setColor(_ color: CGColor) {
        guard ring.strokeColor != color else { return }
        // Playing or paused: the same crossfade as the rest of the ring.
        CATransaction.begin()
        CATransaction.setAnimationDuration(ring.strokeColor == nil ? 0 : 0.55)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        ring.strokeColor = color
        CATransaction.commit()
    }

    func show(_ motion: ProgressMotion) {
        guard !tracker.matches(motion) else { return }
        let current = (ring.presentation()?.strokeEnd).map(Double.init) ?? tracker.expected
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.removeAnimation(forKey: "progress")
        ring.strokeEnd = CGFloat(motion.fraction)
        // The ring used to glide half a second toward each new reading.
        if let animation = motion.animation(keyPath: "strokeEnd", from: current, glide: !tracker.isFresh) {
            ring.add(animation, forKey: "progress")
        }
        CATransaction.commit()
        tracker.record(motion)
    }
}
