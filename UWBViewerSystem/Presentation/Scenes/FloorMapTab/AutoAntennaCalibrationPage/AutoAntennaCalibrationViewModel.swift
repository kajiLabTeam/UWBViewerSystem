import Combine
import Foundation
import SwiftData

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// アンテナ別信号品質表示用データ
struct SignalQualityDisplay: Equatable {
    let averageRSSI: Double
    let losPercentage: Double
    let averageStrength: Double
    let dataPointCount: Int

    /// 品質レベル（0: 悪い, 1: 普通, 2: 良い）
    var qualityLevel: Int {
        if self.averageStrength >= 0.7 && self.losPercentage >= 70 {
            return 2  // 良い
        } else if self.averageStrength >= 0.4 && self.losPercentage >= 40 {
            return 1  // 普通
        } else {
            return 0  // 悪い
        }
    }
}

/// 自動アンテナキャリブレーション画面のViewModel
@MainActor
class AutoAntennaCalibrationViewModel: ObservableObject {

    // MARK: - Published Properties

    /// 現在のステップ (0: アンテナ選択, 1: タグ位置設定, 2: データ収集, 3: キャリブレーション結果表示)
    @Published var currentStep: Int = 0

    /// 現在処理中のアンテナID
    @Published var currentAntennaId: String?

    /// 完了したアンテナIDのセット
    @Published var completedAntennaIds: Set<String> = []

    /// タグの真の位置（既知の座標）
    @Published var trueTagPositions: [TagPosition] = []

    /// 選択可能なアンテナリスト
    @Published var availableAntennas: [AntennaInfo] = []

    /// データ収集の進行状況
    @Published var collectionProgress: Double = 0.0

    /// データ収集中かどうか
    @Published var isCollecting: Bool = false

    /// 現在測定中のタグ位置インデックス
    @Published var currentTagPositionIndex: Int = 0

    /// キャリブレーション実行中かどうか
    @Published var isCalibrating: Bool = false

    /// 現在のアンテナのキャリブレーション結果
    @Published var currentAntennaResult: CalibrationResult?

    /// 全アンテナのキャリブレーション結果（履歴）
    @Published var calibrationResults: [String: CalibrationResult] = [:]

    /// 接続エラー表示フラグ
    @Published var showConnectionRecovery: Bool = false

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

    /// 現在のセンシング中のデータポイント（マップ表示用）
    @Published var currentSensingDataPoints: [Point3D] = []

    /// すべてのアンテナ位置（マップ常時表示用）
    @Published var allAntennaPositions: [AntennaPositionData] = []

    /// キャリブレーション前の現在のアンテナ位置
    @Published var originalAntennaPosition: AntennaPositionData?

    // MARK: - Real-time Feedback Properties

    /// センシング経過時間（秒）
    @Published var sensingElapsedTime: Double = 0.0

    /// 現在のデータポイント数
    @Published var currentDataPointCount: Int = 0

    /// リアルタイムRMSE推定値（計算可能な場合）
    @Published var currentRMSEEstimate: Double?

    /// アンテナ別信号品質情報
    @Published var signalQualityByAntenna: [String: SignalQualityDisplay] = [:]

    /// センシング中に(0,0)付近のデータが検出された数
    @Published var suspiciousZeroDataCount: Int = 0

    /// センシング時間（秒）
    let sensingDuration: Double = 10.0

    /// センシング中に(0,0)付近の疑わしいデータが検出されているかどうか
    var hasSuspiciousDataDuringSensing: Bool {
        suspiciousZeroDataCount > 0
    }

    /// センシング中のデータ品質警告メッセージ
    var sensingDataWarningMessage: String? {
        guard hasSuspiciousDataDuringSensing else { return nil }
        return "(0,0)付近のデータが\(suspiciousZeroDataCount)件検出されました。センサーの接続状態を確認してください。"
    }

    // MARK: - Dependencies

    private var autoCalibrationUsecase: AutoAntennaCalibrationUsecase?
    private var observationUsecase: ObservationDataUsecase?
    private var realtimeDataUsecase: RealtimeDataUsecase?
    private var swiftDataRepository: SwiftDataRepository?
    private var sensingControlUsecase: SensingControlUsecase?
    private var modelContext: ModelContext?
    private weak var flowNavigator: SensingFlowNavigator?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    var currentStepTitle: String {
        switch self.currentStep {
        case 0: return "アンテナ選択"
        case 1: return "タグ位置設定"
        case 2: return "データ収集"
        case 3: return "キャリブレーション結果"
        default: return ""
        }
    }

    var canProceedToNext: Bool {
        switch self.currentStep {
        case 0: return self.currentAntennaId != nil
        case 1: return self.trueTagPositions.count >= 3
        case 2: return !self.isCollecting && self.collectionProgress >= 1.0
        case 3: return false // 結果表示ステップ（次のアンテナへ進むか完了）
        default: return false
        }
    }

    var canGoBack: Bool {
        self.currentStep > 0 && !self.isCollecting && !self.isCalibrating
    }

    var canStartCollection: Bool {
        self.currentAntennaId != nil &&
            self.currentTagPositionIndex < self.trueTagPositions.count &&
            !self.isCollecting
    }

    var canStartCalibration: Bool {
        !self.isCollecting && self.allTagPositionsCollected
    }

    var canGoToPreviousTag: Bool {
        // データ収集ステップで、完了済みのタグが1つ以上ある場合に戻れる
        self.currentStep == 2 &&
            !self.isCollecting &&
            !self.isCalibrating &&
            self.trueTagPositions.contains(where: { $0.isCollected })
    }

    var hasMoreAntennas: Bool {
        let uncalibratedAntennas = self.availableAntennas.filter { !self.completedAntennaIds.contains($0.id) }
        return !uncalibratedAntennas.isEmpty
    }

    var currentAntennaName: String {
        guard let currentId = self.currentAntennaId else { return "" }
        return self.availableAntennas.first { $0.id == currentId }?.name ?? currentId
    }

    var currentTagPosition: TagPosition? {
        guard self.currentTagPositionIndex < self.trueTagPositions.count else { return nil }
        return self.trueTagPositions[self.currentTagPositionIndex]
    }

    var hasMoreTagPositions: Bool {
        self.currentTagPositionIndex < self.trueTagPositions.count - 1
    }

    var allTagPositionsCollected: Bool {
        self.trueTagPositions.allSatisfy { $0.isCollected }
    }

    /// キャリブレーション結果が問題のある状態かどうかを判定
    /// (0, 0) 付近の位置は明らかに異常な結果
    var hasCalibrationWarning: Bool {
        guard let result = currentAntennaResult else { return false }
        return isPositionSuspicious(result.position)
    }

    /// キャリブレーション結果の警告メッセージ
    var calibrationWarningMessage: String? {
        guard let result = currentAntennaResult else { return nil }

        var warnings: [String] = []

        // 位置が (0, 0) 付近の場合
        if isPositionSuspicious(result.position) {
            warnings.append("推定位置が原点(0,0)付近です。データ収集に問題がある可能性があります。")
        }

        // RMSEが異常に高い場合
        if result.rmse > 1.0 {
            warnings.append("RMSE値が高すぎます。測定データの品質を確認してください。")
        }

        // スケールファクターが異常な場合
        if result.scaleFactors.sx < 0.1 || result.scaleFactors.sx > 10.0 ||
            result.scaleFactors.sy < 0.1 || result.scaleFactors.sy > 10.0
        {
            warnings.append("スケールファクターが異常です。キャリブレーションデータに問題がある可能性があります。")
        }

        return warnings.isEmpty ? nil : warnings.joined(separator: "\n")
    }

    /// 位置が疑わしい（原点付近）かどうかを判定
    private func isPositionSuspicious(_ position: Point3D) -> Bool {
        let threshold: Double = 0.01  // 1cm以内は (0, 0) とみなす
        return abs(position.x) < threshold && abs(position.y) < threshold
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

        // RealtimeDataUsecaseを初期化してConnectionUsecaseに設定
        let realtimeUsecase = RealtimeDataUsecase(
            swiftDataRepository: swiftDataRepo,
            sensingControlUsecase: self.sensingControlUsecase
        )
        self.realtimeDataUsecase = realtimeUsecase
        connectionUsecase.setRealtimeDataUsecase(realtimeUsecase)

        // 接続監視を設定
        self.setupConnectionMonitoring()

        self.loadInitialData()
    }

    /// SensingFlowNavigatorを設定
    func setFlowNavigator(_ navigator: SensingFlowNavigator) {
        self.flowNavigator = navigator
    }

    /// 接続監視を設定
    private func setupConnectionMonitoring() {
        // hasConnectionErrorの変更を監視
        ConnectionManagementUsecase.shared.$hasConnectionError
            .sink { [weak self] hasError in
                guard let self else { return }
                if hasError {
                    print("⚠️ 接続断検出: 接続復旧画面を表示します")
                    self.handleConnectionError()
                }
            }
            .store(in: &self.cancellables)

        // 接続デバイス数の変更を監視してアンテナリストを更新
        ConnectionManagementUsecase.shared.$connectedDeviceNames
            .sink { [weak self] _ in
                guard let self else { return }
                Task {
                    print("🔌 接続デバイスの変更を検出: アンテナリストを再読み込みします")
                    await self.loadAvailableAntennas()
                }
            }
            .store(in: &self.cancellables)
    }

    /// 接続エラーハンドリング
    private func handleConnectionError() {
        // データ収集中・キャリブレーション中の場合は停止
        if self.isCollecting || self.isCalibrating {
            print("⚠️ データ収集/キャリブレーションを中断します")
            self.isCollecting = false
            self.isCalibrating = false
        }

        // エラーメッセージを設定
        if let deviceName = ConnectionManagementUsecase.shared.lastDisconnectedDevice {
            self.errorMessage = "デバイス「\(deviceName)」との接続が切断されました"
        } else {
            self.errorMessage = "接続が切断されました"
        }

        // 接続復旧画面を表示
        self.showConnectionRecovery = true
    }

    // MARK: - Public Methods

    func loadInitialData() {
        Task {
            await self.loadFloorMapInfo()
            await self.loadAvailableAntennas()
        }
    }

    /// 指定されたフロアマップ情報を読み込み
    func loadFloorMapInfo(floorMapId: String) {
        Task {
            await self.loadFloorMapInfoById(floorMapId: floorMapId)
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

    func selectAntennaForCalibration(_ antennaId: String) {
        guard self.currentStep == 0 else { return }
        self.currentAntennaId = antennaId

        // キャリブレーション前のアンテナ位置を保存
        self.originalAntennaPosition = self.allAntennaPositions.first { $0.antennaId == antennaId }

        print("📡 アンテナ選択: \(self.currentAntennaName) (ID: \(antennaId))")
        if let original = originalAntennaPosition {
            print("   現在位置: (\(original.position.x), \(original.position.y)), 角度: \(original.rotation)°")
        }
    }

    func proceedToNext() {
        guard self.canProceedToNext else { return }
        self.currentStep += 1

        if self.currentStep == 2 {
            // データ収集ステップに進んだら、真のタグ位置をUsecaseに設定
            Task {
                await self.setTruePositionsInUsecase()
            }
        }
    }

    func goBack() {
        guard self.canGoBack else { return }
        self.currentStep -= 1

        // ステップ0（アンテナ選択）に戻る場合、タグ位置とデータをクリア
        if self.currentStep == 0 {
            self.trueTagPositions.removeAll()
            self.collectionProgress = 0.0
            self.currentTagPositionIndex = 0
            Task {
                guard let usecase = autoCalibrationUsecase,
                      let antennaId = self.currentAntennaId else { return }
                await usecase.clearData(for: antennaId)
            }
        }
    }

    func startCurrentTagPositionCollection() {
        guard self.canStartCollection else { return }
        guard self.currentTagPositionIndex < self.trueTagPositions.count else { return }

        self.isCollecting = true

        Task {
            await self.performCurrentTagPositionCollection()
        }
    }

    func proceedToNextTagPosition() {
        guard self.currentTagPositionIndex < self.trueTagPositions.count - 1 else { return }
        self.currentTagPositionIndex += 1
        print("➡️  次のタグ位置へ: \(self.trueTagPositions[self.currentTagPositionIndex].tagId)")
    }

    /// 前のタグ位置に戻る（最後に完了したタグのデータを取り消してそのタグからやり直す）
    func goToPreviousTagPosition() {
        guard self.canGoToPreviousTag else { return }

        // 最後に完了したタグを見つける（後ろから探す）
        guard let lastCompletedIndex = self.trueTagPositions.indices.reversed().first(where: { index in
            self.trueTagPositions[index].isCollected
        }) else {
            print("⚠️  完了済みのタグが見つかりません")
            return
        }

        let tagToUndo = self.trueTagPositions[lastCompletedIndex]

        Task {
            guard let usecase = autoCalibrationUsecase,
                  let antennaId = currentAntennaId
            else { return }

            // 最後に完了したタグのデータをクリア
            await usecase.clearData(for: antennaId, tagId: tagToUndo.tagId)

            // そのタグの収集状態をリセット
            self.trueTagPositions[lastCompletedIndex].isCollected = false

            // インデックスをそのタグに戻す
            self.currentTagPositionIndex = lastCompletedIndex

            // 進行状況を更新
            let completedCount = self.trueTagPositions.filter { $0.isCollected }.count
            self.collectionProgress = Double(completedCount) / Double(self.trueTagPositions.count)

            print("⬅️  タグ(\(tagToUndo.tagId))を取り消してそのタグ位置に戻る（index: \(lastCompletedIndex)）")

            // データ統計を更新
            await self.updateDataStatistics()
        }
    }

    func startCalibration() {
        guard self.canStartCalibration else { return }

        self.isCalibrating = true

        Task {
            await self.performCalibration()
        }
    }

    func proceedToNextAntenna() {
        guard let currentId = self.currentAntennaId else { return }

        // 現在のアンテナを完了リストに追加
        self.completedAntennaIds.insert(currentId)

        // 次の未キャリブレーションアンテナを探す
        let nextAntenna = self.availableAntennas.first { antenna in
            !self.completedAntennaIds.contains(antenna.id)
        }

        // 初期化
        self.currentAntennaId = nextAntenna?.id
        self.currentAntennaResult = nil
        self.trueTagPositions.removeAll()
        self.collectionProgress = 0.0
        self.currentTagPositionIndex = 0
        self.currentStep = 0

        if let nextId = nextAntenna?.id {
            print("➡️  次のアンテナへ: \(self.currentAntennaName) (ID: \(nextId))")
        } else {
            print("✅ 全アンテナのキャリブレーション完了")

            // キャリブレーション結果をUserDefaultsに保存
            self.saveCalibrationResultToUserDefaults()

            // 成功アラートを表示
            self.showSuccessAlert = true

            // フローナビゲーターで次のステップへ進む
            if let flowNavigator = self.flowNavigator {
                print("🚀 次のステップ（センシング実行）へ自動遷移します")
                // アラート表示後に自動で次へ進むため、少し待機
                let floorMapId = self.currentFloorMapInfo?.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    flowNavigator.proceedToNextStep(floorMapId: floorMapId)
                }
            } else {
                print("⚠️ FlowNavigatorが設定されていないため、手動で次へ進んでください")
            }
        }
    }

    /// キャリブレーション結果をUserDefaultsに保存
    private func saveCalibrationResultToUserDefaults() {
        // キャリブレーションデータを作成（アンテナ数の情報を含める）
        let calibrationData: [String: Double] = [
            "completedAntennaCount": Double(self.completedAntennaIds.count),
            "totalAntennaCount": Double(self.availableAntennas.count)
        ]

        let calibrationResult = SystemCalibrationResult(
            timestamp: Date(),
            wasSuccessful: true,
            calibrationData: calibrationData,
            errorMessage: nil
        )

        if let encoded = try? JSONEncoder().encode(calibrationResult) {
            UserDefaults.standard.set(encoded, forKey: "lastCalibrationResult")
            print("💾 キャリブレーション結果をUserDefaultsに保存しました")
        }
    }

    func resetCalibration() {
        self.currentStep = 0
        self.currentAntennaId = nil
        self.completedAntennaIds.removeAll()
        self.trueTagPositions.removeAll()
        self.currentAntennaResult = nil
        self.calibrationResults.removeAll()
        self.collectionProgress = 0.0
        self.currentTagPositionIndex = 0
        self.errorMessage = ""

        Task {
            guard let usecase = autoCalibrationUsecase else { return }
            await usecase.clearData()
        }
    }

    // MARK: - Private Methods

    /// 指定されたIDのフロアマップ情報を読み込み
    private func loadFloorMapInfoById(floorMapId: String) async {
        guard let repository = swiftDataRepository else {
            print("⚠️ SwiftDataRepositoryが利用できません")
            return
        }

        do {
            if let floorMap = try await repository.loadFloorMap(by: floorMapId) {
                self.currentFloorMapInfo = floorMap

                // フロアマップ画像を読み込み
                #if canImport(UIKit)
                    #if os(iOS)
                        self.floorMapImage = floorMap.image
                    #elseif os(macOS)
                        self.floorMapImage = floorMap.image
                    #endif
                #elseif canImport(AppKit)
                    self.floorMapImage = floorMap.image
                #endif

                print("🗺️ フロアマップ読み込み完了: \(floorMap.name), 画像: \(self.floorMapImage != nil ? "あり" : "なし")")
            } else {
                print("⚠️ フロアマップが見つかりません (ID: \(floorMapId))")
            }
        } catch {
            self.showError("フロアマップの読み込みに失敗しました: \(error.localizedDescription)")
        }
    }

    private func loadFloorMapInfo() async {
        guard let repository = swiftDataRepository else { return }

        do {
            let floorMaps = try await repository.loadAllFloorMaps()
            if let floorMap = floorMaps.first {
                self.currentFloorMapInfo = floorMap

                // フロアマップ画像を読み込み
                #if canImport(UIKit)
                    #if os(iOS)
                        self.floorMapImage = floorMap.image
                    #elseif os(macOS)
                        self.floorMapImage = floorMap.image
                    #endif
                #elseif canImport(AppKit)
                    self.floorMapImage = floorMap.image
                #endif

                print("🗺️ [DEBUG] フロアマップ読み込み完了: \(floorMap.name), 画像: \(self.floorMapImage != nil ? "あり" : "なし")")
            }
        } catch {
            self.showError("フロアマップの読み込みに失敗しました: \(error.localizedDescription)")
        }
    }

    private func loadAvailableAntennas() async {
        guard let repository = swiftDataRepository else { return }
        guard let floorMapId = currentFloorMapInfo?.id else {
            print("⚠️ [DEBUG] フロアマップIDが取得できません")
            return
        }

        do {
            // フロアマップに紐づくアンテナ位置データから読み込み
            let antennaPositions = try await repository.loadAntennaPositions(for: floorMapId)
            print("🔍 [DEBUG] loadAntennaPositions()で取得したアンテナ数: \(antennaPositions.count)件")

            for (index, position) in antennaPositions.enumerated() {
                print("🔍 [DEBUG] Antenna[\(index)]: id=\(position.antennaId), name=\(position.antennaName), pos=(\(position.position.x), \(position.position.y))")
            }

            // すべてのアンテナ位置を保存（マップ常時表示用）
            self.allAntennaPositions = antennaPositions

            // ConnectionManagementUsecaseからペアリング情報を取得
            let antennaPairings = ConnectionManagementUsecase.shared.antennaPairings
            print("🔗 [DEBUG] ペアリング情報: \(antennaPairings.count)件")

            for (antennaId, deviceName) in antennaPairings {
                print("🔗 [DEBUG] ペアリング: \(antennaId) → \(deviceName)")
            }

            // 接続中のデバイス名を取得
            let connectedDeviceNames = ConnectionManagementUsecase.shared.connectedDeviceNames
            print("🔌 [DEBUG] 接続中のデバイス: \(connectedDeviceNames)")

            // ペアリングされている かつ 接続中のアンテナのみをフィルタリング
            let connectedAntennaPositions = antennaPositions.filter { position in
                // アンテナIDに紐づくデバイス名を取得
                if let deviceName = antennaPairings[position.antennaId] {
                    let isConnected = connectedDeviceNames.contains(deviceName)
                    print("🔍 [DEBUG] \(position.antennaName) (\(position.antennaId)) → デバイス: \(deviceName), 接続: \(isConnected)")
                    return isConnected
                } else {
                    print("⚠️ [DEBUG] \(position.antennaName) (\(position.antennaId)) はペアリングされていません")
                    return false
                }
            }

            print("📡 [DEBUG] 接続中のアンテナ: \(connectedAntennaPositions.count)個")

            // アンテナ位置データからアンテナリストを構築（接続中のアンテナのみ）
            self.availableAntennas = connectedAntennaPositions.map { position in
                AntennaInfo(
                    id: position.antennaId,
                    name: position.antennaName,
                    isSelected: false
                )
            }

            print("📡 キャリブレーション対象アンテナ: \(self.availableAntennas.count)個")
        } catch {
            self.showError("アンテナリストの読み込みに失敗しました: \(error.localizedDescription)")
        }
    }

    private func setTruePositionsInUsecase() async {
        guard let usecase = autoCalibrationUsecase else { return }

        let positions = Dictionary(
            uniqueKeysWithValues: trueTagPositions.map { ($0.tagId, $0.position) }
        )

        await usecase.setTrueTagPositions(positions)
    }

    private func performCurrentTagPositionCollection() async {
        guard let usecase = autoCalibrationUsecase,
              let sensingControl = sensingControlUsecase,
              let antennaId = currentAntennaId,
              currentTagPositionIndex < trueTagPositions.count
        else {
            self.showError("初期化が完了していません")
            self.isCollecting = false
            return
        }

        let tagPos = self.trueTagPositions[self.currentTagPositionIndex]

        print("📍 タグ位置: \(tagPos.tagId) のデータ収集開始")

        do {
            // 接続状態を確認
            let connectionUsecase = ConnectionManagementUsecase.shared
            guard connectionUsecase.hasConnectedDevices() else {
                throw NSError(
                    domain: "AutoAntennaCalibration",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "デバイスが接続されていません。デバイスをペアリングしてください。"]
                )
            }

            print("✅ デバイス接続確認: \(connectionUsecase.getConnectedDeviceCount())台")

            // センシングセッションIDを生成
            let sessionId = UUID().uuidString
            let sessionName = "calibration_\(antennaId)_\(tagPos.tagId)"

            print("🎬 センシングセッション開始: \(sessionId)")

            // センシング中のデータポイントをクリア
            self.currentSensingDataPoints.removeAll()

            // リアルタイムフィードバック用変数をリセット
            self.sensingElapsedTime = 0.0
            self.currentDataPointCount = 0
            self.currentRMSEEstimate = nil
            self.signalQualityByAntenna.removeAll()
            self.suspiciousZeroDataCount = 0

            // 選択中のアンテナに紐づいたデバイス名を取得
            guard let targetDeviceName = ConnectionManagementUsecase.shared.getDeviceName(for: antennaId)
            else {
                throw NSError(
                    domain: "AutoAntennaCalibration",
                    code: -2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "アンテナ \(antennaId) に紐づいたデバイスが見つかりません。ペアリング設定を確認してください。"
                    ]
                )
            }

            // 選択中のアンテナに紐づいたデバイスのみにセンシング開始コマンドを送信
            let sensingStarted = sensingControl.startRemoteSensingForDevice(
                fileName: sessionName,
                deviceName: targetDeviceName
            )

            guard sensingStarted else {
                throw NSError(
                    domain: "AutoAntennaCalibration",
                    code: -3,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "デバイス \(targetDeviceName) へのセンシング開始コマンド送信に失敗しました。"
                    ]
                )
            }

            print("🎯 キャリブレーション用センシング開始: デバイス=\(targetDeviceName), アンテナ=\(antennaId)")

            // データ収集（リアルタイム更新）
            let startTime = Date()
            while Date().timeIntervalSince(startTime) < self.sensingDuration {
                // 0.5秒ごとにデータを更新
                try await Task.sleep(nanoseconds: 500_000_000)

                // 経過時間を更新
                self.sensingElapsedTime = Date().timeIntervalSince(startTime)

                // リアルタイムデータから座標と品質情報を取得
                if let realtimeUsecase = realtimeDataUsecase {
                    var tempDataPoints: [Point3D] = []
                    var qualityByAntenna: [String: SignalQualityDisplay] = [:]
                    var zeroDataCount = 0

                    for deviceData in realtimeUsecase.deviceRealtimeDataList {
                        guard deviceData.isActive else { continue }

                        // 最新データからマップ表示用座標を取得
                        if let latestData = deviceData.latestData {
                            let position = self.calculatePosition(
                                distance: latestData.distance,
                                elevation: latestData.elevation,
                                azimuth: latestData.azimuth
                            )
                            tempDataPoints.append(position)

                            // (0,0)付近のデータを検出
                            if self.isPositionSuspicious(position) {
                                zeroDataCount += 1
                            }
                        }

                        // データ履歴から信号品質を集計
                        let history = deviceData.dataHistory
                        if !history.isEmpty {
                            let avgRSSI = history.map { $0.rssi }.reduce(0, +) / Double(history.count)
                            // nlos == 0 が LoS (Line of Sight)
                            let losCount = history.filter { $0.nlos == 0 }.count
                            let losPercentage = Double(losCount) / Double(history.count) * 100
                            // RSSIを信号強度の指標として使用（-100dBm〜0dBmを0〜1に正規化）
                            let avgStrength = min(1.0, max(0.0, (avgRSSI + 100) / 100))

                            qualityByAntenna[deviceData.deviceName] = SignalQualityDisplay(
                                averageRSSI: avgRSSI,
                                losPercentage: losPercentage,
                                averageStrength: avgStrength,
                                dataPointCount: history.count
                            )

                            // データ履歴からも(0,0)付近のデータをカウント
                            for data in history {
                                let historyPosition = self.calculatePosition(
                                    distance: data.distance,
                                    elevation: data.elevation,
                                    azimuth: data.azimuth
                                )
                                if self.isPositionSuspicious(historyPosition) {
                                    zeroDataCount += 1
                                }
                            }
                        }
                    }

                    self.currentSensingDataPoints = tempDataPoints
                    self.signalQualityByAntenna = qualityByAntenna
                    self.currentDataPointCount = qualityByAntenna.values.map { $0.dataPointCount }.reduce(
                        0, +)
                    self.suspiciousZeroDataCount = zeroDataCount
                }
            }

            // センシング完了時の経過時間を最終値に設定
            self.sensingElapsedTime = self.sensingDuration

            // センシング停止（特定デバイスのみ）
            sensingControl.stopRemoteSensingForDevice(deviceName: targetDeviceName)

            print("🛑 センシング停止: デバイス=\(targetDeviceName)")

            // センシング停止後、リモートデバイスからのデータ送信を待つ
            // CSVファイルの受信とRealtimeDataの更新を待機
            print("⏳ データ送信待機中...")
            try await Task.sleep(nanoseconds: 3_000_000_000) // 3秒待機

            // RealtimeDataUsecaseから測定データを収集
            guard let realtimeUsecase = realtimeDataUsecase else {
                throw NSError(
                    domain: "AutoAntennaCalibration",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "RealtimeDataUsecaseが初期化されていません"]
                )
            }

            print("🎯 ターゲットデバイス: \(targetDeviceName) (アンテナ: \(antennaId))")

            // 選択中のアンテナに紐づいたデバイスのデータだけを収集
            guard
                let targetDeviceData = realtimeUsecase.deviceRealtimeDataList.first(where: {
                    $0.deviceName == targetDeviceName && $0.isActive
                })
            else {
                throw NSError(
                    domain: "AutoAntennaCalibration",
                    code: -3,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "デバイス \(targetDeviceName) からのデータが取得できませんでした。接続状態を確認してください。"
                    ]
                )
            }

            print(
                "📊 デバイス \(targetDeviceData.deviceName) のデータ収集: \(targetDeviceData.dataHistory.count)件"
            )

            // データ履歴から座標を取得
            for data in targetDeviceData.dataHistory {
                // UWBデータから3D座標を計算
                let position = self.calculatePosition(
                    distance: data.distance,
                    elevation: data.elevation,
                    azimuth: data.azimuth
                )

                // AutoAntennaCalibrationUsecaseにデータを追加
                await usecase.addMeasuredData(
                    antennaId: antennaId,
                    tagId: tagPos.tagId,
                    measuredPosition: position
                )

                print(
                    "  ➕ データ追加: antenna=\(antennaId), tag=\(tagPos.tagId), pos=(\(String(format: "%.2f", position.x)), \(String(format: "%.2f", position.y)))"
                )
            }

            // リアルタイムデータをクリア
            realtimeUsecase.clearRealtimeDataForSensing()

            // タグの収集状態を更新
            self.trueTagPositions[self.currentTagPositionIndex].isCollected = true

            // 進行状況を更新
            let completedCount = self.trueTagPositions.filter { $0.isCollected }.count
            self.collectionProgress = Double(completedCount) / Double(self.trueTagPositions.count)

            print("✅ タグ位置: \(tagPos.tagId) のデータ収集完了 (\(completedCount)/\(self.trueTagPositions.count))")

        } catch {
            self.showError("タグ位置: \(tagPos.tagId) のデータ収集に失敗しました: \(error.localizedDescription)")
        }

        self.isCollecting = false

        // データ統計を更新
        await self.updateDataStatistics()
    }

    private func performCalibration() async {
        guard let usecase = autoCalibrationUsecase,
              let floorMapId = currentFloorMapInfo?.id,
              let antennaId = currentAntennaId
        else {
            self.showError("初期化が完了していません")
            self.isCalibrating = false
            return
        }

        print("🔧 \(self.currentAntennaName) のキャリブレーション開始")

        do {
            // 単一アンテナのキャリブレーション実行
            let results = try await usecase.executeAutoCalibration(
                for: [antennaId],
                minObservationsPerTag: 5
            )

            guard let config = results[antennaId] else {
                throw NSError(
                    domain: "AutoAntennaCalibrationViewModel",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "キャリブレーション結果が取得できませんでした"]
                )
            }

            // 現在のアンテナの結果を保存
            let result = CalibrationResult(
                antennaId: antennaId,
                position: config.position,
                angleDegrees: config.angleDegrees,
                rmse: config.rmse,
                scaleFactors: config.scaleFactors
            )
            self.currentAntennaResult = result
            self.calibrationResults[antennaId] = result

            // SwiftDataに保存
            try await usecase.saveCalibrationResults(
                floorMapId: floorMapId,
                results: results
            )

            // アンテナ位置リストを再読み込みして最新の位置を取得
            await self.loadAvailableAntennas()

            self.isCalibrating = false

            // 結果表示ステップに自動遷移
            self.currentStep = 3

            print("🎉 \(self.currentAntennaName) のキャリブレーション完了")
            print("   位置: (\(config.x), \(config.y)), 角度: \(config.angleDegrees)°, RMSE: \(config.rmse)")

        } catch {
            self.isCalibrating = false
            self.showError("\(self.currentAntennaName) のキャリブレーションに失敗しました: \(error.localizedDescription)")
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

    /// UWBデータから3D座標を計算
    ///
    /// - Parameters:
    ///   - distance: 距離（メートル）
    ///   - elevation: 仰角（度）
    ///   - azimuth: 方位角（度）
    /// - Returns: 3D座標（メートル単位）
    private func calculatePosition(distance: Double, elevation: Double, azimuth: Double) -> Point3D {
        // 角度をラジアンに変換
        let elevationRad = elevation * .pi / 180.0
        let azimuthRad = azimuth * .pi / 180.0

        // 球面座標から直交座標への変換
        // x = r * cos(elevation) * cos(azimuth)
        // y = r * cos(elevation) * sin(azimuth)
        // z = r * sin(elevation)
        let x = distance * cos(elevationRad) * cos(azimuthRad)
        let y = distance * cos(elevationRad) * sin(azimuthRad)
        let z = distance * sin(elevationRad)

        return Point3D(x: x, y: y, z: z)
    }
}
