import SwiftData
import SwiftUI

// MARK: - FloorMapCanvas - 共通のフロアマップ表示コンポーネント

struct FloorMapCanvas<Content: View>: View {
    let floorMapImage: FloorMapImage?
    let floorMapInfo: FloorMapInfo?
    let calibrationPoints: [MapCalibrationPoint]?
    let onMapTap: ((CGPoint) -> Void)?
    let enableZoom: Bool
    let fixedHeight: CGFloat?
    let showGrid: Bool
    @ViewBuilder let content: (FloorMapCanvasGeometry) -> Content

    @State private var canvasSize: CGSize = CGSize(width: 400, height: 300)
    @State private var currentScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    init(
        floorMapImage: FloorMapImage?,
        floorMapInfo: FloorMapInfo?,
        calibrationPoints: [MapCalibrationPoint]? = nil,
        onMapTap: ((CGPoint) -> Void)? = nil,
        enableZoom: Bool = false,
        fixedHeight: CGFloat? = 300,
        showGrid: Bool = true,
        @ViewBuilder content: @escaping (FloorMapCanvasGeometry) -> Content
    ) {
        self.floorMapImage = floorMapImage
        self.floorMapInfo = floorMapInfo
        self.calibrationPoints = calibrationPoints
        self.onMapTap = onMapTap
        self.enableZoom = enableZoom
        self.fixedHeight = fixedHeight
        self.showGrid = showGrid
        self.content = content
    }

    // フロアマップのスケールを計算(ピクセル/メートル)
    private var mapScale: Double {
        guard let floorMapInfo else { return 100.0 }
        let canvasWidth = Double(canvasSize.width)
        let mapWidthInMeters = floorMapInfo.width
        return canvasWidth / mapWidthInMeters
    }

    // アスペクト比を考慮した実際の画像表示領域を計算
    private func calculateActualImageFrame(canvasSize: CGSize, imageAspectRatio: Double) -> CGRect {
        let canvasAspectRatio = Double(canvasSize.width / canvasSize.height)

        var imageWidth: CGFloat
        var imageHeight: CGFloat

        if imageAspectRatio > canvasAspectRatio {
            // 画像の方が横長 → 横幅がフィット
            imageWidth = canvasSize.width
            imageHeight = imageWidth / CGFloat(imageAspectRatio)
        } else {
            // 画像の方が縦長(または同じ) → 縦幅がフィット
            imageHeight = canvasSize.height
            imageWidth = imageHeight * CGFloat(imageAspectRatio)
        }

        let offsetX = (canvasSize.width - imageWidth) / 2
        let offsetY = (canvasSize.height - imageHeight) / 2

        return CGRect(x: offsetX, y: offsetY, width: imageWidth, height: imageHeight)
    }

    var body: some View {
        GeometryReader { geometry in
            let currentCanvasSize = geometry.size
            let imageAspectRatio = self.floorMapInfo?.aspectRatio ?? 1.0
            let actualImageFrame = self.calculateActualImageFrame(
                canvasSize: currentCanvasSize, imageAspectRatio: imageAspectRatio)

            let canvasGeometry = FloorMapCanvasGeometry(
                canvasSize: currentCanvasSize,
                imageFrame: actualImageFrame,
                mapScale: mapScale * Double(self.currentScale),
                floorMapInfo: self.floorMapInfo,
                currentScale: self.currentScale
            )

            ZStack {
                // マップ背景
                FloorMapBackground(image: self.floorMapImage, floorMapInfo: self.floorMapInfo)
                    .allowsHitTesting(false)

                // グリッド線の描画
                if self.showGrid {
                    GridOverlay(geometry: canvasGeometry)
                }

                // タップ領域(背景層)
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        self.handleMapTap(location: location, geometry: canvasGeometry)
                    }

                // キャリブレーション結果の表示
                if let calibrationPoints = self.calibrationPoints {
                    ForEach(calibrationPoints) { point in
                        let screenPosition = self.realWorldToScreen(
                            realWorldPoint: point.realWorldCoordinate,
                            geometry: canvasGeometry
                        )
                        // 固定サイズで表示
                        CalibrationResultMarker(
                            point: point,
                            position: screenPosition,
                            size: 16,
                            isSelected: false,
                            isDraggable: false
                        )
                    }
                }

                // コンテンツ(アンテナ、基準点など)- 最前面
                self.content(canvasGeometry)
            }
            .scaleEffect(self.enableZoom ? self.currentScale : 1.0, anchor: .center)
            .offset(self.enableZoom ? self.offset : .zero)
            .if(self.enableZoom) { view in
                view.gesture(
                    SimultaneousGesture(
                        MagnificationGesture(minimumScaleDelta: 0.0)
                            .onChanged { value in
                                let newScale = self.lastScale * value
                                self.currentScale = min(max(newScale, 0.5), 5.0)
                            }
                            .onEnded { _ in
                                self.lastScale = self.currentScale
                            },
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                self.offset = CGSize(
                                    width: self.lastOffset.width + value.translation.width,
                                    height: self.lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                self.lastOffset = self.offset
                            }
                    )
                )
            }
            .animation(.none, value: self.currentScale)  // アニメーションを無効化
            .animation(.none, value: self.offset)
            .onAppear {
                self.canvasSize = currentCanvasSize
            }
            .onChange(of: geometry.size) { _, newSize in
                self.canvasSize = newSize
            }
        }
        .if(self.fixedHeight != nil) { view in
            view.frame(height: self.fixedHeight)
        }
        .cornerRadius(12)
    }

    private func handleMapTap(location: CGPoint, geometry: FloorMapCanvasGeometry) {
        guard let onMapTap else { return }

        // タップ位置が画像エリア内かチェック
        if geometry.imageFrame.contains(location) {
            // 正規化座標を計算(0.0-1.0)
            let normalizedX = (location.x - geometry.imageFrame.origin.x) / geometry.imageFrame.width
            let normalizedY = (location.y - geometry.imageFrame.origin.y) / geometry.imageFrame.height

            // フロアマップサイズに基づいて実世界座標に変換
            // Y座標を反転して実世界座標系に合わせる
            let realWorldLocation: CGPoint
            if let floorMapInfo {
                realWorldLocation = CGPoint(
                    x: normalizedX * floorMapInfo.width,
                    y: (1.0 - normalizedY) * floorMapInfo.depth  // Y座標を反転
                )
            } else {
                // フォールバック
                realWorldLocation = CGPoint(
                    x: normalizedX * 10,
                    y: (1.0 - normalizedY) * 10  // Y座標を反転
                )
            }
            onMapTap(realWorldLocation)
        }
    }

    // 実世界座標をスクリーン座標に変換するヘルパーメソッド
    private func realWorldToScreen(realWorldPoint: Point3D, geometry: FloorMapCanvasGeometry) -> CGPoint {
        guard let floorMapInfo = geometry.floorMapInfo else {
            return CGPoint(x: 0, y: 0)
        }

        // 実世界座標を正規化座標(0.0-1.0)に変換
        let normalizedX = realWorldPoint.x / floorMapInfo.width
        let normalizedY = 1.0 - (realWorldPoint.y / floorMapInfo.depth)  // Y座標を反転

        // 正規化座標をスクリーン座標に変換
        let screenX = geometry.imageFrame.origin.x + normalizedX * geometry.imageFrame.width
        let screenY = geometry.imageFrame.origin.y + normalizedY * geometry.imageFrame.height

        return CGPoint(x: screenX, y: screenY)
    }
}

// MARK: - Grid Overlay

private struct GridOverlay: View {
    let geometry: FloorMapCanvasGeometry

    // グリッド線の間隔(メートル単位)
    private let gridInterval: Double = 1.0

    var body: some View {
        ZStack {
            // グリッド線の描画
            Canvas { context, _ in
                guard let floorMapInfo = geometry.floorMapInfo else { return }

                let imageFrame = self.geometry.imageFrame

                // グリッド線のスタイル
                let gridLineColor = Color.gray.opacity(0.3)
                let axisLineColor = Color.blue.opacity(0.5)
                let lineWidth: CGFloat = 1.0

                // 縦線(X軸方向)を描画
                var x = 0.0
                while x <= floorMapInfo.width {
                    let normalizedX = x / floorMapInfo.width
                    let screenX = imageFrame.origin.x + normalizedX * imageFrame.width

                    let path = Path { p in
                        p.move(to: CGPoint(x: screenX, y: imageFrame.origin.y))
                        p.addLine(to: CGPoint(x: screenX, y: imageFrame.origin.y + imageFrame.height))
                    }

                    // X=0の線は軸線として強調
                    let color = x == 0 ? axisLineColor : gridLineColor
                    context.stroke(path, with: .color(color), lineWidth: lineWidth)

                    x += self.gridInterval
                }

                // 横線(Y軸方向)を描画
                var y = 0.0
                while y <= floorMapInfo.depth {
                    let normalizedY = 1.0 - (y / floorMapInfo.depth)  // Y座標を反転
                    let screenY = imageFrame.origin.y + normalizedY * imageFrame.height

                    let path = Path { p in
                        p.move(to: CGPoint(x: imageFrame.origin.x, y: screenY))
                        p.addLine(to: CGPoint(x: imageFrame.origin.x + imageFrame.width, y: screenY))
                    }

                    // Y=0の線は軸線として強調
                    let color = y == 0 ? axisLineColor : gridLineColor
                    context.stroke(path, with: .color(color), lineWidth: lineWidth)

                    y += self.gridInterval
                }
            }
            .drawingGroup()  // グリッド線のみオフスクリーンレンダリングで最適化
            .allowsHitTesting(false)  // グリッド線はタッチイベントを受け取らない

            // 座標ラベルの表示
            // X軸のラベル(上部、画像フレーム内)
            ForEach(Array(stride(from: 0.0, through: self.geometry.floorMapInfo?.width ?? 0, by: self.gridInterval)), id: \.self) { x in
                let normalizedX = x / (geometry.floorMapInfo?.width ?? 1.0)
                let screenX = self.geometry.imageFrame.origin.x + normalizedX * self.geometry.imageFrame.width

                Text(String(format: "%.0f", x))
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                    .padding(2)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(2)
                    .position(
                        x: screenX,
                        y: self.geometry.imageFrame.origin.y + 12
                    )
                    .allowsHitTesting(false)  // ラベルはタッチイベントを受け取らない
            }

            // Y軸のラベル(左側、画像フレーム内)
            ForEach(Array(stride(from: 0.0, through: self.geometry.floorMapInfo?.depth ?? 0, by: self.gridInterval)), id: \.self) { y in
                let normalizedY = 1.0 - (y / (geometry.floorMapInfo?.depth ?? 1.0))
                let screenY = self.geometry.imageFrame.origin.y + normalizedY * self.geometry.imageFrame.height

                Text(String(format: "%.0f", y))
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                    .padding(2)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(2)
                    .position(
                        x: self.geometry.imageFrame.origin.x + 16,
                        y: screenY
                    )
                    .allowsHitTesting(false)  // ラベルはタッチイベントを受け取らない
            }
        }
        .allowsHitTesting(false)  // GridOverlay全体がタッチイベントを受け取らない
    }
}

// MARK: - FloorMapCanvasGeometry - キャンバスの幾何学情報

struct FloorMapCanvasGeometry {
    let canvasSize: CGSize
    let imageFrame: CGRect
    let mapScale: Double
    let floorMapInfo: FloorMapInfo?
    let currentScale: CGFloat

    // 正規化座標を実際の画像表示座標に変換
    func normalizedToImageCoordinate(_ normalizedPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: self.imageFrame.origin.x + normalizedPoint.x * self.imageFrame.width,
            y: self.imageFrame.origin.y + normalizedPoint.y * self.imageFrame.height
        )
    }

    // 実際の画像表示座標を正規化座標に変換
    func imageCoordinateToNormalized(_ imagePoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (imagePoint.x - self.imageFrame.origin.x) / self.imageFrame.width,
            y: (imagePoint.y - self.imageFrame.origin.y) / self.imageFrame.height
        )
    }

    // 実世界座標から正規化座標に変換
    func realWorldToNormalized(_ realWorldPoint: CGPoint) -> CGPoint {
        guard let floorMapInfo else {
            // フォールバック: デフォルトは28x37メートル
            let normalizedX = realWorldPoint.x / 28.0
            let normalizedY = realWorldPoint.y / 37.0
            let flippedY = 1.0 - normalizedY
            return CGPoint(x: normalizedX, y: flippedY)
        }

        // 実世界座標をフロアマップサイズに対する比率で正規化
        let normalizedX = realWorldPoint.x / floorMapInfo.width
        let normalizedY = realWorldPoint.y / floorMapInfo.depth

        // SwiftUIの座標系は上から下に向かって増加するため、Y座標を反転
        let flippedY = 1.0 - normalizedY

        return CGPoint(x: normalizedX, y: flippedY)
    }

    // 正規化座標から実世界座標に変換
    func normalizedToRealWorld(_ normalizedPoint: CGPoint) -> CGPoint {
        guard let floorMapInfo else {
            // フォールバック: デフォルトは28x37メートル
            return CGPoint(
                x: normalizedPoint.x * 28.0,
                y: (1.0 - normalizedPoint.y) * 37.0  // Y座標を反転
            )
        }

        return CGPoint(
            x: normalizedPoint.x * floorMapInfo.width,
            y: (1.0 - normalizedPoint.y) * floorMapInfo.depth  // Y座標を反転
        )
    }

    // アンテナサイズを計算（固定サイズで小さめに表示）
    func antennaSizeInPixels() -> CGFloat {
        // 固定サイズ: 15px（小さめで表示）
        15.0
    }

    // センサー範囲（50m）をピクセルに変換（実寸計算+ズーム補正）
    func sensorRangeInPixels() -> CGFloat {
        let baseCanvasSize: Double = 400.0
        let actualCanvasSize = min(canvasSize.width, self.canvasSize.height)
        let scale = Double(actualCanvasSize) / baseCanvasSize

        let rangeInPixels = CGFloat(50.0 * self.mapScale * scale)

        // currentScaleの逆数で補正して、ズームしても一定サイズを保つ
        return rangeInPixels / self.currentScale
    }
}

// MARK: - FloorMapBackground - フロアマップの背景表示

struct FloorMapBackground: View {
    let image: FloorMapImage?
    let floorMapInfo: FloorMapInfo?

    var body: some View {
        if let mapImage = image {
            #if os(macOS)
                Image(nsImage: mapImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .background(Color(NSColor.controlColor))
                    .cornerRadius(8)
            #elseif os(iOS)
                Image(uiImage: mapImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(8)
            #endif
        } else {
            RoundedRectangle(cornerRadius: 8)
            #if os(macOS)
                .fill(Color(NSColor.controlColor))
            #elseif os(iOS)
                .fill(Color(UIColor.systemGray5))
            #endif
                .overlay(
                    VStack {
                        Image(systemName: "map")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)

                        if let floorMapInfo {
                            Text(floorMapInfo.name)
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text("画像ファイルが見つかりません")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Text("フロアマップが設定されていません")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text("フロアマップタブで設定してください")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                )
        }
    }
}

// MARK: - 使用例のための型定義

#if os(macOS)
    typealias FloorMapImage = NSImage
#elseif os(iOS)
    typealias FloorMapImage = UIImage
#endif

// MARK: - View Extension for Conditional Modifiers

extension View {
    @ViewBuilder
    func `if`(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
