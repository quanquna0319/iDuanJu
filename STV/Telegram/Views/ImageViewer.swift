import SwiftUI

/// Full-screen image viewer shared by Telegram posts, downloads and the manga reader:
/// swipe left/right between images, pinch / double-tap to zoom, drag down to close.
struct ImageViewer: View {
    struct Item: Identifiable, Hashable { var url: String; var id: String { url } }
    let items: [Item]
    @State var index: Int
    var headers: [String: String] = [:]
    var onSave: ((Item) async throws -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var drag: CGFloat = 0
    @State private var zoomed = false
    @State private var toast: String?

    var body: some View {
        ZStack {
            Color.black.opacity(1 - min(0.7, abs(drag) / CGFloat(600))).ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(items.indices, id: \.self) { i in
                    ZoomableImage(url: items[i].url, headers: headers, zoomed: $zoomed).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .offset(y: drag)
            .simultaneousGesture(zoomed ? nil : DragGesture(minimumDistance: 20)
                .onChanged { v in if abs(v.translation.height) > abs(v.translation.width) { drag = v.translation.height } }
                .onEnded { v in
                    if abs(v.translation.height) > 120 || abs(v.predictedEndTranslation.height) > 300 { dismiss() }
                    else { withAnimation(.spring(response: 0.3)) { drag = 0 } }
                })
            VStack {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).padding(12).background(.ultraThinMaterial, in: Circle()) }
                        .accessibilityIdentifier("viewer.close")
                    Spacer()
                    Text("\(index + 1) / \(items.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.white)
                        .accessibilityIdentifier("viewer.counter")
                    Spacer()
                    if let onSave {
                        Button {
                            Task {
                                do { try await onSave(items[index]); toast = "已保存到相册" } catch { toast = error.localizedDescription }
                            }
                        } label: { Image(systemName: "square.and.arrow.down").font(.headline).padding(12).background(.ultraThinMaterial, in: Circle()) }
                            .accessibilityLabel("保存到相册")
                    } else { Color.clear.frame(width: 44, height: 44) }
                }
                .foregroundStyle(.white).padding(.horizontal, 16)
                Spacer()
                if let toast { Text(toast).font(.footnote).foregroundStyle(.white).padding(10).background(.black.opacity(0.6), in: Capsule()).padding(.bottom, 30) }
            }
            .opacity(drag == 0 ? 1 : 0)
        }
        .statusBarHidden()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tg.viewer")
        .task(id: toast) { if toast != nil { try? await Task.sleep(for: .seconds(2)); toast = nil } }
    }
}

struct ZoomableImage: View {
    let url: String
    var headers: [String: String] = [:]
    @Binding var zoomed: Bool
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .scaleEffect(scale).offset(offset)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .gesture(MagnifyGesture()
                            .onChanged { v in scale = max(1, min(5, base * v.magnification)); zoomed = scale > 1.01 }
                            .onEnded { _ in base = scale; if scale <= 1.01 { reset() } })
                        .simultaneousGesture(scale > 1.01 ? DragGesture()
                            .onChanged { v in offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height) }
                            .onEnded { _ in lastOffset = offset } : nil)
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3)) { if scale > 1.01 { reset() } else { scale = 2.5; base = 2.5; zoomed = true } }
                        }
                        .accessibilityIdentifier("viewer.image")
                        .accessibilityValue(scale > 1.01 ? "zoomed" : "fit")
                } else if failed {
                    Image(systemName: "photo").font(.largeTitle).foregroundStyle(.white.opacity(0.4))
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task(id: url) {
            do { image = try await CoverStore.shared.image(url: url, headers: headers) } catch { failed = true }
        }
    }

    private func reset() { scale = 1; base = 1; offset = .zero; lastOffset = .zero; zoomed = false }
}
