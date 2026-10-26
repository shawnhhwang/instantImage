import Foundation
import CoreGraphics
import CoreImage

/// Individual spot / blemish removal patch storing normalized center coordinates (0.0...1.0) and pixel/normalized radius
public struct SpotRemovalItem: Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var normalizedX: CGFloat // 0.0 to 1.0 (relative to image width)
    public var normalizedY: CGFloat // 0.0 to 1.0 (relative to image height)
    public var radius: CGFloat      // in normalized units (0.005 to 0.10)
    
    public init(id: UUID = UUID(), normalizedX: CGFloat, normalizedY: CGFloat, radius: CGFloat = 0.02) {
        self.id = id
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.radius = radius
    }
}

/// Light, Color, and Portrait Beauty adjustment parameters mimicking Adobe Lightroom and nEOiMAGING
public struct LightCorrectionParams: Equatable, Hashable, Sendable {
    // Tone adjustments
    public var exposure: Float    // -2.0 to +2.0 (EV stops)
    public var contrast: Float    // 0.5 to 1.5 (1.0 = neutral)
    public var highlights: Float  // -1.0 to 1.0 (recovers blown highlights or adds pop)
    public var shadows: Float     // -1.0 to 1.0 (lifts dark shadows or deepens blacks)
    
    // Feature A: White Balance (Temperature & Tint)
    // temperature: neutral is 6500K. Stored as offset: -2000K (cool/blue) to +2000K (warm/yellow)
    public var temperature: Float // -2000 to +2000
    // tint: neutral is 0. Stored as offset: -100 (green) to +100 (magenta)
    public var tint: Float        // -100 to +100
    
    // Feature B: Portrait Beauty & Skin Tone Protection
    public var skinToneProtection: Float // 0.0 to 1.0 (0.6 = default recommended protection)
    public var skinSmoothing: Float      // 0.0 to 1.0 (0 = off, 1.0 = maximum smooth porcelain)
    public var redEyeCorrection: Bool    // true = automatically neutralize pupil red glare
    public var spotRemovals: [SpotRemovalItem] // user-placed spot/blemish heals
    
    public init(
        exposure: Float = 0.0,
        contrast: Float = 1.0,
        highlights: Float = 0.0,
        shadows: Float = 0.0,
        temperature: Float = 0.0,
        tint: Float = 0.0,
        skinToneProtection: Float = 0.6,
        skinSmoothing: Float = 0.0,
        redEyeCorrection: Bool = false,
        spotRemovals: [SpotRemovalItem] = []
    ) {
        self.exposure = exposure
        self.contrast = contrast
        self.highlights = highlights
        self.shadows = shadows
        self.temperature = temperature
        self.tint = tint
        self.skinToneProtection = skinToneProtection
        self.skinSmoothing = skinSmoothing
        self.redEyeCorrection = redEyeCorrection
        self.spotRemovals = spotRemovals
    }
    
    public static let neutral = LightCorrectionParams()
    
    public var isNeutral: Bool {
        return abs(exposure) < 0.001 &&
               abs(contrast - 1.0) < 0.001 &&
               abs(highlights) < 0.001 &&
               abs(shadows) < 0.001 &&
               abs(temperature) < 1.0 &&
               abs(tint) < 1.0 &&
               skinSmoothing < 0.01 &&
               !redEyeCorrection &&
               spotRemovals.isEmpty
    }
}

/// Comprehensive photographic analysis results capturing luminance histograms, multi-zone chrominance, and skin tone pools.
public struct RGBAnalysisResult: Sendable {
    public let histogram: [Int]
    public let totalPixels: Int
    public let avgR: Float
    public let avgG: Float
    public let avgB: Float
    
    // Quasi-neutral candidate pool (Low chroma / near-gray reference surfaces)
    public let neutralAvgR: Float
    public let neutralAvgG: Float
    public let neutralAvgB: Float
    public let neutralCount: Int
    
    // White-patch specular candidate pool (High luminance, low saturation)
    public let whitePatchAvgR: Float
    public let whitePatchAvgG: Float
    public let whitePatchAvgB: Float
    public let whitePatchCount: Int
    
    // Skin-tone candidate pool (Human skin chrominance corridor)
    public let skinAvgR: Float
    public let skinAvgG: Float
    public let skinAvgB: Float
    public let skinCount: Int
    
    public init(
        histogram: [Int],
        totalPixels: Int,
        avgR: Float,
        avgG: Float,
        avgB: Float,
        neutralAvgR: Float = 128.0,
        neutralAvgG: Float = 128.0,
        neutralAvgB: Float = 128.0,
        neutralCount: Int = 0,
        whitePatchAvgR: Float = 128.0,
        whitePatchAvgG: Float = 128.0,
        whitePatchAvgB: Float = 128.0,
        whitePatchCount: Int = 0,
        skinAvgR: Float = 180.0,
        skinAvgG: Float = 140.0,
        skinAvgB: Float = 120.0,
        skinCount: Int = 0
    ) {
        self.histogram = histogram
        self.totalPixels = totalPixels
        self.avgR = avgR
        self.avgG = avgG
        self.avgB = avgB
        self.neutralAvgR = neutralAvgR
        self.neutralAvgG = neutralAvgG
        self.neutralAvgB = neutralAvgB
        self.neutralCount = neutralCount
        self.whitePatchAvgR = whitePatchAvgR
        self.whitePatchAvgG = whitePatchAvgG
        self.whitePatchAvgB = whitePatchAvgB
        self.whitePatchCount = whitePatchCount
        self.skinAvgR = skinAvgR
        self.skinAvgG = skinAvgG
        self.skinAvgB = skinAvgB
        self.skinCount = skinCount
    }
}

/// Professional tone, white-balance, and portrait beauty calibration engine adhering to Adobe Lightroom and classic nEOiMAGING (光影魔術手) standards.
public enum AutoLightCorrector {
    
    /// Analyze an unnormalized raw bin count histogram (256 bins) to determine optimal exposure, contrast, highlights and shadows.
    /// Incorporates Ansel Adams Zone System midtone calibration, highlight headroom protection, and filmic rolloff.
    public static func analyze(histogram: [Int], totalPixelCount: Int) -> LightCorrectionParams {
        guard totalPixelCount > 0 else { return .neutral }
        
        var cumulative = 0
        var p05: Float = 0    // 0.5th percentile (extreme black floor)
        var p1: Float = 0     // 1st percentile (shadow clipping)
        var p5: Float = 0     // 5th percentile
        var p10: Float = 0    // 10th percentile (lower midtones)
        var p25: Float = 0    // 25th percentile
        var p50: Float = 128  // 50th percentile (median luminance)
        var p75: Float = 180  // 75th percentile
        var p90: Float = 220  // 90th percentile
        var p95: Float = 240  // 95th percentile
        var p98: Float = 250  // 98th percentile (highlight ceiling)
        var p995: Float = 255 // 99.5th percentile (specular peak)
        
        var sumLuminance: Double = 0
        var shadowPixelCount = 0
        var highlightPixelCount = 0
        
        for (binIndex, count) in histogram.enumerated() {
            let lum = Float(binIndex)
            sumLuminance += Double(binIndex * count)
            cumulative += count
            let ratio = Float(cumulative) / Float(totalPixelCount)
            
            if p05 == 0 && ratio >= 0.005 { p05 = lum }
            if p1 == 0 && ratio >= 0.01 { p1 = lum }
            if p5 == 0 && ratio >= 0.05 { p5 = lum }
            if p10 == 0 && ratio >= 0.10 { p10 = lum }
            if p25 == 0 && ratio >= 0.25 { p25 = lum }
            if p50 == 128 && ratio >= 0.50 { p50 = lum }
            if p75 == 180 && ratio >= 0.75 { p75 = lum }
            if p90 == 220 && ratio >= 0.90 { p90 = lum }
            if p95 == 240 && ratio >= 0.95 { p95 = lum }
            if p98 == 250 && ratio >= 0.98 { p98 = lum }
            if p995 == 255 && ratio >= 0.995 { p995 = lum }
            
            if binIndex < 35 { shadowPixelCount += count }
            if binIndex > 220 { highlightPixelCount += count }
        }
        
        let meanLuminance = Float(sumLuminance / Double(totalPixelCount))
        let shadowFrac = Float(shadowPixelCount) / Float(totalPixelCount)
        let highlightFrac = Float(highlightPixelCount) / Float(totalPixelCount)
        let midtoneCurrent = (p50 * 0.65) + (meanLuminance * 0.35)
        
        // 1. Dynamic Scene Key Detection (Low-key / Mid-key / High-key)
        // Calibrated to 104.0 for standard sRGB scenes (~18% reflectance perceptual display gamma)
        var targetMidtone: Float = 104.0
        if shadowFrac > 0.45 && p50 < 75.0 {
            // Low-key / dark background: preserve mood and avoid washing out darks
            targetMidtone = max(68.0, p50 * 1.15)
        } else if highlightFrac > 0.35 && p50 > 135.0 {
            // High-key / snow / bright studio scene: avoid dulling highlights
            targetMidtone = min(138.0, p50 * 0.96)
        }
        
        // 2. Exposure with Highlight Headroom Guard (Prevents Over-brightening & Clipping)
        let rawEV = log2(targetMidtone / max(12.0, midtoneCurrent))
        var exposureEV: Float = 0.0
        
        // Headroom ceiling: p98 must not be pushed past 250
        let maxSafeEV = p98 > 180.0 ? max(0.0, log2(250.0 / p98)) : 0.75
        
        if rawEV > 0 {
            // Brighten with progressive logarithmic damping and strict headroom guard
            exposureEV = min(rawEV * 0.55, maxSafeEV)
            exposureEV = min(0.65, exposureEV)
        } else {
            // Darken overexposed image with responsive correction
            exposureEV = max(-1.15, rawEV * 0.70)
        }
        if abs(exposureEV) < 0.04 { exposureEV = 0.0 }
        
        // 3. Filmic Highlight Recovery (nEOiMAGING / Lightroom highlight preservation)
        var highlights: Float = 0.0
        if p95 > 225.0 || p995 > 248.0 {
            let excess = (p95 - 215.0) / 40.0
            highlights = -min(0.38, max(0.08, excess * 0.35))
        } else if p95 < 170.0 && exposureEV > 0.10 {
            highlights = 0.10
        }
        
        // 4. Shadows & Black Point Anchor (Prevents foggy blacks while rescuing crushed shadows)
        var shadows: Float = 0.0
        if p10 < 20.0 && p1 < 8.0 {
            let deficit = (20.0 - p10) / 20.0
            shadows = min(0.30, deficit * 0.32)
        } else if p1 > 22.0 && shadowFrac < 0.08 {
            shadows = -min(0.15, (p1 - 18.0) / 35.0)
        }
        
        // 5. Dynamic Micro-Contrast Adjustment
        let dynamicRange = p95 - p5
        var contrast: Float = 1.0
        if dynamicRange < 125.0 {
            contrast = min(1.18, 1.0 + (125.0 - dynamicRange) / 220.0)
        } else if dynamicRange > 225.0 {
            contrast = max(0.92, 1.0 - (dynamicRange - 225.0) / 350.0)
        }
        
        return LightCorrectionParams(
            exposure: exposureEV,
            contrast: contrast,
            highlights: highlights,
            shadows: shadows,
            temperature: 0.0,
            tint: 0.0
        )
    }
    
    /// Multi-tier Quasi-Neutral and White-Patch Illuminant Estimator for Auto White Balance with Skin Tone Protection.
    /// Accurately eliminates yellow and color casts without sterilizing natural scene ambiance or human skin tones.
    public static func analyzeWhiteBalance(rgbResult: RGBAnalysisResult) -> (temperature: Float, tint: Float) {
        let minNeutralRequired = max(25, rgbResult.totalPixels / 200)
        let illR: Float
        let illG: Float
        let illB: Float
        
        if rgbResult.neutralCount >= minNeutralRequired {
            illR = rgbResult.neutralAvgR
            illG = rgbResult.neutralAvgG
            illB = rgbResult.neutralAvgB
        } else if rgbResult.whitePatchCount >= 20 {
            illR = rgbResult.whitePatchAvgR
            illG = rgbResult.whitePatchAvgG
            illB = rgbResult.whitePatchAvgB
        } else {
            illR = rgbResult.avgR
            illG = rgbResult.avgG
            illB = rgbResult.avgB
        }
        
        var (temp, tint) = analyzeWhiteBalanceFromIlluminant(avgR: illR, avgG: illG, avgB: illB)
        
        // Feature: Skin Tone Protection (protect warmth and rosiness of human skin)
        if rgbResult.skinCount > max(30, rgbResult.totalPixels / 50) {
            // Scene contains prominent human skin.
            // Check if aggressive cooling would turn skin pale or cyan
            let skinRG = rgbResult.skinAvgR / max(1.0, rgbResult.skinAvgG)
            let skinBG = rgbResult.skinAvgB / max(1.0, rgbResult.skinAvgG)
            
            // If skin is already close to neutral or cool, avoid excessive negative temp
            if temp < -200.0 && (skinRG - skinBG) < 0.40 {
                // Dampen cooling to preserve natural skin tones
                temp *= 0.65
            }
            
            // Protect tint from excessive magenta or green that makes faces look sick
            tint = max(-25.0, min(25.0, tint))
        }
        
        return (temp, tint)
    }
    
    /// Legacy fallback method using direct RGB averages
    public static func analyzeWhiteBalance(avgR: Float, avgG: Float, avgB: Float) -> (temperature: Float, tint: Float) {
        return analyzeWhiteBalanceFromIlluminant(avgR: avgR, avgG: avgG, avgB: avgB)
    }
    
    private static func analyzeWhiteBalanceFromIlluminant(avgR: Float, avgG: Float, avgB: Float) -> (temperature: Float, tint: Float) {
        guard avgG > 1.0 else { return (0.0, 0.0) }
        
        let rRatio = avgR / avgG
        let bRatio = avgB / avgG
        
        // Color Cast Delta:
        // In our unified Lightroom convention (matching inputNeutral = 6500 + tempOffset):
        // If image has warm/yellow cast (R > B): (bRatio - rRatio) is negative.
        // A negative tempOffset shifts cooler (adds blue), neutralizing the yellow cast!
        // If image has cool/blue cast (B > R): (bRatio - rRatio) is positive.
        // A positive tempOffset shifts warmer (adds amber), neutralizing the blue cast!
        let colorCast = bRatio - rRatio
        
        // Apply 78% perceptual chromatic adaptation (Lightroom standard preserves natural warmth)
        let damping: Float = 0.78
        var targetTemp = colorCast * 1800.0 * damping
        targetTemp = max(-1400.0, min(1400.0, targetTemp))
        if abs(targetTemp) < 15.0 { targetTemp = 0.0 }
        
        // Tint: Green vs Magenta balance
        // If G is higher than expected -> green cast -> positive tint (magenta correction)
        // If G is lower than expected -> magenta cast -> negative tint (green correction)
        let expectedG = (avgR + avgB) * 0.5
        let tintDiff = (expectedG - avgG) / max(1.0, avgG)
        var targetTint = tintDiff * 70.0 * damping
        targetTint = max(-45.0, min(45.0, targetTint))
        if abs(targetTint) < 1.0 { targetTint = 0.0 }
        
        return (targetTemp, targetTint)
    }
    
    /// Full analysis of both light exposure and auto white balance
    public static func analyzeFull(rgbResult: RGBAnalysisResult) -> LightCorrectionParams {
        var params = analyze(histogram: rgbResult.histogram, totalPixelCount: rgbResult.totalPixels)
        let (temp, tint) = analyzeWhiteBalance(rgbResult: rgbResult)
        params.temperature = temp
        params.tint = tint
        return params
    }
}
