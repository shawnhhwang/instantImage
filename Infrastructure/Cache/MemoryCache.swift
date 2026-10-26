import Foundation
import CoreGraphics

public actor MemoryCache {
    public static let shared = MemoryCache()
    
    private final class CacheEntry: NSObject {
        let image: CGImage
        let cost: Int
        
        init(image: CGImage, cost: Int) {
            self.image = image
            self.cost = cost
        }
    }
    
    private let cache = NSCache<NSString, CacheEntry>()
    
    private init() {
        let baseMegabytes = AppSettings.shared.appConfiguration.maxMemoryCacheMegabytes
        let multiplier = SystemHardwareProfile.shared.cacheMultiplier
        let maxMegabytes = max(128, Int(Double(baseMegabytes) * multiplier))
        let limitInBytes = maxMegabytes * 1024 * 1024
        
        cache.totalCostLimit = limitInBytes
        cache.name = "com.project.lumina.memorycache"
        
        LoggerManager.shared.log("MemoryCache initialized for \(SystemHardwareProfile.shared.architecture.rawValue) with limit: \(maxMegabytes) MB (multiplier: \(multiplier))", level: .info)
    }
    
    /// Retrieve image from the cache
    /// - Parameter key: The unique cache key (usually image URL path)
    /// - Returns: The cached CGImage, or nil if not found
    public func get(forKey key: String) -> CGImage? {
        let nsKey = key as NSString
        guard let entry = cache.object(forKey: nsKey) else {
            return nil
        }
        return entry.image
    }
    
    /// Store image in the cache
    /// - Parameters:
    ///   - image: The CGImage to cache
    ///   - key: The unique cache key
    public func set(_ image: CGImage, forKey key: String) {
        let nsKey = key as NSString
        let cost = image.height * image.bytesPerRow
        
        let entry = CacheEntry(image: image, cost: cost)
        cache.setObject(entry, forKey: nsKey, cost: cost)
    }
    
    /// Clear all cached elements
    public func clear() {
        cache.removeAllObjects()
        LoggerManager.shared.log("MemoryCache cleared", level: .info)
    }
}
