import Foundation
import CoreGraphics

public struct SourceFaceItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let url: URL
    
    public init(url: URL) {
        self.id = url.path
        self.name = url.deletingPathExtension().lastPathComponent
        self.url = url
    }
}

public struct FaceSwapResult: Identifiable, Sendable {
    public let id: UUID
    public let targetURL: URL
    public let sourceFaceURL: URL?
    public let previewOutputURL: URL
    public let filename: String
    public let createdAt: Date
    
    public init(id: UUID = UUID(), targetURL: URL, sourceFaceURL: URL?, previewOutputURL: URL, filename: String, createdAt: Date = Date()) {
        self.id = id
        self.targetURL = targetURL
        self.sourceFaceURL = sourceFaceURL
        self.previewOutputURL = previewOutputURL
        self.filename = filename
        self.createdAt = createdAt
    }
}

public enum FaceSwapSaveDestination: String, CaseIterable, Identifiable {
    case sameFolder = "儲存並取代原檔 (刪除舊檔)"
    case swapOutput = "儲存於 swap/output"
    case saveAs = "另存新檔 (選擇資料夾)..."
    
    public var id: String { rawValue }
}

public enum FaceSwapDecision: String, CaseIterable, Identifiable, Sendable {
    case pending = "待審查"
    case saved = "已儲存換臉"
    case keptOriginal = "保持原圖"
    
    public var id: String { rawValue }
}

public struct FaceSwapBatchItem: Identifiable, Sendable {
    public let id: UUID
    public let targetURL: URL
    public var result: FaceSwapResult?
    public var errorMessage: String?
    public var decision: FaceSwapDecision
    public var savedURL: URL?
    
    public init(
        id: UUID = UUID(),
        targetURL: URL,
        result: FaceSwapResult? = nil,
        errorMessage: String? = nil,
        decision: FaceSwapDecision = .pending,
        savedURL: URL? = nil
    ) {
        self.id = id
        self.targetURL = targetURL
        self.result = result
        self.errorMessage = errorMessage
        self.decision = decision
        self.savedURL = savedURL
    }
    
    public var filename: String {
        targetURL.lastPathComponent
    }
}

public enum FaceSwapBatchTargetMode: String, CaseIterable, Identifiable {
    case single = "單張相片"
    case folder = "整套相片資料夾"
    case selected = "多選相片"
    
    public var id: String { rawValue }
}

public enum FaceSwapConnectionStatus: Equatable, Sendable {
    case idle
    case testing
    case connected(latencyMs: Int)
    case failed(error: String)
}
