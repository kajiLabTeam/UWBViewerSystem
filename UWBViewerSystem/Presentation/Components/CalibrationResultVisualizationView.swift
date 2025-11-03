import SwiftUI

/// キャリブレーション結果を可視化するビューコンポーネント
///
/// Pythonの`visualize_calibration_result`関数と同等の機能を提供します。
/// - タグの既知位置を青色のマーカーで表示
/// - 初期アンテナ位置をオレンジ色の三角形で表示
/// - キャリブレーション後のアンテナ位置を赤色の三角形で表示
/// - アンテナの向きを矢印で表示
/// - 初期位置からの移動を灰色の点線矢印で表示
struct CalibrationResultVisualizationView: View {

    // MARK: - Properties

    let tagPositions: [TagPosition]
    let initialAntennaPositions: [AntennaCalibrationPosition]
    let calibratedAntennaPositions: [AntennaCalibrationPosition]
    let floorMapInfo: FloorMapInfo
    let showInitialPositions: Bool

    // MARK: - Constants

    private let arrowLength: Double = 2.0  // メートル単位
    private let markerSize: CGFloat = 10.0
    private let antennaSize: CGFloat = 15.0

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let scale = self.calculateScale(canvasSize: size)

            ZStack {
                // グリッド背景
                self.gridBackground

                // タグ位置（青色の円）
                ForEach(self.tagPositions) { tag in
                    self.tagMarker(tag: tag, scale: scale, size: size)
                }

                // 初期アンテナ位置（オレンジ色の三角形）
                if self.showInitialPositions {
                    ForEach(self.initialAntennaPositions) { antenna in
                        self.initialAntennaMarker(antenna: antenna, scale: scale, size: size)
                    }
                }

                // キャリブレーション後のアンテナ位置（赤色の三角形）
                ForEach(self.calibratedAntennaPositions) { antenna in
                    self.calibratedAntennaMarker(antenna: antenna, scale: scale, size: size)
                }

                // 初期位置からキャリブレーション後への移動矢印
                if self.showInitialPositions {
                    ForEach(
                        Array(
                            zip(self.initialAntennaPositions.indices, self.calibratedAntennaPositions.indices)
                        ),
                        id: \.0
                    ) { initialIndex, calibratedIndex in
                        if initialIndex < self.initialAntennaPositions.count
                            && calibratedIndex < self.calibratedAntennaPositions.count
                        {
                            self.movementArrow(
                                from: self.initialAntennaPositions[initialIndex],
                                to: self.calibratedAntennaPositions[calibratedIndex],
                                scale: scale,
                                size: size
                            )
                        }
                    }
                }
            }
        }
        .aspectRatio(contentMode: .fit)
        .overlay(
            self.legend
                .padding()
            , alignment: .topTrailing
        )
    }

    // MARK: - Components

    /// グリッド背景
    private var gridBackground: some View {
        GeometryReader { geometry in
            let size = geometry.size
            Path { path in
                // 縦線
                let verticalSpacing = size.width / 10
                for i in 0...10 {
                    let x = CGFloat(i) * verticalSpacing
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }

                // 横線
                let horizontalSpacing = size.height / 10
                for i in 0...10 {
                    let y = CGFloat(i) * horizontalSpacing
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
            }
            .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
        }
    }

    /// 凡例
    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 12, height: 12)
                Text("タグ位置")
                    .font(.caption)
            }

            if self.showInitialPositions {
                HStack(spacing: 4) {
                    Triangle()
                        .fill(Color.orange.opacity(0.6))
                        .frame(width: 12, height: 12)
                    Text("初期位置")
                        .font(.caption)
                }
            }

            HStack(spacing: 4) {
                Triangle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                Text("キャリブレーション後")
                    .font(.caption)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.9))
        .cornerRadius(8)
        .shadow(radius: 2)
    }

    /// タグマーカー
    private func tagMarker(tag: TagPosition, scale: Double, size: CGSize) -> some View {
        let screenPos = self.realWorldToScreen(
            realWorld: tag.position,
            scale: scale,
            canvasSize: size
        )

        return ZStack {
            Circle()
                .fill(Color.blue)
                .frame(width: self.markerSize, height: self.markerSize)

            Text(tag.name)
                .font(.caption2)
                .offset(x: self.markerSize, y: self.markerSize)
        }
        .position(screenPos)
    }

    /// 初期アンテナマーカー
    private func initialAntennaMarker(antenna: AntennaCalibrationPosition, scale: Double, size: CGSize)
        -> some View
    {
        let screenPos = self.realWorldToScreen(
            realWorld: antenna.position,
            scale: scale,
            canvasSize: size
        )

        return ZStack {
            // 三角形マーカー
            Triangle()
                .fill(Color.orange.opacity(0.6))
                .frame(width: self.antennaSize, height: self.antennaSize)
                .rotationEffect(.degrees(antenna.rotation))

            // 向き矢印
            self.directionArrow(
                from: screenPos,
                angle: antenna.rotation,
                color: Color.orange.opacity(0.4),
                scale: scale
            )

            // ラベル
            VStack(alignment: .leading, spacing: 2) {
                Text("初期位置")
                    .font(.caption2)
                Text(
                    String(
                        format: "(%.2f, %.2f)m\n%.0f°",
                        antenna.position.x,
                        antenna.position.y,
                        antenna.rotation
                    )
                )
                .font(.caption2)
            }
            .foregroundColor(.orange)
            .offset(x: -self.antennaSize * 3, y: -self.antennaSize * 2)
        }
        .position(screenPos)
    }

    /// キャリブレーション後のアンテナマーカー
    private func calibratedAntennaMarker(
        antenna: AntennaCalibrationPosition,
        scale: Double,
        size: CGSize
    ) -> some View {
        let screenPos = self.realWorldToScreen(
            realWorld: antenna.position,
            scale: scale,
            canvasSize: size
        )

        return ZStack {
            // 三角形マーカー
            Triangle()
                .fill(Color.red)
                .frame(width: self.antennaSize, height: self.antennaSize)
                .rotationEffect(.degrees(antenna.rotation))

            // 向き矢印
            self.directionArrow(
                from: screenPos,
                angle: antenna.rotation,
                color: Color.red.opacity(0.5),
                scale: scale
            )

            // ラベル
            VStack(alignment: .leading, spacing: 2) {
                Text(antenna.name)
                    .font(.caption2)
                    .fontWeight(.bold)
                Text(
                    String(
                        format: "(%.2f, %.2f)m\n%.0f°",
                        antenna.position.x,
                        antenna.position.y,
                        antenna.rotation
                    )
                )
                .font(.caption2)
            }
            .foregroundColor(.red)
            .offset(x: self.antennaSize * 2, y: -self.antennaSize)
        }
        .position(screenPos)
    }

    /// 向き矢印を描画
    private func directionArrow(from position: CGPoint, angle: Double, color: Color, scale: Double)
        -> some View
    {
        let arrowLengthPixels = CGFloat(arrowLength / scale)
        let angleRad = angle * .pi / 180.0
        let endX = position.x + arrowLengthPixels * CGFloat(cos(angleRad))
        let endY = position.y - arrowLengthPixels * CGFloat(sin(angleRad))  // Y軸は下向きが正

        return Path { path in
            path.move(to: position)
            path.addLine(to: CGPoint(x: endX, y: endY))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        .overlay(
            // 矢印の先端
            Triangle()
                .fill(color)
                .frame(width: 8, height: 8)
                .rotationEffect(.degrees(angle))
                .position(x: endX, y: endY)
        )
    }

    /// 初期位置からキャリブレーション後への移動矢印
    private func movementArrow(
        from initial: AntennaCalibrationPosition,
        to calibrated: AntennaCalibrationPosition,
        scale: Double,
        size: CGSize
    ) -> some View {
        let startPos = self.realWorldToScreen(
            realWorld: initial.position,
            scale: scale,
            canvasSize: size
        )
        let endPos = self.realWorldToScreen(
            realWorld: calibrated.position,
            scale: scale,
            canvasSize: size
        )

        return Path { path in
            path.move(to: startPos)
            path.addLine(to: endPos)
        }
        .stroke(
            Color.gray.opacity(0.7),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 5])
        )
    }

    // MARK: - Helper Methods

    /// スケールを計算（メートル/ピクセル）
    private func calculateScale(canvasSize: CGSize) -> Double {
        let maxRealSize = max(floorMapInfo.width, self.floorMapInfo.depth)
        let maxCanvasSize = max(canvasSize.width, canvasSize.height)
        return maxRealSize / Double(maxCanvasSize)
    }

    /// 実世界座標をスクリーン座標に変換
    /// - 実世界座標: 左下原点(0,0)、Y軸上向き
    /// - スクリーン座標: 左上原点(0,0)、Y軸下向き
    private func realWorldToScreen(realWorld: Point3D, scale: Double, canvasSize: CGSize) -> CGPoint {
        let x = CGFloat(realWorld.x / scale)
        let y = canvasSize.height - CGFloat(realWorld.y / scale)  // Y軸を反転
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Supporting Types

/// タグ位置情報
struct TagPosition: Identifiable {
    let id: String
    let name: String
    let position: Point3D
}

/// アンテナキャリブレーション位置情報
struct AntennaCalibrationPosition: Identifiable {
    let id: String
    let name: String
    let position: Point3D
    let rotation: Double  // 度単位
}

/// 三角形シェイプ（上向き）
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Preview

#Preview {
    CalibrationResultVisualizationView(
        tagPositions: [
            TagPosition(
                id: "tag1",
                name: "Tag 1",
                position: Point3D(x: 14.090, y: 18.134, z: 0)
            ),
            TagPosition(
                id: "tag2",
                name: "Tag 2",
                position: Point3D(x: 15.260, y: 18.090, z: 0)
            ),
            TagPosition(
                id: "tag3",
                name: "Tag 3",
                position: Point3D(x: 14.592, y: 16.592, z: 0)
            ),
        ],
        initialAntennaPositions: [
            AntennaCalibrationPosition(
                id: "antenna1",
                name: "Antenna 1",
                position: Point3D(x: 14.500, y: 8.000, z: 0),
                rotation: 90.0
            )
        ],
        calibratedAntennaPositions: [
            AntennaCalibrationPosition(
                id: "antenna1",
                name: "Antenna 1",
                position: Point3D(x: 14.650, y: 8.200, z: 0),
                rotation: 92.5
            )
        ],
        floorMapInfo: FloorMapInfo(
            id: "preview",
            name: "Preview Floor",
            buildingName: "Preview Building",
            width: 28.0,
            depth: 37.0,
            createdAt: Date()
        ),
        showInitialPositions: true
    )
    .frame(width: 600, height: 800)
}
