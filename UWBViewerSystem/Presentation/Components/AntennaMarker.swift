import SwiftUI

// MARK: - AntennaMarker - 共通のアンテナマーカーコンポーネント

struct AntennaMarker: View {
    let antenna: AntennaDisplayData
    let position: CGPoint
    let size: CGFloat
    let sensorRange: CGFloat?
    let isSelected: Bool
    let isDraggable: Bool
    let showRotationControls: Bool
    let onPositionChanged: ((CGPoint) -> Void)?
    let onRotationChanged: ((Double) -> Void)?
    let onTap: (() -> Void)?

    @State private var dragOffset = CGSize.zero
    @State private var showRotationControlsState = false

    init(
        antenna: AntennaDisplayData,
        position: CGPoint,
        size: CGFloat,
        sensorRange: CGFloat? = nil,
        isSelected: Bool = false,
        isDraggable: Bool = false,
        showRotationControls: Bool = false,
        onPositionChanged: ((CGPoint) -> Void)? = nil,
        onRotationChanged: ((Double) -> Void)? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.antenna = antenna
        self.position = position
        self.size = size
        self.sensorRange = sensorRange
        self.isSelected = isSelected
        self.isDraggable = isDraggable
        self.showRotationControls = showRotationControls
        self.onPositionChanged = onPositionChanged
        self.onRotationChanged = onRotationChanged
        self.onTap = onTap
    }

    private var displaySize: CGFloat {
        max(min(size, 80), 20) // 最小20px、最大80px
    }

    var body: some View {
        ZStack {
            // センサー範囲を示す扇形（選択時のみ表示）
            if isSelected, let range = sensorRange {
                SensorRangeView(rotation: antenna.rotation, sensorRange: range)
                    .frame(width: range, height: range)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 4) {
                ZStack {
                    // アンテナ背景円
                    Circle()
                        .fill(isSelected ? Color.blue : (antenna.color ?? Color.gray.opacity(0.8)))
                        .frame(width: displaySize, height: displaySize)
                        .shadow(radius: isSelected ? 4 : 2)

                    // アンテナアイコン（回転対応）
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: displaySize * 0.5))
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(antenna.rotation))

                    // 向きを示す矢印
                    if (showRotationControls || showRotationControlsState) && antenna.rotation != 0 {
                        Image(systemName: "arrow.up")
                            .font(.system(size: displaySize * 0.3))
                            .foregroundColor(.yellow)
                            .offset(y: -displaySize * 0.6)
                            .rotationEffect(.degrees(antenna.rotation))
                    }
                }
                .onTapGesture(count: isDraggable ? 2 : 1) {
                    if isDraggable {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showRotationControlsState.toggle()
                        }
                    } else {
                        onTap?()
                    }
                }

                // アンテナ名表示
                Text(antenna.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(antennaNameBackground)
                    .foregroundColor(isSelected ? .blue : .primary)
            }

            // 回転コントロール（表示時のみ、固定サイズ）
            if (showRotationControls || showRotationControlsState), isDraggable {
                AntennaRotationControl(
                    rotation: antenna.rotation,
                    onRotationChanged: { newRotation in
                        onRotationChanged?(newRotation)
                    }
                )
                .offset(y: displaySize + 50) // アンテナアイコンの下に十分な余白を確保
                .zIndex(1000) // 最前面に表示
                .transition(.scale.combined(with: .opacity))
            }
        }
        .position(
            x: position.x + dragOffset.width,
            y: position.y + dragOffset.height
        )
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .zIndex(isSelected ? 100 : 10)
        .gesture(
            isDraggable ?
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    let newPosition = CGPoint(
                        x: position.x + value.translation.width,
                        y: position.y + value.translation.height
                    )
                    onPositionChanged?(newPosition)
                    dragOffset = .zero
                } : nil
        )
    }

    private var antennaNameBackground: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(backgroundFillColor)
            .shadow(radius: 1)
    }

    private var backgroundFillColor: Color {
        #if os(macOS)
        return Color(NSColor.controlBackgroundColor).opacity(0.9)
        #elseif os(iOS)
        return Color(UIColor.systemBackground).opacity(0.9)
        #endif
    }
}

// MARK: - AntennaDisplayData - アンテナ表示用のデータモデル

struct AntennaDisplayData {
    let id: String
    let name: String
    let rotation: Double
    let color: Color?

    init(id: String, name: String, rotation: Double = 0.0, color: Color? = nil) {
        self.id = id
        self.name = name
        self.rotation = rotation
        self.color = color
    }
}

// MARK: - SensorRangeView - センサー範囲表示

struct SensorRangeView: View {
    let rotation: Double
    let sensorRange: CGFloat

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                let radius = min(geometry.size.width, geometry.size.height) / 2

                // センサー範囲: -60度から+60度（120度の扇形）
                let startAngle = -60.0
                let endAngle = 60.0

                // 中心点から開始
                path.move(to: center)

                // 扇形を描画（SwiftUIの角度は時計回りで、0度が上）
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(startAngle - 90), // -90度オフセットで上向きを0度に
                    endAngle: .degrees(endAngle - 90),
                    clockwise: false
                )

                // 中心点に戻る
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.blue.opacity(0.3),
                        Color.blue.opacity(0.1)
                    ]),
                    startPoint: .center,
                    endPoint: .bottom
                )
            )
            .overlay(
                // 扇形の境界線
                Path { path in
                    let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    let radius = min(geometry.size.width, geometry.size.height) / 2

                    let startAngle = -60.0
                    let endAngle = 60.0

                    path.move(to: center)
                    path.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .degrees(startAngle - 90),
                        endAngle: .degrees(endAngle - 90),
                        clockwise: false
                    )
                    path.closeSubpath()
                }
                .stroke(Color.blue.opacity(0.5), lineWidth: 1)
            )
        }
        .rotationEffect(.degrees(rotation))
    }
}

// MARK: - AntennaRotationControl - アンテナ回転コントロール

struct AntennaRotationControl: View {
    let rotation: Double
    let onRotationChanged: (Double) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("向き調整")
                .font(.caption)
                .fontWeight(.medium)

            HStack(spacing: 12) {
                Button(action: { onRotationChanged(rotation - 15) }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Text("\(Int(rotation))°")
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .frame(width: 40)

                Button(action: { onRotationChanged(rotation + 15) }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 8) {
                ForEach([0, 90, 180, 270], id: \.self) { angle in
                    Button("\(angle)°") {
                        onRotationChanged(Double(angle))
                    }
                    .font(.caption2)
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(8)
        #if os(macOS)
        .background(Color(NSColor.controlBackgroundColor))
        #elseif os(iOS)
        .background(Color(UIColor.systemBackground))
        #endif
        .cornerRadius(8)
        .shadow(radius: 4)
    }
}