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
    
    public init(targetURL: URL, sourceFaceURL: URL?, previewOutputURL: URL, filename: String) {
        self.id = UUID()
        self.targetURL = targetURL
        self.sourceFaceURL = sourceFaceURL
        self.previewOutputURL = previewOutputURL
        self.filename = filename
        self.createdAt = Date()
    }
}

public enum FaceSwapSaveDestination: String, CaseIterable, Identifiable {
    case sameFolder = "儲存於相片同資料夾"
    case swapOutput = "儲存於 swap/output"
    case saveAs = "另存新檔 (選擇資料夾)..."
    
    public var id: String { rawValue }
}
