import SwiftUI

struct CropPoint: Codable, Equatable { var x: Double; var y: Double }
struct CropSelection: Codable, Equatable {
    var quarterTurns = 0
    // Clockwise, starting at the top left, in display coordinates.
    var points = [CropPoint(x: 0, y: 0), CropPoint(x: 1, y: 0), CropPoint(x: 1, y: 1), CropPoint(x: 0, y: 1)]
    var valid: Bool {
        guard points.count == 4, (0...3).contains(quarterTurns), points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else { return false }
        var area = 0.0
        for i in 0..<4 {
            let a = points[i], b = points[(i + 1) % 4], c = points[(i + 2) % 4]
            guard (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x) > 0.0001 else { return false }
            area += a.x * b.y - b.x * a.y
        }
        return area / 2 > 0.02
    }
}
struct CropEditor: View {
    let data: Data
    let onApply: (CropSelection) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: CropSelection
    private let labels = ["Top left", "Top right", "Bottom right", "Bottom left"]
    init(data: Data, initial: CropSelection?, onApply: @escaping (CropSelection) -> Void) {
        self.data = data; self.onApply = onApply
        _selection = State(initialValue: initial ?? CropSelection())
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Drag each corner to the card edge. The original photo is always preserved.").font(.subheadline).padding(.horizontal)
                GeometryReader { geometry in
                    if let source = UIImage(data: data) {
                        let image = Imaging.rotated(source, quarterTurns: selection.quarterTurns)
                        let scale = min(geometry.size.width / image.size.width, geometry.size.height / image.size.height)
                        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                        ZStack(alignment: .topLeading) {
                            Image(uiImage: image).resizable().frame(width: size.width, height: size.height)
                            Path { path in
                                let points = selection.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
                                path.addLines(points); path.closeSubpath()
                            }.stroke(selection.valid ? .yellow : .red, lineWidth: 3)
                            ForEach(0..<4, id: \.self) { index in
                                Circle().fill(.yellow).frame(width: 28, height: 28)
                                    .overlay(Circle().stroke(.black, lineWidth: 2))
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                                    .position(x: selection.points[index].x * size.width, y: selection.points[index].y * size.height)
                                    .gesture(DragGesture(coordinateSpace: .named("crop")).onChanged { value in
                                        selection.points[index] = CropPoint(x: min(1, max(0, value.location.x / size.width)), y: min(1, max(0, value.location.y / size.height)))
                                    })
                                    .accessibilityLabel(labels[index] + " crop corner")
                            }
                        }.frame(width: size.width, height: size.height).coordinateSpace(name: "crop")
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }.padding(24)
                HStack {
                    Button("Rotate 90°", systemImage: "rotate.right") { selection.quarterTurns = (selection.quarterTurns + 1) % 4; selection.points = CropSelection().points }
                    Spacer()
                    Button("Reset") { selection = CropSelection() }
                }.padding(.horizontal)
                if !selection.valid { Text("Keep the corners in order around the card.").foregroundStyle(.red) }
            }.padding(.vertical).navigationTitle("Adjust photograph").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Apply") { onApply(selection); dismiss() }.disabled(!selection.valid) }
                }
        }
    }
}
