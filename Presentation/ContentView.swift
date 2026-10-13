import SwiftUI
import AppKit

public struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            // Left Sidebar
            FolderTreeView(viewModel: viewModel)
                .frame(minWidth: 220, idealWidth: 260)
        } detail: {
            // Main Stage Area
            ZStack {
                // Base Canvas: Image Grid View
                ImageGridView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Fullscreen Metal Detail View
                if viewModel.isDetailActive {
                    ImageDetailView(viewModel: viewModel)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98)).animation(.spring(response: 0.24, dampingFraction: 0.8)),
                            removal: .opacity.animation(.easeOut(duration: 0.16))
                        ))
                        .zIndex(1)
                }
                
                // Multi-Photo Compare Arena
                if viewModel.isCompareActive {
                    CompareView(viewModel: viewModel)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98)).animation(.spring(response: 0.24, dampingFraction: 0.8)),
                            removal: .opacity.animation(.easeOut(duration: 0.16))
                        ))
                        .zIndex(2)
                }
                
                // Loading Overlay with Camera Aperture Pulse
                if viewModel.isLoading {
                    ZStack {
                        Color.black.opacity(0.4)
                            .edgesIgnoringSafeArea(.all)
                        
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.1)
                                .colorScheme(.dark)
                            
                            Text("正在快速解析影像快取...")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(LuminaTheme.Colors.textPrimary)
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 24)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.black.opacity(0.85))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                                )
                        )
                        .luminaGlow(color: LuminaTheme.Colors.cyanAccent, radius: 12)
                    }
                    .zIndex(3)
                }
                
                // Toast Notification Overlay
                if let toast = viewModel.toastMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(LuminaTheme.Colors.cyanAccent)
                        
                        Text(toast)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 9)
                    .padding(.horizontal, 18)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.92))
                            .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).clipShape(Capsule()))
                            .overlay(
                                Capsule().stroke(LuminaTheme.Colors.cyanAccent.opacity(0.4), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.5), radius: 12, x: 0, y: 6)
                    )
                    .luminaGlow(color: LuminaTheme.Colors.cyanAccent, radius: 8)
                    .padding(.bottom, 28)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(4)
                }
                
                // Global Keyboard Shortcuts Sheet Modal Overlay
                if viewModel.isShortcutSheetVisible {
                    KeyboardCheatSheetView(isPresented: $viewModel.isShortcutSheetVisible)
                        .zIndex(5)
                }
            }
            .navigationTitle(viewModel.selectedFolder?.lastPathComponent ?? "Lumina Pro")
        }
        .frame(minWidth: 1040, minHeight: 640)
        .preferredColorScheme(.dark)
    }
}

// macOS Native NSVisualEffectView wrapper for glassmorphism
public struct VisualEffectView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material = .hudWindow
    public var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    
    public init(material: NSVisualEffectView.Material = .hudWindow, blendingMode: NSVisualEffectView.BlendingMode = .withinWindow) {
        self.material = material
        self.blendingMode = blendingMode
    }
    
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
