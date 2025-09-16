import SwiftData
import SwiftUI

// MARK: - FloorMapCanvas - 共通のフロアマップ表示コンポーネント

struct FloorMapCanvas<Content: View>: View {
    let floorMapImage: FloorMapImage?
    let floorMapInfo: FloorMapInfo?
    let onMapTap: ((CGPoint) -> Void)?
    @ViewBuilder let content: (FloorMapCanvasGeometry) -> Content

    @State private var canvasSize: CGSize = CGSize(width: 400, height: 300)

    // フロアマップのスケールを計算（ピクセル/メートル）
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
            // 画像の方が縦長（または同じ） → 縦幅がフィット
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
            let imageAspectRatio = floorMapInfo?.aspectRatio ?? 1.0
            let actualImageFrame = calculateActualImageFrame(canvasSize: currentCanvasSize, imageAspectRatio: imageAspectRatio)

            let canvasGeometry = FloorMapCanvasGeometry(
                canvasSize: currentCanvasSize,
                imageFrame: actualImageFrame,
                mapScale: mapScale,
                floorMapInfo: floorMapInfo
            )

            ZStack {
                // マップ背景
                FloorMapBackground(image: floorMapImage, floorMapInfo: floorMapInfo)
                    .allowsHitTesting(false)

                // タップ領域（背景層）
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        handleMapTap(location: location, geometry: canvasGeometry)
                    }

                // コンテンツ（アンテナ、基準点など）- 最前面
                content(canvasGeometry)
            }
            .onAppear {
                canvasSize = currentCanvasSize
            }
            .onChange(of: geometry.size) { _, newSize in
                canvasSize = newSize
            }
        }
        .frame(height: 300)
        .cornerRadius(12)
    }

    private func handleMapTap(location: CGPoint, geometry: FloorMapCanvasGeometry) {
        guard let onMapTap else { return }

        // タップ位置が画像エリア内かチェック
        if geometry.imageFrame.contains(location) {
            // 正規化座標を計算（0.0-1.0）
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
}

// MARK: - FloorMapCanvasGeometry - キャンバスの幾何学情報

struct FloorMapCanvasGeometry {
    let canvasSize: CGSize
    let imageFrame: CGRect
    let mapScale: Double
    let floorMapInfo: FloorMapInfo?

    // 正規化座標を実際の画像表示座標に変換
    func normalizedToImageCoordinate(_ normalizedPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: imageFrame.origin.x + normalizedPoint.x * imageFrame.width,
            y: imageFrame.origin.y + normalizedPoint.y * imageFrame.height
        )
    }

    // 実際の画像表示座標を正規化座標に変換
    func imageCoordinateToNormalized(_ imagePoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (imagePoint.x - imageFrame.origin.x) / imageFrame.width,
            y: (imagePoint.y - imageFrame.origin.y) / imageFrame.height
        )
    }

    // 実世界座標から正規化座標に変換
    func realWorldToNormalized(_ realWorldPoint: CGPoint) -> CGPoint {
        guard let floorMapInfo else {
            // フォールバック: 実世界座標をスケール変換してピクセル座標に変換後、正規化
            let pixelX = realWorldPoint.x * 100.0  // デフォルトスケール 100px/m
            let pixelY = realWorldPoint.y * 100.0
            return CGPoint(
                x: pixelX / canvasSize.width,
                y: pixelY / canvasSize.height
            )
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
            // フォールバック
            return CGPoint(
                x: normalizedPoint.x * 10,
                y: (1.0 - normalizedPoint.y) * 10  // Y座標を反転
            )
        }

        return CGPoint(
            x: normalizedPoint.x * floorMapInfo.width,
            y: (1.0 - normalizedPoint.y) * floorMapInfo.depth  // Y座標を反転
        )
    }

    // アンテナサイズを計算（30cmの実寸サイズ）
    func antennaSizeInPixels() -> CGFloat {
        let baseCanvasSize: Double = 400.0
        let actualCanvasSize = min(canvasSize.width, canvasSize.height)
        let scale = Double(actualCanvasSize) / baseCanvasSize

        let sizeInPixels = CGFloat(0.30 * mapScale * scale) // 0.30m = 30cm
        return max(min(sizeInPixels, 80), 20) // 最小20px、最大80px
    }

    // センサー範囲（50m）をピクセルに変換
    func sensorRangeInPixels() -> CGFloat {
        let baseCanvasSize: Double = 400.0
        let actualCanvasSize = min(canvasSize.width, canvasSize.height)
        let scale = Double(actualCanvasSize) / baseCanvasSize

        return CGFloat(50.0 * mapScale * scale)
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