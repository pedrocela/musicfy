import SwiftUI

/// Todo lo visual que se puede cambiar sin tocar la lógica: medidas, colores,
/// tipografía y animaciones. Dirección "Vidrio" (A) + modo Isla.
enum Theme {
    // MARK: Medidas (puntos)
    static let artworkSize = CGSize(width: 320, height: 320)
    static let compactSize = CGSize(width: 320, height: 136)
    static let islandCollapsed = CGSize(width: 300, height: 40)
    static let islandExpanded = CGSize(width: 380, height: 156)
    static let islandRadius: CGFloat = 20
    static let islandOpenRadius: CGFloat = 26
    /// La ventana de la Isla tiene lugar para la sombra alrededor de la cápsula abierta.
    static let islandShadowMargin: CGFloat = 24
    /// Distancia entre la barra de menú y la Isla.
    static let islandTopGap: CGFloat = 8
    /// Margen a los costados de la pantalla cuando la Isla se pega a un lado.
    static let islandSideGap: CGFloat = 12

    /// Alto del panel de letras o de cola que se abre debajo.
    static let drawerHeight: CGFloat = 380

    static let artworkRadius: CGFloat = 18
    static let compactRadius: CGFloat = 16

    // MARK: Texto
    static let artworkTitle = Font.system(size: 18, weight: .semibold)
    static let artworkSubtitle = Font.system(size: 13)
    static let compactTitle = Font.system(size: 14, weight: .semibold)
    static let compactSubtitle = Font.system(size: 12)
    static let islandTitle = Font.system(size: 13, weight: .semibold)
    static let islandSubtitle = Font.system(size: 11)
    static let islandOpenTitle = Font.system(size: 15, weight: .semibold)
    static let time = Font.system(size: 11, weight: .medium).monospacedDigit()
    static let chip = Font.system(size: 12, weight: .semibold)
    static let lyric = Font.system(size: 21, weight: .bold)

    static let primary = Color.white
    static let secondary = Color.white.opacity(0.72)
    static let tertiary = Color.white.opacity(0.62)
    static let timeColor = Color.white.opacity(0.70)

    // MARK: Barras
    static let barTrack = Color.white.opacity(0.22)
    static let barFill = Color.white.opacity(0.88)
    static let barHeight: CGFloat = 4
    static let barHeightActive: CGFloat = 7

    // MARK: Vidrio
    static let chipFill = Color.black.opacity(0.38)
    static let capsuleFill = Color(red: 0.157, green: 0.141, blue: 0.133).opacity(0.5)
    static let capsuleStroke = Color.white.opacity(0.2)
    static let roundButtonFill = Color.white.opacity(0.14)
    static let windowStroke = Color.white.opacity(0.12)
    /// Sombra interna de luz arriba del modo compacto.
    static let topHighlight = Color.white.opacity(0.12)
    /// Fondo de la Isla: casi negro, un poco translúcido sobre el vidrio del sistema.
    static let islandFill = Color(red: 0.055, green: 0.047, blue: 0.043).opacity(0.96)
    static let islandStroke = Color.white.opacity(0.09)

    // MARK: Color de cada app (punto del chip)
    static func sourceColor(_ kind: SourceKind) -> Color {
        switch kind {
        case .music: return Color(red: 1.0, green: 0.353, blue: 0.447)
        case .spotify: return Color(red: 0.118, green: 0.843, blue: 0.376)
        }
    }

    // MARK: Animaciones
    /// Cambios de modo, cápsula de volumen, apertura de la Isla.
    static let smooth = Animation.spring(response: 0.42, dampingFraction: 0.86)
    /// Mostrar y esconder controles al pasar el mouse.
    static let fade = Animation.easeInOut(duration: 0.22)
    /// Cambio de tapa, de título y de color entre canciones.
    static let crossfade = Animation.easeInOut(duration: 0.55)
    /// Respuesta al apretar un botón.
    static let press = Animation.spring(response: 0.24, dampingFraction: 0.62)
    /// Duración del cambio de tamaño de la ventana (AppKit), con curva suave de salida.
    static let resizeDuration: TimeInterval = 0.4
}
