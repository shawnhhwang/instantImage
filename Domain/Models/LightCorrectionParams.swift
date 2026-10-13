import Foundation
import CoreGraphics
import CoreImage

/// Light and Color adjustment parameters mimicking Adobe Lightroom's Basic Tone & Color panel
public struct LightCorrectionParams: Equatable, Hashable, Sendable {
    public var exposure: Float    // -2.0 to +2.0 (EV stops)
    public var contrast: Float    // 0.5 to 1.5 (1.0 = neutral)
    public var highlights: Float  // -1.0 to 1.0 (recovers blown highlights or adds pop)
    public var shadows: Float     // -1.0 to 1.0 (lifts dark shadows or deepens blacks)
    
    // Feature A: White Balance (Temperature & Tint)
    // temperature: neutral is 6500K. Stored as offset: -2000K (cool/blue) to +2000K (warm/yellow)
    public var temperature: Float // -2000 to +2000
    // tint: neutral is 0. Stored as offset: -100 (green) to +100 (magenta)
    public var tint: Float        // -100 to +100
    
    public init(
        exposure: Float = 0.0,
        contrast: Float = 1.0,
        highlights: Float = 0.0,
        shadows: Float = 0.0,
        temperature: Float = 0.0,
        tint: Float = 0.0
    ) {
        self.exposure = exposure
        self.contrast = contrast
        self.highlights = highlights
        self.shadows = shadows
        self.temperature = temperature
        self.tint = tint
    }
    
    public static let neutral = LightCorrectionParams()
    
    public var isNeutral: Bool {
        return abs(exposure) < 0.001 &&
               abs(contrast - 1.0) < 0.001 &&
               abs(highlights) < 0.001 &&
               abs(shadows) < 0.001 &&
               abs(temperature) < 1.0 &&
               abs(tint) < 1.0
    }
}

public struct RGBAnalysisResult: Sendable {
    public let histogram: [Int]
    public let totalPixels: Int
    public let avgR: Float
    public let avgG: Float
    public let avgB: Float
    
    public init(histogram: [Int], totalPixels: Int, avgR: Float, avgG: Float, avgB: Float) {
        self.histogram = histogram
        self.totalPixels = totalPixels
        self.avgR = avgR
        self.avgG = avgG
        self.avgB = avgB
    }
}

public enum AutoLightCorrector {
    /// Analyze an unnormalized raw bin count histogram (256 bins) to determine optimal exposure, contrast, highlights and shadows.
    public static func analyze(histogram: [Int], totalPixelCount: Int) -> LightCorrectionParams {
        guard totalPixelCount > 0 else { return .neutral }
        
        var cumulative = 0
        var p1: Float = 0     // 1st percentile (shadow clipping)
        var p5: Float = 0     // 5th percentile
        var p50: Float = 128  // median luminance (middle gray)
        var p95: Float = 255  // 95th percentile
        var p99: Float = 255  // 99th percentile (highlight clipping)
        
        var sumLuminance: Double = 0
        
        for (binIndex, count) in histogram.enumerated() {
            sumLuminance += Double(binIndex * count)
            cumulative += count
            let ratio = Float(cumulative) / Float(totalPixelCount)
            
            if p1 == 0 && ratio >= 0.01 { p1 = Float(binIndex) }
            if p5 == 0 && ratio >= 0.05 { p5 = Float(binIndex) }
            if p50 == 128 && ratio >= 0.50 { p50 = Float(binIndex) }
            if p95 == 255 && ratio >= 0.95 { p95 = Float(binIndex) }
            if p99 == 255 && ratio >= 0.99 { p99 = Float(binIndex) }
        }
        
        let meanLuminance = Float(sumLuminance / Double(totalPixelCount))
        let targetMidtone: Float = 118.0
        
        // 1. Exposure calculation (EV stops)
        let midtoneCurrent = (p50 * 0.6) + (meanLuminance * 0.4)
        var exposureEV: Float = 0.0
        
        if midtoneCurrent > 5.0 {
            let ratio = targetMidtone / max(10.0, midtoneCurrent)
            exposureEV = log2(ratio)
            exposureEV = max(-1.5, min(1.8, exposureEV))
        }
        
        // 2. Shadows recovery:
        var shadows: Float = 0.0
        if p5 < 25.0 {
            let shadowDeficit = (25.0 - p5) / 25.0
            shadows = min(0.65, shadowDeficit * 0.75)
        } else if p5 > 50.0 && midtoneCurrent > 120.0 {
            shadows = -0.15
        }
        
        // 3. Highlights recovery:
        var highlights: Float = 0.0
        if p95 > 235.0 || p99 > 250.0 {
            let highlightExcess = (p95 - 220.0) / 35.0
            highlights = -min(0.75, max(0.1, highlightExcess * 0.65))
        } else if p95 < 180.0 && exposureEV > 0.0 {
            highlights = 0.15
        }
        
        // 4. Contrast:
        let dynamicRange = p95 - p5
        var contrast: Float = 1.0
        if dynamicRange < 110.0 {
            contrast = min(1.35, 1.0 + (110.0 - dynamicRange) / 200.0)
        } else if dynamicRange > 220.0 {
            contrast = max(0.88, 1.0 - (dynamicRange - 220.0) / 300.0)
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
    
    /// Gray World algorithm to calculate Auto White Balance (Temperature and Tint offsets)
    public static func analyzeWhiteBalance(avgR: Float, avgG: Float, avgB: Float) -> (temperature: Float, tint: Float) {
        guard avgG > 1.0 else { return (0.0, 0.0) }
        
        // Target: Gray world assumes average R, G, B should be roughly balanced
        // R / G ratio reflects Color Temperature (cool < 1.0 < warm)
        // B / G ratio reflects Blue component
        let rRatio = avgR / avgG
        let bRatio = avgB / avgG
        
        // If R > B, image has warm/amber cast -> shift cooler (negative temperature)
        // If B > R, image has cool/blue cast -> shift warmer (positive temperature)
        let tempDiff = bRatio - rRatio // positive means too blue, negative means too orange
        var targetTemp = tempDiff * 1400.0
        targetTemp = max(-1800.0, min(1800.0, targetTemp))
        
        // Tint: Green vs Magenta balance
        // Expected G ~= (R + B) / 2. If G is higher -> green cast (need magenta / positive tint)
        let expectedG = (avgR + avgB) * 0.5
        let tintDiff = (expectedG - avgG) / max(1.0, avgG)
        var targetTint = tintDiff * 60.0
        targetTint = max(-60.0, min(60.0, targetTint))
        
        return (targetTemp, targetTint)
    }
    
    /// Full analysis of both light exposure and auto white balance
    public static func analyzeFull(rgbResult: RGBAnalysisResult) -> LightCorrectionParams {
        var params = analyze(histogram: rgbResult.histogram, totalPixelCount: rgbResult.totalPixels)
        let (temp, tint) = analyzeWhiteBalance(avgR: rgbResult.avgR, avgG: rgbResult.avgG, avgB: rgbResult.avgB)
        params.temperature = temp
        params.tint = tint
        return params
    }
}
