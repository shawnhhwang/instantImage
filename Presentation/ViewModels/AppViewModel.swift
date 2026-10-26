import Foundation
import SwiftUI
import CoreGraphics
import AppKit
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

public enum SortOption: String, CaseIterable, Identifiable {
    case filename = "檔名"
    case date = "拍攝日期"
    case size = "檔案大小"
    case rating = "星級評等"
    case iso = "感光度 (ISO)"
    
    public var id: String { rawValue }
}

@MainActor
public final class AppViewModel: ObservableObject {
    @Published public var selectedFolder: URL?
    @Published public var subfolders: [FolderNode] = []
    @Published public var images: [ImageItem] = []
    @Published public var displayedImages: [ImageItem] = []
    
    // Filters & Search
    @Published public var filterRating: Int = 0
    @Published public var filterTaggedOnly: Bool = false
    @Published public var filterOnlyRaw: Bool = false
    @Published public var filterOnlyEdited: Bool = false
    @Published public var searchQuery: String = ""
    
    // Sorting
    @Published public var sortOption: SortOption = .filename
    @Published public var sortAscending: Bool = true
    
    // UI Layout & Inspection Controls
    @Published public var thumbnailScale: Double = 165
    @Published public var isShortcutSheetVisible: Bool = false
    @Published public var isFilmstripVisible: Bool = true
    @Published public var isSidebarOpenInDetail: Bool = true
    @Published public var splitCurtainPosition: CGFloat = 0.5
    
    @Published public var selectedImageIndex: Int?
    @Published public var isDetailActive: Bool = false
    
    @Published public var thumbnails: [String: CGImage] = [:]
    @Published public var exifMetadata: [String: ImageMetadata] = [:]
    @Published public var isLoading: Bool = false
    @Published public var isZoomed: Bool = false
    @Published public var activeHistogram: [Float] = []
    
    // Lightroom-style Light / Tone Correction
    @Published public var lightCorrections: [String: LightCorrectionParams] = [:]
    @Published public var isAutoLightEnabled: [String: Bool] = [:]
    @Published public var isAutoWBEnabled: [String: Bool] = [:]
    @Published public var isBeforeAfterComparisonActive: Bool = false
    @Published public var isClippingWarningActive: Bool = false
    public var copiedLightCorrection: LightCorrectionParams? = nil
    
    @Published public var favoriteFolders: [URL] = []
    private let favoritesKey = "com.project.lumina.favorites"
    
    // Toast system
    @Published public var toastMessage: String? = nil
    private var toastTimer: Task<Void, Never>? = nil
    
    // Culling Move Destination
    @Published public var cullingDestinationFolder: URL? = nil
    private let cullingDestinationKey = "com.project.lumina.cullingDestination"
    
    // Loupe Magnifier properties
    @Published public var loupeLocation: CGPoint = .zero
    @Published public var isHoveringImage: Bool = false
    @Published public var isLoupeEnabled: Bool = false
    
    // Compare Mode properties
    @Published public var selectedIndexes: Set<Int> = []
    @Published public var isCompareActive: Bool = false
    @Published public var focusedCompareIndex: Int = 0
    
    // FaceSwap (FaceFusion API) properties
    @Published public var isFaceSwapSetupPresented: Bool = false
    @Published public var isFaceSwapProcessing: Bool = false
    @Published public var faceSwapStatusMessage: String = ""
    @Published public var availableSourceFaces: [SourceFaceItem] = []
    @Published public var selectedSourceFace: SourceFaceItem? = nil
    @Published public var faceEnhancerBlend: Double = 60.0
    @Published public var currentFaceSwapResult: FaceSwapResult? = nil
    @Published public var isFaceSwapPreviewPresented: Bool = false
    @Published public var faceSwapTargetImage: ImageItem? = nil
    @Published public var faceSwapErrorMessage: String? = nil
    @Published public var faceSwapPreviewMode: FaceSwapPreviewMode = .sideBySide
    @Published public var faceSwapSplitPosition: CGFloat = 0.5
    
    // FaceSwap Settings properties
    @Published public var isFaceSwapSettingsPresented: Bool = false
    @Published public var faceSwapApiUrl: String = "http://192.168.1.3:7870/api/predict"
    @Published public var faceSwapConnectionStatus: FaceSwapConnectionStatus = .idle
    @Published public var faceSwapConnectionMessage: String = ""
    
    // FaceSwap Batch Mode & Review properties
    @Published public var faceSwapBatchTargetMode: FaceSwapBatchTargetMode = .single
    @Published public var faceSwapBatchFolderURL: URL? = nil
    @Published public var faceSwapBatchTargets: [URL] = []
    @Published public var isFaceSwapBatchProcessing: Bool = false
    @Published public var faceSwapBatchCurrentIndex: Int = 0
    @Published public var faceSwapBatchTotalCount: Int = 0
    @Published public var faceSwapBatchItems: [FaceSwapBatchItem] = []
    @Published public var isFaceSwapBatchReviewPresented: Bool = false
    @Published public var faceSwapBatchReviewIndex: Int = 0
    @Published public var faceSwapBatchSaveDestination: FaceSwapSaveDestination = .sameFolder
    @Published public var currentFaceSwapStagingDir: URL? = nil
    
    // Detected FaceSwap from Folder
    @Published public var detectedFaceSwapItems: [FaceSwapBatchItem] = []
    @Published public var detectedFaceSwapCount: Int = 0
    @Published public var hasDetectedFaceSwaps: Bool = false
    @Published public var showDetectedFaceSwapBanner: Bool = true
    @Published public var faceSwapResultByTargetURL: [String: FaceSwapResult] = [:]
    @Published public var isFaceSwapDetailSplitActive: Bool = false
    
    // Recent Folders & Grid Metrics
    @Published public var recentFolders: [URL] = []
    @Published public var gridColumnCount: Int = 4
    private let recentFoldersKey = "com.project.lumina.recentFolders"
    
    // Hardware Architecture & Performance Tuning Engine
    public let hardwareProfile = SystemHardwareProfile.shared
    
    private let fileSystemRepo = FileSystemRepository()
    private let directoryMonitor = DirectoryMonitor()
    
    private var db: SQLiteDatabase?
    private var exifRepo: ExifCacheRepository?
    private var keyboardObserver: Any?
    private var loadGeneration = 0
    
    public init() {
        setupDatabase()
        setupDirectoryMonitor()
        loadInitialBookmarks()
        loadFavorites()
        loadRecentFolders()
        loadCullingDestination()
        loadFaceSwapSettings()
        setupKeyboardNotificationObserver()
    }
    
    private func setupDatabase() {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let dbDir = appSupport.appendingPathComponent("ProjectLumina", isDirectory: true)
        
        do {
            try fileManager.createDirectory(at: dbDir, withIntermediateDirectories: true)
            let dbURL = dbDir.appendingPathComponent("metadata_cache.db")
            let database = try SQLiteDatabase(dbPath: dbURL.path)
            self.db = database
            self.exifRepo = ExifCacheRepository(database: database)
            LoggerManager.shared.log("SQLite Database initialized at \(dbURL.path)", level: .info)
        } catch {
            LoggerManager.shared.log("Failed to setup SQLite database: \(error.localizedDescription)", level: .error)
        }
    }
    
    private func setupDirectoryMonitor() {
        Task {
            for await _ in directoryMonitor.events {
                LoggerManager.shared.log("Directory change detected by monitor, reloading contents...", level: .info)
                self.refreshFolderContents()
            }
        }
    }
    
    private func loadInitialBookmarks() {
        let bookmarks = SecurityScopedBookmarkManager.shared.loadSavedBookmarks()
        if let first = bookmarks.first {
            selectFolder(first)
        }
    }
    
    public func selectFolder(_ url: URL) {
        selectedFolder = url
        SecurityScopedBookmarkManager.shared.saveBookmark(for: url)
        addRecentFolder(url)
        
        // Start watching the directory
        directoryMonitor.startMonitoring(url: url)
        
        // Load initial contents
        refreshFolderContents()
    }
    
    public func refreshFolderContents() {
        guard let url = selectedFolder else { return }
        isLoading = true
        loadGeneration += 1
        let currentGen = loadGeneration
        
        Task {
            do {
                let folders = try await fileSystemRepo.loadSubfolders(of: url)
                let loadedImages = try await fileSystemRepo.loadImages(of: url)
                
                self.subfolders = folders
                self.images = loadedImages
                self.updateDisplayedImages()
                self.isLoading = false
                
                // Ensure valid selection
                if let index = selectedImageIndex {
                    if index >= self.displayedImages.count {
                        selectedImageIndex = self.displayedImages.isEmpty ? nil : self.displayedImages.count - 1
                        if let validIdx = selectedImageIndex {
                            selectedIndexes = [validIdx]
                        }
                    }
                } else if !self.displayedImages.isEmpty {
                    selectedImageIndex = 0
                    selectedIndexes = [0]
                }
                
                // Begin background loading of thumbnails and EXIF metadata
                loadThumbnailsAndMetadata(for: loadedImages, generation: currentGen)
                
                // Detect completed face swap photos in this folder
                self.checkForDetectedFaceSwaps(in: url, images: loadedImages)
            } catch {
                LoggerManager.shared.log("Failed to load folder contents: \(error.localizedDescription)", level: .error)
                self.isLoading = false
            }
        }
    }
    
    public func updateDisplayedImages() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        var filtered = images.filter { item in
            let key = item.url.path
            let metadata = exifMetadata[key]
            
            // Search Query Filter
            if !query.isEmpty {
                let nameMatch = item.filename.lowercased().contains(query)
                let makeMatch = metadata?.cameraMake?.lowercased().contains(query) ?? false
                let modelMatch = metadata?.cameraModel?.lowercased().contains(query) ?? false
                if !nameMatch && !makeMatch && !modelMatch {
                    return false
                }
            }
            
            // Star Rating Filter
            if filterRating > 0 {
                let rating = metadata?.rating ?? 0
                if rating < filterRating {
                    return false
                }
            }
            
            // Tagged Filter
            if filterTaggedOnly {
                let isTagged = metadata?.isTagged ?? false
                if !isTagged {
                    return false
                }
            }
            
            // RAW Format Filter
            if filterOnlyRaw {
                let ext = item.url.pathExtension.lowercased()
                let rawExts = ["raw", "cr2", "nef", "arw", "dng", "orf", "rw2"]
                if !rawExts.contains(ext) {
                    return false
                }
            }
            
            // Edited Filter
            if filterOnlyEdited {
                let isEdited = isAutoLightEnabled[key] == true || (lightCorrections[key] != nil && !lightCorrections[key]!.isNeutral)
                if !isEdited {
                    return false
                }
            }
            
            return true
        }
        
        // Dynamic Multi-Criteria Sorting
        filtered.sort { (a, b) -> Bool in
            let aMeta = exifMetadata[a.url.path]
            let bMeta = exifMetadata[b.url.path]
            
            let result: Bool
            switch sortOption {
            case .filename:
                result = a.filename.localizedStandardCompare(b.filename) == .orderedAscending
            case .date:
                let aDate = aMeta?.creationDate ?? a.creationDate ?? Date.distantPast
                let bDate = bMeta?.creationDate ?? b.creationDate ?? Date.distantPast
                result = aDate < bDate
            case .size:
                result = a.sizeBytes < b.sizeBytes
            case .rating:
                let aRating = aMeta?.rating ?? 0
                let bRating = bMeta?.rating ?? 0
                result = aRating < bRating
            case .iso:
                let aISO = aMeta?.iso ?? 0
                let bISO = bMeta?.iso ?? 0
                result = aISO < bISO
            }
            
            return sortAscending ? result : !result
        }
        
        displayedImages = filtered
        
        // Keep selection in bounds
        if let index = selectedImageIndex {
            if index >= displayedImages.count {
                selectedImageIndex = displayedImages.isEmpty ? nil : displayedImages.count - 1
            }
        }
    }
    
    private func loadThumbnailsAndMetadata(for items: [ImageItem], generation: Int) {
        // 1. Batch load cached EXIF metadata from SQLite database in a single background task
        Task {
            if let repo = exifRepo {
                var loadedMetadata: [String: ImageMetadata] = [:]
                for item in items {
                    if Task.isCancelled || self.loadGeneration != generation { return }
                    let key = item.url.path
                    if self.exifMetadata[key] == nil {
                        if var cachedExif = try? await repo.getMetadata(for: key) {
                            // Sync XMP sidecar values if available and they differ from the database cache
                            if let xmpData = XmpMetadataWriter.readXmpSidecar(for: item.url) {
                                if cachedExif.rating != xmpData.rating || cachedExif.isTagged != xmpData.isTagged {
                                    cachedExif.rating = xmpData.rating
                                    cachedExif.isTagged = xmpData.isTagged
                                    try? await repo.updateRating(for: key, rating: xmpData.rating)
                                    try? await repo.updateTagged(for: key, isTagged: xmpData.isTagged)
                                }
                            }
                            loadedMetadata[key] = cachedExif
                        }
                    }
                }
                
                if Task.isCancelled || self.loadGeneration != generation { return }
                
                if !loadedMetadata.isEmpty {
                    // Update in a single batch on the main actor
                    for (key, metadata) in loadedMetadata {
                        self.exifMetadata[key] = metadata
                    }
                    self.updateDisplayedImages()
                }
            }
            
            let localRepo = self.exifRepo
            
            // 2. Process items using a TaskGroup for fully managed parallel execution
            await withTaskGroup(of: Void.self) { group in
                for item in items {
                    let key = item.url.path
                    let filename = item.filename
                    let url = item.url
                    
                    // A. Process Thumbnail
                    if self.thumbnails[key] == nil {
                        group.addTask {
                            if Task.isCancelled { return }
                            let isOldGeneration = await MainActor.run { self.loadGeneration != generation }
                            if isOldGeneration { return }
                            
                            if let cachedImage = await MemoryCache.shared.get(forKey: key) {
                                await MainActor.run {
                                    if self.loadGeneration == generation {
                                        self.thumbnails[key] = cachedImage
                                    }
                                }
                                return
                            }
                            
                            do {
                                let thumbnailSize = AppSettings.shared.rendering.thumbnailSize.width
                                let thumbnail = try await ImageLoaderService.shared.loadThumbnail(from: url, maxPixelSize: thumbnailSize)
                                await MemoryCache.shared.set(thumbnail, forKey: key)
                                
                                await MainActor.run {
                                    if self.loadGeneration == generation {
                                        self.thumbnails[key] = thumbnail
                                    }
                                }
                            } catch {
                                LoggerManager.shared.log("Failed to load thumbnail for \(filename): \(error.localizedDescription)", level: .debug)
                            }
                        }
                    }
                    
                    // B. Process non-cached EXIF Metadata (requires ImageIO parsing)
                    if self.exifMetadata[key] == nil {
                        group.addTask {
                            if Task.isCancelled { return }
                            let isOldGeneration = await MainActor.run { self.loadGeneration != generation }
                            if isOldGeneration { return }
                            
                            do {
                                let exif = try await ImageLoaderService.shared.extractMetadata(
                                    from: url,
                                    creationDate: item.creationDate,
                                    sizeBytes: item.sizeBytes
                                )
                                
                                await MainActor.run {
                                    if self.loadGeneration == generation {
                                        self.exifMetadata[key] = exif
                                        // Only trigger main-thread filtering and layout update if a filter is active!
                                        if self.filterRating > 0 || self.filterTaggedOnly {
                                            self.updateDisplayedImages()
                                        }
                                    }
                                }
                                
                                if let repo = localRepo {
                                    try? await repo.saveMetadata(exif)
                                }
                            } catch {
                                LoggerManager.shared.log("Failed to extract EXIF for \(filename): \(error.localizedDescription)", level: .debug)
                            }
                        }
                    }
                }
            }
        }
    }
    
    public var selectedImage: ImageItem? {
        guard let index = selectedImageIndex, index >= 0, index < displayedImages.count else {
            return nil
        }
        return displayedImages[index]
    }
    
    public func selectNextImage(extendSelection: Bool = false) {
        guard !displayedImages.isEmpty else { return }
        let current = selectedImageIndex ?? (selectedIndexes.sorted().last ?? 0)
        let nextIdx = min(displayedImages.count - 1, current + 1)
        selectedImageIndex = nextIdx
        if extendSelection {
            let from = selectedIndexes.sorted().first ?? current
            selectRange(from: from, to: nextIdx)
        } else {
            selectedIndexes = [nextIdx]
        }
        if isDetailActive { calculateHistogramForSelected() }
        prefetchAdjacentImages()
    }
    
    public func selectPreviousImage(extendSelection: Bool = false) {
        guard !displayedImages.isEmpty else { return }
        let current = selectedImageIndex ?? (selectedIndexes.sorted().first ?? 0)
        let nextIdx = max(0, current - 1)
        selectedImageIndex = nextIdx
        if extendSelection {
            let from = selectedIndexes.sorted().first ?? current
            selectRange(from: from, to: nextIdx)
        } else {
            selectedIndexes = [nextIdx]
        }
        if isDetailActive { calculateHistogramForSelected() }
        prefetchAdjacentImages()
    }
    
    public func selectImageAbove(extendSelection: Bool = false) {
        guard !displayedImages.isEmpty else { return }
        if isDetailActive {
            selectFirstImage()
            return
        }
        let cols = max(1, gridColumnCount)
        let current = selectedImageIndex ?? (selectedIndexes.sorted().first ?? 0)
        let nextIdx = max(0, current - cols)
        selectedImageIndex = nextIdx
        if extendSelection {
            let from = selectedIndexes.sorted().first ?? current
            selectRange(from: from, to: nextIdx)
        } else {
            selectedIndexes = [nextIdx]
        }
        prefetchAdjacentImages()
    }
    
    public func selectImageBelow(extendSelection: Bool = false) {
        guard !displayedImages.isEmpty else { return }
        if isDetailActive {
            selectLastImage()
            return
        }
        let cols = max(1, gridColumnCount)
        let lastIdx = displayedImages.count - 1
        let current = selectedImageIndex ?? (selectedIndexes.sorted().first ?? 0)
        let nextIdx = min(lastIdx, current + cols)
        selectedImageIndex = nextIdx
        if extendSelection {
            let from = selectedIndexes.sorted().first ?? current
            selectRange(from: from, to: nextIdx)
        } else {
            selectedIndexes = [nextIdx]
        }
        prefetchAdjacentImages()
    }
    
    public func selectFirstImage() {
        guard !displayedImages.isEmpty else { return }
        selectedImageIndex = 0
        selectedIndexes = [0]
        if isDetailActive { calculateHistogramForSelected() }
        prefetchAdjacentImages()
    }
    
    public func selectLastImage() {
        guard !displayedImages.isEmpty else { return }
        let lastIdx = displayedImages.count - 1
        selectedImageIndex = lastIdx
        selectedIndexes = [lastIdx]
        if isDetailActive { calculateHistogramForSelected() }
        prefetchAdjacentImages()
    }
    
    public func resetLightCorrectionForSelected() {
        guard let image = selectedImage else { return }
        let key = image.url.path
        lightCorrections[key] = .neutral
        isAutoLightEnabled[key] = false
        isAutoWBEnabled[key] = false
        showToast("已重置所有調光與白平衡參數至原始狀態")
        calculateHistogramForSelected()
    }
    
    public func toggleZoom() {
        isZoomed.toggle()
    }
    
    public func toggleFullScreen() {
        if let window = NSApp.keyWindow {
            window.toggleFullScreen(nil)
        }
    }
    
    public func calculateHistogramForSelected() {
        guard let image = selectedImage else {
            self.activeHistogram = []
            return
        }
        let key = image.url.path
        
        if let thumbnail = thumbnails[key] {
            Task.detached(priority: .userInitiated) {
                let histogram = ImageLoaderService.shared.calculateLuminanceHistogram(for: thumbnail)
                await MainActor.run {
                    self.activeHistogram = histogram
                }
            }
        } else {
            // Fallback: If thumbnail isn't loaded yet, try to load it quickly in background
            Task {
                do {
                    let thumbnailSize = AppSettings.shared.rendering.thumbnailSize.width
                    let thumbnail = try await ImageLoaderService.shared.loadThumbnail(from: image.url, maxPixelSize: thumbnailSize)
                    let histogram = ImageLoaderService.shared.calculateLuminanceHistogram(for: thumbnail)
                    self.activeHistogram = histogram
                } catch {
                    self.activeHistogram = []
                }
            }
        }
    }
    
    // MARK: - Lightroom-style Auto Light Correction
    
    /// Toggle or recalculate Auto Light Correction for currently active/selected image
    public func toggleAutoLightForSelected() {
        guard let image = selectedImage else { return }
        let key = image.url.path
        let currentlyEnabled = isAutoLightEnabled[key] ?? false
        
        if currentlyEnabled {
            // Disable auto light correction (reset tone parameters only, preserve White Balance!)
            isAutoLightEnabled[key] = false
            var current = lightCorrections[key] ?? .neutral
            current.exposure = 0.0
            current.contrast = 1.0
            current.highlights = 0.0
            current.shadows = 0.0
            lightCorrections[key] = current
            showToast("已關閉一鍵校光")
        } else {
            // Enable and calculate optimal Lightroom parameters
            applyAutoLightCorrection(for: image)
        }
    }
    
    /// Trigger Auto Light Correction calculation for a given ImageItem adhering to Lightroom standards
    public func applyAutoLightCorrection(for image: ImageItem) {
        let key = image.url.path
        
        let applyParams: (LightCorrectionParams) -> Void = { [weak self] rawParams in
            guard let self = self else { return }
            var params = rawParams
            // Preserve user-adjusted or auto white balance if already applied
            if let existing = self.lightCorrections[key] {
                params.temperature = existing.temperature
                params.tint = existing.tint
            }
            self.lightCorrections[key] = params
            self.isAutoLightEnabled[key] = true
            let evString = String(format: "%+.2f EV", params.exposure)
            self.showToast("一鍵校光已套用 (曝光 \(evString), 對比 \(String(format: "%.2f", params.contrast)))")
        }
        
        if let thumbnail = thumbnails[key] {
            let params = ImageLoaderService.shared.calculateAutoLightCorrection(for: thumbnail, includeWhiteBalance: false)
            applyParams(params)
        } else {
            Task {
                do {
                    let thumbnailSize = AppSettings.shared.rendering.thumbnailSize.width
                    let thumbnail = try await ImageLoaderService.shared.loadThumbnail(from: image.url, maxPixelSize: thumbnailSize)
                    let params = ImageLoaderService.shared.calculateAutoLightCorrection(for: thumbnail, includeWhiteBalance: false)
                    await MainActor.run {
                        applyParams(params)
                    }
                } catch {
                    await MainActor.run {
                        self.showToast("校光計算失敗")
                    }
                }
            }
        }
    }
    
    // Feature A: Auto White Balance
    
    /// Toggle Auto White Balance for currently active/selected image
    public func toggleAutoWhiteBalanceForSelected() {
        guard let image = selectedImage else { return }
        let key = image.url.path
        let currentlyEnabled = isAutoWBEnabled[key] ?? false
        
        if currentlyEnabled {
            // Disable Auto WB, reset temperature & tint to neutral (0), but preserve tone!
            isAutoWBEnabled[key] = false
            var current = lightCorrections[key] ?? .neutral
            current.temperature = 0.0
            current.tint = 0.0
            lightCorrections[key] = current
            showToast("已重設白平衡至原始狀態")
        } else {
            applyAutoWhiteBalanceForSelected()
        }
    }
    
    public func applyAutoWhiteBalanceForSelected() {
        guard let image = selectedImage else { return }
        let key = image.url.path
        
        let applyWB: ((temperature: Float, tint: Float)) -> Void = { [weak self] wb in
            guard let self = self else { return }
            var current = self.lightCorrections[key] ?? .neutral
            // Only update temperature and tint! Do NOT touch exposure, contrast, highlights, shadows!
            current.temperature = wb.temperature
            current.tint = wb.tint
            self.lightCorrections[key] = current
            self.isAutoWBEnabled[key] = true
            // IMPORTANT: Do NOT touch self.isAutoLightEnabled[key]! They are separate!
            let tempSign = wb.temperature >= 0 ? "+\(Int(wb.temperature))" : "\(Int(wb.temperature))"
            let tintSign = wb.tint >= 0 ? "+\(Int(wb.tint))" : "\(Int(wb.tint))"
            self.showToast("自動白平衡: 色溫 \(tempSign)K, 色調 \(tintSign)")
        }
        
        if let thumbnail = thumbnails[key] {
            let wb = ImageLoaderService.shared.calculateAutoWhiteBalance(for: thumbnail)
            applyWB(wb)
        } else {
            Task {
                do {
                    let thumbnailSize = AppSettings.shared.rendering.thumbnailSize.width
                    let thumbnail = try await ImageLoaderService.shared.loadThumbnail(from: image.url, maxPixelSize: thumbnailSize)
                    let wb = ImageLoaderService.shared.calculateAutoWhiteBalance(for: thumbnail)
                    await MainActor.run {
                        applyWB(wb)
                    }
                } catch {
                    await MainActor.run {
                        self.showToast("白平衡計算失敗")
                    }
                }
            }
        }
    }
    
    // Feature B: Clipping Warning Toggle
    public func toggleClippingWarning() {
        isClippingWarningActive.toggle()
        showToast(isClippingWarningActive ? "已開啟過曝/死黑剪裁警告 (J)" : "已關閉剪裁警告")
    }
    
    // Feature C: Batch Sync Settings
    public func copyLightCorrectionForSelected() {
        guard let image = selectedImage else { return }
        let key = image.url.path
        let params = lightCorrections[key] ?? .neutral
        copiedLightCorrection = params
        showToast("已複製照片調光參數 (曝光 \(String(format: "%+.2f EV", params.exposure)))")
    }
    
    public func pasteLightCorrectionToSelected() {
        guard let copied = copiedLightCorrection else {
            showToast("剪貼簿尚無調光參數")
            return
        }
        
        if !selectedIndexes.isEmpty {
            // Batch paste to all selected images
            var count = 0
            for idx in selectedIndexes where idx >= 0 && idx < displayedImages.count {
                let item = displayedImages[idx]
                lightCorrections[item.url.path] = copied
                isAutoLightEnabled[item.url.path] = !copied.isNeutral
                count += 1
            }
            showToast("已將調光參數同步套用至 \(count) 張照片")
        } else if let image = selectedImage {
            // Paste to single image
            let key = image.url.path
            lightCorrections[key] = copied
            isAutoLightEnabled[key] = !copied.isNeutral
            showToast("已套用調光參數")
        }
    }
    
    /// Batch run Auto Light Correction on all selected images (or all displayed images)
    public func batchAutoLightCorrectionForSelected() {
        let targets: [ImageItem]
        if !selectedIndexes.isEmpty {
            targets = selectedIndexes.compactMap { idx in
                guard idx >= 0 && idx < displayedImages.count else { return nil }
                return displayedImages[idx]
            }
        } else {
            targets = displayedImages
        }
        
        guard !targets.isEmpty else { return }
        showToast("正在批次校光 \(targets.count) 張照片...")
        
        Task {
            var processed = 0
            for item in targets {
                let key = item.url.path
                let thumbnail: CGImage
                if let cached = thumbnails[key] {
                    thumbnail = cached
                } else {
                    guard let loaded = try? await ImageLoaderService.shared.loadThumbnail(from: item.url, maxPixelSize: 320) else { continue }
                    thumbnail = loaded
                }
                var params = ImageLoaderService.shared.calculateAutoLightCorrection(for: thumbnail, includeWhiteBalance: false)
                if let existing = self.lightCorrections[key] {
                    params.temperature = existing.temperature
                    params.tint = existing.tint
                }
                self.lightCorrections[key] = params
                self.isAutoLightEnabled[key] = true
                processed += 1
            }
            self.showToast("已完成 \(processed) 張照片批次一鍵校光")
        }
    }
    
    /// Update manual correction parameters for the selected image
    public func updateLightCorrection(for image: ImageItem, params: LightCorrectionParams) {
        let key = image.url.path
        lightCorrections[key] = params
    }
    
    // MARK: - Portrait Beauty & Retouching
    
    @Published public var isSpotRemovalModeActive: Bool = false
    @Published public var spotBrushRadius: CGFloat = 24.0
    
    public func toggleRedEyeCorrectionForSelected() {
        guard let image = selectedImage else { return }
        let key = image.url.path
        var current = lightCorrections[key] ?? .neutral
        current.redEyeCorrection.toggle()
        lightCorrections[key] = current
        showToast(current.redEyeCorrection ? "已啟用智慧紅眼校正" : "已關閉紅眼校正")
    }
    
    public func toggleSpotRemovalMode() {
        isSpotRemovalModeActive.toggle()
        showToast(isSpotRemovalModeActive ? "已開啟污漬修復模式 (B)：點擊畫面斑點即可消除" : "已關閉污漬修復模式")
    }
    
    public func addSpotRemoval(normalizedPoint: CGPoint, normalizedRadius: CGFloat) {
        guard let image = selectedImage else { return }
        let key = image.url.path
        var current = lightCorrections[key] ?? .neutral
        let spot = SpotRemovalItem(normalizedX: normalizedPoint.x, normalizedY: normalizedPoint.y, radius: normalizedRadius)
        current.spotRemovals.append(spot)
        lightCorrections[key] = current
        showToast("已修復污漬斑點 (共 \(current.spotRemovals.count) 處)")
    }
    
    public func undoLastSpotRemoval() {
        guard let image = selectedImage else { return }
        let key = image.url.path
        var current = lightCorrections[key] ?? .neutral
        guard !current.spotRemovals.isEmpty else { return }
        current.spotRemovals.removeLast()
        lightCorrections[key] = current
        showToast("已復原上一個污漬修復 (剩餘 \(current.spotRemovals.count) 處)")
    }
    
    public func clearAllSpotRemovals() {
        guard let image = selectedImage else { return }
        let key = image.url.path
        var current = lightCorrections[key] ?? .neutral
        current.spotRemovals.removeAll()
        lightCorrections[key] = current
        showToast("已清除所有污漬修復點")
    }
    
    public func updateSkinSmoothing(to value: Float) {
        guard let image = selectedImage else { return }
        let key = image.url.path
        var current = lightCorrections[key] ?? .neutral
        current.skinSmoothing = max(0.0, min(1.0, value))
        lightCorrections[key] = current
    }
    
    public func updateSkinToneProtection(to value: Float) {
        guard let image = selectedImage else { return }
        let key = image.url.path
        var current = lightCorrections[key] ?? .neutral
        current.skinToneProtection = max(0.0, min(1.0, value))
        lightCorrections[key] = current
    }
    
    /// Look-ahead prefetching of adjacent images for seamless ACDSee-style culling
    public func prefetchAdjacentImages() {
        guard let currentIndex = selectedImageIndex, !displayedImages.isEmpty else { return }
        
        let prefetchWindow = hardwareProfile.recommendedPrefetchWindow
        var indicesToPrefetch: [Int] = []
        
        for offset in 1...prefetchWindow {
            let nextIndex = currentIndex + offset
            let prevIndex = currentIndex - offset
            
            if nextIndex < displayedImages.count {
                indicesToPrefetch.append(nextIndex)
            }
            if prevIndex >= 0 {
                indicesToPrefetch.append(prevIndex)
            }
        }
        
        // Map to ImageItems and run light background preloading
        let items = indicesToPrefetch.map { displayedImages[$0] }
        loadThumbnailsAndMetadata(for: items, generation: loadGeneration)
    }
    
    // Centralized Culling Actions for specific items
    public func updateRating(for item: ImageItem, to rating: Int) {
        let key = item.url.path
        var metadata = exifMetadata[key] ?? ImageMetadata(id: key, url: item.url, filename: item.filename)
        metadata.rating = rating
        exifMetadata[key] = metadata
        
        Task {
            try? await exifRepo?.updateRating(for: key, rating: rating)
            XmpMetadataWriter.writeXmpSidecar(for: item.url, rating: rating, isTagged: metadata.isTagged)
        }
        
        if filterRating > 0 {
            updateDisplayedImages()
        }
    }
    
    public func toggleTagged(for item: ImageItem) {
        let key = item.url.path
        var metadata = exifMetadata[key] ?? ImageMetadata(id: key, url: item.url, filename: item.filename)
        metadata.isTagged.toggle()
        let newTagged = metadata.isTagged
        exifMetadata[key] = metadata
        
        Task {
            try? await exifRepo?.updateTagged(for: key, isTagged: newTagged)
            XmpMetadataWriter.writeXmpSidecar(for: item.url, rating: metadata.rating, isTagged: newTagged)
        }
        
        if filterTaggedOnly {
            updateDisplayedImages()
        }
        
        showToast(newTagged ? "已新增標籤" : "已移除標籤")
    }
    
    // Selection Culling Actions (triggered by keyboard or global buttons)
    public func updateRatingForSelected(to rating: Int) {
        let index: Int
        if isCompareActive {
            let compareItems = Array(selectedIndexes).sorted()
            guard focusedCompareIndex >= 0, focusedCompareIndex < compareItems.count else { return }
            index = compareItems[focusedCompareIndex]
        } else {
            guard let selIdx = selectedImageIndex, selIdx >= 0, selIdx < displayedImages.count else { return }
            index = selIdx
        }
        
        let item = displayedImages[index]
        updateRating(for: item, to: rating)
        showToast("評等已更新為 \(rating) 星")
    }
    
    public func toggleTaggedForSelected() {
        let index: Int
        if isCompareActive {
            let compareItems = Array(selectedIndexes).sorted()
            guard focusedCompareIndex >= 0, focusedCompareIndex < compareItems.count else { return }
            index = compareItems[focusedCompareIndex]
        } else {
            guard let selIdx = selectedImageIndex, selIdx >= 0, selIdx < displayedImages.count else { return }
            index = selIdx
        }
        
        let item = displayedImages[index]
        toggleTagged(for: item)
    }
    
    public func deleteSelectedImage() {
        if isCompareActive {
            let compareItems = Array(selectedIndexes).sorted()
            guard focusedCompareIndex >= 0, focusedCompareIndex < compareItems.count else { return }
            let index = compareItems[focusedCompareIndex]
            let item = displayedImages[index]
            let fileURL = item.url
            
            LoggerManager.shared.log("Trashing file from compare: \(fileURL.path)", level: .info)
            NSWorkspace.shared.recycle([fileURL])
            if let imgIndex = images.firstIndex(where: { $0.url == fileURL }) {
                images.remove(at: imgIndex)
            }
            selectedIndexes.remove(index)
            if selectedIndexes.isEmpty {
                isCompareActive = false
            } else if focusedCompareIndex >= selectedIndexes.count {
                focusedCompareIndex = max(0, selectedIndexes.count - 1)
            }
            updateDisplayedImages()
            showToast("已將 \(item.filename) 移至資源回收桶")
            return
        }
        
        if selectedIndexes.count > 1 {
            let sortedIndices = Array(selectedIndexes).sorted(by: >)
            var urlsToRecycle: [URL] = []
            var count = 0
            for idx in sortedIndices {
                if idx >= 0 && idx < displayedImages.count {
                    let item = displayedImages[idx]
                    urlsToRecycle.append(item.url)
                    count += 1
                }
            }
            guard !urlsToRecycle.isEmpty else { return }
            LoggerManager.shared.log("Trashing \(count) files", level: .info)
            NSWorkspace.shared.recycle(urlsToRecycle)
            let urlSet = Set(urlsToRecycle)
            images.removeAll(where: { urlSet.contains($0.url) })
            clearSelectedIndexes()
            updateDisplayedImages()
            if displayedImages.isEmpty {
                selectedImageIndex = nil
            } else {
                let fallback = min(sortedIndices.last ?? 0, displayedImages.count - 1)
                selectedImageIndex = max(0, fallback)
                if let newIdx = selectedImageIndex {
                    selectedIndexes = [newIdx]
                }
            }
            if isDetailActive { calculateHistogramForSelected() }
            showToast("已將 \(count) 張相片移至資源回收桶")
            return
        }
        
        guard let selIdx = selectedImageIndex ?? selectedIndexes.first, selIdx >= 0, selIdx < displayedImages.count else { return }
        let index = selIdx
        let item = displayedImages[index]
        let fileURL = item.url
        
        LoggerManager.shared.log("Trashing file: \(fileURL.path)", level: .info)
        
        var nextSelectIndex: Int? = nil
        if displayedImages.count > 1 {
            if index < displayedImages.count - 1 {
                nextSelectIndex = index
            } else {
                nextSelectIndex = index - 1
            }
        }
        
        NSWorkspace.shared.recycle([fileURL])
        
        if let imgIndex = images.firstIndex(where: { $0.url == fileURL }) {
            images.remove(at: imgIndex)
        }
        
        // Adjust selected indexes after deletion
        var newSelectedIndexes = Set<Int>()
        for idx in selectedIndexes {
            if idx < index {
                newSelectedIndexes.insert(idx)
            } else if idx > index {
                newSelectedIndexes.insert(idx - 1)
            }
        }
        selectedIndexes = newSelectedIndexes
        
        selectedImageIndex = nextSelectIndex
        if let newIdx = selectedImageIndex {
            selectedIndexes.insert(newIdx)
        }
        
        updateDisplayedImages()
        if displayedImages.isEmpty {
            selectedImageIndex = nil
            isDetailActive = false
        } else if isDetailActive {
            calculateHistogramForSelected()
        }
        
        LoggerManager.shared.log("Successfully trashed \(item.filename)", level: .info)
        showToast("已將 \(item.filename) 移至資源回收桶")
    }
    
    private func setupKeyboardNotificationObserver() {
        keyboardObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("didReceiveKeyboardEvent"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, let event = notification.userInfo?["event"] as? NSEvent else { return }
            Task { @MainActor in
                self.handleKeyboardEvent(event)
            }
        }
    }
    
    private enum KeyCode {
        static let leftArrow: UInt16 = 123
        static let rightArrow: UInt16 = 124
        static let upArrow: UInt16 = 126
        static let downArrow: UInt16 = 125
        static let space: UInt16 = 49
        static let escape: UInt16 = 53
        static let fKey: UInt16 = 3
        static let enter: UInt16 = 36
        static let zKey: UInt16 = 6
        static let key1: UInt16 = 18
        static let key2: UInt16 = 19
        static let key3: UInt16 = 20
        static let key4: UInt16 = 21
        static let key5: UInt16 = 23
        static let key0: UInt16 = 29
        static let tKey: UInt16 = 17
        static let keypadEnter: UInt16 = 76
        static let delete: UInt16 = 51
        static let forwardDelete: UInt16 = 117
        static let hKey: UInt16 = 4
    }
    
    private func handleKeyboardEvent(_ event: NSEvent) {
        LoggerManager.shared.log("handleKeyboardEvent: keyCode=\(event.keyCode)", level: .debug)
        
        // Modal 1: FaceSwap Batch Review
        if isFaceSwapBatchReviewPresented {
            switch event.keyCode {
            case KeyCode.leftArrow:
                previousBatchReviewItem()
            case KeyCode.rightArrow:
                nextBatchReviewItem()
            case KeyCode.delete, KeyCode.forwardDelete, 7, KeyCode.space: // Delete, DEL, X, Space -> Keep Original
                decideBatchItem(at: faceSwapBatchReviewIndex, decision: .keptOriginal)
            case KeyCode.enter, KeyCode.keypadEnter, 1: // Enter, Keypad Enter, S -> Save Swapped
                decideBatchItem(at: faceSwapBatchReviewIndex, decision: .saved)
            case KeyCode.escape, 15: // Esc, R -> Return to browsing
                closeFaceSwapBatchReview()
            default:
                break
            }
            return
        }
        
        // Modal 2: FaceSwap Single Preview
        if isFaceSwapPreviewPresented {
            switch event.keyCode {
            case KeyCode.delete, KeyCode.forwardDelete, KeyCode.escape, 7: // Delete, DEL, Esc, X -> Discard
                discardFaceSwapResult()
            case KeyCode.enter, KeyCode.keypadEnter, 1: // Enter, Keypad Enter, S -> Save
                saveFaceSwapResult(destination: .sameFolder)
            default:
                break
            }
            return
        }
        
        // Modal 3: FaceSwap Setup
        if isFaceSwapSetupPresented {
            switch event.keyCode {
            case KeyCode.escape:
                if !isFaceSwapProcessing {
                    isFaceSwapSetupPresented = false
                }
            default:
                break
            }
            return
        }
        
        // Modal 4: Shortcut Guide Sheet
        if isShortcutSheetVisible {
            if event.keyCode == KeyCode.escape {
                isShortcutSheetVisible = false
                return
            }
        }
        
        // Modal 5: Compare Arena Navigation
        if isCompareActive {
            let total = min(4, selectedIndexes.count)
            switch event.keyCode {
            case KeyCode.leftArrow:
                if focusedCompareIndex > 0 {
                    focusedCompareIndex -= 1
                }
                return
            case KeyCode.rightArrow:
                if focusedCompareIndex < total - 1 {
                    focusedCompareIndex += 1
                }
                return
            case KeyCode.escape:
                isCompareActive = false
                return
            default:
                break
            }
        }
        
        let isShift = event.modifierFlags.contains(.shift)
        let isCmd = event.modifierFlags.contains(.command)
        
        // Standard Grid / Detail / Compare Keyboard Navigation
        switch event.keyCode {
        case KeyCode.leftArrow:
            selectPreviousImage(extendSelection: isShift && !isDetailActive)
        case KeyCode.rightArrow:
            selectNextImage(extendSelection: isShift && !isDetailActive)
        case KeyCode.upArrow:
            if isCmd {
                selectFirstImage()
            } else {
                selectImageAbove(extendSelection: isShift && !isDetailActive)
            }
        case KeyCode.downArrow:
            if isCmd {
                selectLastImage()
            } else {
                selectImageBelow(extendSelection: isShift && !isDetailActive)
            }
        case KeyCode.space:
            isDetailActive.toggle()
        case KeyCode.escape:
            if isDetailActive {
                isDetailActive = false
            }
            isCompareActive = false
            isShortcutSheetVisible = false
        case 1: // S Key (AI FaceSwap)
            if !isFaceSwapSetupPresented && !isFaceSwapPreviewPresented {
                openFaceSwapSetup()
            }
        case KeyCode.fKey, KeyCode.enter, KeyCode.keypadEnter:
            toggleFullScreen()
        case KeyCode.zKey:
            toggleZoom()
        case 46: // M Key
            moveSelectedImageToDestination()
        case 37: // L Key
            isLoupeEnabled.toggle()
            showToast(isLoupeEnabled ? "已開啟放大鏡 (L)" : "已關閉放大鏡")
        case KeyCode.key1:
            updateRatingForSelected(to: 1)
        case KeyCode.key2:
            updateRatingForSelected(to: 2)
        case KeyCode.key3:
            updateRatingForSelected(to: 3)
        case KeyCode.key4:
            updateRatingForSelected(to: 4)
        case KeyCode.key5:
            updateRatingForSelected(to: 5)
        case KeyCode.key0:
            updateRatingForSelected(to: 0)
        case KeyCode.tKey:
            toggleTaggedForSelected()
        case 14: // E Key (Auto Exposure / Auto Light)
            if isDetailActive {
                toggleAutoLightForSelected()
            }
        case 13: // W Key (Auto White Balance)
            if isDetailActive {
                toggleAutoWhiteBalanceForSelected()
            }
        case 11: // B Key (Spot / Blemish Removal mode)
            if isDetailActive {
                toggleSpotRemovalMode()
            }
        case 38: // J Key (Lightroom Clipping Warning toggle)
            if isDetailActive {
                toggleClippingWarning()
            }
        case 8: // C Key (Cmd+C: Copy Settings)
            if event.modifierFlags.contains(.command) {
                copyLightCorrectionForSelected()
            }
        case 9: // V Key (Cmd+V: Paste / Sync Settings)
            if event.modifierFlags.contains(.command) {
                pasteLightCorrectionToSelected()
            }
        case 42: // Backslash \ Key (Lightroom Before/After toggle)
            if isDetailActive {
                isBeforeAfterComparisonActive.toggle()
                showToast(isBeforeAfterComparisonActive ? "已開啟前後對比 (\\)" : "已關閉前後對比")
            }
        case 44: // '?' or '/' Key (Shortcut Guide)
            isShortcutSheetVisible.toggle()
        case 34: // 'I' Key (Toggle Inspector Sidebar)
            if isDetailActive {
                isSidebarOpenInDetail.toggle()
            }
        case 3: // 'F' Key (Toggle Filmstrip)
            if isDetailActive {
                isFilmstripVisible.toggle()
            }
        case KeyCode.delete, KeyCode.forwardDelete:
            deleteSelectedImage()
        case KeyCode.hKey:
            convertSelectedImagesToHEIC()
        case 45: // N Key (Apply Short Hash to Selected Filenames)
            applyShortHashToSelectedFilenames()
        case 0: // A Key (Cmd+A: Select All Images)
            if event.modifierFlags.contains(.command) && !isDetailActive {
                selectAllImages()
            }
        case 15: // R Key (Cmd+R or R: Toggle FaceSwap Confirmation Mode)
            if hasDetectedFaceSwaps || !faceSwapBatchItems.isEmpty {
                toggleFaceSwapBatchReview()
            }
        default:
            break
        }
    }
    
    private func loadFavorites() {
        let paths = UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []
        let bookmarksMap = UserDefaults.standard.dictionary(forKey: "com.project.lumina.bookmarks") as? [String: Data] ?? [:]
        
        var resolvedFavorites: [URL] = []
        for path in paths {
            if let data = bookmarksMap[path] {
                do {
                    var isStale = false
                    let url = try URL(
                        resolvingBookmarkData: data,
                        options: .withSecurityScope,
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )
                    if isStale {
                        SecurityScopedBookmarkManager.shared.saveBookmark(for: url)
                    }
                    resolvedFavorites.append(url)
                } catch {
                    LoggerManager.shared.log("Failed to resolve favorite bookmark for \(path): \(error.localizedDescription)", level: .error)
                    let url = URL(fileURLWithPath: path)
                    resolvedFavorites.append(url)
                }
            } else {
                let url = URL(fileURLWithPath: path)
                resolvedFavorites.append(url)
            }
        }
        self.favoriteFolders = resolvedFavorites
    }
    
    public func isFavorite(_ url: URL) -> Bool {
        return favoriteFolders.contains(where: { $0.path == url.path })
    }
    
    public func toggleFavorite(_ url: URL) {
        let path = url.path
        var paths = UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []
        
        if let index = paths.firstIndex(of: path) {
            paths.remove(at: index)
            favoriteFolders.removeAll(where: { $0.path == path })
        } else {
            paths.append(path)
            SecurityScopedBookmarkManager.shared.saveBookmark(for: url)
            if !favoriteFolders.contains(where: { $0.path == path }) {
                favoriteFolders.append(url)
            }
        }
        UserDefaults.standard.set(paths, forKey: favoritesKey)
    }
    
    // MARK: - Recent Folders System
    public func addRecentFolder(_ url: URL) {
        var recents = self.recentFolders.filter { $0.path != url.path }
        recents.insert(url, at: 0)
        if recents.count > 8 {
            recents = Array(recents.prefix(8))
        }
        self.recentFolders = recents
        saveRecentFolders()
    }
    
    private func saveRecentFolders() {
        let paths = recentFolders.map { $0.path }
        UserDefaults.standard.set(paths, forKey: recentFoldersKey)
    }
    
    private func loadRecentFolders() {
        let paths = UserDefaults.standard.stringArray(forKey: recentFoldersKey) ?? []
        let bookmarksMap = UserDefaults.standard.dictionary(forKey: "com.project.lumina.bookmarks") as? [String: Data] ?? [:]
        var loaded: [URL] = []
        for path in paths {
            if let data = bookmarksMap[path] {
                do {
                    var isStale = false
                    let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                    _ = url.startAccessingSecurityScopedResource()
                    loaded.append(url)
                } catch {
                    loaded.append(URL(fileURLWithPath: path))
                }
            } else {
                loaded.append(URL(fileURLWithPath: path))
            }
        }
        self.recentFolders = loaded
    }
    
    // Toast System
    public func showToast(_ message: String) {
        Task { @MainActor in
            self.toastMessage = message
            self.toastTimer?.cancel()
            self.toastTimer = Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if !Task.isCancelled {
                    self.toastMessage = nil
                }
            }
        }
    }
    
    // Culling Destination
    private func loadCullingDestination() {
        if let data = UserDefaults.standard.data(forKey: cullingDestinationKey) {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if isStale {
                    SecurityScopedBookmarkManager.shared.saveBookmark(for: url)
                }
                _ = url.startAccessingSecurityScopedResource()
                self.cullingDestinationFolder = url
            } catch {
                LoggerManager.shared.log("Failed to resolve culling destination bookmark: \(error.localizedDescription)", level: .error)
            }
        }
    }
    
    public func selectCullingDestinationFolder() {
        Task { @MainActor in
            let openPanel = NSOpenPanel()
            openPanel.title = "選取選片搬移目標資料夾"
            openPanel.showsResizeIndicator = true
            openPanel.showsHiddenFiles = false
            openPanel.canChooseFiles = false
            openPanel.canChooseDirectories = true
            openPanel.allowsMultipleSelection = false
            
            if openPanel.runModal() == .OK {
                if let url = openPanel.url {
                    do {
                        let data = try url.bookmarkData(
                            options: .withSecurityScope,
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil
                        )
                        UserDefaults.standard.set(data, forKey: cullingDestinationKey)
                        _ = url.startAccessingSecurityScopedResource()
                        self.cullingDestinationFolder = url
                        self.showToast("已設定選片目標：\(url.lastPathComponent)")
                    } catch {
                        LoggerManager.shared.log("Failed to create bookmark for culling destination: \(error.localizedDescription)", level: .error)
                    }
                }
            }
        }
    }
    
    public func moveSelectedImageToDestination() {
        let index: Int
        if isCompareActive {
            let compareItems = Array(selectedIndexes).sorted()
            guard focusedCompareIndex >= 0, focusedCompareIndex < compareItems.count else { return }
            index = compareItems[focusedCompareIndex]
        } else {
            guard let selIdx = selectedImageIndex, selIdx >= 0, selIdx < displayedImages.count else { return }
            index = selIdx
        }
        
        guard let destFolder = cullingDestinationFolder else {
            selectCullingDestinationFolder()
            return
        }
        
        let item = displayedImages[index]
        let sourceURL = item.url
        let destURL = destFolder.appendingPathComponent(item.filename)
        
        LoggerManager.shared.log("Moving file: \(sourceURL.path) to \(destURL.path)", level: .info)
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            let sourceAccess = SecurityScopedBookmarkManager.shared.performAccessingSecurityScopedResource(at: sourceURL.deletingLastPathComponent()) { () -> Bool in
                let destAccess = SecurityScopedBookmarkManager.shared.performAccessingSecurityScopedResource(at: destFolder) { () -> Bool in
                    do {
                        let fileManager = FileManager.default
                        var finalDestURL = destURL
                        if fileManager.fileExists(atPath: destURL.path) {
                            let ext = destURL.pathExtension
                            let nameWithoutExt = destURL.deletingPathExtension().lastPathComponent
                            var counter = 1
                            while fileManager.fileExists(atPath: finalDestURL.path) {
                                finalDestURL = destFolder.appendingPathComponent("\(nameWithoutExt)_\(counter)").appendingPathExtension(ext)
                                counter += 1
                            }
                        }
                        
                        try fileManager.moveItem(at: sourceURL, to: finalDestURL)
                        return true
                    } catch {
                        LoggerManager.shared.log("Failed to move file: \(error.localizedDescription)", level: .error)
                        return false
                    }
                }
                return destAccess
            }
            
            if sourceAccess {
                await MainActor.run {
                    var nextSelectIndex: Int? = nil
                    if self.displayedImages.count > 1 {
                        if index < self.displayedImages.count - 1 {
                            nextSelectIndex = index
                        } else {
                            nextSelectIndex = index - 1
                        }
                    }
                    
                    if let imgIndex = self.images.firstIndex(where: { $0.url == sourceURL }) {
                        self.images.remove(at: imgIndex)
                    }
                    
                    // Adjust selected indexes after move
                    var newSelectedIndexes = Set<Int>()
                    for idx in self.selectedIndexes {
                        if idx < index {
                            newSelectedIndexes.insert(idx)
                        } else if idx > index {
                            newSelectedIndexes.insert(idx - 1)
                        }
                    }
                    self.selectedIndexes = newSelectedIndexes
                    
                    if self.isCompareActive {
                        if self.selectedIndexes.isEmpty {
                            self.isCompareActive = false
                        } else if self.focusedCompareIndex >= self.selectedIndexes.count {
                            self.focusedCompareIndex = max(0, self.selectedIndexes.count - 1)
                        }
                    } else {
                        self.selectedImageIndex = nextSelectIndex
                    }
                    
                    self.updateDisplayedImages()
                    if self.isDetailActive { self.calculateHistogramForSelected() }
                    
                    self.showToast("已搬移 \(item.filename) 至目標資料夾")
                }
            } else {
                await MainActor.run {
                    self.showToast("搬移失敗，請檢查權限")
                }
            }
        }
    }
    
    // Multi-Select & Compare Mode helpers
    public func toggleSelectIndex(_ index: Int) {
        if selectedIndexes.contains(index) {
            selectedIndexes.remove(index)
            if selectedImageIndex == index {
                selectedImageIndex = selectedIndexes.sorted().first
            }
        } else {
            selectedIndexes.insert(index)
            selectedImageIndex = index
        }
    }
    
    public func clearSelectedIndexes() {
        selectedIndexes.removeAll()
    }
    
    public func selectAllImages() {
        guard !displayedImages.isEmpty else { return }
        selectedIndexes = Set(0..<displayedImages.count)
        if selectedImageIndex == nil {
            selectedImageIndex = 0
        }
        showToast("已全選 \(displayedImages.count) 張相片 (⌘A)")
    }
    
    public func deselectAllImages() {
        selectedIndexes.removeAll()
        selectedImageIndex = nil
        showToast("已取消選取相片")
    }
    
    public func selectRange(from start: Int, to end: Int) {
        guard !displayedImages.isEmpty else { return }
        let low = max(0, min(start, end))
        let high = min(displayedImages.count - 1, max(start, end))
        for i in low...high {
            selectedIndexes.insert(i)
        }
        selectedImageIndex = end
    }
    
    // MARK: - FaceSwap Actions
    
    public func loadFaceSwapSettings() {
        if let url = FaceSwapService.shared.readApiServerUrl() {
            self.faceSwapApiUrl = url
        }
    }
    
    public func saveFaceSwapApiUrl(_ newUrl: String) {
        do {
            try FaceSwapService.shared.saveApiServerUrl(newUrl)
            self.faceSwapApiUrl = newUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            showToast("已更新 FaceSwap API 端點設定")
        } catch {
            showToast("儲存設定失敗: \(error.localizedDescription)")
        }
    }
    
    public func testFaceSwapConnection(url: String) {
        self.faceSwapConnectionStatus = .testing
        self.faceSwapConnectionMessage = "正在測試連線..."
        
        Task {
            let res = await FaceSwapService.shared.testApiConnection(urlString: url)
            await MainActor.run {
                if res.success {
                    self.faceSwapConnectionStatus = .connected(latencyMs: res.latencyMs)
                    self.faceSwapConnectionMessage = "\(res.message) (\(res.latencyMs)ms)"
                } else {
                    self.faceSwapConnectionStatus = .failed(error: res.message)
                    self.faceSwapConnectionMessage = res.message
                }
            }
        }
    }
    
    public func loadSourceFaces() {
        let faces = FaceSwapService.shared.loadAvailableSourceFaces()
        self.availableSourceFaces = faces
        if selectedSourceFace == nil, let first = faces.first {
            selectedSourceFace = first
        }
    }
    
    public func openFaceSwapSetup(for item: ImageItem? = nil, mode: FaceSwapBatchTargetMode = .single) {
        loadSourceFaces()
        loadFaceSwapSettings()
        self.faceSwapBatchTargetMode = mode
        self.faceSwapErrorMessage = nil
        self.faceSwapStatusMessage = ""
        
        switch mode {
        case .single:
            let target = item ?? selectedImage
            guard let target = target else {
                showToast("請先選取一張目標相片以進行換臉")
                return
            }
            self.faceSwapTargetImage = target
            self.faceSwapBatchTargets = [target.url]
            
        case .folder:
            if let currentFolder = selectedFolder {
                self.faceSwapBatchFolderURL = currentFolder
                let validExts: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "heif", "dng", "tiff"]
                let folderImages = self.images.map { $0.url }.filter { validExts.contains($0.pathExtension.lowercased()) }
                self.faceSwapBatchTargets = folderImages
            } else {
                chooseCustomBatchFolder()
            }
            
        case .selected:
            let selectedURLs = selectedIndexes.compactMap { idx -> URL? in
                guard idx < displayedImages.count else { return nil }
                return displayedImages[idx].url
            }
            if selectedURLs.isEmpty, let single = item ?? selectedImage {
                self.faceSwapBatchTargets = [single.url]
            } else {
                self.faceSwapBatchTargets = selectedURLs
            }
        }
        
        self.isFaceSwapSetupPresented = true
    }
    
    public func chooseCustomBatchFolder() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.prompt = "選擇此相片資料夾"
        openPanel.message = "請選擇包含目標相片的資料夾以進行批次 AI 換臉"
        
        if openPanel.runModal() == .OK, let folderURL = openPanel.url {
            self.faceSwapBatchFolderURL = folderURL
            let validExts: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "heif", "dng", "tiff"]
            if let enumerator = FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                var found: [URL] = []
                for case let fileURL as URL in enumerator {
                    if validExts.contains(fileURL.pathExtension.lowercased()) {
                        found.append(fileURL)
                    }
                }
                self.faceSwapBatchTargets = found.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            }
        }
    }
    
    public func setFaceSwapTargetMode(_ mode: FaceSwapBatchTargetMode) {
        self.faceSwapBatchTargetMode = mode
        switch mode {
        case .single:
            if let target = faceSwapTargetImage ?? selectedImage {
                self.faceSwapTargetImage = target
                self.faceSwapBatchTargets = [target.url]
            } else if let first = images.first {
                self.faceSwapTargetImage = first
                self.faceSwapBatchTargets = [first.url]
            }
        case .folder:
            if faceSwapBatchFolderURL == nil {
                faceSwapBatchFolderURL = selectedFolder
            }
            selectAllFolderTargets()
        case .selected:
            let selectedURLs = selectedIndexes.sorted().compactMap { idx -> URL? in
                guard idx < displayedImages.count else { return nil }
                return displayedImages[idx].url
            }
            if !selectedURLs.isEmpty {
                self.faceSwapBatchTargets = selectedURLs
            } else if let single = selectedImage {
                self.faceSwapBatchTargets = [single.url]
            }
        }
    }
    
    public func selectAllFolderTargets() {
        let validExts: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "heif", "dng", "tiff"]
        let folder = faceSwapBatchFolderURL ?? selectedFolder
        guard let folder = folder else { return }
        
        if folder.path == selectedFolder?.path {
            let folderImages = self.images.map { $0.url }.filter { validExts.contains($0.pathExtension.lowercased()) }
            self.faceSwapBatchTargets = folderImages
        } else {
            if let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                var found: [URL] = []
                for case let fileURL as URL in enumerator {
                    if validExts.contains(fileURL.pathExtension.lowercased()) {
                        found.append(fileURL)
                    }
                }
                self.faceSwapBatchTargets = found.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            }
        }
        showToast("已全選資料夾內 \(faceSwapBatchTargets.count) 張相片")
    }
    
    public func deselectAllFolderTargets() {
        self.faceSwapBatchTargets.removeAll()
        showToast("已清空換臉相片選取")
    }
    
    public func toggleBatchTargetURL(_ url: URL) {
        if let idx = faceSwapBatchTargets.firstIndex(where: { $0.path == url.path }) {
            faceSwapBatchTargets.remove(at: idx)
        } else {
            faceSwapBatchTargets.append(url)
            faceSwapBatchTargets.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
    }
    
    public func startFaceSwap() {
        if faceSwapBatchTargetMode == .single {
            startSingleFaceSwap()
        } else {
            startBatchFaceSwap()
        }
    }
    
    private func startSingleFaceSwap() {
        guard let target = faceSwapTargetImage else {
            showToast("未指定目標相片")
            return
        }
        
        self.isFaceSwapProcessing = true
        self.faceSwapErrorMessage = nil
        self.faceSwapStatusMessage = "正在連線 FaceFusion 伺服器..."
        
        let stagingDir = resolveFaceSwapStagingDirectory(for: [target.url])
        self.currentFaceSwapStagingDir = stagingDir
        
        let sourceURL = selectedSourceFace?.url
        let blend = self.faceEnhancerBlend
        let api = self.faceSwapApiUrl
        
        Task {
            do {
                let result = try await FaceSwapService.shared.runFaceSwap(
                    targetURL: target.url,
                    sourceFaceURL: sourceURL,
                    blend: blend,
                    apiUrl: api,
                    stagingDirectoryURL: stagingDir
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.faceSwapStatusMessage = progress
                    }
                }
                
                await MainActor.run {
                    self.currentFaceSwapResult = result
                    self.isFaceSwapProcessing = false
                    self.isFaceSwapSetupPresented = false
                    self.faceSwapPreviewMode = .sideBySide
                    self.isFaceSwapPreviewPresented = true
                    self.faceSwapSplitPosition = 0.5
                    self.showToast("✨ AI 換臉成功！請比對成果後決定是否儲存")
                }
            } catch {
                await MainActor.run {
                    self.isFaceSwapProcessing = false
                    self.faceSwapErrorMessage = error.localizedDescription
                    self.showToast("換臉失敗: \(error.localizedDescription)")
                }
            }
        }
    }
    
    public func startBatchFaceSwap() {
        guard !faceSwapBatchTargets.isEmpty else {
            showToast("批次目標列表為空，請指定相片資料夾或勾選相片")
            return
        }
        
        self.isFaceSwapProcessing = true
        self.isFaceSwapBatchProcessing = true
        self.faceSwapErrorMessage = nil
        self.faceSwapBatchCurrentIndex = 0
        self.faceSwapBatchTotalCount = faceSwapBatchTargets.count
        self.faceSwapBatchItems = faceSwapBatchTargets.map { FaceSwapBatchItem(targetURL: $0, decision: .pending) }
        self.faceSwapStatusMessage = "正在初始化批次工作佇列 (共 \(faceSwapBatchTargets.count) 張)..."
        
        let stagingDir = resolveFaceSwapStagingDirectory(for: faceSwapBatchTargets)
        self.currentFaceSwapStagingDir = stagingDir
        
        let sourceURL = selectedSourceFace?.url
        let blend = self.faceEnhancerBlend
        let targets = self.faceSwapBatchTargets
        let api = self.faceSwapApiUrl
        
        Task {
            do {
                let items = try await FaceSwapService.shared.runBatchFaceSwap(
                    targetURLs: targets,
                    sourceFaceURL: sourceURL,
                    blend: blend,
                    apiUrl: api,
                    stagingDirectoryURL: stagingDir,
                    onProgress: { [weak self] cur, total, line in
                        Task { @MainActor in
                            self?.faceSwapBatchCurrentIndex = cur
                            self?.faceSwapBatchTotalCount = total
                            self?.faceSwapStatusMessage = line
                        }
                    },
                    onItemCompleted: { [weak self] completedResult in
                        Task { @MainActor in
                            if let idx = self?.faceSwapBatchItems.firstIndex(where: { $0.targetURL.path == completedResult.targetURL.path }) {
                                self?.faceSwapBatchItems[idx].result = completedResult
                            }
                            self?.faceSwapResultByTargetURL[completedResult.targetURL.standardizedFileURL.path] = completedResult
                        }
                    },
                    onItemFailed: { [weak self] failedURL, errorMsg in
                        Task { @MainActor in
                            if let idx = self?.faceSwapBatchItems.firstIndex(where: { $0.targetURL.path == failedURL.path }) {
                                self?.faceSwapBatchItems[idx].errorMessage = errorMsg
                            }
                        }
                    }
                )
                
                await MainActor.run {
                    self.faceSwapBatchItems = items
                    self.saveFaceSwapManifest(items: items, to: stagingDir)
                    self.syncDetectedFaceSwaps(with: items)
                    self.isFaceSwapProcessing = false
                    self.isFaceSwapBatchProcessing = false
                    self.isFaceSwapSetupPresented = false
                    self.faceSwapBatchReviewIndex = 0
                    self.faceSwapPreviewMode = .sideBySide
                    self.isFaceSwapBatchReviewPresented = true
                    let successCount = items.filter { $0.result != nil }.count
                    self.showToast("🎉 批次運算完成 (成功 \(successCount)/\(items.count))！進入逐張審查比對")
                }
            } catch {
                await MainActor.run {
                    self.isFaceSwapProcessing = false
                    self.isFaceSwapBatchProcessing = false
                    self.faceSwapErrorMessage = error.localizedDescription
                    self.showToast("批次換臉中斷: \(error.localizedDescription)")
                }
            }
        }
    }
    
    public func cancelFaceSwap() {
        FaceSwapService.shared.cancelRunningSwap()
        self.isFaceSwapProcessing = false
        self.isFaceSwapBatchProcessing = false
        self.faceSwapStatusMessage = "已取消換臉運算"
    }
    
    // MARK: - Batch Review Decisions
    
    public func decideBatchItem(at index: Int, decision: FaceSwapDecision, destination: FaceSwapSaveDestination? = nil) {
        guard index >= 0 && index < faceSwapBatchItems.count else { return }
        faceSwapBatchItems[index].decision = decision
        
        let item = faceSwapBatchItems[index]
        if decision == .saved {
            showToast("已標記儲存取代: \(item.filename)")
        } else if decision == .keptOriginal {
            showToast("已標記保持原圖: \(item.filename)")
        }
        
        if faceSwapBatchReviewIndex < faceSwapBatchItems.count - 1 {
            nextBatchReviewItem()
        }
    }
    
    public func decideAllBatchItems(decision: FaceSwapDecision, destination: FaceSwapSaveDestination? = nil) {
        var count = 0
        for idx in 0..<faceSwapBatchItems.count {
            if faceSwapBatchItems[idx].decision == .pending {
                faceSwapBatchItems[idx].decision = decision
                count += 1
            }
        }
        
        if decision == .saved {
            showToast("✨ 已將 \(count) 張待決定相片標記為「儲存取代原檔」")
        } else {
            showToast("已將 \(count) 張待決定相片標記為「保持原圖」")
        }
    }
    
    public func nextBatchReviewItem() {
        if faceSwapBatchReviewIndex < faceSwapBatchItems.count - 1 {
            faceSwapBatchReviewIndex += 1
        }
    }
    
    public func previousBatchReviewItem() {
        if faceSwapBatchReviewIndex > 0 {
            faceSwapBatchReviewIndex -= 1
        }
    }
    
    public func applyBatchDecisionsAndFinish() {
        let fileManager = FileManager.default
        let itemsToSave = faceSwapBatchItems.filter { $0.decision == .saved && $0.result != nil }
        let itemsToKeep = faceSwapBatchItems.filter { $0.decision == .keptOriginal || $0.decision == .pending }
        let saveDest = faceSwapBatchSaveDestination
        var savedCount = 0
        var failCount = 0
        
        // 1. Process items marked as .saved -> replace original file with swapped photo
        for item in itemsToSave {
            guard let result = item.result else { continue }
            do {
                let savedURL = try performSaveFaceSwap(result: result, destination: saveDest)
                savedCount += 1
                
                // Ensure preview / temp swapped file is deleted if different from savedURL
                if result.previewOutputURL.path != savedURL.path && fileManager.fileExists(atPath: result.previewOutputURL.path) {
                    try? fileManager.removeItem(at: result.previewOutputURL)
                }
            } catch {
                LoggerManager.shared.log("Failed to save FaceSwap for \(item.filename): \(error.localizedDescription)", level: .error)
                failCount += 1
            }
        }
        
        // 2. Process items marked as .keptOriginal (or left .pending) -> keep original, discard swapped preview
        for item in itemsToKeep {
            if let result = item.result {
                let swappedURL = result.previewOutputURL
                if swappedURL.path != item.targetURL.path && fileManager.fileExists(atPath: swappedURL.path) {
                    // If preview was a file in the folder (e.g. a paired _swap file), safely recycle it
                    if swappedURL.deletingLastPathComponent().path == item.targetURL.deletingLastPathComponent().path {
                        NSWorkspace.shared.recycle([swappedURL])
                    } else {
                        try? fileManager.removeItem(at: swappedURL)
                    }
                }
            }
        }
        
        let keptCount = itemsToKeep.count
        
        // 3. Remove all staging folders (faceswap_temp) and manifest files
        if let stagingDir = self.currentFaceSwapStagingDir {
            try? fileManager.removeItem(at: stagingDir)
            self.currentFaceSwapStagingDir = nil
        }
        
        // Remove faceswap_temp & faceswap_manifest.json in selectedFolder
        if let folderURL = self.selectedFolder {
            let tempDir = folderURL.appendingPathComponent("faceswap_temp", isDirectory: true)
            try? fileManager.removeItem(at: tempDir)
            let manifestFile = folderURL.appendingPathComponent("faceswap_manifest.json")
            try? fileManager.removeItem(at: manifestFile)
            let outputManifest = folderURL.appendingPathComponent("output").appendingPathComponent("faceswap_manifest.json")
            try? fileManager.removeItem(at: outputManifest)
        }
        
        // Clean up faceswap_temp & faceswap_manifest.json in any unique target directories
        var checkedDirs = Set<String>()
        for item in faceSwapBatchItems {
            let dir = item.targetURL.deletingLastPathComponent()
            if !checkedDirs.contains(dir.path) {
                checkedDirs.insert(dir.path)
                let tempDir = dir.appendingPathComponent("faceswap_temp", isDirectory: true)
                try? fileManager.removeItem(at: tempDir)
                let manifest = dir.appendingPathComponent("faceswap_manifest.json")
                try? fileManager.removeItem(at: manifest)
            }
        }
        
        // Clean temporary preview directories in NSTemporaryDirectory
        let tempPreviewDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ProjectLumina/FaceSwapBatchPreview")
        try? fileManager.removeItem(at: tempPreviewDir)
        let tempFallback = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ProjectLumina/faceswap_temp")
        try? fileManager.removeItem(at: tempFallback)
        
        // 4. Reset batch review and detected items state so UI reflects clean state
        self.isFaceSwapBatchReviewPresented = false
        self.faceSwapBatchItems = []
        self.detectedFaceSwapItems = []
        self.detectedFaceSwapCount = 0
        self.hasDetectedFaceSwaps = false
        self.showDetectedFaceSwapBanner = false
        self.faceSwapResultByTargetURL = [:]
        
        // 5. Refresh folder contents so the grid displays only the final confirmed files
        self.refreshFolderContents()
        
        if failCount > 0 {
            showToast("完成審查: 已取代 \(savedCount) 張，失敗 \(failCount) 張 (原檔保留 \(keptCount) 張，已清理所有暫存)")
        } else if savedCount == 0 {
            showToast("🎉 批次審查完成！已保留全部 \(keptCount) 張原檔，已清理所有換臉暫存")
        } else {
            showToast("🎉 批次審查完成！已取代 \(savedCount) 張相片，保留 \(keptCount) 張原檔，已清理所有暫存")
        }
    }
    
    public func finishBatchReview(applyDecisions: Bool = false) {
        if applyDecisions {
            applyBatchDecisionsAndFinish()
            return
        }
        closeFaceSwapBatchReview()
    }
    
    public func closeFaceSwapBatchReview() {
        self.isFaceSwapBatchReviewPresented = false
        self.showToast("已返回相片瀏覽 (保留換臉進度，隨時可按 ⌘R 再次確認)")
    }
    
    public func toggleFaceSwapBatchReview() {
        if isFaceSwapBatchReviewPresented {
            closeFaceSwapBatchReview()
        } else {
            openFaceSwapBatchReview()
        }
    }
    
    public func openFaceSwapBatchReview(startIndex: Int? = nil) {
        if faceSwapBatchItems.isEmpty && !detectedFaceSwapItems.isEmpty {
            self.faceSwapBatchItems = detectedFaceSwapItems
        }
        guard !faceSwapBatchItems.isEmpty else {
            showToast("目前沒有可供比對審查的換臉相片")
            return
        }
        if let idx = startIndex, idx >= 0 && idx < faceSwapBatchItems.count {
            self.faceSwapBatchReviewIndex = idx
        } else if let selected = selectedImage,
                  let matchIdx = faceSwapBatchItems.firstIndex(where: { $0.targetURL.path == selected.url.path }) {
            self.faceSwapBatchReviewIndex = matchIdx
        } else {
            self.faceSwapBatchReviewIndex = 0
        }
        self.faceSwapPreviewMode = .sideBySide
        self.isFaceSwapBatchReviewPresented = true
    }
    
    public func openFaceSwapBatchReview(for item: ImageItem) {
        if let idx = displayedImages.firstIndex(where: { $0.id == item.id }) {
            self.selectedImageIndex = idx
            self.selectedIndexes = [idx]
        }
        openFaceSwapBatchReview()
    }
    
    public func discardAllFaceSwapStaging() {
        let fm = FileManager.default
        if let stagingDir = self.currentFaceSwapStagingDir {
            try? fm.removeItem(at: stagingDir)
            self.currentFaceSwapStagingDir = nil
        }
        
        if let folderURL = self.selectedFolder {
            let tempDir = folderURL.appendingPathComponent("faceswap_temp", isDirectory: true)
            try? fm.removeItem(at: tempDir)
            let manifestFile = folderURL.appendingPathComponent("faceswap_manifest.json")
            try? fm.removeItem(at: manifestFile)
            let outputManifest = folderURL.appendingPathComponent("output").appendingPathComponent("faceswap_manifest.json")
            try? fm.removeItem(at: outputManifest)
        }
        
        for item in faceSwapBatchItems {
            if let result = item.result {
                let swappedURL = result.previewOutputURL
                if swappedURL.path != item.targetURL.path && fm.fileExists(atPath: swappedURL.path) {
                    if swappedURL.deletingLastPathComponent().path == item.targetURL.deletingLastPathComponent().path {
                        NSWorkspace.shared.recycle([swappedURL])
                    } else {
                        try? fm.removeItem(at: swappedURL)
                    }
                }
            }
        }
        
        let tempPreviewDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ProjectLumina/FaceSwapBatchPreview")
        try? fm.removeItem(at: tempPreviewDir)
        let tempFallback = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ProjectLumina/faceswap_temp")
        try? fm.removeItem(at: tempFallback)
        
        self.isFaceSwapBatchReviewPresented = false
        self.faceSwapBatchItems = []
        self.detectedFaceSwapItems = []
        self.detectedFaceSwapCount = 0
        self.hasDetectedFaceSwaps = false
        self.showDetectedFaceSwapBanner = false
        self.faceSwapResultByTargetURL = [:]
        self.refreshFolderContents()
        self.showToast("已清空並放棄換臉暫存檔 (保留原圖)")
    }
    
    // MARK: - Detect Completed FaceSwaps in Folder
    
    public func checkForDetectedFaceSwaps(in folderURL: URL, images: [ImageItem]) {
        let fileManager = FileManager.default
        var pairedItems: [FaceSwapBatchItem] = []
        var resultMap: [String: FaceSwapResult] = [:]
        var seenTargetPaths = Set<String>()
        
        func addPair(targetURL: URL, previewOutputURL: URL, sourceFaceURL: URL? = nil) {
            let key = targetURL.standardizedFileURL.path
            guard !seenTargetPaths.contains(key) else { return }
            guard fileManager.fileExists(atPath: targetURL.path),
                  fileManager.fileExists(atPath: previewOutputURL.path) else { return }
            
            seenTargetPaths.insert(key)
            let result = FaceSwapResult(
                targetURL: targetURL,
                sourceFaceURL: sourceFaceURL,
                previewOutputURL: previewOutputURL,
                filename: previewOutputURL.lastPathComponent
            )
            let item = FaceSwapBatchItem(
                targetURL: targetURL,
                result: result,
                decision: .pending
            )
            pairedItems.append(item)
            resultMap[key] = result
        }
        
        let validImageExts: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "heif", "dng", "tiff"]
        
        // 1. Check faceswap_temp/faceswap_manifest.json or folder/faceswap_manifest.json
        let tempDir = folderURL.appendingPathComponent("faceswap_temp", isDirectory: true)
        let manifestURLs = [
            tempDir.appendingPathComponent("faceswap_manifest.json"),
            folderURL.appendingPathComponent("faceswap_manifest.json"),
            folderURL.appendingPathComponent("output").appendingPathComponent("faceswap_manifest.json")
        ]
        
        for manifestURL in manifestURLs {
            if fileManager.fileExists(atPath: manifestURL.path),
               let data = try? Data(contentsOf: manifestURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["items"] as? [[String: Any]] {
                for it in items {
                    if let tgtPath = it["target_path"] as? String,
                       let outPath = it["output_path"] as? String {
                        let tgtURL = URL(fileURLWithPath: tgtPath)
                        let outURL = URL(fileURLWithPath: outPath)
                        let srcPath = it["source_path"] as? String
                        let srcURL = (srcPath != nil && !srcPath!.isEmpty) ? URL(fileURLWithPath: srcPath!) : nil
                        addPair(targetURL: tgtURL, previewOutputURL: outURL, sourceFaceURL: srcURL)
                    }
                }
            }
        }
        
        // 2. Check files inside faceswap_temp (match target images by base name)
        if fileManager.fileExists(atPath: tempDir.path),
           let contents = try? fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            let tempImageFiles = contents.filter { validImageExts.contains($0.pathExtension.lowercased()) }
            
            for tempImg in tempImageFiles {
                let tempBase = tempImg.deletingPathExtension().lastPathComponent
                let strippedBase = tempBase.hasSuffix("_swap") ? String(tempBase.dropLast(5)) : tempBase
                
                if let matchedTarget = images.first(where: {
                    let tgtBase = $0.url.deletingPathExtension().lastPathComponent
                    return tgtBase.caseInsensitiveCompare(tempBase) == .orderedSame || tgtBase.caseInsensitiveCompare(strippedBase) == .orderedSame
                }) {
                    addPair(targetURL: matchedTarget.url, previewOutputURL: tempImg)
                }
            }
        }
        
        // 3. Check inside folder itself for files ending with _swap.<ext> or _faceswap.<ext>
        for img in images {
            let base = img.url.deletingPathExtension().lastPathComponent
            if base.lowercased().hasSuffix("_swap") {
                let origBase = String(base.dropLast(5))
                if let origImg = images.first(where: {
                    let otherBase = $0.url.deletingPathExtension().lastPathComponent
                    return otherBase.caseInsensitiveCompare(origBase) == .orderedSame && $0.url.path != img.url.path
                }) {
                    addPair(targetURL: origImg.url, previewOutputURL: img.url)
                }
            } else if base.lowercased().hasSuffix("_faceswap") {
                let origBase = String(base.dropLast(9))
                if let origImg = images.first(where: {
                    let otherBase = $0.url.deletingPathExtension().lastPathComponent
                    return otherBase.caseInsensitiveCompare(origBase) == .orderedSame && $0.url.path != img.url.path
                }) {
                    addPair(targetURL: origImg.url, previewOutputURL: img.url)
                }
            }
        }
        
        // Update State
        Task { @MainActor in
            self.detectedFaceSwapItems = pairedItems
            self.detectedFaceSwapCount = pairedItems.count
            self.hasDetectedFaceSwaps = !pairedItems.isEmpty
            self.faceSwapResultByTargetURL = resultMap
            if !pairedItems.isEmpty {
                if self.faceSwapBatchItems.isEmpty {
                    self.faceSwapBatchItems = pairedItems
                }
                self.currentFaceSwapStagingDir = tempDir
                self.showDetectedFaceSwapBanner = true
            } else {
                self.showDetectedFaceSwapBanner = false
            }
        }
    }
    
    public func saveFaceSwapManifest(items: [FaceSwapBatchItem], to directory: URL) {
        let manifestURL = directory.appendingPathComponent("faceswap_manifest.json")
        var entries: [[String: Any]] = []
        for it in items {
            guard let res = it.result else { continue }
            entries.append([
                "target_path": it.targetURL.path,
                "output_path": res.previewOutputURL.path,
                "filename": res.filename,
                "source_path": res.sourceFaceURL?.path ?? ""
            ])
        }
        let dict: [String: Any] = ["items": entries]
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }
    
    public func syncDetectedFaceSwaps(with items: [FaceSwapBatchItem]) {
        var map: [String: FaceSwapResult] = [:]
        let validItems = items.filter { $0.result != nil }
        for it in validItems {
            if let res = it.result {
                map[it.targetURL.standardizedFileURL.path] = res
            }
        }
        self.detectedFaceSwapItems = validItems
        self.detectedFaceSwapCount = validItems.count
        self.hasDetectedFaceSwaps = !validItems.isEmpty
        self.faceSwapResultByTargetURL = map
        if !validItems.isEmpty {
            self.showDetectedFaceSwapBanner = true
        }
    }
    
    // MARK: - Save Implementation
    
    @discardableResult
    private func performSaveFaceSwap(result: FaceSwapResult, destination: FaceSwapSaveDestination) throws -> URL {
        let fileManager = FileManager.default
        let sourceTempURL = result.previewOutputURL
        guard fileManager.fileExists(atPath: sourceTempURL.path) else {
            throw NSError(domain: "FaceSwap", code: 2, userInfo: [NSLocalizedDescriptionKey: "暫存成果檔案遺失"])
        }
        
        switch destination {
        case .sameFolder:
            let oldURL = result.targetURL
            let targetDir = oldURL.deletingLastPathComponent()
            let targetBaseName = oldURL.deletingPathExtension().lastPathComponent
            let finalDestURL = targetDir.appendingPathComponent("\(targetBaseName).heic")
            let tempWorkingURL = targetDir.appendingPathComponent("\(targetBaseName)_swap_\(UUID().uuidString.prefix(6)).heic")
            
            // 1. Copy from faceswap_temp to temporary working file in targetDir
            try fileManager.copyItem(at: sourceTempURL, to: tempWorkingURL)
            
            // 2. Atomic replacement handling collision with existing .heic or old file
            if oldURL.path.lowercased() == finalDestURL.path.lowercased() {
                // The old file was already .heic! Rename old file to holding trash path, then move new .heic into place
                let holdingTrashURL = targetDir.appendingPathComponent("\(targetBaseName)_orig_trash_\(UUID().uuidString.prefix(6)).heic")
                try fileManager.moveItem(at: oldURL, to: holdingTrashURL)
                try fileManager.moveItem(at: tempWorkingURL, to: finalDestURL)
                NSWorkspace.shared.recycle([holdingTrashURL])
            } else {
                // The old file has a different extension (e.g. .jpg, .png)
                if fileManager.fileExists(atPath: finalDestURL.path) {
                    try? fileManager.removeItem(at: finalDestURL)
                }
                try fileManager.moveItem(at: tempWorkingURL, to: finalDestURL)
                if fileManager.fileExists(atPath: oldURL.path) {
                    NSWorkspace.shared.recycle([oldURL])
                }
            }
            
            // Clean up source temp file if distinct from finalDestURL
            if sourceTempURL.path != finalDestURL.path && fileManager.fileExists(atPath: sourceTempURL.path) {
                try? fileManager.removeItem(at: sourceTempURL)
            }
            
            return finalDestURL
            
        case .swapOutput:
            guard let swapDir = FaceSwapService.shared.resolveSwapDirectory() else {
                throw NSError(domain: "FaceSwap", code: 1, userInfo: [NSLocalizedDescriptionKey: "無法定位 swap 資料夾"])
            }
            let outputDir = swapDir.appendingPathComponent("output")
            try? fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)
            var finalDestURL = outputDir.appendingPathComponent(result.filename)
            var counter = 1
            while fileManager.fileExists(atPath: finalDestURL.path) {
                let base = (result.filename as NSString).deletingPathExtension
                let ext = (result.filename as NSString).pathExtension
                finalDestURL = outputDir.appendingPathComponent("\(base)_\(counter).\(ext)")
                counter += 1
            }
            try fileManager.copyItem(at: sourceTempURL, to: finalDestURL)
            if sourceTempURL.path != finalDestURL.path && fileManager.fileExists(atPath: sourceTempURL.path) {
                try? fileManager.removeItem(at: sourceTempURL)
            }
            return finalDestURL
            
        case .saveAs:
            let savePanel = NSSavePanel()
            savePanel.title = "儲存換臉成果影像"
            savePanel.nameFieldStringValue = (result.targetURL.deletingPathExtension().lastPathComponent) + ".heic"
            savePanel.allowedContentTypes = [.heic]
            if savePanel.runModal() == .OK, let selectedURL = savePanel.url {
                if fileManager.fileExists(atPath: selectedURL.path) {
                    try? fileManager.removeItem(at: selectedURL)
                }
                try fileManager.copyItem(at: sourceTempURL, to: selectedURL)
                if sourceTempURL.path != selectedURL.path && fileManager.fileExists(atPath: sourceTempURL.path) {
                    try? fileManager.removeItem(at: sourceTempURL)
                }
                return selectedURL
            } else {
                throw NSError(domain: "FaceSwap", code: 3, userInfo: [NSLocalizedDescriptionKey: "已取消另存新檔"])
            }
        }
    }
    
    public func saveFaceSwapResult(destination: FaceSwapSaveDestination) {
        guard let result = currentFaceSwapResult else { return }
        do {
            let savedURL = try performSaveFaceSwap(result: result, destination: destination)
            try? FileManager.default.removeItem(at: result.previewOutputURL)
            if let stagingDir = currentFaceSwapStagingDir {
                cleanupFaceSwapStagingFolder(stagingDir: stagingDir)
                currentFaceSwapStagingDir = nil
            }
            
            // Remove target from detected items
            let targetPath = result.targetURL.standardizedFileURL.path
            self.faceSwapResultByTargetURL.removeValue(forKey: targetPath)
            self.detectedFaceSwapItems.removeAll { $0.targetURL.standardizedFileURL.path == targetPath }
            self.detectedFaceSwapCount = self.detectedFaceSwapItems.count
            self.hasDetectedFaceSwaps = !self.detectedFaceSwapItems.isEmpty
            
            self.currentFaceSwapResult = nil
            self.isFaceSwapPreviewPresented = false
            self.showToast("✨ 已刪除舊檔並以換臉成果取代: \(savedURL.lastPathComponent)")
            self.refreshFolderContents()
        } catch {
            showToast("儲存失敗: \(error.localizedDescription)")
        }
    }
    
    public func discardFaceSwapResult() {
        if let result = currentFaceSwapResult {
            try? FileManager.default.removeItem(at: result.previewOutputURL)
            let targetPath = result.targetURL.standardizedFileURL.path
            self.faceSwapResultByTargetURL.removeValue(forKey: targetPath)
            self.detectedFaceSwapItems.removeAll { $0.targetURL.standardizedFileURL.path == targetPath }
            self.detectedFaceSwapCount = self.detectedFaceSwapItems.count
            self.hasDetectedFaceSwaps = !self.detectedFaceSwapItems.isEmpty
        }
        if let stagingDir = currentFaceSwapStagingDir {
            cleanupFaceSwapStagingFolder(stagingDir: stagingDir)
            currentFaceSwapStagingDir = nil
        }
        self.currentFaceSwapResult = nil
        self.isFaceSwapPreviewPresented = false
        self.showToast("已放棄換臉成果 (保留原圖)")
    }
    
    // MARK: - FaceSwap Staging Directory Helpers
    
    private func resolveFaceSwapStagingDirectory(for targetURLs: [URL]) -> URL {
        if let firstTarget = targetURLs.first {
            let parentDir = firstTarget.deletingLastPathComponent()
            let staging = parentDir.appendingPathComponent("faceswap_temp", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true, attributes: nil)
                return staging
            } catch {
                LoggerManager.shared.log("Failed to create staging directory in target folder: \(error.localizedDescription)", level: .error)
            }
        }
        
        let fallback = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ProjectLumina/faceswap_temp", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true, attributes: nil)
        return fallback
    }
    
    private func cleanupFaceSwapStagingFolder(stagingDir: URL?) {
        guard let dir = stagingDir else { return }
        let fm = FileManager.default
        if let contents = try? fm.contentsOfDirectory(atPath: dir.path) {
            let nonHidden = contents.filter { !$0.hasPrefix(".") && !$0.hasSuffix(".json") }
            if nonHidden.isEmpty {
                try? fm.removeItem(at: dir)
            }
        }
    }
    
    // MARK: - Fast Convert & Save to HEIC (H Key)
    
    public func convertSelectedImagesToHEIC() {
        let targetsToConvert: [ImageItem]
        if !selectedIndexes.isEmpty {
            let sorted = Array(selectedIndexes).sorted()
            targetsToConvert = sorted.compactMap { idx in
                (idx >= 0 && idx < displayedImages.count) ? displayedImages[idx] : nil
            }
        } else if let selIdx = selectedImageIndex, selIdx >= 0, selIdx < displayedImages.count {
            targetsToConvert = [displayedImages[selIdx]]
        } else {
            showToast("請先選取要轉換為 HEIC 的相片")
            return
        }
        
        guard !targetsToConvert.isEmpty else { return }
        
        showToast("⚡️ 正在轉換 \(targetsToConvert.count) 張相片為 HEIC...")
        
        Task {
            var convertedCount = 0
            var skippedCount = 0
            var failedCount = 0
            var lastNewURL: URL? = nil
            
            for item in targetsToConvert {
                let sourceURL = item.url
                let ext = sourceURL.pathExtension.lowercased()
                
                // If already HEIC, skip
                if ext == "heic" || ext == "heif" {
                    skippedCount += 1
                    continue
                }
                
                do {
                    let correction = await MainActor.run { self.lightCorrections[sourceURL.path] }
                    let newURL = try await convertSingleImageToHEIC(sourceURL: sourceURL, correction: correction)
                    lastNewURL = newURL
                    convertedCount += 1
                } catch {
                    LoggerManager.shared.log("Failed to convert \(sourceURL.lastPathComponent) to HEIC: \(error.localizedDescription)", level: .error)
                    failedCount += 1
                }
            }
            
            await MainActor.run {
                if convertedCount > 0 {
                    self.refreshFolderContents()
                    if targetsToConvert.count == 1, let newURL = lastNewURL {
                        self.showToast("⚡️ 已轉換為 HEIC 並取代舊檔案: \(newURL.lastPathComponent)")
                    } else {
                        self.showToast("⚡️ 已完成 \(convertedCount) 張相片 HEIC 轉換並刪除原檔" + (skippedCount > 0 ? " (跳過 \(skippedCount) 張已是 HEIC)" : ""))
                    }
                } else if skippedCount > 0 {
                    self.showToast("選取的相片已是 HEIC 格式，無需重複轉換")
                } else if failedCount > 0 {
                    self.showToast("HEIC 轉換失敗，請檢查檔案權限或格式")
                }
            }
        }
    }
    
    private func convertSingleImageToHEIC(sourceURL: URL, quality: Float = 0.92, correction: LightCorrectionParams? = nil) async throws -> URL {
        return try await Task.detached(priority: .userInitiated) {
            let targetDir = sourceURL.deletingLastPathComponent()
            let baseName = sourceURL.deletingPathExtension().lastPathComponent
            let destURL = targetDir.appendingPathComponent("\(baseName).heic")
            let tempDestURL = targetDir.appendingPathComponent("\(baseName)_conv_\(UUID().uuidString.prefix(6)).heic")
            
            guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
                throw NSError(domain: "HEICConversion", code: 1, userInfo: [NSLocalizedDescriptionKey: "無法讀取原始影像檔案: \(sourceURL.lastPathComponent)"])
            }
            
            let sourceProps = (CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]) ?? [:]
            
            guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "HEICConversion", code: 2, userInfo: [NSLocalizedDescriptionKey: "無法解碼影像內容: \(sourceURL.lastPathComponent)"])
            }
            
            var imageToEncode = cgImage
            if let params = correction, !params.isNeutral {
                var ci = CIImage(cgImage: cgImage)
                if abs(params.exposure) > 0.001 {
                    ci = ci.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: params.exposure])
                }
                if abs(params.temperature) > 1.0 || abs(params.tint) > 1.0 {
                    let sourceNeutral = CIVector(x: CGFloat(6500 + params.temperature), y: CGFloat(params.tint))
                    let targetNeutral = CIVector(x: 6500, y: 0)
                    ci = ci.applyingFilter("CITemperatureAndTint", parameters: [
                        "inputNeutral": sourceNeutral,
                        "inputTargetNeutral": targetNeutral
                    ])
                }
                if abs(params.contrast - 1.0) > 0.001 {
                    ci = ci.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: params.contrast])
                }
                if abs(params.highlights) > 0.001 || abs(params.shadows) > 0.001 {
                    let hlAmount = max(0.0, 1.0 + Double(params.highlights))
                    let shAmount = max(0.0, Double(params.shadows))
                    ci = ci.applyingFilter("CIHighlightShadowAdjust", parameters: [
                        "inputHighlightAmount": hlAmount,
                        "inputShadowAmount": shAmount
                    ])
                }
                // Apply Portrait Beauty & Retouch Pipeline (Red Eye, Blemish Inpainting, Skin Smoothing)
                if params.redEyeCorrection || !params.spotRemovals.isEmpty || params.skinSmoothing > 0.01 || params.skinToneProtection > 0.1 {
                    ci = PortraitRetouchService.shared.applyPortraitRetouch(to: ci, params: params, baseCGImage: cgImage)
                }
                let ciContext = CIContext(options: SystemHardwareProfile.shared.createCIContextOptions())
                if let processedCG = ciContext.createCGImage(ci, from: ci.extent) {
                    imageToEncode = processedCG
                }
            }
            
            guard let destination = CGImageDestinationCreateWithURL(tempDestURL as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
                throw NSError(domain: "HEICConversion", code: 3, userInfo: [NSLocalizedDescriptionKey: "系統不支援 HEIC 影像編碼"])
            }
            
            var options: [CFString: Any] = sourceProps
            options[kCGImageDestinationLossyCompressionQuality] = quality as CFNumber
            
            CGImageDestinationAddImage(destination, imageToEncode, options as CFDictionary)
            
            guard CGImageDestinationFinalize(destination) else {
                try? FileManager.default.removeItem(at: tempDestURL)
                throw NSError(domain: "HEICConversion", code: 4, userInfo: [NSLocalizedDescriptionKey: "HEIC 編碼寫入失敗"])
            }
            
            // If destURL already exists and is different from sourceURL, recycle it
            if FileManager.default.fileExists(atPath: destURL.path) && destURL.path != sourceURL.path {
                NSWorkspace.shared.recycle([destURL])
            }
            
            // Move temp file to destURL
            if FileManager.default.fileExists(atPath: destURL.path) {
                try? FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.moveItem(at: tempDestURL, to: destURL)
            
            // Delete old file by safely recycling to macOS Trash
            NSWorkspace.shared.recycle([sourceURL])
            
            LoggerManager.shared.log("Converted \(sourceURL.lastPathComponent) to HEIC: \(destURL.lastPathComponent) and trashed original", level: .info)
            return destURL
        }.value
    }
    
    // MARK: - Single & Batch Short Hash Filename Renaming (Decoupled from HEIC)
    
    /// Compute an 8-character hex SHA-256 content short-hash for an image file
    public static func computeFileShortHash(for url: URL, length: Int = 8) -> String {
        if let fileData = try? Data(contentsOf: url, options: .mappedIfSafe) {
            let digest = SHA256.hash(data: fileData)
            let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
            return String(hex.prefix(length))
        } else {
            let attr = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
            let modDate = (attr[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let size = (attr[.size] as? UInt64) ?? 0
            let seed = "\(url.path)_\(size)_\(modDate)"
            let digest = SHA256.hash(data: Data(seed.utf8))
            let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
            return String(hex.prefix(length))
        }
    }
    
    /// Apply short-hash to the selected single image or multi-selected batch of images
    public func applyShortHashToSelectedFilenames() {
        let targetsToHash: [ImageItem]
        if !selectedIndexes.isEmpty {
            let sorted = Array(selectedIndexes).sorted()
            targetsToHash = sorted.compactMap { idx in
                (idx >= 0 && idx < displayedImages.count) ? displayedImages[idx] : nil
            }
        } else if let selIdx = selectedImageIndex, selIdx >= 0, selIdx < displayedImages.count {
            targetsToHash = [displayedImages[selIdx]]
        } else {
            showToast("請先選取要進行短 Hash 命名的相片")
            return
        }
        
        guard !targetsToHash.isEmpty else { return }
        
        showToast("⚡️ 正在對 \(targetsToHash.count) 張相片進行短 Hash 命名...")
        
        Task {
            var renamedCount = 0
            var skippedCount = 0
            var failedCount = 0
            var lastNewURL: URL? = nil
            let fileManager = FileManager.default
            
            for item in targetsToHash {
                let sourceURL = item.url
                let targetDir = sourceURL.deletingLastPathComponent()
                let currentBaseName = sourceURL.deletingPathExtension().lastPathComponent
                let ext = sourceURL.pathExtension
                
                // 1. Calculate content short hash
                let shortHash = Self.computeFileShortHash(for: sourceURL, length: 8)
                
                // 2. Strip any preexisting 8-char hex hash suffix (e.g. "_a1b2c3d4") to prevent infinite chaining like "_hash_hash"
                var pureBaseName = currentBaseName
                if let hashRange = currentBaseName.range(of: "_[0-9a-fA-F]{8}$", options: .regularExpression) {
                    let existingHash = String(currentBaseName[hashRange].dropFirst()) // drop leading '_'
                    if existingHash.lowercased() == shortHash.lowercased() {
                        // Already accurately hashed with matching short hash
                        skippedCount += 1
                        continue
                    }
                    pureBaseName = String(currentBaseName[..<hashRange.lowerBound])
                }
                
                // 3. Resolve destination URL with collision avoidance
                let newBaseName = "\(pureBaseName)_\(shortHash)"
                var destURL = ext.isEmpty ? targetDir.appendingPathComponent(newBaseName) : targetDir.appendingPathComponent("\(newBaseName).\(ext)")
                
                if destURL.path == sourceURL.path {
                    skippedCount += 1
                    continue
                }
                
                var collisionIndex = 1
                while fileManager.fileExists(atPath: destURL.path) && destURL.path != sourceURL.path {
                    let collidedName = "\(newBaseName)_\(collisionIndex)"
                    destURL = ext.isEmpty ? targetDir.appendingPathComponent(collidedName) : targetDir.appendingPathComponent("\(collidedName).\(ext)")
                    collisionIndex += 1
                }
                
                // 4. Atomic rename and companion XMP sidecar sync
                do {
                    try fileManager.moveItem(at: sourceURL, to: destURL)
                    
                    // Companion XMP sidecar if present
                    let xmpSource = sourceURL.deletingPathExtension().appendingPathExtension("xmp")
                    if fileManager.fileExists(atPath: xmpSource.path) {
                        let xmpDest = destURL.deletingPathExtension().appendingPathExtension("xmp")
                        try? fileManager.moveItem(at: xmpSource, to: xmpDest)
                    }
                    
                    await MainActor.run {
                        // Migrate in-memory state mappings to new path
                        if let light = self.lightCorrections.removeValue(forKey: sourceURL.path) {
                            self.lightCorrections[destURL.path] = light
                        }
                        if let lightEnabled = self.isAutoLightEnabled.removeValue(forKey: sourceURL.path) {
                            self.isAutoLightEnabled[destURL.path] = lightEnabled
                        }
                        if let wbEnabled = self.isAutoWBEnabled.removeValue(forKey: sourceURL.path) {
                            self.isAutoWBEnabled[destURL.path] = wbEnabled
                        }
                        if let meta = self.exifMetadata.removeValue(forKey: sourceURL.path) {
                            self.exifMetadata[destURL.path] = meta
                        }
                        if let thumb = self.thumbnails.removeValue(forKey: sourceURL.path) {
                            self.thumbnails[destURL.path] = thumb
                        }
                    }
                    
                    lastNewURL = destURL
                    renamedCount += 1
                    LoggerManager.shared.log("Renamed \(sourceURL.lastPathComponent) -> \(destURL.lastPathComponent)", level: .info)
                } catch {
                    LoggerManager.shared.log("Failed to rename \(sourceURL.lastPathComponent) to short hash: \(error.localizedDescription)", level: .error)
                    failedCount += 1
                }
            }
            
            await MainActor.run {
                if renamedCount > 0 {
                    self.refreshFolderContents()
                    if targetsToHash.count == 1, let newURL = lastNewURL {
                        if let newIndex = self.displayedImages.firstIndex(where: { $0.url == newURL }) {
                            self.selectedImageIndex = newIndex
                        }
                        self.showToast("⚡️ 檔名已成功附加短 Hash: \(newURL.lastPathComponent)")
                    } else {
                        self.showToast("⚡️ 已完成 \(renamedCount) 張相片短 Hash 命名" + (skippedCount > 0 ? " (跳過 \(skippedCount) 張已具備最新短 Hash)" : ""))
                    }
                } else if skippedCount > 0 {
                    self.showToast("選取的相片已具備對應短 Hash，無需重複命名")
                } else if failedCount > 0 {
                    self.showToast("短 Hash 命名失敗，請檢查檔案寫入權限")
                }
            }
        }
    }
}

public enum FaceSwapPreviewMode: String, CaseIterable, Identifiable {
    case sideBySide = "左右分開"
    case splitCurtain = "前後分割簾"
    
    public var id: String { rawValue }
}
