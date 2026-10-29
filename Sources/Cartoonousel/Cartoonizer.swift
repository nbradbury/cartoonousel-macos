import CoreImage
import CoreML
import Foundation

/// Turns a photo into a black-and-white cartoon using AnimeGANv2 (celeba_distill weights from
/// bryandlee/animegan2-pytorch, MIT), bundled as Cartoonizer.mlmodelc, then drops the colour.
enum Cartoonizer {
    /// Longest edge the model runs at. Smaller stylises harder but smears detail; 1024 keeps faces and text legible.
    static let maxEdge: CGFloat = 1024

    private static let context = CIContext()
    /// CPU only: with flexible input sizes the GPU path recompiles per size (~2.5 s per photo) and can
    /// assert in MPSGraph, while the CPU runs a 1024 px photo in ~0.3 s.
    private static let model: MLModel? = Bundle.module.url(forResource: "Cartoonizer", withExtension: "mlmodelc")
        .flatMap { url in
            let config = MLModelConfiguration()
            config.computeUnits = .cpuOnly
            return try? MLModel(contentsOf: url, configuration: config)
        }

    /// Returns PNG data and pixel size, or nil if the file can't be read as an image.
    static func cartoon(from url: URL) -> (png: Data, size: CGSize)? {
        guard let model,
              let photo = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { return nil }

        // The network downsamples twice and upsamples by 2, so sides must be multiples of 32.
        let scale = min(1, maxEdge / max(photo.extent.width, photo.extent.height))
        let w = max(64, Int(photo.extent.width * scale) / 32 * 32)
        let h = max(64, Int(photo.extent.height * scale) / 32 * 32)
        let small = photo.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale])

        guard let cg = context.createCGImage(small, from: small.extent),
              let input = try? MLFeatureValue(cgImage: cg, pixelsWide: w, pixelsHigh: h,
                                              pixelFormatType: kCVPixelFormatType_32BGRA, options: nil),
              let features = try? MLDictionaryFeatureProvider(dictionary: ["image": input]),
              let buffer = try? model.prediction(from: features).featureValue(for: "cartoon")?.imageBufferValue
        else { return nil }

        let grey = CIImage(cvPixelBuffer: buffer)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        guard let space = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2),
              let png = context.pngRepresentation(of: grey, format: .L8, colorSpace: space)
        else { return nil }
        return (png, CGSize(width: w, height: h))
    }
}
