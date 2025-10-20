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
        // サイズは既にFloorMapCanvasGeometryで計算済み（スケール補正含む）
        self.size
    }

    var body: some View {
        ZStack {
            // センサー範囲を示す扇形（選択時のみ表示）
            if self.isSelected, let range = sensorRange {
                SensorRangeView(rotation: self.antenna.rotation, sensorRange: range)
                    .frame(width: range, height: range)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 4) {
                ZStack {
                    // アンテナ背景円
                    Circle()
                        .fill(self.isSelected ? Color.blue : (self.antenna.color ?? Color.gray.opacity(0.8)))
                        .frame(width: self.displaySize, height: self.displaySize)
                        .shadow(radius: self.isSelected ? 4 : 2)

                    // アンテナアイコン（回転対応）
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: self.displaySize * 0.5))
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(self.antenna.rotation))

                    // 向きを示す矢印
                    if (self.showRotationControls || self.showRotationControlsState) && self.antenna.rotation != 0 {
                        Image(systemName: "arrow.up")
                            .font(.system(size: self.displaySize * 0.3))
                            .foregroundColor(.yellow)
                            .offset(y: -self.displaySize * 0.6)
                            .rotationEffect(.degrees(self.antenna.rotation))
                    }
                }
                .onTapGesture(count: self.isDraggable ? 2 : 1) {
                    if self.isDraggable {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            self.showRotationControlsState.toggle()
                        }
                    } else {
                        self.onTap?()
                    }
                }

                // アンテナ名表示
                Text(self.antenna.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(self.antennaNameBackground)
                    .foregroundColor(self.isSelected ? .blue : .primary)
            }

            // 回転コントロール（表示時のみ、固定サイズ）
            if self.showRotationControls || self.showRotationControlsState, self.isDraggable {
                AntennaRotationControl(
                    rotation: self.antenna.rotation,
                    onRotationChanged: { newRotation in
                        self.onRotationChanged?(newRotation)
                    }
                )
                .offset(y: self.displaySize + 50)  // アンテナアイコンの下に十分な余白を確保
                .zIndex(1000)  // 最前面に表示
                .transition(.scale.combined(with: .opacity))
            }
        }
        .position(
            x: self.position.x + self.dragOffset.width,
            y: self.position.y + self.dragOffset.height
        )
        .zIndex(self.isSelected ? 100 : 10)
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard self.isDraggable else { return }
                    self.dragOffset = value.translation
                }
                .onEnded { value in
                    guard self.isDraggable else { return }
                    let newPosition = CGPoint(
                        x: self.position.x + value.translation.width,
                        y: self.position.y + value.translation.height
                    )
                    self.onPositionChanged?(newPosition)
                    self.dragOffset = .zero
                }
        )
    }

    private var antennaNameBackground: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(self.backgroundFillColor)
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
                    startAngle: .degrees(startAngle - 90),  // -90度オフセットで上向きを0度に
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
                        Color.blue.opacity(0.1),
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
        .rotationEffect(.degrees(self.rotation))
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
                Button(action: { self.onRotationChanged(self.rotation - 15) }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Text("\(Int(self.rotation))°")
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .frame(width: 40)

                Button(action: { self.onRotationChanged(self.rotation + 15) }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 8) {
                ForEach([0, 90, 180, 270], id: \.self) { angle in
                    Button("\(angle)°") {
                        self.onRotationChanged(Double(angle))
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
