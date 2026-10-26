import Foundation
import Metal
import AppKit

public enum MacArchitecture: String, Sendable {
    case appleSilicon = "Apple Silicon (M-Series)"
    case intel = "Intel Core / Xeon"
    case appleSiliconRosetta = "Apple Silicon (Rosetta 2)"
    case unknown = "Universal"
}

/// Comprehensive Hardware Profiler & Architecture-Specific Performance Optimizer
/// Automatically tunes thread pools, prefetch windows, Metal pipelines, and memory caches
/// based on whether the host is Apple Silicon (M1/M2/M3/M4) or Intel Core/Xeon.
public final class SystemHardwareProfile: @unchecked Sendable {
    public static let shared = SystemHardwareProfile()
    
    public let architecture: MacArchitecture
    public let chipName: String
    public let gpuName: String
    public let hasUnifiedMemory: Bool
    public let isRosettaTranslated: Bool
    public let physicalMemoryGB: Int
    public let activeCores: Int
    
    // Dynamically tuned performance parameters
    public let recommendedThumbnailConcurrency: Int
    public let recommendedMetadataConcurrency: Int
    public let recommendedPrefetchWindow: Int
    public let cacheMultiplier: Double
    public let hardwareEngineName: String
    public let shortEngineTag: String
    public let engineSummary: String
    
    public var isAppleSilicon: Bool {
        architecture == .appleSilicon || architecture == .appleSiliconRosetta
    }
    
    public var isIntel: Bool {
        architecture == .intel
    }
    
    private init() {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        self.activeCores = cores
        
        let memBytes = ProcessInfo.processInfo.physicalMemory
        self.physicalMemoryGB = max(1, Int(memBytes / (1024 * 1024 * 1024)))
        
        // 1. Check Rosetta Translation
        var isTranslated = false
        var size = MemoryLayout<Int32>.size
        var translatedVal: Int32 = 0
        if sysctlbyname("sysctl.proc_translated", &translatedVal, &size, nil, 0) == 0 {
            isTranslated = (translatedVal == 1)
        }
        self.isRosettaTranslated = isTranslated
        
        // 2. Query CPU Brand String
        var brandSize: size_t = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &brandSize, nil, 0)
        var brandString = ""
        if brandSize > 0 {
            var brandData = [CChar](repeating: 0, count: brandSize)
            if sysctlbyname("machdep.cpu.brand_string", &brandData, &brandSize, nil, 0) == 0 {
                brandString = String(cString: brandData).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // 3. Query Metal Device & Unified Memory
        let mtlDevice = MTLCreateSystemDefaultDevice()
        let detectedGpuName = mtlDevice?.name ?? "Default Metal GPU"
        let isUnified = mtlDevice?.hasUnifiedMemory ?? false
        self.gpuName = detectedGpuName
        self.hasUnifiedMemory = isUnified
        
        // 4. Resolve Architecture
        #if arch(arm64)
        self.architecture = .appleSilicon
        self.chipName = brandString.isEmpty ? "Apple Silicon" : brandString
        #elseif arch(x86_64)
        if isTranslated {
            self.architecture = .appleSiliconRosetta
            self.chipName = brandString.isEmpty ? "Apple Silicon (Rosetta 2)" : "\(brandString) [Rosetta 2]"
        } else {
            self.architecture = .intel
            self.chipName = brandString.isEmpty ? "Intel Core / Xeon" : brandString
        }
        #else
        self.architecture = .unknown
        self.chipName = brandString.isEmpty ? "Universal Mac" : brandString
        #endif
        
        // 5. Hardware-Specific Performance Tuning
        if self.architecture == .appleSilicon {
            // Apple Silicon (M-Series):
            // - Unified Memory Architecture (UMA) provides massive memory bandwidth (>100GB/s).
            // - Scaling concurrency to take full advantage of high-performance cores.
            // - Expanding lookahead prefetch window for 0-latency ACDSee-grade photo culling.
            let concurrency = min(16, max(6, cores))
            self.recommendedThumbnailConcurrency = concurrency
            self.recommendedMetadataConcurrency = min(12, max(6, cores))
            self.recommendedPrefetchWindow = 6
            self.cacheMultiplier = 1.5
            self.hardwareEngineName = "Apple Silicon M-Series [UMA 統一記憶體加速引擎]"
            self.shortEngineTag = "Apple Silicon M-Series"
            self.engineSummary = "\(chipName) • \(cores) 核心 • \(physicalMemoryGB)GB 統一記憶體 • \(concurrency) 路並行極速管線"
        } else if self.architecture == .appleSiliconRosetta {
            let concurrency = min(12, max(4, cores))
            self.recommendedThumbnailConcurrency = concurrency
            self.recommendedMetadataConcurrency = min(8, max(4, cores))
            self.recommendedPrefetchWindow = 4
            self.cacheMultiplier = 1.2
            self.hardwareEngineName = "Apple Silicon [Rosetta 2 兼容管線]"
            self.shortEngineTag = "Apple Silicon (Rosetta)"
            self.engineSummary = "\(chipName) • \(cores) 核心 • \(physicalMemoryGB)GB 統一記憶體 (建議使用 arm64 原生版以獲極致效能)"
        } else {
            // Intel Core / Xeon:
            // - Traditional PCIe bus separation between CPU and Discrete GPU (AMD Radeon) or shared integrated GPU.
            // - Hyper-threaded cores can overheat under sustained 100% throughput; bounded concurrency ensures smooth thermals.
            // - Balanced lookahead prefetch window to avoid memory thrashing.
            let concurrency = min(8, max(4, max(1, cores - 1)))
            self.recommendedThumbnailConcurrency = concurrency
            self.recommendedMetadataConcurrency = min(6, max(3, max(1, cores - 2)))
            self.recommendedPrefetchWindow = 3
            self.cacheMultiplier = 1.0
            self.hardwareEngineName = "Intel Core / Xeon [高效能管線與溫控優化引擎]"
            self.shortEngineTag = "Intel x86_64"
            self.engineSummary = "\(chipName) • \(cores) 邏輯核心 • \(physicalMemoryGB)GB RAM • \(gpuName)"
        }
    }
    
    /// Create optimized CIContext options specifically configured for the host architecture
    public func createCIContextOptions() -> [CIContextOption: Any] {
        var options: [CIContextOption: Any] = [
            .cacheIntermediates: false,
            .priorityRequestLow: false
        ]
        
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        options[.workingColorSpace] = sRGB
        options[.outputColorSpace] = sRGB
        
        #if arch(arm64)
        // On Apple Silicon, allow Metal to take full advantage of unified memory textures
        options[.allowLowPower] = false
        #else
        // On Intel discrete GPU Macs, prevent GPU bus stalling
        options[.useSoftwareRenderer] = false
        #endif
        
        return options
    }
}
