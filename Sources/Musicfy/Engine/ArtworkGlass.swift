import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// El vidrio del modo tapa, sacado de la tapa misma, como en Music:
/// - `progressive`: la tapa con la parte de abajo difuminada de a poco
///   (nítida arriba, cada vez más borrosa hacia abajo). Va debajo de los controles.
/// - `frosted`: la tapa entera muy difuminada. Es el fondo de las cápsulas de arriba,
///   recortado justo donde está cada una, así se ve "a través" de ellas.
///
/// Se calcula una vez por tapa, fuera del hilo principal.
struct ArtworkGlass {
    let progressive: NSImage
    let frosted: NSImage

    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func make(from image: NSImage) -> ArtworkGlass? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var input = CIImage(cgImage: cgImage)

        // Tope de tamaño: alcanza para una tapa de 640 pt en pantalla Retina.
        let longest = max(input.extent.width, input.extent.height)
        if longest > 1280 {
            let scale = CIFilter.lanczosScaleTransform()
            scale.inputImage = input
            scale.scale = Float(1280 / longest)
            scale.aspectRatio = 1
            if let output = scale.outputImage { input = output }
        }
        let extent = input.extent
        let side = max(extent.width, extent.height)
        let clamped = input.clampedToExtent()

        // Máscara: blanco (borroso) abajo, negro (nítido) arriba. En Core Image la y crece hacia arriba.
        let gradient = CIFilter.linearGradient()
        gradient.point0 = CGPoint(x: 0, y: extent.minY + extent.height * 0.24)
        gradient.color0 = CIColor(red: 1, green: 1, blue: 1)
        gradient.point1 = CGPoint(x: 0, y: extent.minY + extent.height * 0.44)
        gradient.color1 = CIColor(red: 0, green: 0, blue: 0)
        guard let mask = gradient.outputImage else { return nil }

        let variable = CIFilter.maskedVariableBlur()
        variable.inputImage = clamped
        variable.mask = mask
        variable.radius = Float(side * 0.075)
        guard let blurred = variable.outputImage?.cropped(to: extent) else { return nil }

        // La parte borrosa pierde un poco de color y de brillo, como el material de Music.
        let tone = CIFilter.colorControls()
        tone.inputImage = blurred
        tone.saturation = 0.9
        tone.brightness = -0.03
        tone.contrast = 0.94
        let blend = CIFilter.blendWithMask()
        blend.inputImage = tone.outputImage
        blend.backgroundImage = input
        blend.maskImage = mask
        guard let progressive = blend.outputImage?.cropped(to: extent) else { return nil }

        let gaussian = CIFilter.gaussianBlur()
        gaussian.inputImage = clamped
        gaussian.radius = Float(side * 0.06)
        let frostTone = CIFilter.colorControls()
        frostTone.inputImage = gaussian.outputImage
        frostTone.saturation = 1.15
        guard let frosted = frostTone.outputImage?.cropped(to: extent) else { return nil }

        guard
            let progressiveCG = context.createCGImage(progressive, from: extent),
            let frostedCG = context.createCGImage(frosted, from: extent)
        else { return nil }
        return ArtworkGlass(
            progressive: NSImage(cgImage: progressiveCG, size: image.size),
            frosted: NSImage(cgImage: frostedCG, size: image.size)
        )
    }
}
