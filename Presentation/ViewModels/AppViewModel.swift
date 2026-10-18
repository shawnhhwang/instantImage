import Foundation
import SwiftUI
import CoreGraphics
import AppKit

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
    @Published public var faceSwapPreviewMode: FaceSwapPreviewMode = .splitCurtain
    @Published public var faceSwapSplitPosition: CGFloat = 0.5
    
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
        loadCullingDestination()
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
                
                // Clear selection if index is out of bounds
                if let index = selectedImageIndex, index >= self.displayedImages.count {
                    selectedImageIndex = nil
                }
                
                // Begin background loading of thumbnails and EXIF metadata
                loadThumbnailsAndMetadata(for: loadedImages, generation: currentGen)
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
    
    public func selectNextImage() {
        guard !displayedImages.isEmpty else { return }
        if let current = selectedImageIndex {
            if current < displayedImages.count - 1 {
                selectedImageIndex = current + 1
            }
        } else {
            selectedImageIndex = 0
        }
        if isDetailActive { calculateHistogramForSelected() }
        prefetchAdjacentImages()
    }
    
    public func selectPreviousImage() {
        guard !displayedImages.isEmpty else { return }
        if let current = selectedImageIndex {
            if current > 0 {
                selectedImageIndex = current - 1
            }
        } else {
            selectedImageIndex = 0
        }
        if isDetailActive { calculateHistogramForSelected() }
        prefetchAdjacentImages()
    }
    
    public func selectFirstImage() {
        guard !displayedImages.isEmpty else { return }
        selectedImageIndex = 0
        if isDetailActive { calculateHistogramForSelected() }
        prefetchAdjacentImages()
    }
    
    public func selectLastImage() {
        guard !displayedImages.isEmpty else { return }
        selectedImageIndex = displayedImages.count - 1
        if isDetailActive { calculateHistogramForSelected() }
        prefetchAdjacentImages()
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
            // Disable auto light correction
            isAutoLightEnabled[key] = false
            lightCorrections[key] = .neutral
            showToast("已關閉一鍵校光")
        } else {
            // Enable and calculate optimal Lightroom parameters
            applyAutoLightCorrection(for: image)
        }
    }
    
    /// Trigger Auto Light Correction calculation for a given ImageItem
    public func applyAutoLightCorrection(for image: ImageItem) {
        let key = image.url.path
        
        if let thumbnail = thumbnails[key] {
            let params = ImageLoaderService.shared.calculateAutoLightCorrection(for: thumbnail)
            self.lightCorrections[key] = params
            self.isAutoLightEnabled[key] = true
            let evString = String(format: "%+.1f EV", params.exposure)
            showToast("一鍵校光已套用 (曝光 \(evString), 對比 \(String(format: "%.2f", params.contrast)))")
        } else {
            Task {
                do {
                    let thumbnailSize = AppSettings.shared.rendering.thumbnailSize.width
                    let thumbnail = try await ImageLoaderService.shared.loadThumbnail(from: image.url, maxPixelSize: thumbnailSize)
                    let params = ImageLoaderService.shared.calculateAutoLightCorrection(for: thumbnail)
                    self.lightCorrections[key] = params
                    self.isAutoLightEnabled[key] = true
                    let evString = String(format: "%+.1f EV", params.exposure)
                    self.showToast("一鍵校光已套用 (曝光 \(evString))")
                } catch {
                    self.showToast("校光計算失敗")
                }
            }
        }
    }
    
    // Feature A: Auto White Balance
    public func applyAutoWhiteBalanceForSelected() {
        guard let image = selectedImage else { return }
        let key = image.url.path
        
        let applyWB: ((temperature: Float, tint: Float)) -> Void = { [weak self] wb in
            guard let self = self else { return }
            var current = self.lightCorrections[key] ?? .neutral
            current.temperature = wb.temperature
            current.tint = wb.tint
            self.lightCorrections[key] = current
            self.isAutoLightEnabled[key] = true
            self.showToast("自動白平衡: 色溫 \(Int(wb.temperature))K, 色調 \(Int(wb.tint))")
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
                    applyWB(wb)
                } catch {
                    self.showToast("白平衡計算失敗")
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
                let params = ImageLoaderService.shared.calculateAutoLightCorrection(for: thumbnail)
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
        isAutoLightEnabled[key] = !params.isNeutral
    }
    
    /// Reset light adjustments to standard original neutral
    public func resetLightCorrectionForSelected() {
        guard let image = selectedImage else { return }
        let key = image.url.path
        lightCorrections[key] = .neutral
        isAutoLightEnabled[key] = false
        showToast("已重設光線調整")
    }
    
    /// Look-ahead prefetching of adjacent images for seamless ACDSee-style culling
    public func prefetchAdjacentImages() {
        guard let currentIndex = selectedImageIndex, !displayedImages.isEmpty else { return }
        
        let prefetchWindow = 3 // Prefetch 3 ahead and 3 behind
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
        
        if isCompareActive {
            if selectedIndexes.isEmpty {
                isCompareActive = false
            } else if focusedCompareIndex >= selectedIndexes.count {
                focusedCompareIndex = max(0, selectedIndexes.count - 1)
            }
        } else {
            selectedImageIndex = nextSelectIndex
        }
        
        updateDisplayedImages()
        if isDetailActive { calculateHistogramForSelected() }
        
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
        static let delete: UInt16 = 51
        static let forwardDelete: UInt16 = 117
    }
    
    private func handleKeyboardEvent(_ event: NSEvent) {
        switch event.keyCode {
        case KeyCode.leftArrow:
            selectPreviousImage()
        case KeyCode.rightArrow:
            selectNextImage()
        case KeyCode.upArrow:
            selectFirstImage()
        case KeyCode.downArrow:
            selectLastImage()
        case KeyCode.space:
            isDetailActive.toggle()
        case KeyCode.escape:
            if isFaceSwapPreviewPresented {
                discardFaceSwapResult()
            } else if isFaceSwapSetupPresented {
                if !isFaceSwapProcessing { isFaceSwapSetupPresented = false }
            } else if isDetailActive {
                isDetailActive = false
            }
            isCompareActive = false
        case 1: // S Key (AI FaceSwap)
            if !isFaceSwapSetupPresented && !isFaceSwapPreviewPresented {
                openFaceSwapSetup()
            }
        case KeyCode.fKey, KeyCode.enter:
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
                applyAutoWhiteBalanceForSelected()
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
        case 11: // 'B' Key (Toggle Filmstrip)
            if isDetailActive {
                isFilmstripVisible.toggle()
            }
        case KeyCode.delete, KeyCode.forwardDelete:
            if event.modifierFlags.contains(.command) {
                deleteSelectedImage()
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
        } else {
            selectedIndexes.insert(index)
        }
    }
    
    public func clearSelectedIndexes() {
        selectedIndexes.removeAll()
    }
    
    // MARK: - FaceSwap Actions
    
    public func loadSourceFaces() {
        let faces = FaceSwapService.shared.loadAvailableSourceFaces()
        self.availableSourceFaces = faces
        if selectedSourceFace == nil, let first = faces.first {
            selectedSourceFace = first
        }
    }
    
    public func openFaceSwapSetup(for item: ImageItem? = nil) {
        let target = item ?? selectedImage
        guard let target = target else {
            showToast("請先選取一張目標相片以進行換臉")
            return
        }
        self.faceSwapTargetImage = target
        loadSourceFaces()
        self.faceSwapErrorMessage = nil
        self.faceSwapStatusMessage = ""
        self.isFaceSwapSetupPresented = true
    }
    
    public func startFaceSwap() {
        guard let target = faceSwapTargetImage else {
            showToast("未指定目標相片")
            return
        }
        
        self.isFaceSwapProcessing = true
        self.faceSwapErrorMessage = nil
        self.faceSwapStatusMessage = "正在初始化 FaceFusion 連線..."
        
        let sourceURL = selectedSourceFace?.url
        let blend = self.faceEnhancerBlend
        
        Task {
            do {
                let result = try await FaceSwapService.shared.runFaceSwap(
                    targetURL: target.url,
                    sourceFaceURL: sourceURL,
                    blend: blend
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.faceSwapStatusMessage = progress
                    }
                }
                
                await MainActor.run {
                    self.currentFaceSwapResult = result
                    self.isFaceSwapProcessing = false
                    self.isFaceSwapSetupPresented = false
                    self.isFaceSwapPreviewPresented = true
                    self.faceSwapSplitPosition = 0.5
                    self.showToast("✨ AI 換臉成功！請在預覽視窗比對成果後決定是否儲存")
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
    
    public func cancelFaceSwap() {
        FaceSwapService.shared.cancelRunningSwap()
        self.isFaceSwapProcessing = false
        self.faceSwapStatusMessage = "已取消運算"
    }
    
    public func saveFaceSwapResult(destination: FaceSwapSaveDestination) {
        guard let result = currentFaceSwapResult else { return }
        
        let fileManager = FileManager.default
        let sourceTempURL = result.previewOutputURL
        guard fileManager.fileExists(atPath: sourceTempURL.path) else {
            showToast("找不到暫存成果檔案，無法儲存")
            return
        }
        
        do {
            switch destination {
            case .sameFolder:
                let targetDir = result.targetURL.deletingLastPathComponent()
                let targetBaseName = result.targetURL.deletingPathExtension().lastPathComponent
                var finalDestURL = targetDir.appendingPathComponent("\(targetBaseName)_swap.heic")
                
                var counter = 1
                while fileManager.fileExists(atPath: finalDestURL.path) {
                    finalDestURL = targetDir.appendingPathComponent("\(targetBaseName)_swap_\(counter).heic")
                    counter += 1
                }
                
                try fileManager.copyItem(at: sourceTempURL, to: finalDestURL)
                showToast("已儲存換臉影像至: \(finalDestURL.lastPathComponent)")
                
            case .swapOutput:
                guard let swapDir = FaceSwapService.shared.resolveSwapDirectory() else {
                    throw NSError(domain: "FaceSwap", code: 1, userInfo: [NSLocalizedDescriptionKey: "無法找到 swap 資料夾"])
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
                showToast("已儲存換臉影像至 swap/output: \(finalDestURL.lastPathComponent)")
                
            case .saveAs:
                let savePanel = NSSavePanel()
                savePanel.title = "儲存換臉成果影像"
                savePanel.nameFieldStringValue = (result.targetURL.deletingPathExtension().lastPathComponent) + "_swap.heic"
                savePanel.allowedContentTypes = [.heic]
                
                if savePanel.runModal() == .OK, let selectedURL = savePanel.url {
                    if fileManager.fileExists(atPath: selectedURL.path) {
                        try? fileManager.removeItem(at: selectedURL)
                    }
                    try fileManager.copyItem(at: sourceTempURL, to: selectedURL)
                    showToast("已儲存換臉成果至: \(selectedURL.lastPathComponent)")
                } else {
                    return
                }
            }
            
            // Clean up preview file and dismiss
            try? fileManager.removeItem(at: sourceTempURL)
            self.currentFaceSwapResult = nil
            self.isFaceSwapPreviewPresented = false
            self.refreshFolderContents()
            
        } catch {
            showToast("儲存失敗: \(error.localizedDescription)")
        }
    }
    
    public func discardFaceSwapResult() {
        if let result = currentFaceSwapResult {
            try? FileManager.default.removeItem(at: result.previewOutputURL)
        }
        self.currentFaceSwapResult = nil
        self.isFaceSwapPreviewPresented = false
        self.showToast("已放棄換臉成果")
    }
}

public enum FaceSwapPreviewMode: String, CaseIterable, Identifiable {
    case splitCurtain = "前後分割簾"
    case sideBySide = "雙圖並排"
    
    public var id: String { rawValue }
}
