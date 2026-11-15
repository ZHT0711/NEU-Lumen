import SwiftUI

private struct IndoorMapIdentity: Hashable {
    let key: String?
    let points: [IndoorCoordinate]
    let first: Bool
    let last: Bool
    let attempt: Int
}

struct IndoorRouteMapCard: View {
    let step: IndoorRouteStep
    let first: Bool
    let last: Bool
    @State private var image: UIImage?
    @State private var failed = false
    @State private var enlarged = false
    @State private var attempt = 0
    private let client = PathlyClient()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(step.title).font(.headline)
            if let image {
                Button { enlarged = true } label: {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity).frame(maxHeight: 340)
                        .background(.white).clipShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).accessibilityLabel(step.title + "，放大地图")
                Label("点按放大，可双指缩放和拖动", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.caption).foregroundStyle(.secondary)
            } else if failed {
                Button("楼层图加载失败，点按重试", systemImage: "arrow.clockwise") { attempt += 1 }
            } else { ProgressView("正在加载楼层图…").frame(height: 180).frame(maxWidth: .infinity) }
        }
        .padding(.vertical, 8)
        .task(id: IndoorMapIdentity(key: step.imageKey, points: step.points, first: first, last: last, attempt: attempt)) { await load() }
        .fullScreenCover(isPresented: $enlarged) {
            NavigationStack {
                if let image { IndoorZoomableMap(image: image).ignoresSafeArea(edges: .bottom)
                    .navigationTitle(step.title).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { enlarged = false } } }
                }
            }
        }
    }
    private func load() async {
        guard let url = step.imageURL else { failed = true; return }
        failed = false; image = nil
        do {
            let data = try await client.image(url)
            guard !Task.isCancelled else { return }
            guard let source = UIImage(data: data) else { failed = true; return }
            image = Self.draw(source: source, points: step.points, first: first, last: last)
        } catch { if !Task.isCancelled { failed = true } }
    }
    static func draw(source: UIImage, points: [IndoorCoordinate], first: Bool, last: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: source.size, format: format).image { _ in
            source.draw(at: .zero)
            let positions = points.map { CGPoint(x: CGFloat($0.x) / 100 * source.size.width, y: CGFloat($0.y) / 100 * source.size.height) }
            let width = max(4, source.size.width / 300)
            let line = UIBezierPath()
            if let start = positions.first {
                line.move(to: start)
                for point in positions.dropFirst() { line.addLine(to: point) }
                line.lineWidth = width; line.lineJoinStyle = .round; line.lineCapStyle = .round
                UIColor.systemRed.setStroke(); line.stroke()
            }
            func marker(_ point: CGPoint, text: String, color: UIColor) {
                let radius = max(15, source.size.width / 65)
                let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                color.setFill(); UIBezierPath(ovalIn: rect).fill()
                UIColor.white.setStroke(); let border = UIBezierPath(ovalIn: rect); border.lineWidth = width / 2; border.stroke()
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: radius * 1.2), .foregroundColor: UIColor.white]
                let size = (text as NSString).size(withAttributes: attributes)
                (text as NSString).draw(at: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), withAttributes: attributes)
            }
            if first, let point = positions.first { marker(point, text: "起", color: .systemBlue) }
            if last, let point = positions.last { marker(point, text: "终", color: .systemRed) }
        }
    }
}

private struct IndoorZoomableMap: UIViewRepresentable {
    let image: UIImage
    func makeUIView(context: Context) -> IndoorMapScrollView { IndoorMapScrollView(image: image) }
    func updateUIView(_ uiView: IndoorMapScrollView, context: Context) {}
}

private final class IndoorMapScrollView: UIScrollView, UIScrollViewDelegate {
    private let map: UIImageView
    private var fittedBounds = CGSize.zero
    init(image: UIImage) {
        map = UIImageView(image: image)
        super.init(frame: .zero)
        backgroundColor = .white
        delegate = self
        map.frame = CGRect(origin: .zero, size: image.size)
        addSubview(map)
        contentSize = image.size
        accessibilityLabel = "楼层路线图，可缩放"
    }
    required init?(coder: NSCoder) { return nil }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, map.bounds.width > 0, map.bounds.height > 0 else { return }
        if fittedBounds != bounds.size {
            fittedBounds = bounds.size
            let scale = min(bounds.width / map.bounds.width, bounds.height / map.bounds.height)
            minimumZoomScale = scale; maximumZoomScale = max(scale * 8, 2)
            zoomScale = scale
        }
        centerImage()
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { map }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }
    private func centerImage() {
        let inset = UIEdgeInsets(top: max(0, (bounds.height - contentSize.height) / 2), left: max(0, (bounds.width - contentSize.width) / 2), bottom: 0, right: 0)
        if contentInset != inset { contentInset = inset }
    }
}
