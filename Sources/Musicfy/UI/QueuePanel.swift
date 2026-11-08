import SwiftUI

/// "A continuación": lo que sigue en el disco o la lista que está sonando en Music.
struct QueuePanel: View {
    @ObservedObject var player: PlayerController

    var body: some View {
        Group {
            if player.state?.source == .spotify {
                PanelMessage(
                    title: "Cola no disponible",
                    detail: "Spotify no deja ver la cola desde otras apps."
                )
            } else if player.queueLoading {
                ProgressView().controlSize(.small).tint(.white)
            } else if let queue = player.queue, !queue.items.isEmpty {
                list(queue)
            } else {
                PanelMessage(title: "No sigue nada", detail: "Es el último tema de la lista.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func list(_ queue: QueueInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("A continuación")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                if !queue.playlistName.isEmpty {
                    Text("De \(queue.playlistName)")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 0.5)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(queue.items.enumerated()), id: \.element.id) { offset, item in
                        QueueRow(player: player, item: item, isLast: offset == queue.items.count - 1)
                            .transition(.opacity.combined(with: .offset(y: 8)))
                    }
                }
                .animation(Theme.smooth, value: queue)
            }
        }
    }
}

private struct QueueRow: View {
    @ObservedObject var player: PlayerController
    let item: QueueInfo.Item
    let isLast: Bool

    var body: some View {
        Button { player.playQueueItem(item) } label: {
            HStack(spacing: 12) {
                QueueThumb(player: player, item: item)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.primary)
                    Text(item.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 0.5)
                        .padding(.leading, 62)
                        .padding(.trailing, 16)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowStyle())
        .help("Reproducir")
    }
}

private struct RowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.1 : 0))
            .animation(Theme.fade, value: configuration.isPressed)
    }
}

/// Miniatura de cada tema: la tapa actual si es del mismo disco, si no la del catálogo.
private struct QueueThumb: View {
    @ObservedObject var player: PlayerController
    let item: QueueInfo.Item
    @State private var image: NSImage?

    private var sameAlbum: Bool {
        guard let state = player.state else { return false }
        return state.album == item.album && state.artist == item.artist
    }

    var body: some View {
        ArtworkFill(image: sameAlbum ? player.artwork : image)
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .task(id: item.id) {
                guard !sameAlbum else { return }
                let key = "catalog|\(item.artist)|\(item.album)"
                if let hit = ArtworkLoader.shared.cached(key) {
                    image = hit
                    return
                }
                if let found = await ArtworkLoader.shared.searchCatalog(artist: item.artist, album: item.album, title: item.title) {
                    ArtworkLoader.shared.store(found, for: key)
                    withAnimation(Theme.fade) { image = found }
                }
            }
    }
}
