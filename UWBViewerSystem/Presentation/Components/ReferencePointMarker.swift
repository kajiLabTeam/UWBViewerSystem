import SwiftUI

// MARK: - ReferencePointMarker - 基準点マーカーコンポーネント

struct ReferencePointMarker: View {
    let point: ReferencePointDisplayData
    let position: CGPoint
    let size: CGFloat
    let isSelected: Bool
    let isDraggable: Bool
    let onPositionChanged: ((CGPoint) -> Void)?
    let onTap: (() -> Void)?

    @State private var dragOffset = CGSize.zero

    init(
        point: ReferencePointDisplayData,
        position: CGPoint,
        size: CGFloat = 12,
        isSelected: Bool = false,
        isDraggable: Bool = false,
        onPositionChanged: ((CGPoint) -> Void)? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.point = point
        self.position = position
        self.size = size
        self.isSelected = isSelected
        self.isDraggable = isDraggable
        self.onPositionChanged = onPositionChanged
        self.onTap = onTap
    }

    private var displaySize: CGFloat {
        self.isSelected ? self.size * 1.2 : self.size
    }

    var body: some View {
        Circle()
            .fill(self.point.color)
            .frame(width: self.displaySize, height: self.displaySize)
            .overlay(
                Text(self.point.label)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            )
            .shadow(radius: self.isSelected ? 3 : 1)
            .position(
                x: self.position.x + self.dragOffset.width,
                y: self.position.y + self.dragOffset.height
            )
            .scaleEffect(self.isSelected ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: self.isSelected)
            .zIndex(self.isSelected ? 50 : 5)
            .onTapGesture {
                self.onTap?()
            }
            .gesture(
                self.isDraggable
                    ? DragGesture()
                    .onChanged { value in
                        self.dragOffset = value.translation
                    }
                    .onEnded { value in
                        let newPosition = CGPoint(
                            x: position.x + value.translation.width,
                            y: self.position.y + value.translation.height
                        )
                        self.onPositionChanged?(newPosition)
                        self.dragOffset = .zero
                    } : nil
            )
    }
}

// MARK: - ReferencePointDisplayData - 基準点表示用のデータモデル

struct ReferencePointDisplayData {
    let id: String
    let label: String
    let color: Color
    let coordinates: Point3D?

    init(id: String, label: String, color: Color = .red, coordinates: Point3D? = nil) {
        self.id = id
        self.label = label
        self.color = color
        self.coordinates = coordinates
    }
}

// MARK: - ReferencePointList - 基準点リスト表示コンポーネント

struct ReferencePointList: View {
    let points: [ReferencePointDisplayData]
    let onClear: (() -> Void)?
    let onPointTap: ((String) -> Void)?

    var body: some View {
        if !self.points.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("設定済み基準点")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    if let onClear {
                        Button("クリア", action: onClear)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                ForEach(Array(self.points.enumerated()), id: \.offset) { index, point in
                    ReferencePointRow(
                        point: point,
                        index: index,
                        onTap: { self.onPointTap?(point.id) }
                    )
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)
        }
    }
}

// MARK: - ReferencePointRow - 基準点行表示

struct ReferencePointRow: View {
    let point: ReferencePointDisplayData
    let index: Int
    let onTap: (() -> Void)?

    var body: some View {
        HStack {
            Circle()
                .fill(self.point.color)
                .frame(width: 12, height: 12)
                .overlay(
                    Text(self.point.label)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                )

            if let coordinates = point.coordinates {
                Text("座標: (\(String(format: "%.2f", coordinates.x)), \(String(format: "%.2f", coordinates.y)))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("基準点 \(self.index + 1)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            self.onTap?()
        }
    }
}
