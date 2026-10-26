import SwiftUI
import AppKit

public struct ImageGridView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var hoveredCardIndex: Int? = nil
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: CGFloat(viewModel.thumbnailScale), maximum: CGFloat(viewModel.thumbnailScale * 1.5)), spacing: 14)]
    }
    
    private func updateColumnCount(width: CGFloat) {
        let availableWidth = max(100, width - 32)
        let itemWidth = CGFloat(viewModel.thumbnailScale) + 14
        let cols = max(1, Int(availableWidth / itemWidth))
        if viewModel.gridColumnCount != cols {
            viewModel.gridColumnCount = cols
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Filter, Search & Sort Control Deck
            controlDeck
            
            // MARK: - Detected FaceSwap Alert Banner
            if viewModel.hasDetectedFaceSwaps && viewModel.showDetectedFaceSwapBanner {
                detectedFaceSwapBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // MARK: - Batch Action Floating Island (if items selected)
            if !viewModel.selectedIndexes.isEmpty {
                batchActionIsland
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // MARK: - Photo Grid Content Area
            ZStack {
                KeyCaptureView()
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .allowsHitTesting(false)
                
                ScrollViewReader { proxy in
                    GeometryReader { geo in
                        ScrollView {
                            if viewModel.displayedImages.isEmpty {
                                emptyStateView
                            } else {
                                LazyVGrid(columns: gridColumns, spacing: 16) {
                                    ForEach(0..<viewModel.displayedImages.count, id: \.self) { index in
                                        photoCard(for: index)
                                            .id(index)
                                    }
                                }
                                .padding(16)
                            }
                        }
                        .background(LuminaTheme.Colors.bgCanvas)
                        .simultaneousGesture(TapGesture().onEnded {
                            NSApp.keyWindow?.makeFirstResponder(nil)
                        })
                        .onAppear {
                            updateColumnCount(width: geo.size.width)
                        }
                        .onChange(of: geo.size.width) { _, newWidth in
                            updateColumnCount(width: newWidth)
                        }
                        .onChange(of: viewModel.thumbnailScale) { _, _ in
                            updateColumnCount(width: geo.size.width)
                        }
                        .onChange(of: viewModel.selectedImageIndex) { _, newIndex in
                            if let idx = newIndex {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo(idx, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Control Deck
    private var controlDeck: some View {
        VStack(spacing: 8) {
            // Upper Deck: Search & Culling Filter Pills
            HStack(spacing: 10) {
                // Search Field
                LuminaSearchField(text: $viewModel.searchQuery)
                    .frame(maxWidth: 240)
                
                Divider()
                    .background(LuminaTheme.Colors.borderSubtle)
                    .frame(height: 18)
                
                // Star Rating Quick Filter
                HStack(spacing: 4) {
                    LuminaPillButton(
                        label: "全部",
                        isSelected: viewModel.filterRating == 0,
                        selectedColor: LuminaTheme.Colors.cyanAccent
                    ) {
                        viewModel.filterRating = 0
                        viewModel.updateDisplayedImages()
                    }
                    
                    ForEach(1...5, id: \.self) { star in
                        LuminaPillButton(
                            icon: "star.fill",
                            label: "\(star)+",
                            isSelected: viewModel.filterRating == star,
                            selectedColor: LuminaTheme.Colors.amberGold
                        ) {
                            viewModel.filterRating = star
                            viewModel.updateDisplayedImages()
                        }
                    }
                }
                
                // Tagged Filter
                LuminaPillButton(
                    icon: "flag.fill",
                    label: "標記",
                    isSelected: viewModel.filterTaggedOnly,
                    selectedColor: LuminaTheme.Colors.neonCoral,
                    shortcut: "T"
                ) {
                    viewModel.filterTaggedOnly.toggle()
                    viewModel.updateDisplayedImages()
                }
                
                // RAW format Filter
                LuminaPillButton(
                    label: "RAW",
                    isSelected: viewModel.filterOnlyRaw,
                    selectedColor: LuminaTheme.Colors.electricIndigo
                ) {
                    viewModel.filterOnlyRaw.toggle()
                    viewModel.updateDisplayedImages()
                }
                
                // Edited / Light-Corrected Filter
                LuminaPillButton(
                    icon: "wand.and.stars",
                    label: "已校光",
                    isSelected: viewModel.filterOnlyEdited,
                    selectedColor: LuminaTheme.Colors.mintEmerald
                ) {
                    viewModel.filterOnlyEdited.toggle()
                    viewModel.updateDisplayedImages()
                }
                
                Spacer()
                
                // Detected FaceSwap Button
                if viewModel.hasDetectedFaceSwaps {
                    Button(action: {
                        viewModel.openFaceSwapBatchReview()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles.rectangle.stack.fill")
                                .font(.system(size: 10))
                            Text("換臉確認 (\(viewModel.detectedFaceSwapCount))")
                                .font(.system(size: 10.5, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 9)
                        .background(
                            Capsule()
                                .fill(LuminaTheme.Colors.electricIndigo)
                        )
                        .shadow(color: LuminaTheme.Colors.electricIndigo.opacity(0.3), radius: 4, x: 0, y: 1)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("切換至換臉確認模式 (⌘R)")
                }
                
                // Select All (Cmd+A) / Deselect All Button
                Button(action: {
                    if viewModel.selectedIndexes.count == viewModel.displayedImages.count && !viewModel.displayedImages.isEmpty {
                        viewModel.deselectAllImages()
                    } else {
                        viewModel.selectAllImages()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.selectedIndexes.count == viewModel.displayedImages.count && !viewModel.displayedImages.isEmpty ? "checkmark.circle.fill" : "circle.grid.2x2")
                            .font(.system(size: 10))
                        Text(viewModel.selectedIndexes.count == viewModel.displayedImages.count && !viewModel.displayedImages.isEmpty ? "取消全選" : "全選 (⌘A)")
                            .font(.system(size: 10.5, weight: .bold))
                    }
                    .foregroundColor(LuminaTheme.Colors.cyanAccent)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 9)
                    .background(
                        Capsule()
                            .fill(LuminaTheme.Colors.cyanAccent.opacity(0.12))
                            .overlay(Capsule().stroke(LuminaTheme.Colors.cyanAccent.opacity(0.35), lineWidth: 0.75))
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                // Total Count HUD Chip
                HStack(spacing: 4) {
                    Text("顯示 \(viewModel.displayedImages.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(LuminaTheme.Colors.textPrimary)
                    Text("/ \(viewModel.images.count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(LuminaTheme.Colors.textTertiary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.04))
                        .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 0.75))
                )
            }
            
            // Lower Deck: Sorting, Grid Zoom Slider
            HStack(spacing: 12) {
                // Sorting Controls
                HStack(spacing: 6) {
                    Text("排序方式:")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(LuminaTheme.Colors.textTertiary)
                    
                    Menu {
                        ForEach(SortOption.allCases) { opt in
                            Button(action: {
                                viewModel.sortOption = opt
                            }) {
                                HStack {
                                    Text(opt.rawValue)
                                    if viewModel.sortOption == opt {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(viewModel.sortOption.rawValue)
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundColor(LuminaTheme.Colors.cyanAccent)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8))
                                .foregroundColor(LuminaTheme.Colors.textSecondary)
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.black.opacity(0.04))
                        )
                    }
                    .menuStyle(BorderlessButtonMenuStyle())
                    
                    // Order Asc/Desc Toggle
                    Button(action: {
                        viewModel.sortAscending.toggle()
                    }) {
                        Image(systemName: viewModel.sortAscending ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(LuminaTheme.Colors.textSecondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(viewModel.sortAscending ? "目前為遞增排序 (點擊切換為遞減)" : "目前為遞減排序 (點擊切換為遞增)")
                    
                    // Reset Filters button if any filter is active
                    let hasActiveFilters = viewModel.filterRating > 0 || viewModel.filterTaggedOnly || viewModel.filterOnlyRaw || viewModel.filterOnlyEdited || !viewModel.searchQuery.isEmpty
                    if hasActiveFilters {
                        Button(action: {
                            viewModel.filterRating = 0
                            viewModel.filterTaggedOnly = false
                            viewModel.filterOnlyRaw = false
                            viewModel.filterOnlyEdited = false
                            viewModel.searchQuery = ""
                            viewModel.updateDisplayedImages()
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 9))
                                Text("重置篩選")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(LuminaTheme.Colors.neonCoral)
                            .padding(.vertical, 3)
                            .padding(.horizontal, 7)
                            .background(Capsule().fill(LuminaTheme.Colors.neonCoral.opacity(0.12)))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("清除所有篩選與搜尋條件")
                    }
                }
                
                Spacer()
                
                // Grid Zoom Slider
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.3x3")
                        .font(.system(size: 10))
                        .foregroundColor(LuminaTheme.Colors.textTertiary)
                    
                    Slider(value: $viewModel.thumbnailScale, in: 120...300)
                        .frame(width: 90)
                        .controlSize(.mini)
                    
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 11))
                        .foregroundColor(LuminaTheme.Colors.textSecondary)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(
            LuminaTheme.Colors.bgSurface.opacity(0.95)
                .background(VisualEffectView(material: .sidebar, blendingMode: .withinWindow))
        )
        .overlay(
            VStack {
                Spacer()
                Rectangle().fill(LuminaTheme.Colors.borderSubtle).frame(height: 1)
            }
        )
    }
    
    // MARK: - Detected FaceSwap Alert Banner
    private var detectedFaceSwapBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LuminaTheme.Colors.electricIndigo.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.electricIndigo)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("偵測到此資料夾有 \(viewModel.detectedFaceSwapCount) 張換臉完成相片")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.textPrimary)
                Text("可切換至換臉確認模式逐張進行前後比對，決定保持原檔或取代")
                    .font(.system(size: 10.5))
                    .foregroundColor(LuminaTheme.Colors.textTertiary)
            }
            
            Spacer()
            
            Button(action: {
                viewModel.openFaceSwapBatchReview()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                    Text("切換至換臉確認模式 (⌘R)")
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(.vertical, 6)
                .padding(.horizontal, 14)
                .background(Capsule().fill(LuminaTheme.Colors.electricIndigo))
                .shadow(color: LuminaTheme.Colors.electricIndigo.opacity(0.35), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {
                viewModel.showDetectedFaceSwapBanner = false
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.black.opacity(0.04)))
            }
            .buttonStyle(PlainButtonStyle())
            .help("關閉此提示 (隨時可點擊工具列按鈕或按 ⌘R 進入)")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(LuminaTheme.Colors.electricIndigo.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: LuminaTheme.Shadows.ambient, radius: 10, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // MARK: - Batch Action Floating Island
    private var batchActionIsland: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(LuminaTheme.Colors.cyanAccent)
                Text("已選取 \(viewModel.selectedIndexes.count) 張")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.textPrimary)
            }
            .padding(.trailing, 4)
            
            // Compare Button (if >= 2 selected)
            if viewModel.selectedIndexes.count >= 2 {
                Button(action: {
                    viewModel.isCompareActive = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "columns.2")
                        Text("多圖對比")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(
                        Capsule().fill(LuminaTheme.Gradients.brandCyanIndigo)
                    )
                    .luminaGlow(color: LuminaTheme.Colors.cyanAccent, radius: 6)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Batch Auto Light
            Button(action: {
                viewModel.batchAutoLightCorrectionForSelected()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "wand.and.stars")
                    Text("批次一鍵校光")
                }
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(LuminaTheme.Colors.amberGold)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    Capsule().fill(LuminaTheme.Colors.amberGold.opacity(0.18))
                        .overlay(Capsule().stroke(LuminaTheme.Colors.amberGold.opacity(0.4), lineWidth: 0.75))
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            // AI FaceSwap
            Button(action: {
                if viewModel.selectedIndexes.count > 1 {
                    viewModel.openFaceSwapSetup(mode: .selected)
                } else if let firstIdx = viewModel.selectedIndexes.sorted().first,
                          firstIdx < viewModel.displayedImages.count {
                    let target = viewModel.displayedImages[firstIdx]
                    viewModel.openFaceSwapSetup(for: target, mode: .single)
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                    Text("AI 換臉")
                }
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(LuminaTheme.Colors.electricIndigo)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    Capsule().fill(LuminaTheme.Colors.electricIndigo.opacity(0.14))
                        .overlay(Capsule().stroke(LuminaTheme.Colors.electricIndigo.opacity(0.35), lineWidth: 0.75))
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Paste Tone Settings
            if viewModel.copiedLightCorrection != nil {
                Button(action: {
                    viewModel.pasteLightCorrectionToSelected()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("同步貼上調光")
                    }
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.cyanAccent)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        Capsule().fill(LuminaTheme.Colors.cyanAccent.opacity(0.18))
                            .overlay(Capsule().stroke(LuminaTheme.Colors.cyanAccent.opacity(0.4), lineWidth: 0.75))
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Fast Convert to HEIC (H)
            Button(action: {
                viewModel.convertSelectedImagesToHEIC()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.badge.automatic.fill")
                    Text("轉為 HEIC")
                    Text("H")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(LuminaTheme.Colors.cyanAccent.opacity(0.25)))
                }
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(LuminaTheme.Colors.cyanAccent)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    Capsule().fill(LuminaTheme.Colors.cyanAccent.opacity(0.12))
                        .overlay(Capsule().stroke(LuminaTheme.Colors.cyanAccent.opacity(0.35), lineWidth: 0.75))
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Short Hash Renaming (N)
            Button(action: {
                viewModel.applyShortHashToSelectedFilenames()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "number")
                    Text("短 Hash 命名")
                    Text("N")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(LuminaTheme.Colors.amberGold.opacity(0.25)))
                }
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(LuminaTheme.Colors.amberGold)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    Capsule().fill(LuminaTheme.Colors.amberGold.opacity(0.12))
                        .overlay(Capsule().stroke(LuminaTheme.Colors.amberGold.opacity(0.35), lineWidth: 0.75))
                )
            }
            .buttonStyle(PlainButtonStyle())
            .help("計算影像內容 8 碼短 Hash 並附加於檔名，防止同名重複 (N)")
            
            Spacer()
            
            // Select All (Cmd+A) in Batch Island
            if viewModel.selectedIndexes.count < viewModel.displayedImages.count {
                Button(action: {
                    viewModel.selectAllImages()
                }) {
                    Text("全選所有 (⌘A)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(LuminaTheme.Colors.cyanAccent)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Capsule().fill(LuminaTheme.Colors.cyanAccent.opacity(0.12)))
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Clear Selection
            Button(action: {
                viewModel.clearSelectedIndexes()
            }) {
                Text("取消選取")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.textTertiary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Capsule().fill(Color.black.opacity(0.06)))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(LuminaTheme.Colors.cyanAccent.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: LuminaTheme.Shadows.ambient, radius: 12, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // MARK: - Photographic Viewfinder Card
    private func photoCard(for index: Int) -> some View {
        let item = viewModel.displayedImages[index]
        let key = item.url.path
        let isSelected = viewModel.selectedImageIndex == index
        let isMultiSelected = viewModel.selectedIndexes.contains(index)
        let isHovered = hoveredCardIndex == index
        let metadata = viewModel.exifMetadata[key]
        let lightParams = viewModel.lightCorrections[key]
        let isEdited = viewModel.isAutoLightEnabled[key] == true || (lightParams != nil && !lightParams!.isNeutral)
        
        return VStack(alignment: .leading, spacing: 6) {
            // Viewfinder Thumbnail Frame
            ZStack {
                // Card Base
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LuminaTheme.Colors.bgSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                isSelected ? LuminaTheme.Colors.cyanAccent : (isHovered ? Color.black.opacity(0.18) : Color.black.opacity(0.06)),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
                    .shadow(color: isSelected ? LuminaTheme.Colors.cyanAccent.opacity(0.3) : LuminaTheme.Shadows.ambient, radius: isSelected ? 8 : 3, x: 0, y: 2)
                
                // Actual Image Thumbnail
                if let cgImage = viewModel.thumbnails[key] {
                    Image(nsImage: NSImage(cgImage: cgImage, size: .zero))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: CGFloat(viewModel.thumbnailScale * 0.85))
                        .clipped()
                        .cornerRadius(8)
                        .padding(isSelected ? 3 : 2)
                        .transition(.opacity.animation(.easeIn(duration: 0.15)))
                } else {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(height: CGFloat(viewModel.thumbnailScale * 0.85))
                }
                
                // Viewfinder Reticle Brackets (Autofocus aesthetic on active selection)
                if isSelected {
                    ViewfinderBracket(color: LuminaTheme.Colors.cyanAccent, size: 10, thickness: 2)
                        .padding(5)
                }
                
                // Top-Left Overlays: Flag Badge & Edit Indicator
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        // Tag Flag (interactive toggle)
                        Button(action: {
                            viewModel.toggleTagged(for: item)
                        }) {
                            let isTagged = metadata?.isTagged ?? false
                            Image(systemName: isTagged ? "flag.fill" : "flag")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(isTagged ? .white : Color.white.opacity(0.6))
                                .padding(4)
                                .background(
                                    Circle()
                                        .fill(isTagged ? LuminaTheme.Colors.neonCoral : Color.black.opacity(0.55))
                                )
                                .luminaGlow(color: LuminaTheme.Colors.neonCoral, radius: 4, isActive: isTagged)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Edited Badge
                        if isEdited {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.yellow)
                                .padding(3)
                                .background(Circle().fill(Color.black.opacity(0.6)))
                        }
                    }
                    Spacer()
                }
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                
                // Top-Right Overlays: Format badge & Dimensions & FaceSwap status
                VStack(alignment: .trailing, spacing: 3) {
                    if viewModel.faceSwapResultByTargetURL[item.url.standardizedFileURL.path] != nil {
                        HStack(spacing: 2.5) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 7.5, weight: .bold))
                            Text("已換臉")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 4.5)
                        .background(
                            Capsule().fill(LuminaTheme.Colors.electricIndigo)
                        )
                        .shadow(color: LuminaTheme.Colors.electricIndigo.opacity(0.4), radius: 3, x: 0, y: 1)
                    }
                    
                    let ext = item.url.pathExtension.uppercased()
                    LuminaBadge(ext, color: ext == "RAW" || ext == "CR2" || ext == "NEF" || ext == "ARW" ? LuminaTheme.Colors.cyanAccent : LuminaTheme.Colors.textSecondary)
                    
                    if let exif = metadata, let w = exif.width, let h = exif.height {
                        let mp = Double(w * h) / 1_000_000.0
                        LuminaBadge(mp >= 1.0 ? String(format: "%.0fMP", mp) : "\(w)×\(h)")
                    }
                    
                    Spacer()
                }
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                
                // Bottom-Left Overlay: Interactive Rating Bar
                VStack {
                    Spacer()
                    HStack {
                        let curRating = metadata?.rating ?? 0
                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= curRating ? "star.fill" : "star")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(star <= curRating ? LuminaTheme.Colors.amberGold : Color.white.opacity(0.25))
                                    .onTapGesture {
                                        viewModel.updateRating(for: item, to: curRating == star ? 0 : star)
                                    }
                            }
                        }
                        .padding(.vertical, 2.5)
                        .padding(.horizontal, 5)
                        .background(
                            Capsule().fill(Color.black.opacity(0.7))
                        )
                        
                        Spacer()
                        
                        // Multi-Select Checkbox Overlay
                        Button(action: {
                            viewModel.toggleSelectIndex(index)
                        }) {
                            Image(systemName: isMultiSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(isMultiSelected ? LuminaTheme.Colors.cyanAccent : Color.white.opacity(0.6))
                                .background(Circle().fill(Color.black.opacity(0.4)))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: CGFloat(viewModel.thumbnailScale * 0.85))
            
            // Filename & Metadata Footer
            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? LuminaTheme.Colors.cyanAccent : LuminaTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                if let exif = metadata {
                    HStack(spacing: 4) {
                        if let ap = exif.aperture {
                            Text(String(format: "f/%.1f", ap))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(LuminaTheme.Colors.textTertiary)
                        }
                        if let ss = exif.shutterSpeed {
                            let ssText = ss >= 1.0 ? String(format: "%.1fs", ss) : String(format: "1/%.0f", 1.0 / ss)
                            Text(ssText)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(LuminaTheme.Colors.textTertiary)
                        }
                        if let iso = exif.iso {
                            Text("ISO \(iso)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(LuminaTheme.Colors.textTertiary)
                        }
                    }
                }
            }
            .padding(.horizontal, 3)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
            let flags = NSEvent.modifierFlags
            if flags.contains(.command) {
                viewModel.toggleSelectIndex(index)
            } else if flags.contains(.shift) {
                let from = viewModel.selectedImageIndex ?? index
                viewModel.selectRange(from: from, to: index)
            } else {
                viewModel.selectedImageIndex = index
                viewModel.selectedIndexes = [index]
            }
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            NSApp.keyWindow?.makeFirstResponder(nil)
            viewModel.selectedImageIndex = index
            viewModel.selectedIndexes = [index]
            viewModel.isDetailActive = true
            viewModel.calculateHistogramForSelected()
        })
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isHovered)
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isSelected)
        .onHover { hovering in
            hoveredCardIndex = hovering ? index : nil
        }
        .contextMenu {
            if viewModel.faceSwapResultByTargetURL[item.url.standardizedFileURL.path] != nil {
                Button(action: {
                    viewModel.openFaceSwapBatchReview(for: item)
                }) {
                    Label("進入換臉確認模式 (比對此張 ⌘R)...", systemImage: "sparkles.rectangle.stack.fill")
                }
                Divider()
            } else if viewModel.hasDetectedFaceSwaps || !viewModel.faceSwapBatchItems.isEmpty {
                Button(action: {
                    viewModel.openFaceSwapBatchReview()
                }) {
                    Label("進入換臉確認模式 (⌘R)...", systemImage: "sparkles.rectangle.stack")
                }
                Divider()
            }
            
            Button(action: {
                viewModel.openFaceSwapSetup(for: item)
            }) {
                Label("AI 人臉替換 (FaceSwap)...", systemImage: "sparkles.rectangle.stack")
            }
            Divider()
            Button(action: {
                viewModel.selectedImageIndex = index
                viewModel.isDetailActive = true
            }) {
                Label("檢視大圖 (Space)", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            Button(action: {
                viewModel.selectedImageIndex = index
                viewModel.applyShortHashToSelectedFilenames()
            }) {
                Label("檔名附加短 Hash 防重複 (N)", systemImage: "number")
            }
            Button(action: {
                viewModel.toggleTagged(for: item)
            }) {
                let isTagged = metadata?.isTagged ?? false
                Label(isTagged ? "取消標記 (T)" : "標記相片 (T)", systemImage: isTagged ? "flag.slash" : "flag")
            }
        }
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.04))
                    .frame(width: 88, height: 88)
                
                Image(systemName: viewModel.selectedFolder == nil ? "folder.badge.plus" : "photo.badge.magnifyingglass")
                    .font(.system(size: 38))
                    .foregroundColor(LuminaTheme.Colors.cyanAccent.opacity(0.85))
                    .luminaGlow(color: LuminaTheme.Colors.cyanAccent, radius: 10)
            }
            
            VStack(spacing: 6) {
                Text(viewModel.selectedFolder == nil ? "尚未開啟影像資料夾" : (viewModel.images.isEmpty ? "此資料夾內無相片" : "查無符合篩選條件的影像"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.textPrimary)
                
                Text(viewModel.selectedFolder == nil ? "請點擊下方按鈕或直接將相片資料夾拖放至視窗中" : (viewModel.images.isEmpty ? "請將相片放入此資料夾，支援 RAW / JPEG / HEIC" : "請調整上方星級、標籤或搜尋關鍵字"))
                    .font(.system(size: 12))
                    .foregroundColor(LuminaTheme.Colors.textSecondary)
            }
            
            if viewModel.selectedFolder == nil {
                VStack(spacing: 12) {
                    Button(action: {
                        Task {
                            if let selected = await SecurityScopedBookmarkManager.shared.selectFolder() {
                                viewModel.selectFolder(selected)
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.badge.plus")
                            Text("選取相片資料夾 (⌘O)")
                        }
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 20)
                        .background(
                            Capsule().fill(LuminaTheme.Colors.cyanAccent)
                        )
                        .luminaGlow(color: LuminaTheme.Colors.cyanAccent, radius: 8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    if !viewModel.recentFolders.isEmpty {
                        VStack(spacing: 6) {
                            Text("或從近期工作階段快速開啟:")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(LuminaTheme.Colors.textTertiary)
                            
                            HStack(spacing: 6) {
                                ForEach(viewModel.recentFolders.prefix(3), id: \.self) { recent in
                                    Button(action: {
                                        viewModel.selectFolder(recent)
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "folder")
                                                .font(.system(size: 9))
                                            Text(recent.lastPathComponent)
                                                .font(.system(size: 10.5, weight: .medium))
                                        }
                                        .foregroundColor(LuminaTheme.Colors.textSecondary)
                                        .padding(.vertical, 4)
                                        .padding(.horizontal, 8)
                                        .background(Capsule().fill(Color.black.opacity(0.04)))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.top, 4)
            } else if !viewModel.images.isEmpty && viewModel.displayedImages.isEmpty {
                Button(action: {
                    viewModel.filterRating = 0
                    viewModel.filterTaggedOnly = false
                    viewModel.filterOnlyRaw = false
                    viewModel.filterOnlyEdited = false
                    viewModel.searchQuery = ""
                    viewModel.updateDisplayedImages()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("重置並清除所有篩選條件")
                    }
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.cyanAccent)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 14)
                    .background(
                        Capsule().fill(LuminaTheme.Colors.cyanAccent.opacity(0.12))
                            .overlay(Capsule().stroke(LuminaTheme.Colors.cyanAccent.opacity(0.35), lineWidth: 1))
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 450)
        .padding(.top, 60)
    }
}
