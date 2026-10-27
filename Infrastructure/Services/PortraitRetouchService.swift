import Foundation
import CoreGraphics
import CoreImage
import Vision

/// High-performance portrait beauty, skin softening, red-eye correction, and blemish healing service
public final class PortraitRetouchService: @unchecked Sendable {
    public static let shared = PortraitRetouchService()
    
    private let ciContext: CIContext
    
    private init() {
        self.ciContext = CIContext(options: SystemHardwareProfile.shared.createCIContextOptions())
    }
    
    /// Apply full portrait beauty pipeline: Red-Eye Correction -> Spot Healing -> Skin Smoothing & Tone Protection
    public func applyPortraitRetouch(to inputImage: CIImage, params: LightCorrectionParams, baseCGImage: CGImage? = nil) -> CIImage {
        var processed = inputImage
        
        // 1. Red-Eye Correction (Vision & Pupil Specular Neutralizer)
        if params.redEyeCorrection {
            processed = correctRedEye(in: processed, baseCGImage: baseCGImage)
        }
        
        // 2. Spot & Blemish Healing
        if !params.spotRemovals.isEmpty {
            processed = healSpots(in: processed, spots: params.spotRemovals)
        }
        
        // 3. Edge-Preserving Skin Smoothing & Tone Protection
        if params.skinSmoothing > 0.01 || params.skinToneProtection > 0.1 {
            processed = smoothSkinAndProtectTone(in: processed, smoothingAmount: params.skinSmoothing, toneProtection: params.skinToneProtection)
        }
        
        return processed
    }
    
    // MARK: - 1. Red-Eye Correction
    
    /// Detect face eye landmarks and neutralize abnormal red pupil reflection
    public func correctRedEye(in image: CIImage, baseCGImage: CGImage?) -> CIImage {
        guard let cgImage = baseCGImage ?? ciContext.createCGImage(image, from: image.extent) else {
            return image
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let faceRequest = VNDetectFaceLandmarksRequest()
        do {
            try handler.perform([faceRequest])
        } catch {
            return image
        }
        
        guard let faces = faceRequest.results, !faces.isEmpty else {
            return image
        }
        
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        
        var pupilCenters: [CGPoint] = []
        
        for face in faces {
            guard let landmarks = face.landmarks else { continue }
            let bbox = face.boundingBox
            
            // Left eye / pupil
            if let leftPupil = landmarks.leftPupil {
                for pt in leftPupil.normalizedPoints {
                    let cx = (bbox.origin.x + pt.x * bbox.width) * width
                    let cy = (bbox.origin.y + pt.y * bbox.height) * height
                    pupilCenters.append(CGPoint(x: cx, y: cy))
                }
            } else if let leftEye = landmarks.leftEye {
                let pts = leftEye.normalizedPoints
                if !pts.isEmpty {
                    let avgX = pts.map(\.x).reduce(0, +) / CGFloat(pts.count)
                    let avgY = pts.map(\.y).reduce(0, +) / CGFloat(pts.count)
                    let cx = (bbox.origin.x + avgX * bbox.width) * width
                    let cy = (bbox.origin.y + avgY * bbox.height) * height
                    pupilCenters.append(CGPoint(x: cx, y: cy))
                }
            }
            
            // Right eye / pupil
            if let rightPupil = landmarks.rightPupil {
                for pt in rightPupil.normalizedPoints {
                    let cx = (bbox.origin.x + pt.x * bbox.width) * width
                    let cy = (bbox.origin.y + pt.y * bbox.height) * height
                    pupilCenters.append(CGPoint(x: cx, y: cy))
                }
            } else if let rightEye = landmarks.rightEye {
                let pts = rightEye.normalizedPoints
                if !pts.isEmpty {
                    let avgX = pts.map(\.x).reduce(0, +) / CGFloat(pts.count)
                    let avgY = pts.map(\.y).reduce(0, +) / CGFloat(pts.count)
                    let cx = (bbox.origin.x + avgX * bbox.width) * width
                    let cy = (bbox.origin.y + avgY * bbox.height) * height
                    pupilCenters.append(CGPoint(x: cx, y: cy))
                }
            }
        }
        
        guard !pupilCenters.isEmpty else { return image }
        
        // Neutralize red specular around pupil centers
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = cgImage.width * 4
        var pixelData = [UInt8](repeating: 0, count: cgImage.height * bytesPerRow)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let ctx = CGContext(
            data: &pixelData,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return image }
        
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        
        let pupilRadius = max(6.0, min(35.0, min(width, height) * 0.015))
        var didCorrect = false
        
        for pupil in pupilCenters {
            let px = Int(pupil.x)
            let py = Int(pupil.y)
            let rInt = Int(ceil(pupilRadius))
            
            let minX = max(0, px - rInt)
            let maxX = min(cgImage.width - 1, px + rInt)
            let minY = max(0, py - rInt)
            let maxY = min(cgImage.height - 1, py + rInt)
            
            for y in minY...maxY {
                let row = y * bytesPerRow
                for x in minX...maxX {
                    let dx = CGFloat(x - px)
                    let dy = CGFloat(y - py)
                    let dist = sqrt(dx * dx + dy * dy)
                    if dist <= pupilRadius {
                        let offset = row + x * 4
                        let r = Float(pixelData[offset])
                        let g = Float(pixelData[offset + 1])
                        let b = Float(pixelData[offset + 2])
                        
                        // Check if pixel exhibits abnormal red dominance (red eye flash reflection)
                        let maxGB = max(g, b)
                        if r > maxGB * 1.35 && r > 75.0 {
                            let dark = UInt8(max(10.0, min(65.0, Double(maxGB) * 0.55)))
                            let falloff = Float(1.0 - (dist / pupilRadius))
                            let newR = UInt8(Float(r) * (1.0 - falloff) + Float(dark) * falloff)
                            pixelData[offset] = newR
                            pixelData[offset + 1] = dark
                            pixelData[offset + 2] = dark
                            didCorrect = true
                        }
                    }
                }
            }
        }
        
        guard didCorrect, let correctedCG = ctx.makeImage() else {
            return image
        }
        return CIImage(cgImage: correctedCG)
    }
    
    // MARK: - 2. Spot & Blemish Healing
    
    /// Pure GPU-accelerated seamless texture-cloning and blemish inpainting
    public func healSpots(in image: CIImage, spots: [SpotRemovalItem]) -> CIImage {
        guard !spots.isEmpty else { return image }
        
        let extent = image.extent
        guard extent.width > 0 && extent.height > 0 else { return image }
        
        var currentImage = image
        let minDim = min(extent.width, extent.height)
        
        for spot in spots {
            let cx = extent.origin.x + spot.normalizedX * extent.width
            let cy = extent.origin.y + spot.normalizedY * extent.height
            let pixelRadius = max(8.0, spot.radius * minDim)
            
            // 1. Sample clean adjacent texture patch (diagonal offset 1.0 * r in X & Y, distance ~1.414r)
            let dx = (cx + pixelRadius * 1.5 < extent.maxX - 10) ? pixelRadius * 1.0 : -pixelRadius * 1.0
            let dy = (cy + pixelRadius * 1.5 < extent.maxY - 10) ? pixelRadius * 1.0 : -pixelRadius * 1.0
            let sourcePatch = currentImage.transformed(by: CGAffineTransform(translationX: -dx, y: -dy))
            
            // 2. Feathered radial gradient mask centered on the blemish (inner 80% solid inpaint, outer 38% feathered)
            guard let radialFilter = CIFilter(name: "CIRadialGradient") else { continue }
            radialFilter.setValue(CIVector(x: cx, y: cy), forKey: "inputCenter")
            radialFilter.setValue(Double(pixelRadius) * 0.80, forKey: "inputRadius0")
            radialFilter.setValue(Double(pixelRadius) * 1.18, forKey: "inputRadius1")
            radialFilter.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 1), forKey: "inputColor0")
            radialFilter.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0), forKey: "inputColor1")
            
            guard let radialMask = radialFilter.outputImage?.cropped(to: extent) else { continue }
            
            // 3. GPU Masked Composite: Blend healthy adjacent skin texture into the blemish spot
            currentImage = sourcePatch.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: currentImage,
                kCIInputMaskImageKey: radialMask
            ])
        }
        
        return currentImage
    }
    
    // MARK: - 3. Edge-Preserving Skin Smoothing & Tone Protection
    
    /// Edge-preserving bilateral skin smoothing that softens pores and blemishes while keeping eyes, eyelashes, and lips sharp
    public func smoothSkinAndProtectTone(in image: CIImage, smoothingAmount: Float, toneProtection: Float) -> CIImage {
        guard smoothingAmount > 0.01 || toneProtection > 0.1 else { return image }
        
        // Step A: Generate Edge-Preserving Smoothed Image via Guided Filter
        let radius = max(2.0, Double(smoothingAmount * 9.0 + 3.0))
        let blur = image.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius]).cropped(to: image.extent)
        let guided = blur.applyingFilter("CIGuidedFilter", parameters: [
            "inputGuideImage": image,
            "inputRadius": radius,
            "inputEpsilon": 0.015
        ])
        
        // Step B: Subtle pore-refining noise reduction
        let smoothedLayer = guided.applyingFilter("CINoiseReduction", parameters: [
            "inputNoiseLevel": Double(smoothingAmount * 0.05),
            "inputSharpness": 0.5
        ])
        
        // Step C: Skin Chromaticity Mask Extraction
        // Human skin tone in RGB normalized space: R > G > B, Saturation 0.15 ~ 0.65, Hue in 15°..45°
        // We isolate skin so that non-skin areas (eyes, hair, background) are 100% untouched.
        let skinToneMatrix = image
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.0, y: -0.6, z: -0.4, w: 0),
                "inputGVector": CIVector(x: 0, y: 1.0, z: -0.8, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0.8, y: 0.4, z: -0.6, w: 0)
            ])
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])
        
        let softMask = skinToneMatrix.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 4.0]).cropped(to: image.extent)
        
        // Step D: Blend smoothed layer with original based on skin mask and smoothing amount
        let blendedSmooth = smoothedLayer.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: image,
            kCIInputMaskImageKey: softMask.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.2, kCIInputBrightnessKey: Double(smoothingAmount * 0.4 - 0.2)])
        ])
        
        // Step E: Skin Tone Protection (preserve rosy warmth in skin regions)
        if toneProtection > 0.15 {
            let warmSkinOverlay = blendedSmooth.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: CGFloat(6500 + (toneProtection * 180.0)), y: CGFloat(toneProtection * 5.0)),
                "inputTargetNeutral": CIVector(x: 6500, y: 0)
            ])
            return blendedSmooth.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: warmSkinOverlay,
                kCIInputMaskImageKey: softMask.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: Double(toneProtection * 0.2 - 0.5)])
            ])
        }
        
        return blendedSmooth
    }
}
