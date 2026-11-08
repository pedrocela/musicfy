import AppKit
import SwiftUI

// MARK: - Translucent background

/// macOS dark glass, blended with whatever is behind the window.
/// Clipped with its own mask: SwiftUI's clip doesn't always reach an AppKit view.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var cornerRadius: CGFloat = 16

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.maskImage = Self.mask(radius: cornerRadius)
    }

    private static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

// MARK: - Dragging the window

/// Empty area to drag the player from. Double click: switch mode.
/// Right click: the menu. Sits below the controls, which get their clicks first.
struct WindowDragArea: NSViewRepresentable {
    var onDoubleClick: () -> Void = {}
    var onRightClick: (() -> Void)? = nil

    final class DragView: NSView {
        var onDoubleClick: () -> Void = {}
        var onRightClick: (() -> Void)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                onDoubleClick()
            } else {
                // Drag the window, never past the screen's edges; dropped at the top
                // center, it becomes the Island.
                drag(from: event)
            }
        }

        private func drag(from event: NSEvent) {
            guard let window, let app = AppDelegate.shared else { return }
            app.windowDragBegan()
            let startMouse = NSEvent.mouseLocation
            let startOrigin = window.frame.origin
            window.trackEvents(
                matching: [.leftMouseDragged, .leftMouseUp],
                timeout: NSEvent.foreverDuration,
                mode: .eventTracking
            ) { event, stop in
                guard let event else { return }
                if event.type == .leftMouseUp {
                    stop.pointee = true
                    return
                }
                let mouse = NSEvent.mouseLocation
                let proposed = NSRect(
                    x: startOrigin.x + mouse.x - startMouse.x,
                    y: startOrigin.y + mouse.y - startMouse.y,
                    width: window.frame.width,
                    height: window.frame.height
                )
                window.setFrameOrigin(app.windowDragged(to: proposed, mouse: mouse))
            }
            app.windowDragEnded()
        }

        override func rightMouseDown(with event: NSEvent) {
            if let onRightClick {
                onRightClick()
            } else {
                AppDelegate.shared?.showMainMenu()
            }
        }
    }

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: DragView, context: Context) {
        view.onDoubleClick = onDoubleClick
        view.onRightClick = onRightClick
    }
}

// MARK: - Buttons

/// Shrinks a little when pressed, with a bounce.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

/// Bare icon (playback controls).
struct IconButton: View {
    let symbol: String
    var size: CGFloat = 20
    var tint: Color = Theme.primary
    var help: String = ""
    /// Toggles (shuffle, repeat): when on, the icon sits on a light rounded chip, as in Music.
    var active: Bool? = nil
    let action: () -> Void
    @Environment(\.uiScale) private var scale

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * scale, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: (size + 10) * scale, height: (size + 8) * scale)
                .background(
                    RoundedRectangle(cornerRadius: 7 * scale, style: .continuous)
                        .fill(Color.white.opacity(active == true ? 0.22 : 0))
                )
                .frame(width: (size + 18) * scale, height: (size + 14) * scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .help(help)
        .animation(Theme.fade, value: symbol)
        .animation(Theme.fade, value: tint)
        .animation(Theme.press, value: active)
    }
}

/// Round button on glass (star, ellipsis).
struct RoundButton: View {
    let symbol: String
    var tint: Color = Theme.primary
    var diameter: CGFloat = 30
    var help: String = ""
    let action: () -> Void
    @Environment(\.uiScale) private var scale

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13 * scale, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: diameter * scale, height: diameter * scale)
                .background(Circle().fill(Theme.roundButtonFill))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help(help)
        .animation(Theme.fade, value: symbol)
    }
}

// MARK: - Progress / volume bar

/// Thin bar that thickens when touched. Drag it or click anywhere on it.
struct ScrubBar: View {
    let fraction: Double
    /// How fast the fill moves on its own, per second (the playing song). 0: still.
    var rate: Double = 0
    var fill: Color = Theme.barFill
    var track: Color = Theme.barTrack
    var onChange: (Double) -> Void = { _ in }
    var onCommit: (Double) -> Void = { _ in }
    /// New values glide in (progress) instead of jumping (volume).
    var smoothFill = true
    @State private var active = false
    @Environment(\.uiScale) private var scale

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let clamped = max(0, min(1, fraction))
            let height = (active ? Theme.barHeightActive : Theme.barHeight) * scale
            // Track and fill are Core Animation layers: while a song plays the fill runs
            // by itself, without SwiftUI redrawing it every frame.
            ProgressBarLayer(
                fraction: clamped,
                rate: active ? 0 : rate,
                smooth: smoothFill && !active,
                fill: active ? Color.white : fill,
                track: track
            )
            .frame(height: height)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        active = true
                        onChange(max(0, min(1, value.location.x / width)))
                    }
                    .onEnded { value in
                        active = false
                        onCommit(max(0, min(1, value.location.x / width)))
                    }
            )
            .animation(Theme.press, value: active)
        }
        .frame(height: 16 * scale)
    }
}

// MARK: - Scrolling text

private struct WidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// If the text doesn't fit, it slowly scrolls end to end, as in Music.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    let height: CGFloat
    /// Width of the right fade when the text doesn't fit. `nil`: 8 % of the width.
    var trailingFade: CGFloat? = nil
    /// When `false`, long text doesn't scroll: it's cut off with the fade.
    var scrolls = true

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @Environment(\.marqueeOnLayer) private var onLayer

    private var overflow: CGFloat { max(0, textWidth - containerWidth) }

    /// Scrolling text that's always on screen (compact, the Island) runs on Core Animation:
    /// SwiftUI would redraw the window on every frame of the scroll, paused or not.
    private var layerScroll: Bool { onLayer && scrolls && overflow > 1 && containerWidth > 0 }

    var body: some View {
        base
            .opacity(layerScroll ? 0 : 1)
            .overlay {
                if layerScroll {
                    MarqueeLayer(
                        text: text,
                        font: font,
                        color: color,
                        textWidth: textWidth,
                        containerWidth: containerWidth,
                        fadeStart: fadeStart
                    )
                    .allowsHitTesting(false)
                }
            }
    }

    private var fadeStart: CGFloat {
        trailingFade.map { containerWidth > 0 ? max(0.5, 1 - $0 / containerWidth) : 0.85 } ?? 0.92
    }

    private var base: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .background(GeometryReader { proxy in
                Color.clear.preference(key: WidthKey.self, value: proxy.size.width)
            })
            .onPreferenceChange(WidthKey.self) { textWidth = $0 }
            .offset(x: offset)
            // minWidth 0: without it the frame takes the full text width and pushes
            // the whole player out sideways.
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { containerWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in containerWidth = width }
            })
            .clipped()
            .mask(edgeFade)
            .task(id: "\(text)|\(Int(containerWidth))|\(Int(textWidth))") {
                await scroll()
            }
    }

    /// Edges fade only when text is cut off on that side.
    private var edgeFade: some View {
        return LinearGradient(
            stops: [
                .init(color: offset < 0 ? .clear : .black, location: 0),
                .init(color: .black, location: 0.05),
                .init(color: .black, location: fadeStart),
                .init(color: overflow > 1 ? .clear : .black, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func scroll() async {
        offset = 0
        let distance = overflow
        guard scrolls, distance > 1, !layerScroll else { return }
        let travel = Double(distance) / 28 // points per second
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2.5))
            if Task.isCancelled { return }
            withAnimation(.linear(duration: travel)) { offset = -distance - 6 }
            try? await Task.sleep(for: .seconds(travel + 2))
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: 0.7)) { offset = 0 }
            try? await Task.sleep(for: .seconds(0.7))
        }
    }
}

/// The scrolling part of `MarqueeText` on Core Animation: the same text (SwiftUI, drawn
/// once), the same loop and the same edge fades, moved by the window server.
///
/// The loop, as in `MarqueeText.scroll()`: 2.5 s still, slide left at 28 pt/s until the end
/// shows, 2 s still, 0.7 s back. The left fade appears while it slides and goes away on
/// the way back.
private struct MarqueeLayer: NSViewRepresentable {
    let text: String
    let font: Font
    let color: Color
    let textWidth: CGFloat
    let containerWidth: CGFloat
    let fadeStart: CGFloat

    func makeNSView(context: Context) -> MarqueeLayerView { MarqueeLayerView() }

    func updateNSView(_ view: MarqueeLayerView, context: Context) {
        view.configure(
            content: AnyView(
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize()
            ),
            key: "\(text)|\(Int(textWidth))|\(Int(containerWidth))",
            textWidth: textWidth,
            fadeStart: fadeStart
        )
    }
}

final class MarqueeLayerView: NSView {
    private final class PassThroughHost: NSHostingView<AnyView> {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private let host = PassThroughHost(rootView: AnyView(EmptyView()))
    private let fade = CAGradientLayer()
    private var key = ""
    private var runningLoop = ""
    private var textWidth: CGFloat = 0
    private var fadeStart: CGFloat = 0.92

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        host.sizingOptions = []
        host.wantsLayer = true
        addSubview(host)
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.mask = fade
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(content: AnyView, key: String, textWidth: CGFloat, fadeStart: CGFloat) {
        guard key != self.key || fadeStart != self.fadeStart else { return }
        self.key = key
        self.textWidth = textWidth
        self.fadeStart = fadeStart
        host.rootView = content
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let height = host.fittingSize.height
        host.frame = NSRect(x: 0, y: (bounds.height - height) / 2, width: max(textWidth, host.fittingSize.width) + 2, height: height)
        fade.frame = bounds
        let opaque = NSColor.black.cgColor
        let clear = NSColor.black.withAlphaComponent(0).cgColor
        fade.colors = [opaque, opaque, opaque, clear]
        fade.locations = [0, 0.05, NSNumber(value: Double(fadeStart)), 1]
        CATransaction.commit()
        startLoop()
    }

    /// Starts over only when the text or the room for it changes, like the SwiftUI version.
    private func startLoop() {
        let loop = "\(key)|\(Int(bounds.width))|\(Int(bounds.height))"
        guard loop != runningLoop || host.layer?.animation(forKey: "marquee") == nil else { return }
        runningLoop = loop
        host.layer?.removeAnimation(forKey: "marquee")
        fade.removeAnimation(forKey: "marquee")
        let distance = max(0, textWidth - bounds.width)
        guard distance > 1, let hostLayer = host.layer else { return }

        let travel = Double(distance) / 28
        let total = 2.5 + travel + 2 + 0.7
        let times: [NSNumber] = [0, 2.5 / total, (2.5 + travel) / total, (4.5 + travel) / total, 1].map { NSNumber(value: $0) }
        let timing = [
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .easeInEaseOut),
        ]
        let now = CACurrentMediaTime()

        let slide = CAKeyframeAnimation(keyPath: "transform.translation.x")
        let end = -(distance + 6)
        slide.values = [0, 0, end, end, 0]
        slide.keyTimes = times
        slide.timingFunctions = timing
        slide.duration = total
        slide.repeatCount = .infinity
        slide.beginTime = now
        slide.isRemovedOnCompletion = false
        hostLayer.add(slide, forKey: "marquee")

        // The left edge fades only while the start of the text is out of view.
        let opaque = NSColor.black.cgColor
        let clear = NSColor.black.withAlphaComponent(0).cgColor
        let leftEdge = CAKeyframeAnimation(keyPath: "colors")
        leftEdge.values = [
            [opaque, opaque, opaque, clear],
            [opaque, opaque, opaque, clear],
            [clear, opaque, opaque, clear],
            [clear, opaque, opaque, clear],
            [opaque, opaque, opaque, clear],
        ]
        leftEdge.keyTimes = times
        leftEdge.timingFunctions = timing
        leftEdge.duration = total
        leftEdge.repeatCount = .infinity
        leftEdge.beginTime = now
        leftEdge.isRemovedOnCompletion = false
        fade.add(leftEdge, forKey: "marquee")
    }
}

// MARK: - Artwork

/// The artwork filling its frame, or a gradient with a note when there's none.
struct ArtworkFill: View {
    let image: NSImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(
                        colors: [Color(white: 0.30), Color(white: 0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .font(.system(size: max(12, min(geo.size.width, geo.size.height) * 0.3), weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.28))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}

/// Name of the artwork's coordinate space, to line up the capsules' glass.
enum ArtworkSpace {
    static let name = "artwork"
}

/// Real glass over the artwork: shows the blurred artwork right behind the shape,
/// with a dark veil and a rim of light on top. Only meaningful inside artwork mode.
struct GlassBackdrop<S: InsettableShape>: View {
    @ObservedObject var player: PlayerController
    let shape: S
    @Environment(\.artworkSide) private var side

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named(ArtworkSpace.name))
            ZStack {
                if let frosted = player.glass?.frosted {
                    ArtworkFill(image: frosted)
                } else {
                    ArtworkFill(image: player.artwork)
                        .blur(radius: 20, opaque: true)
                }
            }
            .frame(width: side, height: side)
            .offset(x: -frame.minX, y: -frame.minY)
        }
        .clipShape(shape)
        .overlay(shape.fill(Theme.glassTint))
        .overlay(
            shape.strokeBorder(
                LinearGradient(colors: [Theme.glassEdgeTop, Theme.glassEdgeBottom], startPoint: .top, endPoint: .bottom),
                lineWidth: 0.75
            )
        )
        .allowsHitTesting(false)
    }
}

/// The artwork, crossfading when the song changes.
struct CrossfadingArtwork: View {
    @ObservedObject var player: PlayerController

    var body: some View {
        ZStack {
            ArtworkFill(image: player.artwork)
                .id(player.artworkToken)
                .transition(.opacity)
        }
        .animation(Theme.crossfade, value: player.artworkToken)
    }
}

// MARK: - Formatting

enum TimeText {
    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
