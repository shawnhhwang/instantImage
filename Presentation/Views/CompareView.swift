import SwiftUI

public struct CompareView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isZoomed: Bool = false
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        let compareItems = Array(viewModel.selectedIndexes)
            .sorted()
            .compactMap { idx -> ImageItem? in
                guard idx >= 0 && idx < viewModel.displayedImages.count else { return nil }
                return viewModel.displayedImages[idx]
            }
            .prefix(4)
        
        VStack(spacing: 0) {
            // MARK: - Compare Arena Header
            HStack(spacing: 14) {
                // Return to Grid Button
                LuminaIconButton(
                    icon: "chevron.left",
                    title: "返回網格",
                    shortcut: "ESC",
                    size: 32,
                    iconSize: 12
                ) {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                        viewModel.isCompareActive = false
                    }
                }
                
                // Arena Title Pill
                HStack(spacing: 8) {
                    Image(systemName: "columns.2")
                        .foregroundColor(LuminaTheme.Colors.cyanAccent)
                    Text("多圖對比競技場")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(LuminaTheme.Colors.textPrimary)
                    
                    Text("\(compareItems.count) 張影像")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(LuminaTheme.Colors.cyanAccent)
                        .padding(.vertical, 1.5)
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(LuminaTheme.Colors.cyanAccent.opacity(0.18)))
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 12)
                .luminaGlass(cornerRadius: LuminaTheme.Radius.pill)
                
                Spacer()
                
                // Synced 100% Zoom Button
                LuminaPillButton(
                    icon: isZoomed ? "minus.magnifyingglass" : "plus.magnifyingglass",
                    label: isZoomed ? "取消縮放" : "同步縮放 (100%)",
                    isSelected: isZoomed,
                    selectedColor: LuminaTheme.Colors.cyanAccent,
                    shortcut: "Z"
                ) {
                    isZoomed.toggle()
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(
                LuminaTheme.Colors.bgSurface.opacity(0.9)
                    .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
            )
            .overlay(
                VStack {
                    Spacer()
                    Rectangle().fill(LuminaTheme.Colors.borderSubtle).frame(height: 1)
                }
            )
            
            // MARK: - Multi-Grid Arena Layout
            if compareItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 44))
                        .foregroundColor(LuminaTheme.Colors.textTertiary)
                    Text("尚未勾選對比照片")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(LuminaTheme.Colors.textSecondary)
                    Text("請在網格中勾選 2 至 4 張照片進行同步對比檢查")
                        .font(.system(size: 11))
                        .foregroundColor(LuminaTheme.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let layout = compareItems.count <= 2 ?
                    AnyView(
                        HStack(spacing: 4) {
                            ForEach(0..<compareItems.count, id: \.self) { cIdx in
                                compareCell(item: compareItems[cIdx], cIdx: cIdx, isFocused: viewModel.focusedCompareIndex == cIdx) {
                                    viewModel.focusedCompareIndex = cIdx
                                }
                            }
                        }
                    ) :
                    AnyView(
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                compareCell(item: compareItems[0], cIdx: 0, isFocused: viewModel.focusedCompareIndex == 0) { viewModel.focusedCompareIndex = 0 }
                                compareCell(item: compareItems[1], cIdx: 1, isFocused: viewModel.focusedCompareIndex == 1) { viewModel.focusedCompareIndex = 1 }
                            }
                            HStack(spacing: 4) {
                                if compareItems.count > 2 {
                                    compareCell(item: compareItems[2], cIdx: 2, isFocused: viewModel.focusedCompareIndex == 2) { viewModel.focusedCompareIndex = 2 }
                                } else {
                                    Color.black
                                }
                                if compareItems.count > 3 {
                                    compareCell(item: compareItems[3], cIdx: 3, isFocused: viewModel.focusedCompareIndex == 3) { viewModel.focusedCompareIndex = 3 }
                                } else {
                                    Color.black
                                }
                            }
                        }
                    )
                
                layout
                    .background(Color.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black)
        .onAppear {
            viewModel.focusedCompareIndex = 0
        }
    }
    
    // MARK: - Individual Comparison Cell
    @ViewBuilder
    private func compareCell(item: ImageItem, cIdx: Int, isFocused: Bool, onSelect: @escaping () -> Void) -> some View {
        let key = item.url.path
        let metadata = viewModel.exifMetadata[key] ?? ImageMetadata(id: key, url: item.url, filename: item.filename)
        let lightCorrection = viewModel.lightCorrections[key]
        
        ZStack {
            // Hardware Metal Canvas
            MetalImageView(
                imageURL: item.url,
                isZoomed: isZoomed,
                lightCorrection: lightCorrection,
                isBeforeAfter: false,
                splitPosition: 0.5,
                viewModel: viewModel
            )
            .overlay(
                Rectangle()
                    .stroke(isFocused ? LuminaTheme.Colors.cyanAccent : Color.white.opacity(0.08), lineWidth: isFocused ? 2.5 : 1)
            )
            .onTapGesture {
                onSelect()
            }
            
            // Viewfinder Reticle Brackets on Focused Cell
            if isFocused {
                ViewfinderBracket(color: LuminaTheme.Colors.cyanAccent, size: 12, thickness: 2)
                    .padding(6)
            }
            
            // Top HUD Overlay
            VStack {
                HStack(spacing: 8) {
                    // Filename Badge
                    Text(item.filename)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(LuminaTheme.Colors.textPrimary)
                        .padding(.vertical, 3.5)
                        .padding(.horizontal, 8)
                        .background(
                            Capsule().fill(Color.black.opacity(0.75))
                                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.75))
                        )
                    
                    Spacer()
                    
                    // "Pick Winner / 挑為最佳" Button
                    Button(action: {
                        pickWinner(item: item)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("最佳入選")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.black)
                        .padding(.vertical, 3.5)
                        .padding(.horizontal, 8)
                        .background(
                            Capsule().fill(LuminaTheme.Colors.amberGold)
                        )
                        .luminaGlow(color: LuminaTheme.Colors.amberGold, radius: 6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("將此照片設為 5 星最佳選片並標記")
                    
                    // Flag Ribbon
                    if metadata.isTagged {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(5)
                            .background(Circle().fill(LuminaTheme.Colors.neonCoral))
                            .luminaGlow(color: LuminaTheme.Colors.neonCoral, radius: 4)
                    }
                }
                .padding(10)
                
                Spacer()
                
                // Bottom Camera EXIF & Rating HUD Shelf
                HStack(spacing: 12) {
                    // Rating Stars
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= metadata.rating ? "star.fill" : "star")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(star <= metadata.rating ? LuminaTheme.Colors.amberGold : Color.white.opacity(0.25))
                                .onTapGesture {
                                    updateItemRating(item: item, to: metadata.rating == star ? 0 : star)
                                }
                        }
                    }
                    .padding(.vertical, 3.5)
                    .padding(.horizontal, 7)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    
                    // Sensor Spec Pills
                    HStack(spacing: 4) {
                        if let ap = metadata.aperture {
                            LuminaBadge(String(format: "f/%.1f", ap), icon: "f.circle")
                        }
                        if let ss = metadata.shutterSpeed {
                            let ssText = ss >= 1.0 ? String(format: "%.1fs", ss) : String(format: "1/%.0f", 1.0 / ss)
                            LuminaBadge(ssText, icon: "timer")
                        }
                        if let iso = metadata.iso {
                            LuminaBadge("ISO \(iso)")
                        }
                    }
                    
                    Spacer()
                    
                    // Interactive Tag Toggle
                    Button(action: {
                        toggleItemTag(item: item)
                    }) {
                        Image(systemName: metadata.isTagged ? "flag.fill" : "flag")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(metadata.isTagged ? .white : LuminaTheme.Colors.textSecondary)
                            .padding(5)
                            .background(
                                Circle().fill(metadata.isTagged ? LuminaTheme.Colors.neonCoral : Color.black.opacity(0.75))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(10)
            }
        }
    }
    
    private func updateItemRating(item: ImageItem, to rating: Int) {
        viewModel.updateRating(for: item, to: rating)
        viewModel.showToast("評等已更新為 \(rating) 星")
    }
    
    private func toggleItemTag(item: ImageItem) {
        viewModel.toggleTagged(for: item)
    }
    
    private func pickWinner(item: ImageItem) {
        viewModel.updateRating(for: item, to: 5)
        if !((viewModel.exifMetadata[item.url.path]?.isTagged) ?? false) {
            viewModel.toggleTagged(for: item)
        }
        viewModel.showToast("🏆 已選為最佳照片 (5星並已標記): \(item.filename)")
    }
}
