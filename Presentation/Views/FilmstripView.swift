import SwiftUI
import AppKit

public struct FilmstripView: View {
    @ObservedObject var viewModel: AppViewModel
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(0..<viewModel.displayedImages.count, id: \.self) { index in
                        let item = viewModel.displayedImages[index]
                        let isSelected = viewModel.selectedImageIndex == index
                        let key = item.url.path
                        
                        Button(action: {
                            viewModel.selectedImageIndex = index
                            viewModel.calculateHistogramForSelected()
                            viewModel.prefetchAdjacentImages()
                        }) {
                            ZStack(alignment: .bottom) {
                                // Thumbnail frame
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(isSelected ? LuminaTheme.Colors.cyanAccent : Color.black.opacity(0.1), lineWidth: isSelected ? 2 : 1)
                                    )
                                    .shadow(color: isSelected ? LuminaTheme.Colors.cyanAccent.opacity(0.35) : LuminaTheme.Shadows.ambient, radius: isSelected ? 6 : 2, x: 0, y: 1)
                                
                                if let cgImage = viewModel.thumbnails[key] {
                                    Image(nsImage: NSImage(cgImage: cgImage, size: .zero))
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 72, height: 50)
                                        .clipped()
                                        .cornerRadius(5)
                                        .padding(isSelected ? 2 : 1)
                                } else {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                        .frame(width: 72, height: 50)
                                }
                                
                                // Mini rating / tag indicator bar
                                if let exif = viewModel.exifMetadata[key] {
                                    HStack(spacing: 2) {
                                        if exif.isTagged {
                                            Circle()
                                                .fill(LuminaTheme.Colors.neonCoral)
                                                .frame(width: 4, height: 4)
                                        }
                                        if exif.rating > 0 {
                                            HStack(spacing: 1) {
                                                Image(systemName: "star.fill")
                                                    .font(.system(size: 6))
                                                    .foregroundColor(LuminaTheme.Colors.amberGold)
                                                Text("\(exif.rating)")
                                                    .font(.system(size: 7, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.65))
                                    .cornerRadius(3)
                                    .padding(2)
                                }
                            }
                            .frame(width: 74, height: 52)
                            .id(index)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .background(VisualEffectView(material: .sidebar, blendingMode: .withinWindow).clipShape(RoundedRectangle(cornerRadius: 12)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: LuminaTheme.Shadows.ambient, radius: 10, x: 0, y: 4)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .onChange(of: viewModel.selectedImageIndex) { _, newIndex in
                if let idx = newIndex {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
        }
    }
}
