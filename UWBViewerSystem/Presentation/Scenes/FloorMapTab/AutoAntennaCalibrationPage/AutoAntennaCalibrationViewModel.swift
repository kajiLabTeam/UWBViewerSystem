import Combine
import Foundation
import SwiftData

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// 自動アンテナキャリブレーション画面のViewModel
@MainActor
class AutoAntennaCalibrationViewModel: ObservableObject {

    // MARK: - Published Properties

    /// 現在のステップ (0: タグ位置設定, 1: データ収集, 2: キャリブレーション実行)
    @Published var currentStep: Int = 0

    /// タグの真の位置（既知の座標）
    @Published var trueTagPositions: [TagPosition] = []

    /// 選択可能なアンテナリスト
    @Published var availableAntennas: [AntennaInfo] = []

    /// キャリブレーション対象として選択されたアンテナID
    @Published var selectedAntennaIds: Set<String> = []

    /// データ収集の進行状況
    @Published var collectionProgress: Double = 0.0

    /// データ収集中かどうか
    @Published var isCollecting: Bool = false

    /// キャリブレーション実行中かどうか
    @Published var isCalibrating: Bool = false

    /// キャリブレーション結果
    @Published var calibrationResults: [String: CalibrationResult] = [:]

    /// エラーメッセージ
    @Published var errorMessage: String = ""

    /// エラーアラート表示フラグ
    @Published var showErrorAlert: Bool = false

    /// 成功アラート表示フラグ
    @Published var showSuccessAlert: Bool = false

    /// 現在のフロアマップ情報
    @Published var currentFloorMapInfo: FloorMapInfo?

    /// フロアマップ画像
    #if canImport(UIKit)
        #if os(iOS)
            @Published var floorMapImage: UIImage?
        #elseif os(macOS)
            @Published var floorMapImage: NSImage?
        #endif
    #elseif canImport(AppKit)
        @Published var floorMapImage: NSImage?
    #endif

    /// リアルタイムデータ統計
    @Published var dataStatistics: [String: [String: Int]] = [:]

    // MARK: - Dependencies

    private var autoCalibrationUsecase: AutoAntennaCalibrationUsecase?
    private var observationUsecase: ObservationDataUsecase?
    private var swiftDataRepository: SwiftDataRepository?
    private var sensingControlUsecase: SensingControlUsecase?
    private var modelContext: ModelContext?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    var currentStepTitle: String {
        switch self.currentStep {
        case 0: return "タグ位置設定"
        case 1: return "データ収集"
        case 2: return "キャリブレーション実行"
        default: return ""
        }
    }

    var canProceedToNext: Bool {
        switch self.currentStep {
        case 0: return self.trueTagPositions.count >= 3
        case 1: return !self.isCollecting && self.collectionProgress >= 1.0
        case 2: return false // 最終ステップ
        default: return false
        }
    }

    var canGoBack: Bool {
        self.currentStep > 0 && !self.isCollecting && !self.isCalibrating
    }

    var canStartCollection: Bool {
        !self.selectedAntennaIds.isEmpty && self.trueTagPositions.count >= 3 && !self.isCollecting
    }

    var canStartCalibration: Bool {
        !self.isCollecting && self.collectionProgress >= 1.0 && !self.calibrationResults.isEmpty == false
    }

    // MARK: - Types

    struct TagPosition: Identifiable {
        let id: UUID
        var tagId: String
        var position: Point3D
        var isCollected: Bool = false
    }

    struct AntennaInfo: Identifiable {
        let id: String
        let name: String
        var isSelected: Bool
    }

    struct CalibrationResult {
        let antennaId: String
        let position: Point3D
        let angleDegrees: Double
        let rmse: Double
        let scaleFactors: (sx: Double, sy: Double)
    }

    // MARK: - Initialization

    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
        let swiftDataRepo = SwiftDataRepository(modelContext: modelContext)
        self.swiftDataRepository = swiftDataRepo

        // 依存関係の初期化
        let dataRepository = DataRepository()
        let uwbManager = UWBDataManager()
        let preferenceRepository = PreferenceRepository()

        let observationUsecase = ObservationDataUsecase(
            dataRepository: dataRepository,
            uwbManager: uwbManager,
            preferenceRepository: preferenceRepository
        )
        self.observationUsecase = observationUsecase

        self.autoCalibrationUsecase = AutoAntennaCalibrationUsecase(
            swiftDataRepository: swiftDataRepo,
            observationUsecase: observationUsecase
        )

        let connectionUsecase = ConnectionManagementUsecase.shared
        self.sensingControlUsecase = SensingControlUsecase(
            connectionUsecase: connectionUsecase,
            swiftDataRepository: swiftDataRepo
        )

        self.loadInitialData()
    }

    // MARK: - Public Methods

    func loadInitialData() {
        Task {
            await self.loadFloorMapInfo()
            await self.loadAvailableAntennas()
        }
    }

    func addTagPosition(at point: Point3D) {
        let newTag = TagPosition(
            id: UUID(),
            tagId: "Tag\(trueTagPositions.count + 1)",
            position: point
        )
        self.trueTagPositions.append(newTag)
        print("📍 タグ位置追加: \(newTag.tagId) at (\(point.x), \(point.y))")
    }

    func removeTagPosition(at index: Int) {
        guard index < self.trueTagPositions.count else { return }
        self.trueTagPositions.remove(at: index)
    }

    func clearTagPositions() {
        self.trueTagPositions.removeAll()
    }

    func toggleAntennaSelection(_ antennaId: String) {
        if self.selectedAntennaIds.contains(antennaId) {
            self.selectedAntennaIds.remove(antennaId)
        } else {
            self.selectedAntennaIds.insert(antennaId)
        }
        self.updateAntennaList()
    }

    func selectAllAntennas() {
        self.selectedAntennaIds = Set(self.availableAntennas.map { $0.id })
        self.updateAntennaList()
    }

    func deselectAllAntennas() {
        self.selectedAntennaIds.removeAll()
        self.updateAntennaList()
    }

    func proceedToNext() {
        guard self.canProceedToNext else { return }
        self.currentStep += 1

        if self.currentStep == 1 {
            // データ収集ステップに進んだら、真のタグ位置をUsecaseに設定
            Task {
                await self.setTruePositionsInUsecase()
            }
        }
    }

    func goBack() {
        guard self.canGoBack else { return }
        self.currentStep -= 1
    }

    func startDataCollection() {
        guard self.canStartCollection else { return }

        self.isCollecting = true
        self.collectionProgress = 0.0

        Task {
            await self.performDataCollection()
        }
    }

    func startCalibration() {
        guard self.canStartCalibration else { return }

        self.isCalibrating = true

        Task {
            await self.performCalibration()
        }
    }

    func resetCalibration() {
        self.currentStep = 0
        self.trueTagPositions.removeAll()
        self.selectedAntennaIds.removeAll()
        self.calibrationResults.removeAll()
        self.collectionProgress = 0.0
        self.errorMessage = ""

        Task {
            guard let usecase = autoCalibrationUsecase else { return }
            await usecase.clearData()
        }
    }

    // MARK: - Private Methods

    private func loadFloorMapInfo() async {
        guard let repository = swiftDataRepository else { return }

        do {
            let floorMaps = try await repository.loadAllFloorMaps()
            if let floorMap = floorMaps.first {
                self.currentFloorMapInfo = floorMap

                // Note: FloorMapInfoにはimageDataプロパティがないため、
                // 必要に応じて別途画像読み込みロジックを実装
            }
        } catch {
            self.showError("フロアマップの読み込みに失敗しました: \(error.localizedDescription)")
        }
    }

    private func loadAvailableAntennas() async {
        guard let repository = swiftDataRepository else { return }

        do {
            // まず接続済みデバイスを取得
            let pairings = try await repository.loadAntennaPairings()
            let connectedDevices = pairings.filter { $0.device.isConnected }

            self.availableAntennas = connectedDevices.map { pairing in
                AntennaInfo(
                    id: pairing.device.id,
                    name: pairing.antenna.name,
                    isSelected: self.selectedAntennaIds.contains(pairing.device.id)
                )
            }

            print("📡 利用可能なアンテナ: \(self.availableAntennas.count)個")
        } catch {
            self.showError("アンテナリストの読み込みに失敗しました: \(error.localizedDescription)")
        }
    }

    private func updateAntennaList() {
        self.availableAntennas = self.availableAntennas.map { antenna in
            AntennaInfo(
                id: antenna.id,
                name: antenna.name,
                isSelected: self.selectedAntennaIds.contains(antenna.id)
            )
        }
    }

    private func setTruePositionsInUsecase() async {
        guard let usecase = autoCalibrationUsecase else { return }

        let positions = Dictionary(
            uniqueKeysWithValues: trueTagPositions.map { ($0.tagId, $0.position) }
        )

        await usecase.setTrueTagPositions(positions)
    }

    private func performDataCollection() async {
        guard let usecase = autoCalibrationUsecase,
              let sensingControl = sensingControlUsecase,
              let floorMapId = currentFloorMapInfo?.id
        else {
            self.showError("初期化が完了していません")
            self.isCollecting = false
            return
        }

        let totalSteps = self.trueTagPositions.count
        var completedSteps = 0

        for i in 0..<self.trueTagPositions.count {
            let tagPos = self.trueTagPositions[i]

            print("📍 \(tagPos.tagId) のデータ収集開始")

            // センシングセッションを開始
            let sessionId = UUID().uuidString

            do {
                // センシング開始コマンドを送信
                sensingControl.startRemoteSensing(fileName: "calibration_\(tagPos.tagId)")

                // 10秒間データ収集
                try await Task.sleep(nanoseconds: 10_000_000_000)

                // センシング停止
                sensingControl.stopRemoteSensing()

                // データを収集
                try await usecase.collectDataFromSession(
                    sessionId: sessionId,
                    tagId: tagPos.tagId
                )

                // 進行状況を更新
                completedSteps += 1
                self.collectionProgress = Double(completedSteps) / Double(totalSteps)

                // タグの収集状態を更新
                self.trueTagPositions[i].isCollected = true

                print("✅ \(tagPos.tagId) のデータ収集完了")

            } catch {
                self.showError("\(tagPos.tagId) のデータ収集に失敗しました: \(error.localizedDescription)")
            }

            // 次のタグまで少し待機
            if i < self.trueTagPositions.count - 1 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }

        self.isCollecting = false

        // データ統計を更新
        await self.updateDataStatistics()

        print("🎉 全タグのデータ収集完了")
    }

    private func performCalibration() async {
        guard let usecase = autoCalibrationUsecase,
              let floorMapId = currentFloorMapInfo?.id
        else {
            self.showError("初期化が完了していません")
            self.isCalibrating = false
            return
        }

        do {
            // キャリブレーション実行
            let results = try await usecase.executeAutoCalibration(
                for: Array(self.selectedAntennaIds),
                minObservationsPerTag: 5
            )

            // 結果をViewModelに保存
            self.calibrationResults = results.mapValues { config in
                CalibrationResult(
                    antennaId: "",
                    position: config.position,
                    angleDegrees: config.angleDegrees,
                    rmse: config.rmse,
                    scaleFactors: config.scaleFactors
                )
            }

            // SwiftDataに保存
            try await usecase.saveCalibrationResults(
                floorMapId: floorMapId,
                results: results
            )

            self.isCalibrating = false
            self.showSuccessAlert = true

            print("🎉 キャリブレーション完了")

        } catch {
            self.isCalibrating = false
            self.showError("キャリブレーションに失敗しました: \(error.localizedDescription)")
        }
    }

    private func updateDataStatistics() async {
        guard let usecase = autoCalibrationUsecase else { return }
        self.dataStatistics = await usecase.getDataStatistics()
    }

    private func showError(_ message: String) {
        self.errorMessage = message
        self.showErrorAlert = true
        print("❌ エラー: \(message)")
    }
}
