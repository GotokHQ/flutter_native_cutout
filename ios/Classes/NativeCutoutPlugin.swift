import Flutter
import UIKit
import Vision
import CoreImage
import Accelerate

public class NativeCutoutPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.hugo/native_cutout", binaryMessenger: registrar.messenger())
        let instance = NativeCutoutPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "removeBackground":
            guard let args = call.arguments as? [String: Any],
                  let imagePath = args["imagePath"] as? String else {
                result(FlutterError(code: "INVALID_INPUT", message: "Missing imagePath argument", details: nil))
                return
            }

            let options = args["options"] as? [String: Any] ?? [:]
            let cropToSubject = options["cropToSubject"] as? Bool ?? false
            let writeToCache = options["writeToCache"] as? Bool ?? true
            let featherRadius = (options["featherRadius"] as? NSNumber)?.doubleValue ?? 0
            let edgeErode = (options["edgeErode"] as? NSNumber)?.intValue ?? 0

            guard #available(iOS 17.0, *) else {
                result(FlutterError(
                    code: "UNSUPPORTED_OS",
                    message: "Background removal requires iOS 17 or later",
                    details: nil
                ))
                return
            }

            removeBackground(
                imagePath: imagePath,
                cropToSubject: cropToSubject,
                writeToCache: writeToCache,
                featherRadius: featherRadius,
                edgeErode: edgeErode,
                result: result
            )

        case "clearCache":
            clearCache(result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func cacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("native_cutout", isDirectory: true)
    }

    private func clearCache(result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            let dir = self.cacheDirectory()
            do {
                if fm.fileExists(atPath: dir.path) {
                    try fm.removeItem(at: dir)
                }
                DispatchQueue.main.async { result(true) }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "CACHE_CLEAR_FAILED",
                        message: error.localizedDescription,
                        details: nil
                    ))
                }
            }
        }
    }

    @available(iOS 17.0, *)
    private func removeBackground(
        imagePath: String,
        cropToSubject: Bool,
        writeToCache: Bool,
        featherRadius: Double,
        edgeErode: Int,
        result: @escaping FlutterResult
    ) {
        // Check if running on simulator - Neural Engine not available
        #if targetEnvironment(simulator)
        result(FlutterError(
            code: "PROCESSING_FAILED",
            message: "Background removal requires a real iOS device (Neural Engine not available on Simulator)",
            details: nil
        ))
        return
        #endif

        DispatchQueue.global(qos: .userInitiated).async {
            // Load and fix image orientation
            guard let uiImage = UIImage(contentsOfFile: imagePath),
                  let fixedImage = self.fixImageOrientation(uiImage),
                  let cgImage = fixedImage.cgImage else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "INVALID_INPUT", message: "Could not load image at path: \(imagePath)", details: nil))
                }
                return
            }

            // Create foreground mask request
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "PROCESSING_FAILED", message: "Vision request failed: \(error.localizedDescription)", details: nil))
                }
                return
            }

            guard let observation = request.results?.first else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "NO_SUBJECT", message: "No foreground subject detected in image", details: nil))
                }
                return
            }

            // Generate mask for all instances
            let allInstances = observation.allInstances
            guard !allInstances.isEmpty else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "NO_SUBJECT", message: "No foreground instances found", details: nil))
                }
                return
            }

            do {
                let maskPixelBuffer = try observation.generateScaledMaskForImage(forInstances: allInstances, from: handler)

                // Apply mask directly to create cutout image
                guard let cutoutImage = self.applyMask(
                    sourceImage: cgImage,
                    maskBuffer: maskPixelBuffer,
                    cropToSubject: cropToSubject,
                    featherRadius: featherRadius,
                    edgeErode: edgeErode
                ) else {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "PROCESSING_FAILED", message: "Could not apply mask", details: nil))
                    }
                    return
                }

                // Convert to PNG data
                let outputUIImage = UIImage(cgImage: cutoutImage)
                guard let pngData = outputUIImage.pngData() else {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "PROCESSING_FAILED", message: "Could not encode PNG", details: nil))
                    }
                    return
                }

                if writeToCache {
                    do {
                        let dir = self.cacheDirectory()
                        try FileManager.default.createDirectory(
                            at: dir,
                            withIntermediateDirectories: true
                        )
                        let fileUrl = dir.appendingPathComponent("cutout_\(UUID().uuidString).png")
                        try pngData.write(to: fileUrl, options: .atomic)
                        DispatchQueue.main.async { result(fileUrl.path) }
                    } catch {
                        DispatchQueue.main.async {
                            result(FlutterError(
                                code: "PROCESSING_FAILED",
                                message: "Failed to write PNG to cache: \(error.localizedDescription)",
                                details: nil
                            ))
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        result(FlutterStandardTypedData(bytes: pngData))
                    }
                }

            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "PROCESSING_FAILED", message: "Mask generation failed: \(error.localizedDescription)", details: nil))
                }
            }
        }
    }

    /// Fixes image orientation based on EXIF data
    private func fixImageOrientation(_ image: UIImage) -> UIImage? {
        guard image.imageOrientation != .up else { return image }

        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return normalizedImage
    }

    /// Refines the alpha matte: optional erosion to remove a thin background
    /// fringe, then an optional Gaussian feather for a clean, soft edge.
    private func refineMask(_ mask: CIImage, edgeErode: Int, featherRadius: Double) -> CIImage {
        var refined = mask
        let extent = mask.extent

        if edgeErode > 0, let erode = CIFilter(name: "CIMorphologyMinimum") {
            erode.setValue(refined, forKey: kCIInputImageKey)
            erode.setValue(Double(edgeErode), forKey: "inputRadius")
            if let out = erode.outputImage {
                refined = out.cropped(to: extent)
            }
        }

        if featherRadius > 0, let blur = CIFilter(name: "CIGaussianBlur") {
            // Clamp first so the blur doesn't fade the matte at the image border.
            blur.setValue(refined.clampedToExtent(), forKey: kCIInputImageKey)
            blur.setValue(featherRadius, forKey: "inputRadius")
            if let out = blur.outputImage {
                refined = out.cropped(to: extent)
            }
        }

        return refined
    }

    /// Applies mask to source image and optionally trims transparent pixels.
    private func applyMask(
        sourceImage: CGImage,
        maskBuffer: CVPixelBuffer,
        cropToSubject: Bool,
        featherRadius: Double = 0,
        edgeErode: Int = 0
    ) -> CGImage? {
        // First, create masked image using CIFilter (reliable blending)
        let rawMaskCIImage = CIImage(cvPixelBuffer: maskBuffer)
        let maskCIImage = refineMask(
            rawMaskCIImage,
            edgeErode: edgeErode,
            featherRadius: featherRadius
        )
        let sourceCIImage = CIImage(cgImage: sourceImage)
        let transparentBackground = CIImage.empty()

        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            return nil
        }

        blendFilter.setValue(sourceCIImage, forKey: kCIInputImageKey)
        blendFilter.setValue(transparentBackground, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(maskCIImage, forKey: kCIInputMaskImageKey)

        guard let outputCIImage = blendFilter.outputImage else {
            return nil
        }

        // Render to CGImage
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let maskedImage = context.createCGImage(outputCIImage, from: outputCIImage.extent) else {
            return nil
        }

        guard cropToSubject else {
            return maskedImage
        }

        // Trim transparent pixels using vImage when requested.
        return trimTransparentPixelsWithVImage(maskedImage)
    }

    /// Trims transparent pixels using vImage (Accelerate framework)
    private func trimTransparentPixelsWithVImage(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height

        // Create vImage format for ARGB8888
        var format = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: nil,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue),
            version: 0,
            decode: nil,
            renderingIntent: .defaultIntent
        )

        // Create source buffer from CGImage
        var sourceBuffer = vImage_Buffer()
        var error = vImageBuffer_InitWithCGImage(
            &sourceBuffer,
            &format,
            nil,
            image,
            vImage_Flags(kvImageNoFlags)
        )

        guard error == kvImageNoError else {
            return nil
        }
        defer { free(sourceBuffer.data) }

        // Access pixel data to find bounding box
        let data = sourceBuffer.data.assumingMemoryBound(to: UInt8.self)
        let rowBytes = sourceBuffer.rowBytes

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0

        // Alpha threshold (ARGB format, alpha is first byte)
        let alphaThreshold: UInt8 = 10

        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * rowBytes + x * 4
                let alpha = data[pixelIndex] // ARGB: alpha is first

                if alpha > alphaThreshold {
                    if x < minX { minX = x }
                    if y < minY { minY = y }
                    if x > maxX { maxX = x }
                    if y > maxY { maxY = y }
                }
            }
        }

        // Check if we found any non-transparent pixels
        guard maxX >= minX && maxY >= minY else {
            return nil
        }

        // Calculate crop dimensions
        let cropWidth = maxX - minX + 1
        let cropHeight = maxY - minY + 1
        let cropRect = CGRect(x: minX, y: minY, width: cropWidth, height: cropHeight)

        // Create cropped buffer
        var croppedBuffer = vImage_Buffer()
        error = vImageBuffer_Init(
            &croppedBuffer,
            vImagePixelCount(cropHeight),
            vImagePixelCount(cropWidth),
            32,
            vImage_Flags(kvImageNoFlags)
        )

        guard error == kvImageNoError else {
            return nil
        }
        defer { free(croppedBuffer.data) }

        // Copy cropped region
        let croppedData = croppedBuffer.data.assumingMemoryBound(to: UInt8.self)
        let croppedRowBytes = croppedBuffer.rowBytes

        for y in 0..<cropHeight {
            let srcRow = data.advanced(by: (minY + y) * rowBytes + minX * 4)
            let dstRow = croppedData.advanced(by: y * croppedRowBytes)
            memcpy(dstRow, srcRow, cropWidth * 4)
        }

        // Create CGImage from cropped buffer
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var outputFormat = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: Unmanaged.passUnretained(colorSpace),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue),
            version: 0,
            decode: nil,
            renderingIntent: .defaultIntent
        )

        var vImageError: vImage_Error = kvImageNoError
        let result = vImageCreateCGImageFromBuffer(
            &croppedBuffer,
            &outputFormat,
            nil,
            nil,
            vImage_Flags(kvImageNoFlags),
            &vImageError
        )

        guard vImageError == kvImageNoError else {
            return nil
        }

        return result?.takeRetainedValue()
    }
}
