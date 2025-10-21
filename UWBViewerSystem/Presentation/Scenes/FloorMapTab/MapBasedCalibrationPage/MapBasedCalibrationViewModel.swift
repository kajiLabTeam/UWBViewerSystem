import Foundation
import SwiftUI

/// マップベースキャリブレーション画面のViewModel
@MainActor
class MapBasedCalibrationViewModel: ObservableObject {

    // MARK: - 公開プロパティ

    #if os(iOS)
        @Published var floorMapImage: UIImage?
    #else
        @Published var floorMapImage: NSImage?
    #endif
    @Published var calibrationPoints: [MapCalibrationPoint] = []
    @Published var currentPointIndex: Int = 0

    @Published var inputX: String = ""
    @Published var inputY: String = ""
    @Published var inputZ: String = ""

    @Published var showError: Bool = false
    @Published var showSuccess: Bool = false
    @Published var isCalculating: Bool = false
    @Published var showPreviewMarker: Bool = false
    @Published var previewLocation: CGPoint?

    @Published var errorMessage: String = ""
    @Published var calibrationAccuracy: Double?

    // MARK: - プライベートプロパティ

    private let antennaId: String
    private let floorMapId: String
    private var currentCalibrationData: MapCalibrationData?
    private var pendingMapLocation: CGPoint?

    // 依存関係
    private let dataRepository: SwiftDataRepositoryProtocol

    // MARK: - 計算プロパティ

    var instructionText: String {
        if currentPointIndex < 3 {
            return "基準座標 \(currentPointIndex + 1) を設定してください。\nマップ上をタップして位置を選択し、実世界座標を入力してください。"
        } else {
            return "3つの基準座標が設定されました。アフィン変換を実行してキャリブレーションを完了してください。"
        }
    }

    var canComplete: Bool {
        calibrationPoints.count >= 3 && currentCalibrationData?.affineTransform != nil
    }

    // MARK: - 初期化

    init(antennaId: String, floorMapId: String, dataRepository: SwiftDataRepositoryProtocol? = nil) {
        self.antennaId = antennaId
        self.floorMapId = floorMapId
        self.dataRepository = dataRepository ?? DummySwiftDataRepository()

        loadExistingCalibrationData()
    }

    // MARK: - 公開メソッド

    /// フロアマップ画像を読み込む
    func loadFloorMapImage() {
        Task {
            await loadFloorMapImageAsync()
        }
    }

    /// マップのタップを処理
    func handleMapTap(at location: CGPoint) {
        guard currentPointIndex < 3 else { return }

        pendingMapLocation = location
        showPreviewMarker = true
        previewLocation = location

        // 入力フィールドにフォーカス
        clearInputFields()
    }

    /// キャリブレーション点を追加
    func addCalibrationPoint() {
        guard let mapLocation = pendingMapLocation,
              let realX = Double(inputX),
              let realY = Double(inputY),
              let realZ = Double(inputZ)
        else {
            showErrorMessage("座標値を正しく入力してください")
            return
        }

        let mapCoordinate = Point3D(x: Double(mapLocation.x), y: Double(mapLocation.y), z: 0.0)
        let realWorldCoordinate = Point3D(x: realX, y: realY, z: realZ)

        let calibrationPoint = MapCalibrationPoint(
            mapCoordinate: mapCoordinate,
            realWorldCoordinate: realWorldCoordinate,
            antennaId: antennaId,
            pointIndex: currentPointIndex + 1
        )

        calibrationPoints.append(calibrationPoint)
        currentPointIndex += 1

        // UIリセット
        clearInputFields()
        pendingMapLocation = nil
        showPreviewMarker = false
        previewLocation = nil
    }

    /// キャリブレーション点を削除
    func removeCalibrationPoint(_ point: MapCalibrationPoint) {
        calibrationPoints.removeAll { $0.id == point.id }

        // インデックスを再調整
        recalculatePointIndices()
    }

    /// すべての点をクリア
    func clearAllPoints() {
        calibrationPoints.removeAll()
        currentPointIndex = 0
        clearInputFields()
        pendingMapLocation = nil
        showPreviewMarker = false
        previewLocation = nil
        calibrationAccuracy = nil
    }

    /// キャリブレーション実行
    func performCalibration() async {
        guard calibrationPoints.count >= 3 else {
            showErrorMessage("3つの基準座標が必要です")
            return
        }

        isCalculating = true
        defer { isCalculating = false }

        do {
            // アフィン変換行列を計算
            let affineTransform = try AffineTransform.calculateAffineTransform(from: calibrationPoints)

            // キャリブレーションデータを更新
            let calibrationData = MapCalibrationData(
                antennaId: antennaId,
                floorMapId: floorMapId,
                calibrationPoints: calibrationPoints,
                affineTransform: affineTransform
            )

            currentCalibrationData = calibrationData
            calibrationAccuracy = affineTransform.accuracy

            showSuccess = true

        } catch {
            showErrorMessage("キャリブレーション計算に失敗しました: \(error.localizedDescription)")
        }
    }

    /// キャリブレーション結果を保存
    func saveCalibration() async {
        guard let calibrationData = currentCalibrationData else {
            showErrorMessage("保存するキャリブレーションデータがありません")
            return
        }

        do {
            // データベースに保存
            try await saveMapCalibrationData(calibrationData)
        } catch {
            showErrorMessage("キャリブレーションデータの保存に失敗しました: \(error.localizedDescription)")
        }
    }

    // MARK: - 画像計算メソッド

    /// 画像サイズを計算
    func calculateImageSize(for containerSize: CGSize) -> CGSize {
        guard let image = floorMapImage else { return .zero }

        let imageAspectRatio = image.size.width / image.size.height
        let containerAspectRatio = containerSize.width / containerSize.height

        if imageAspectRatio > containerAspectRatio {
            // 画像の方が横長
            let width = containerSize.width
            let height = width / imageAspectRatio
            return CGSize(width: width, height: height)
        } else {
            // コンテナの方が横長、または同じ
            let height = containerSize.height
            let width = height * imageAspectRatio
            return CGSize(width: width, height: height)
        }
    }

    /// 画像オフセットを計算
    func calculateImageOffset(for containerSize: CGSize, imageSize: CGSize) -> CGSize {
        let offsetX = (containerSize.width - imageSize.width) / 2
        let offsetY = (containerSize.height - imageSize.height) / 2
        return CGSize(width: offsetX, height: offsetY)
    }

    /// タップ位置を画像座標系に変換
    func convertTapToImageCoordinates(
        tapLocation: CGPoint,
        containerSize: CGSize,
        imageSize: CGSize,
        imageOffset: CGSize
    ) -> CGPoint? {
        // タップ位置が画像内にあるかチェック
        let imageRect = CGRect(
            x: imageOffset.width,
            y: imageOffset.height,
            width: imageSize.width,
            height: imageSize.height
        )

        guard imageRect.contains(tapLocation) else { return nil }

        // 画像内での相対位置を計算
        let relativeX = tapLocation.x - imageOffset.width
        let relativeY = tapLocation.y - imageOffset.height

        // 画像座標系（ピクセル）に変換
        guard let image = floorMapImage else { return nil }
        let imageX = (relativeX / imageSize.width) * image.size.width
        let imageY = (relativeY / imageSize.height) * image.size.height

        return CGPoint(x: imageX, y: imageY)
    }

    // MARK: - プライベートメソッド

    /// フロアマップ画像を非同期で読み込む
    private func loadFloorMapImageAsync() async {
        // UserDefaultsからFloorMapInfoを取得
        guard let data = UserDefaults.standard.data(forKey: "currentFloorMapInfo"),
              let floorMapInfo = try? JSONDecoder().decode(FloorMapInfo.self, from: data),
              floorMapInfo.id == floorMapId
        else {
            print("❌ MapBasedCalibrationViewModel: FloorMapInfo not found for ID: \(floorMapId)")
            return
        }

        // フロアマップ画像を読み込む
        if let image = floorMapInfo.image {
            await MainActor.run {
                self.floorMapImage = image
                print("✅ フロアマップ画像読み込み完了: \(image.size)")
            }
        } else {
            print("❌ MapBasedCalibrationViewModel: FloorMap image not found")
        }
    }

    /// 既存のキャリブレーションデータを読み込む
    private func loadExistingCalibrationData() {
        // 既存のデータがあれば読み込む
        // 今回は新規作成のため実装を省略
    }

    /// 入力フィールドをクリア
    private func clearInputFields() {
        inputX = ""
        inputY = ""
        inputZ = ""
    }

    /// ポイントインデックスを再計算
    private func recalculatePointIndices() {
        for (index, _) in calibrationPoints.enumerated() {
            calibrationPoints[index] = MapCalibrationPoint(
                id: calibrationPoints[index].id,
                mapCoordinate: calibrationPoints[index].mapCoordinate,
                realWorldCoordinate: calibrationPoints[index].realWorldCoordinate,
                antennaId: calibrationPoints[index].antennaId,
                timestamp: calibrationPoints[index].timestamp,
                pointIndex: index + 1
            )
        }
        currentPointIndex = calibrationPoints.count
    }

    /// エラーメッセージを表示
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }

    /// マップキャリブレーションデータを保存
    private func saveMapCalibrationData(_ data: MapCalibrationData) async throws {
        try await dataRepository.saveMapCalibrationData(data)
        print("🗄️ MapCalibrationData saved for antenna: \(data.antennaId)")
        print("   FloorMapId: \(data.floorMapId)")
        print("   Calibration Points: \(data.calibrationPoints.count)")
        print("   Affine Transform: \(data.affineTransform?.matrixDescription ?? "None")")
    }
}

// MARK: - 入力処理拡張

extension MapBasedCalibrationViewModel {
    /// キーボード入力完了時の処理
    func handleInputCompletion() {
        guard pendingMapLocation != nil,
              !inputX.isEmpty && !inputY.isEmpty && !inputZ.isEmpty
        else {
            return
        }
        addCalibrationPoint()
    }
}
