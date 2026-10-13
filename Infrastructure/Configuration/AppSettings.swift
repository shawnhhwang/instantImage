import Foundation

public struct AppSettings: Codable, Sendable {
    public struct AppConfiguration: Codable, Sendable {
        public let environment: String
        public let maxMemoryCacheMegabytes: Int
        public let diskCacheLimitGigabytes: Int
        
        enum CodingKeys: String, CodingKey {
            case environment = "Environment"
            case maxMemoryCacheMegabytes = "MaxMemoryCacheMegabytes"
            case diskCacheLimitGigabytes = "DiskCacheLimitGigabytes"
        }
    }
    
    public struct FileSystemSettings: Codable, Sendable {
        public let supportedExtensions: [String]
        public let enableRealtimeFSEvents: Bool
        public let fsEventsDebounceMilliseconds: Int
        
        enum CodingKeys: String, CodingKey {
            case supportedExtensions = "SupportedExtensions"
            case enableRealtimeFSEvents = "EnableRealtimeFSEvents"
            case fsEventsDebounceMilliseconds = "FSEventsDebounceMilliseconds"
        }
    }
    
    public struct RenderingSettings: Codable, Sendable {
        public let targetFPS: Int
        public struct ThumbnailSizeSettings: Codable, Sendable {
            public let width: Int
            public let height: Int
            
            enum CodingKeys: String, CodingKey {
                case width = "Width"
                case height = "Height"
            }
        }
        public let thumbnailSize: ThumbnailSizeSettings
        public let useMetalAcceleration: Bool
        
        enum CodingKeys: String, CodingKey {
            case targetFPS = "TargetFPS"
            case thumbnailSize = "ThumbnailSize"
            case useMetalAcceleration = "UseMetalAcceleration"
        }
    }
    
    public struct LoggingSettings: Codable, Sendable {
        public let subsystem: String
        public let logLevel: String
        public let logToDisk: Bool
        
        enum CodingKeys: String, CodingKey {
            case subsystem = "Subsystem"
            case logLevel = "LogLevel"
            case logToDisk = "LogToDisk"
        }
    }
    
    public let appConfiguration: AppConfiguration
    public let fileSystem: FileSystemSettings
    public let rendering: RenderingSettings
    public let logging: LoggingSettings
    
    enum CodingKeys: String, CodingKey {
        case appConfiguration = "AppConfiguration"
        case fileSystem = "FileSystem"
        case rendering = "Rendering"
        case logging = "Logging"
    }
    
    // Loaded singleton instance
    public static let shared: AppSettings = {
        // Find in main bundle or fallback to a relative path
        let fileManager = FileManager.default
        let possiblePaths = [
            Bundle.main.url(forResource: "appsettings", withExtension: "json"),
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("appsettings.json"),
            URL(fileURLWithPath: "/Users/shawnwang/Documents/agy/image3/appsettings.json")
        ]
        
        for url in possiblePaths {
            guard let url = url, fileManager.fileExists(atPath: url.path) else { continue }
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                return try decoder.decode(AppSettings.self, from: data)
            } catch {
                print("Failed to decode AppSettings from \(url.path): \(error)")
            }
        }
        
        // Fallback default configuration in case loading fails
        return AppSettings(
            appConfiguration: AppConfiguration(environment: "Development", maxMemoryCacheMegabytes: 512, diskCacheLimitGigabytes: 10),
            fileSystem: FileSystemSettings(supportedExtensions: [".jpg", ".jpeg", ".png", ".heic", ".heif", ".tiff", ".raw", ".cr2", ".nef", ".arw"], enableRealtimeFSEvents: true, fsEventsDebounceMilliseconds: 300),
            rendering: RenderingSettings(targetFPS: 120, thumbnailSize: RenderingSettings.ThumbnailSizeSettings(width: 256, height: 256), useMetalAcceleration: true),
            logging: LoggingSettings(subsystem: "com.project.lumina", logLevel: "Debug", logToDisk: true)
        )
    }()
}
