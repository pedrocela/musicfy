import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Artwork mode's glass, made from the artwork itself, as in Music:
/// - `progressive`: the artwork with its lower part progressively blurred
///   (sharp at the top, blurrier toward the bottom). It sits under the controls.
/// - `frosted`: the whole artwork heavily blurred. It backs the capsules at the top,
///   cropped right where each one sits, so you see "through" them.
///
/// Computed once per artwork, off the main thread.
struct ArtworkGlass {
    let progressive: NSImage
    let frosted: NSImage

    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func make(from image: NSImage) -> ArtworkGlass? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var input = CIImage(cgImage: cgImage)

        // Size cap: enough for a 640 pt artwork on a Retina display.
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

        // Mask: white (blurred) at the bottom, black (sharp) at the top. In Core Image y grows upward.
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

        // The blurred part loses a little color and brightness, like Music's material.
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
