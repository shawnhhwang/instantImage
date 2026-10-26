import Foundation
import ImageIO
import AppKit

public final class ImageLoaderService: Sendable {
    public static let shared = ImageLoaderService()
    
    // Dynamically tuned concurrency limiters based on host architecture (Apple Silicon vs Intel)
    private let thumbnailLimiter = ConcurrencyLimiter(maxConcurrency: SystemHardwareProfile.shared.recommendedThumbnailConcurrency)
    private let metadataLimiter = ConcurrencyLimiter(maxConcurrency: SystemHardwareProfile.shared.recommendedMetadataConcurrency)
    
    private init() {}
    
    /// Generates a thumbnail for a given image URL using ImageIO
    /// - Parameters:
    ///   - url: The image file URL
    ///   - maxPixelSize: The target pixel size (width/height) of the thumbnail
    /// - Returns: A CGImage representing the thumbnail
    public func loadThumbnail(from url: URL, maxPixelSize: Int = 256) async throws -> CGImage {
        await thumbnailLimiter.enter()
        do {
            let thumbnail = try await Task.detached(priority: .userInitiated) {
                return try SecurityScopedBookmarkManager.shared.performAccessingSecurityScopedResource(at: url) {
                    let options: [CFString: Any] = [
                        kCGImageSourceShouldCache: false,
                        kCGImageSourceShouldAllowFloat: true
                    ]
                    
                    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
                        throw NSError(domain: "ImageLoaderService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create image source for \(url.path)"])
                    }
                    
                    let thumbnailOptions: [CFString: Any] = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceShouldCacheImmediately: true
                    ]
                    
                    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions as CFDictionary) else {
                        throw NSError(domain: "ImageLoaderService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to generate thumbnail at index 0 for \(url.path)"])
                    }
                    
                    return thumbnail
                }
            }.value
            await thumbnailLimiter.exit()
            return thumbnail
        } catch {
            await thumbnailLimiter.exit()
            throw error
        }
    }
    
    public func extractMetadata(from url: URL, creationDate: Date? = nil, sizeBytes: Int64 = 0) async throws -> ImageMetadata {
        await metadataLimiter.enter()
        do {
            let metadata = try await Task.detached(priority: .userInitiated) {
                return try SecurityScopedBookmarkManager.shared.performAccessingSecurityScopedResource(at: url) {
                    let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
                    
                    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
                        throw NSError(domain: "ImageLoaderService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create image source for \(url.path)"])
                    }
                    
                    let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] ?? [:]
                    
                    // Get basic dimensions
                    let width = properties[kCGImagePropertyPixelWidth] as? Int
                    let height = properties[kCGImagePropertyPixelHeight] as? Int
                    
                    // Parse EXIF dictionary
                    let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
                    let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
                    
                    let cameraMake = tiff[kCGImagePropertyTIFFMake] as? String
                    let cameraModel = tiff[kCGImagePropertyTIFFModel] as? String
                    
                    let isoArray = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int]
                    let iso = isoArray?.first ?? (exif[kCGImagePropertyExifISOSpeedRatings] as? Int)
                    
                    let aperture = exif[kCGImagePropertyExifFNumber] as? Double
                    let shutterSpeed = exif[kCGImagePropertyExifExposureTime] as? Double
                    
                    let id = url.path
                    let filename = url.lastPathComponent
                    
                    var rating = 0
                    var isTagged = false
                    if let xmpData = XmpMetadataWriter.readXmpSidecar(for: url) {
                        rating = xmpData.rating
                        isTagged = xmpData.isTagged
                    }
                    
                    return ImageMetadata(
                        id: id,
                        url: url,
                        filename: filename,
                        creationDate: creationDate,
                        sizeBytes: sizeBytes,
                        width: width,
                        height: height,
                        cameraMake: cameraMake,
                        cameraModel: cameraModel,
                        iso: iso,
                        aperture: aperture,
                        shutterSpeed: shutterSpeed,
                        hasThumbnail: true,
                        rating: rating,
                        isTagged: isTagged
                    )
                }
            }.value
            await metadataLimiter.exit()
            return metadata
        } catch {
            await metadataLimiter.exit()
            throw error
        }
    }
    
    /// High-performance luminance histogram calculation on a CGImage
    public func calculateLuminanceHistogram(for cgImage: CGImage) -> [Float] {
        let (bins, _) = calculateRawLuminanceHistogram(for: cgImage)
        let maxBin = Float(bins.max() ?? 1)
        return bins.map { Float($0) / maxBin }
    }
    
    /// Calculate raw bin counts, total pixels, and multi-tier chromaticity pools for White Balance
    public func calculateRGBAnalysis(for cgImage: CGImage) -> RGBAnalysisResult {
        let width = min(cgImage.width, 256)
        let height = max(1, Int(Float(cgImage.height) * (Float(width) / Float(cgImage.width))))
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)
        
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return RGBAnalysisResult(histogram: Array(repeating: 0, count: 256), totalPixels: 0, avgR: 128, avgG: 128, avgB: 128)
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var bins = Array(repeating: 0, count: 256)
        var totalPixels = 0
        var sumR: Double = 0
        var sumG: Double = 0
        var sumB: Double = 0
        
        var neutralR: Double = 0, neutralG: Double = 0, neutralB: Double = 0, neutralCount = 0
        var wpR: Double = 0, wpG: Double = 0, wpB: Double = 0, wpCount = 0
        var skinR: Double = 0, skinG: Double = 0, skinB: Double = 0, skinCount = 0
        
        for y in 0..<height {
            let rowOffset = y * bytesPerRow
            for x in 0..<width {
                let pixelOffset = rowOffset + x * bytesPerPixel
                let r = pixelData[pixelOffset]
                let g = pixelData[pixelOffset + 1]
                let b = pixelData[pixelOffset + 2]
                
                let flR = Float(r)
                let flG = Float(g)
                let flB = Float(b)
                
                sumR += Double(r)
                sumG += Double(g)
                sumB += Double(b)
                
                // Standard Luminosity Formula: Y = 0.299R + 0.587G + 0.114B
                let lum = 0.299 * flR + 0.587 * flG + 0.114 * flB
                let clampedLum = max(0, min(255, Int(lum)))
                bins[clampedLum] += 1
                totalPixels += 1
                
                let maxC = max(flR, max(flG, flB))
                let minC = min(flR, min(flG, flB))
                let sat = maxC > 0 ? (maxC - minC) / maxC : 0
                
                // Filter noise and extreme highlights for illuminant candidates
                if lum >= 15.0 && lum <= 252.0 {
                    // Candidate Pool 1: Quasi-neutral gray surface candidates (low saturation)
                    if sat < 0.16 && lum >= 28.0 && lum <= 235.0 {
                        neutralR += Double(r)
                        neutralG += Double(g)
                        neutralB += Double(b)
                        neutralCount += 1
                    }
                    
                    // Candidate Pool 2: White-patch specular highlights
                    if lum >= 195.0 && lum <= 250.0 && sat < 0.25 {
                        wpR += Double(r)
                        wpG += Double(g)
                        wpB += Double(b)
                        wpCount += 1
                    }
                    
                    // Candidate Pool 3: Human Skin Chrominance Corridor
                    if flR > flG && flG > flB && (flR - flG) >= 8.0 && (flG - flB) >= 4.0 && sat >= 0.12 && sat <= 0.68 && lum >= 30.0 && lum <= 235.0 {
                        skinR += Double(r)
                        skinG += Double(g)
                        skinB += Double(b)
                        skinCount += 1
                    }
                }
            }
        }
        
        let avgR = totalPixels > 0 ? Float(sumR / Double(totalPixels)) : 128.0
        let avgG = totalPixels > 0 ? Float(sumG / Double(totalPixels)) : 128.0
        let avgB = totalPixels > 0 ? Float(sumB / Double(totalPixels)) : 128.0
        
        let nR = neutralCount > 0 ? Float(neutralR / Double(neutralCount)) : 128.0
        let nG = neutralCount > 0 ? Float(neutralG / Double(neutralCount)) : 128.0
        let nB = neutralCount > 0 ? Float(neutralB / Double(neutralCount)) : 128.0
        
        let wR = wpCount > 0 ? Float(wpR / Double(wpCount)) : 128.0
        let wG = wpCount > 0 ? Float(wpG / Double(wpCount)) : 128.0
        let wB = wpCount > 0 ? Float(wpB / Double(wpCount)) : 128.0
        
        let sR = skinCount > 0 ? Float(skinR / Double(skinCount)) : 180.0
        let sG = skinCount > 0 ? Float(skinG / Double(skinCount)) : 140.0
        let sB = skinCount > 0 ? Float(skinB / Double(skinCount)) : 120.0
        
        return RGBAnalysisResult(
            histogram: bins,
            totalPixels: totalPixels,
            avgR: avgR,
            avgG: avgG,
            avgB: avgB,
            neutralAvgR: nR,
            neutralAvgG: nG,
            neutralAvgB: nB,
            neutralCount: neutralCount,
            whitePatchAvgR: wR,
            whitePatchAvgG: wG,
            whitePatchAvgB: wB,
            whitePatchCount: wpCount,
            skinAvgR: sR,
            skinAvgG: sG,
            skinAvgB: sB,
            skinCount: skinCount
        )
    }
    
    public func calculateRawLuminanceHistogram(for cgImage: CGImage) -> (bins: [Int], totalPixels: Int) {
        let result = calculateRGBAnalysis(for: cgImage)
        return (result.histogram, result.totalPixels)
    }
    
    /// Automatically analyze CGImage and return optimal Lightroom-like tone and white balance parameters
    public func calculateAutoLightCorrection(for cgImage: CGImage, includeWhiteBalance: Bool = false) -> LightCorrectionParams {
        let analysis = calculateRGBAnalysis(for: cgImage)
        if includeWhiteBalance {
            return AutoLightCorrector.analyzeFull(rgbResult: analysis)
        } else {
            return AutoLightCorrector.analyze(histogram: analysis.histogram, totalPixelCount: analysis.totalPixels)
        }
    }
    
    /// Calculate Auto White Balance parameters using multi-tier quasi-neutral illuminant estimation
    public func calculateAutoWhiteBalance(for cgImage: CGImage) -> (temperature: Float, tint: Float) {
        let analysis = calculateRGBAnalysis(for: cgImage)
        return AutoLightCorrector.analyzeWhiteBalance(rgbResult: analysis)
    }
}

/// Actor to limit the maximum number of concurrent asynchronous operations.
/// Safe, lightweight, and prevents thrashed cooperative thread pool in Swift concurrency.
public actor ConcurrencyLimiter: Sendable {
    private let maxConcurrency: Int
    private var activeCount = 0
    private var suspensions: [CheckedContinuation<Void, Never>] = []
    
    public init(maxConcurrency: Int) {
        self.maxConcurrency = maxConcurrency
    }
    
    public func enter() async {
        if activeCount < maxConcurrency {
            activeCount += 1
        } else {
            await withCheckedContinuation { continuation in
                suspensions.append(continuation)
            }
        }
    }
    
    public func exit() {
        if let next = suspensions.first {
            suspensions.removeFirst()
            next.resume()
        } else {
            activeCount -= 1
        }
    }
}
