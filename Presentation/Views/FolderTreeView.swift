import SwiftUI
import AppKit

public struct FolderTreeView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var hoveredSubfolder: URL? = nil
    @State private var isDropTargeted: Bool = false
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Brand Identity Header
            brandHeader
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
            
            // MARK: - Open Folder Primary Action Card
            openFolderCard
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            
            // MARK: - Active Directory Card
            if let root = viewModel.selectedFolder {
                activeDirectoryCard(for: root)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
            
            Divider()
                .background(LuminaTheme.Colors.borderSubtle)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            
            // MARK: - Sidebar Scroll Area (Favorites, Recents, Destination, Subfolders)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    favoritesSection
                    recentFoldersSection
                    cullingDestinationSection
                    subfoldersSection
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            
            // MARK: - Bottom Diagnostics Bar
            systemDiagnosticsFooter
        }
        .frame(minWidth: 220, idealWidth: 260)
        .background(
            ZStack {
                LuminaTheme.Colors.bgDeep
                
                // Subtle top ambient gradient
                LinearGradient(
                    colors: [LuminaTheme.Colors.cyanAccent.opacity(0.04), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
            .edgesIgnoringSafeArea(.all)
        )
        .onDrop(of: ["public.file-url"], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let droppedURL = url {
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: droppedURL.path, isDirectory: &isDir), isDir.boolValue {
                        DispatchQueue.main.async {
                            viewModel.selectFolder(droppedURL)
                        }
                    }
                }
            }
            return true
        }
    }
    
    // MARK: - Brand Header
    private var brandHeader: some View {
        HStack(spacing: 10) {
            // Radiant Logo Icon
            ZStack {
                Circle()
                    .fill(LuminaTheme.Gradients.brandCyanIndigo)
                    .frame(width: 28, height: 28)
                    .luminaGlow(color: LuminaTheme.Colors.cyanAccent, radius: 8)
                
                Image(systemName: "camera.aperture")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("LUMINA")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .tracking(1.2)
                        .foregroundColor(LuminaTheme.Colors.textPrimary)
                    
                    Text("PRO")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundColor(LuminaTheme.Colors.cyanAccent)
                        .padding(.vertical, 1.5)
                        .padding(.horizontal, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 3.5)
                                .fill(LuminaTheme.Colors.cyanAccent.opacity(0.18))
                        )
                }
                
                Text("極速影像瀏覽與挑片器")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(LuminaTheme.Colors.textTertiary)
            }
            
            Spacer()
            
            // Shortcut Help Button
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    viewModel.isShortcutSheetVisible.toggle()
                }
            }) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(LuminaTheme.Colors.textTertiary)
                    .padding(5)
            }
            .buttonStyle(PlainButtonStyle())
            .help("開啟快捷鍵指南 (?)")
        }
    }
    
    // MARK: - Open Folder Card
    private var openFolderCard: some View {
        Button(action: {
            Task {
                if let selected = await SecurityScopedBookmarkManager.shared.selectFolder() {
                    viewModel.selectFolder(selected)
                }
            }
        }) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LuminaTheme.Colors.cyanAccent.opacity(isDropTargeted ? 0.35 : 0.16))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "folder.badge.plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(LuminaTheme.Colors.cyanAccent)
                }
                
                VStack(alignment: .leading, spacing: 1.5) {
                    Text("開啟影像資料夾")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(LuminaTheme.Colors.textPrimary)
                    Text(isDropTargeted ? "放開滑鼠即可開啟資料夾" : "支援拖放資料夾至此 • RAW / HEIC")
                        .font(.system(size: 9.5))
                        .foregroundColor(isDropTargeted ? LuminaTheme.Colors.cyanAccent : LuminaTheme.Colors.textTertiary)
                }
                
                Spacer()
                
                LuminaKeycap("⌘O", isAccent: isDropTargeted)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .luminaGlass(cornerRadius: LuminaTheme.Radius.md, isElevated: true, strokeColor: isDropTargeted ? LuminaTheme.Colors.cyanAccent : LuminaTheme.Colors.borderMedium)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isDropTargeted)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Active Directory Card
    private func activeDirectoryCard(for root: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LuminaTheme.Colors.amberGold.opacity(0.18))
                        .frame(width: 24, height: 24)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(LuminaTheme.Colors.amberGold)
                }
                
                Text(root.lastPathComponent)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .help(root.path)
                
                Spacer()
                
                // Reveal in Finder Button
                Button(action: {
                    NSWorkspace.shared.activateFileViewerSelecting([root])
                }) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                        .foregroundColor(LuminaTheme.Colors.textTertiary)
                        .padding(3)
                }
                .buttonStyle(PlainButtonStyle())
                .help("在 Finder 中顯示")
                
                // Favorite Toggle
                Button(action: {
                    viewModel.toggleFavorite(root)
                }) {
                    let isFav = viewModel.isFavorite(root)
                    Image(systemName: isFav ? "star.fill" : "star")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(isFav ? LuminaTheme.Colors.amberGold : LuminaTheme.Colors.textTertiary)
                        .padding(3)
                        .luminaGlow(color: LuminaTheme.Colors.amberGold, radius: 4, isActive: isFav)
                }
                .buttonStyle(PlainButtonStyle())
                .help(viewModel.isFavorite(root) ? "從我的最愛移除" : "加入我的最愛")
            }
            
            // Directory Stats Pills
            HStack(spacing: 5) {
                LuminaBadge("\(viewModel.images.count) 張", icon: "photo.stack", color: LuminaTheme.Colors.cyanAccent)
                
                let rawCount = viewModel.images.filter { ["cr2", "nef", "arw", "dng", "raw"].contains($0.url.pathExtension.lowercased()) }.count
                if rawCount > 0 {
                    LuminaBadge("\(rawCount) RAW", color: LuminaTheme.Colors.electricIndigo)
                }
                
                let taggedCount = viewModel.images.filter { viewModel.exifMetadata[$0.url.path]?.isTagged == true }.count
                if taggedCount > 0 {
                    LuminaBadge("\(taggedCount) 標記", icon: "flag.fill", color: LuminaTheme.Colors.neonCoral)
                }
                
                Spacer()
                
                // Batch FaceSwap Action Button
                Button(action: {
                    viewModel.openFaceSwapSetup(mode: .folder)
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles")
                        Text("批次換臉")
                    }
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.electricIndigo)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 7)
                    .background(
                        Capsule().fill(LuminaTheme.Colors.electricIndigo.opacity(0.12))
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .help("針對此資料夾內相片執行批次 AI 換臉")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: LuminaTheme.Radius.md, style: .continuous)
                .fill(LuminaTheme.Colors.bgSurfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: LuminaTheme.Radius.md, style: .continuous)
                        .stroke(LuminaTheme.Colors.borderSubtle, lineWidth: 1)
                )
                .shadow(color: LuminaTheme.Shadows.ambient, radius: 4, x: 0, y: 1)
        )
    }
    
    // MARK: - Recent Folders Section
    private var recentFoldersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: "最近開啟資料夾", icon: "clock.arrow.circlepath", iconColor: LuminaTheme.Colors.cyanAccent)
            
            if viewModel.recentFolders.isEmpty {
                Text("尚無近期開啟記錄")
                    .font(.system(size: 10))
                    .foregroundColor(LuminaTheme.Colors.textMuted)
                    .padding(.leading, 6)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 2) {
                    ForEach(viewModel.recentFolders.prefix(5), id: \.self) { recentURL in
                        let isSelected = viewModel.selectedFolder == recentURL
                        
                        Button(action: {
                            viewModel.selectFolder(recentURL)
                        }) {
                            HStack(spacing: 7) {
                                Image(systemName: isSelected ? "folder.fill" : "folder")
                                    .font(.system(size: 11))
                                    .foregroundColor(isSelected ? LuminaTheme.Colors.cyanAccent : LuminaTheme.Colors.textTertiary)
                                
                                Text(recentURL.lastPathComponent)
                                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                    .foregroundColor(isSelected ? LuminaTheme.Colors.cyanAccent : LuminaTheme.Colors.textSecondary)
                                    .lineLimit(1)
                                
                                Spacer()
                            }
                            .padding(.vertical, 4.5)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isSelected ? LuminaTheme.Colors.cyanAccent.opacity(0.12) : Color.clear)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .contextMenu {
                            Button("在 Finder 中顯示") {
                                NSWorkspace.shared.activateFileViewerSelecting([recentURL])
                            }
                            Button("加入我的最愛") {
                                viewModel.toggleFavorite(recentURL)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Favorites Section
    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: "我的最愛", icon: "star.fill", iconColor: LuminaTheme.Colors.amberGold)
            
            if viewModel.favoriteFolders.isEmpty {
                Text("點擊資料夾星號即可釘選收藏")
                    .font(.system(size: 10))
                    .foregroundColor(LuminaTheme.Colors.textMuted)
                    .padding(.leading, 6)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 2) {
                    ForEach(viewModel.favoriteFolders, id: \.self) { favURL in
                        let isSelected = viewModel.selectedFolder == favURL
                        
                        Button(action: {
                            viewModel.selectFolder(favURL)
                        }) {
                            HStack(spacing: 7) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(isSelected ? LuminaTheme.Colors.cyanAccent : LuminaTheme.Colors.amberGold)
                                
                                Text(favURL.lastPathComponent)
                                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                    .foregroundColor(isSelected ? LuminaTheme.Colors.cyanAccent : LuminaTheme.Colors.textSecondary)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                Button(action: {
                                    viewModel.toggleFavorite(favURL)
                                }) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(LuminaTheme.Colors.amberGold.opacity(0.7))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isSelected ? LuminaTheme.Colors.cyanAccent.opacity(0.12) : Color.clear)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .contextMenu {
                            Button("在 Finder 中顯示") {
                                NSWorkspace.shared.activateFileViewerSelecting([favURL])
                            }
                            Button("從我的最愛移除") {
                                viewModel.toggleFavorite(favURL)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Culling Move Destination Section
    private var cullingDestinationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: "挑片搬移目標 (鍵盤 M)", icon: "tray.and.arrow.down.fill", iconColor: LuminaTheme.Colors.cyanAccent)
            
            HStack(spacing: 8) {
                if let dest = viewModel.cullingDestinationFolder {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(LuminaTheme.Colors.mintEmerald.opacity(0.18))
                            .frame(width: 26, height: 26)
                        Image(systemName: "tray.full.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(LuminaTheme.Colors.mintEmerald)
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(dest.lastPathComponent)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(LuminaTheme.Colors.textPrimary)
                            .lineLimit(1)
                        Text("按 M 鍵立即轉移當前照片")
                            .font(.system(size: 9))
                            .foregroundColor(LuminaTheme.Colors.textTertiary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.selectCullingDestinationFolder()
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(LuminaTheme.Colors.textTertiary)
                            .padding(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("更換選片目標資料夾")
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.04))
                            .frame(width: 26, height: 26)
                        Image(systemName: "tray.badge.plus")
                            .font(.system(size: 11))
                            .foregroundColor(LuminaTheme.Colors.textTertiary)
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("尚未設定目標")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(LuminaTheme.Colors.textSecondary)
                        Text("挑出好照片一鍵歸檔")
                            .font(.system(size: 9))
                            .foregroundColor(LuminaTheme.Colors.textTertiary)
                    }
                    
                    Spacer()
                    
                    Button("設定") {
                        viewModel.selectCullingDestinationFolder()
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.cyanAccent)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 7)
                    .background(
                        Capsule()
                            .fill(LuminaTheme.Colors.cyanAccent.opacity(0.14))
                            .overlay(Capsule().stroke(LuminaTheme.Colors.cyanAccent.opacity(0.35), lineWidth: 0.75))
                    )
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LuminaTheme.Colors.bgSurfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(LuminaTheme.Colors.borderSubtle, lineWidth: 1)
                    )
                    .shadow(color: LuminaTheme.Shadows.ambient, radius: 3, x: 0, y: 1)
            )
        }
    }
    
    // MARK: - Subfolders Section
    private var subfoldersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: "子資料夾目錄", icon: "folder.badge.gearshape", iconColor: LuminaTheme.Colors.textTertiary)
            
            if viewModel.subfolders.isEmpty {
                Text("此目錄下無子資料夾")
                    .font(.system(size: 10))
                    .foregroundColor(LuminaTheme.Colors.textMuted)
                    .padding(.leading, 6)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 2) {
                    ForEach(viewModel.subfolders) { subfolder in
                        let isSelected = viewModel.selectedFolder == subfolder.url
                        let isHovered = hoveredSubfolder == subfolder.url
                        
                        Button(action: {
                            viewModel.selectFolder(subfolder.url)
                        }) {
                            HStack(spacing: 7) {
                                Image(systemName: isSelected ? "folder.fill" : "folder")
                                    .font(.system(size: 11))
                                    .foregroundColor(isSelected ? LuminaTheme.Colors.cyanAccent : LuminaTheme.Colors.amberGold.opacity(0.85))
                                
                                Text(subfolder.name)
                                    .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                                    .foregroundColor(isSelected ? LuminaTheme.Colors.cyanAccent : (isHovered ? LuminaTheme.Colors.textPrimary : LuminaTheme.Colors.textSecondary))
                                    .lineLimit(1)
                                
                                Spacer()
                            }
                            .padding(.vertical, 4.5)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isSelected ? LuminaTheme.Colors.cyanAccent.opacity(0.12) : (isHovered ? Color.black.opacity(0.04) : Color.clear))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .onHover { hovering in
                            hoveredSubfolder = hovering ? subfolder.url : nil
                        }
                        .contextMenu {
                            Button("在 Finder 中顯示") {
                                NSWorkspace.shared.activateFileViewerSelecting([subfolder.url])
                            }
                            Button(viewModel.isFavorite(subfolder.url) ? "從我的最愛移除" : "加入我的最愛") {
                                viewModel.toggleFavorite(subfolder.url)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Section Header Reusable View
    private func sectionHeader(title: String, icon: String, iconColor: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(iconColor)
            Text(title)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(0.6)
                .foregroundColor(LuminaTheme.Colors.textTertiary)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }
    
    // MARK: - System Diagnostics Footer
    private var systemDiagnosticsFooter: some View {
        HStack(spacing: 8) {
            // Live Status Beacon
            Circle()
                .fill(LuminaTheme.Colors.mintEmerald)
                .frame(width: 6, height: 6)
                .luminaGlow(color: LuminaTheme.Colors.mintEmerald, radius: 4)
            
            Text("METAL 3")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(LuminaTheme.Colors.textSecondary)
            
            Text("•")
                .foregroundColor(LuminaTheme.Colors.textMuted)
            
            Text("FSEvents 即時監控")
                .font(.system(size: 9))
                .foregroundColor(LuminaTheme.Colors.textTertiary)
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(LuminaTheme.Colors.bgSurface.opacity(0.95))
        .overlay(
            VStack {
                Rectangle().fill(LuminaTheme.Colors.borderSubtle).frame(height: 1)
                Spacer()
            }
        )
    }
}
