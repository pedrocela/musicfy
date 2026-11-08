import AppKit
import SwiftUI

// MARK: - Fondo translúcido

/// Vidrio oscuro de macOS, mezclado con lo que hay detrás de la ventana.
/// Se recorta con una máscara propia: el recorte de SwiftUI no siempre llega a una vista de AppKit.
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

// MARK: - Arrastrar la ventana

/// Zona vacía desde la que se arrastra el player. Doble clic: cambia de modo.
/// Clic derecho: el menú. Va debajo de los controles, que reciben su clic primero.
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
                window?.performDrag(with: event)
            }
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

// MARK: - Botones

/// Se achica un poco al apretar, con rebote.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

/// Ícono suelto (controles de reproducción).
struct IconButton: View {
    let symbol: String
    var size: CGFloat = 20
    var tint: Color = Theme.primary
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size + 18, height: size + 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .help(help)
        .animation(Theme.fade, value: symbol)
        .animation(Theme.fade, value: tint)
    }
}

/// Botón redondo sobre vidrio (estrella, tres puntos).
struct RoundButton: View {
    let symbol: String
    var tint: Color = Theme.primary
    var diameter: CGFloat = 30
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(Theme.roundButtonFill))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help(help)
        .animation(Theme.fade, value: symbol)
    }
}

// MARK: - Barra de progreso / volumen

/// Barra fina que se engrosa al tocarla. Se arrastra o se hace clic en cualquier punto.
struct ScrubBar: View {
    let fraction: Double
    var fill: Color = Theme.barFill
    var track: Color = Theme.barTrack
    var onChange: (Double) -> Void = { _ in }
    var onCommit: (Double) -> Void = { _ in }
    /// La barra de progreso avanza en tramos de 0,25 s; con esto el avance se ve continuo.
    var smoothFill = true
    @State private var active = false

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let clamped = max(0, min(1, fraction))
            let height = active ? Theme.barHeightActive : Theme.barHeight
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Rectangle()
                    .fill(active ? Color.white : fill)
                    .frame(width: clamped * width)
                    .animation(active || !smoothFill ? nil : .linear(duration: 0.25), value: clamped)
            }
            .frame(height: height)
            .clipShape(Capsule())
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
        .frame(height: 16)
    }
}

// MARK: - Texto que se desliza

private struct WidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Si el texto no entra, se desliza despacio de punta a punta, como en Music.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    let height: CGFloat

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var overflow: CGFloat { max(0, textWidth - containerWidth) }

    var body: some View {
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
            .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Bordes que se desvanecen sólo cuando hay texto cortado de ese lado.
    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: offset < 0 ? .clear : .black, location: 0),
                .init(color: .black, location: 0.05),
                .init(color: .black, location: 0.92),
                .init(color: overflow > 1 ? .clear : .black, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func scroll() async {
        offset = 0
        let distance = overflow
        guard distance > 1 else { return }
        let travel = Double(distance) / 28 // puntos por segundo
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

// MARK: - Tapa

/// La tapa llenando su lugar, o un degradé con una nota si no hay.
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

/// La tapa con fundido cruzado cuando cambia la canción.
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

// MARK: - Formato

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
