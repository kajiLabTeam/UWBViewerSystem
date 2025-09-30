import Combine
import Foundation
import SwiftData
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// シンプルな3ステップキャリブレーション画面のViewModel
@MainActor
class SimpleCalibrationViewModel: ObservableObject {
    // MARK: - Published Properties

    /// 現在のステップ (0: アンテナ選択, 1: 基準座標設定, 2: キャリブレーション実行)
    @Published var currentStep: Int = 0

    /// 選択されたアンテナID
    @Published var selectedAntennaId: String = ""

    /// 利用可能なアンテナ一覧
    @Published var availableAntennas: [AntennaInfo] = []

    /// 基準座標（マップから設定された3つの座標）
    @Published var referencePoints: [Point3D] = []

    /// キャリブレーション実行中フラグ
    @Published var isCalibrating: Bool = false

    /// キャリブレーション進行状況 (0.0 - 1.0)
    @Published var calibrationProgress: Double = 0.0

    /// キャリブレーション結果
    @Published var calibrationResult: CalibrationResult?

    /// エラーメッセージ
    @Published var errorMessage: String = ""
    @Published var showErrorAlert: Bool = false

    /// 成功アラート表示フラグ
    @Published var showSuccessAlert: Bool = false

    /// 現在のフロアマップID
    @Published var currentFloorMapId: String = ""

    /// 現在のフロアマップ情報
    @Published var currentFloorMapInfo: FloorMapInfo?

    /// フロアマップ画像
    #if canImport(UIKit)
        @Published var floorMapImage: UIImage?
    #elseif canImport(AppKit)
        @Published var floorMapImage: NSImage?
    #endif

    /// 配置済みアンテナ位置データ
    @Published var antennaPositions: [AntennaPositionData] = []

    // MARK: - 段階的キャリブレーション用プロパティ

    /// 段階的キャリブレーション実行中フラグ
    @Published var isStepByStepCalibrationActive: Bool = false

    /// 現在のステップ指示
    @Published var currentStepInstructions: String = ""

    /// ステップ進行状況
    @Published var stepProgress: Double = 0.0

    /// 現在のステップ番号
    @Published var currentStepNumber: Int = 0

    /// 総ステップ数
    @Published var totalSteps: Int = 0

    /// データ収集進行状況
    @Published var dataCollectionProgress: Double = 0.0

    /// 残り時間
    @Published var timeRemaining: TimeInterval = 0.0

    /// 最終的なアンテナ位置
    @Published var finalAntennaPositions: [String: Point3D] = [:]

    /// アンテナ位置結果表示フラグ
    @Published var showAntennaPositionsResult: Bool = false

    /// CalibrationDataFlow
    private var calibrationDataFlow: CalibrationDataFlow?

    /// ObservationDataUsecase
    private var observationUsecase: ObservationDataUsecase?

    // MARK: - Private Properties

    private let dataRepository: DataRepositoryProtocol
    private let preferenceRepository: PreferenceRepositoryProtocol
    private let calibrationUsecase: CalibrationUsecase
    private var cancellables = Set<AnyCancellable>()
    private var calibrationTimer: Timer?
    private var swiftDataRepository: SwiftDataRepository?

    // MARK: - Computed Properties

    /// 現在のステップタイトル
    var currentStepTitle: String {
        switch self.currentStep {
        case 0: return "アンテナ選択"
        case 1: return "基準座標設定"
        case 2: return "キャリブレーション実行"
        default: return ""
        }
    }

    /// 現在のステップ説明
    var currentStepDescription: String {
        switch self.currentStep {
        case 0: return "キャリブレーションを行うアンテナを選択してください"
        case 1: return "フロアマップ上で3つの基準座標をタップしてください"
        case 2: return "キャリブレーションを開始してください"
        default: return ""
        }
    }

    /// 次へボタンが有効かどうか
    var canProceedToNext: Bool {
        switch self.currentStep {
        case 0: return !self.selectedAntennaId.isEmpty
        case 1: return self.referencePoints.count >= 3
        case 2: return false  // キャリブレーション実行画面では次へボタンは無効
        default: return false
        }
    }

    /// 戻るボタンが有効かどうか
    var canGoBack: Bool {
        self.currentStep > 0 && !self.isCalibrating
    }

    /// キャリブレーション実行可能かどうか
    var canStartCalibration: Bool {
        self.currentStep == 2 && !self.selectedAntennaId.isEmpty && self.referencePoints.count >= 3 && !self.isCalibrating
    }

    /// 進行状況のパーセンテージ表示
    var progressPercentage: String {
        "\(Int(self.calibrationProgress * 100))%"
    }

    /// キャリブレーション結果の精度テキスト
    var calibrationAccuracyText: String {
        if let result = calibrationResult,
           let accuracy = result.transform?.accuracy
        {
            return String(format: "%.2f%%", accuracy * 100)
        }
        return "不明"
    }

    /// キャリブレーション結果のテキスト
    var calibrationResultText: String {
        guard let result = calibrationResult else { return "未実行" }
        return result.success ? "成功" : "失敗"
    }

    /// キャリブレーション結果の色
    var calibrationResultColor: Color {
        guard let result = calibrationResult else { return .secondary }
        return result.success ? .green : .red
    }

    // MARK: - Initialization

    init(
        dataRepository: DataRepositoryProtocol = DataRepository(),
        preferenceRepository: PreferenceRepositoryProtocol = PreferenceRepository()
    ) {
        self.dataRepository = dataRepository
        self.preferenceRepository = preferenceRepository
        self.calibrationUsecase = CalibrationUsecase(dataRepository: dataRepository)

        self.loadInitialData()
        self.setupDataObserver()
    }

    deinit {
        calibrationTimer?.invalidate()
    }

    // MARK: - Public Methods

    /// SwiftDataのModelContextを設定
    func setModelContext(_ context: ModelContext) {
        self.swiftDataRepository = SwiftDataRepository(modelContext: context)

        // SwiftDataRepository設定後にアンテナ位置データを再読み込み
        Task { @MainActor in
            await self.loadAntennaPositionsFromSwiftData()
        }
    }

    /// 初期データの読み込み
    func loadInitialData() {
        self.loadAvailableAntennas()
        self.loadCurrentFloorMapData()
        self.loadAntennaPositions()
    }

    /// データの再読み込み（外部から呼び出し可能）
    func reloadData() {
        self.loadCurrentFloorMapData()
        self.loadAntennaPositions()
    }

    /// 次のステップに進む
    func proceedToNext() {
        guard self.canProceedToNext else { return }

        withAnimation {
            self.currentStep += 1
        }
    }

    /// 前のステップに戻る
    func goBack() {
        guard self.canGoBack else { return }

        withAnimation {
            self.currentStep -= 1
        }
    }

    /// アンテナを選択
    func selectAntenna(_ antennaId: String) {
        self.selectedAntennaId = antennaId
    }

    /// 基準座標を設定（マップからの座標）
    func setReferencePoints(_ points: [Point3D]) {
        self.referencePoints = points
    }

    /// 基準座標を追加
    func addReferencePoint(_ point: Point3D) {
        if self.referencePoints.count < 3 {
            self.referencePoints.append(point)
        }
    }

    /// 基準座標をクリア
    func clearReferencePoints() {
        self.referencePoints.removeAll()
    }

    /// キャリブレーションを開始
    /// キャリブレーションを開始
    func startCalibration() {
        // 事前条件チェック
        guard self.validateCalibrationPreConditions() else {
            return
        }

        self.isCalibrating = true
        self.calibrationProgress = 0.0
        self.calibrationResult = nil
        self.errorMessage = ""

        // 基準座標をキャリブレーション用の測定点として設定
        self.setupCalibrationPoints()

        // キャリブレーション実行
        self.performCalibration()
    }

    /// キャリブレーション開始前の条件をチェック
    private func validateCalibrationPreConditions() -> Bool {
        guard self.canStartCalibration else {
            self.showError("キャリブレーションを開始できません。必要な条件が満たされていません。")
            return false
        }

        guard !self.selectedAntennaId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            self.showError("アンテナが選択されていません。")
            return false
        }

        guard self.referencePoints.count >= 3 else {
            self.showError("基準座標が不足しています。少なくとも3点の設定が必要です。")
            return false
        }

        // 基準座標の妥当性チェック
        for (index, point) in self.referencePoints.enumerated() {
            guard point.x.isFinite && point.y.isFinite && point.z.isFinite else {
                self.showError("基準座標\(index + 1)に無効な値が含まれています。")
                return false
            }
        }

        // 同一座標の重複チェック
        let uniquePoints = Set(referencePoints.map { "\($0.x),\($0.y),\($0.z)" })
        guard uniquePoints.count == self.referencePoints.count else {
            self.showError("基準座標に重複があります。異なる座標を設定してください。")
            return false
        }

        return true
    }

    /// キャリブレーション完了後にリセット
    func resetCalibration() {
        self.currentStep = 0
        self.selectedAntennaId = ""
        self.referencePoints.removeAll()
        self.isCalibrating = false
        self.calibrationProgress = 0.0
        self.calibrationResult = nil

        // 最初のアンテナを再選択
        if !self.availableAntennas.isEmpty {
            self.selectedAntennaId = self.availableAntennas.first?.id ?? ""
        }
    }

    // MARK: - 段階的キャリブレーション関連メソッド

    /// 段階的キャリブレーションの初期化
    func setupStepByStepCalibration(
        calibrationDataFlow: CalibrationDataFlow,
        observationUsecase: ObservationDataUsecase
    ) {
        self.calibrationDataFlow = calibrationDataFlow
        self.observationUsecase = observationUsecase

        self.setupCalibrationDataFlowObservers()
    }

    /// CalibrationDataFlowのObserver設定
    /// CalibrationDataFlowのObserver設定
    private func setupCalibrationDataFlowObservers() {
        guard let flow = calibrationDataFlow else { return }

        // 現在のステップ指示を監視
        flow.$currentStepInstructions
            .receive(on: RunLoop.main)
            .assign(to: &self.$currentStepInstructions)

        // 現在のステップ番号を監視
        flow.$currentReferencePointIndex
            .receive(on: RunLoop.main)
            .assign(to: &self.$currentStepNumber)

        // 総ステップ数を監視
        flow.$totalReferencePoints
            .receive(on: RunLoop.main)
            .assign(to: &self.$totalSteps)

        // ステップ進行状況を監視
        flow.$calibrationStepProgress
            .receive(on: RunLoop.main)
            .assign(to: &self.$stepProgress)

        // データ収集進行状況を監視（CalibrationDataFlowには存在しないため削除）

        // アクティブ状態を監視
        flow.$isCollectingForCurrentPoint
            .receive(on: RunLoop.main)
            .assign(to: &self.$isStepByStepCalibrationActive)
    }

    /// 段階的キャリブレーションを開始
    /// 段階的キャリブレーションを開始
    func startStepByStepCalibration() {
        guard !self.referencePoints.isEmpty else {
            self.showError("基準座標が設定されていません。")
            return
        }

        guard let flow = calibrationDataFlow else {
            self.showError("CalibrationDataFlowが初期化されていません。")
            return
        }

        // 基準座標をCalibrationDataFlowに設定
        let mapPoints = self.referencePoints.enumerated().map { index, point in
            MapCalibrationPoint(
                mapCoordinate: point,
                realWorldCoordinate: point,
                antennaId: self.selectedAntennaId,
                pointIndex: index + 1
            )
        }
        flow.collectReferencePoints(from: mapPoints)

        Task {
            await flow.startStepByStepCalibration()
        }
    }

    /// 現在のポイントでデータ収集を開始
    /// 現在のポイントでデータ収集を開始
    func startDataCollectionForCurrentPoint() {
        guard let flow = calibrationDataFlow else {
            self.showError("CalibrationDataFlowが初期化されていません。")
            return
        }

        Task {
            await flow.startDataCollectionForCurrentPoint()
        }
    }

    /// 段階的キャリブレーション完了時の処理
    /// 段階的キャリブレーション完了時の処理
    /// 段階的キャリブレーション完了時の処理
    func handleStepByStepCalibrationCompletion() {
        guard let flow = calibrationDataFlow else { return }

        // 最終的なアンテナ位置を取得
        if !flow.finalAntennaPositions.isEmpty {
            self.finalAntennaPositions = flow.finalAntennaPositions
            self.showFinalAntennaPositions()
        }

        // キャリブレーション結果を取得
        if let workflowResult = flow.lastCalibrationResult {
            // 選択されたアンテナのキャリブレーション結果を取得
            if let antennaResult = workflowResult.calibrationResults[selectedAntennaId] {
                self.calibrationResult = antennaResult
                if antennaResult.success {
                    self.showSuccessAlert = true
                } else {
                    self.showError(antennaResult.errorMessage ?? "キャリブレーションに失敗しました")
                }
            } else if !workflowResult.success {
                self.showError(workflowResult.errorMessage ?? "キャリブレーションに失敗しました")
            }
        }
    }

    /// 最終的なアンテナ位置を表示
    private func showFinalAntennaPositions() {
        self.showAntennaPositionsResult = true
    }

    /// アンテナ位置結果を閉じる
    func dismissAntennaPositionsResult() {
        self.showAntennaPositionsResult = false
    }

    // MARK: - Private Methods

    /// 利用可能なアンテナを読み込み
    private func loadAvailableAntennas() {
        self.availableAntennas = self.dataRepository.loadFieldAntennaConfiguration() ?? []

        // デフォルトで最初のアンテナを選択
        if !self.availableAntennas.isEmpty && self.selectedAntennaId.isEmpty {
            self.selectedAntennaId = self.availableAntennas.first?.id ?? ""
        }
    }

    /// 現在のフロアマップデータを読み込み
    private func loadCurrentFloorMapData() {
        guard let floorMapInfo = preferenceRepository.loadCurrentFloorMapInfo() else {
            self.handleError("フロアマップ情報が設定されていません。先にフロアマップを設定してください。")
            // 現在の状態をクリア
            self.clearFloorMapData()
            return
        }

        // データの妥当性チェック
        guard !floorMapInfo.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !floorMapInfo.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              floorMapInfo.width > 0,
              floorMapInfo.depth > 0
        else {
            self.handleError("フロアマップデータが無効です")
            self.clearFloorMapData()
            return
        }

        self.currentFloorMapId = floorMapInfo.id
        self.currentFloorMapInfo = floorMapInfo
        self.loadFloorMapImage(for: floorMapInfo.id)
    }

    /// フロアマップデータをクリア
    private func clearFloorMapData() {
        self.currentFloorMapId = ""
        self.currentFloorMapInfo = nil
        self.floorMapImage = nil
    }

    /// フロアマップ画像を読み込み
    private func loadFloorMapImage(for floorMapId: String) {
        // FloorMapInfoのimageプロパティを使用して統一された方法で読み込む
        if let floorMapInfo = currentFloorMapInfo,
           let image = floorMapInfo.image
        {
            self.floorMapImage = image
            return
        }

        // フォールバック: 独自の検索ロジック
        let fileManager = FileManager.default

        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        // 複数の場所を検索
        let searchPaths = [
            documentsPath.appendingPathComponent("\(floorMapId).jpg"),  // Documents直下（FloorMapInfo.imageと同じ）
            documentsPath.appendingPathComponent("\(floorMapId).png"),  // Documents直下（PNG版）
            documentsPath.appendingPathComponent("FloorMaps").appendingPathComponent("\(floorMapId).jpg"),  // FloorMapsサブディレクトリ
            documentsPath.appendingPathComponent("FloorMaps").appendingPathComponent("\(floorMapId).png"),  // FloorMapsサブディレクトリ（PNG版）
        ]

        for imageURL in searchPaths {
            if fileManager.fileExists(atPath: imageURL.path) {
                do {
                    let imageData = try Data(contentsOf: imageURL)

                    #if canImport(UIKit)
                        if let image = UIImage(data: imageData) {
                            self.floorMapImage = image
                            return
                        }
                    #elseif canImport(AppKit)
                        if let image = NSImage(data: imageData) {
                            self.floorMapImage = image
                            return
                        }
                    #endif
                } catch {
                    // ファイル読み込みエラー処理を続ける
                }
            }
        }
    }

    /// SwiftDataからアンテナ位置データを読み込み
    private func loadAntennaPositionsFromSwiftData() async {
        guard let repository = swiftDataRepository else {
            self.antennaPositions = []
            return
        }

        guard let floorMapId = currentFloorMapInfo?.id else {
            self.antennaPositions = []
            return
        }

        do {
            let positions = try await repository.loadAntennaPositions(for: floorMapId)
            self.antennaPositions = positions
        } catch {
            self.antennaPositions = []
        }
    }

    /// アンテナ位置データを読み込み
    private func loadAntennaPositions() {
        // SwiftDataRepositoryが利用可能な場合はそちらを優先
        if let _ = swiftDataRepository {
            Task { @MainActor in
                await self.loadAntennaPositionsFromSwiftData()
            }
            return
        }

        // フォールバック: DataRepositoryを使用
        guard let floorMapId = currentFloorMapInfo?.id else {
            self.antennaPositions = []
            return
        }

        if let positions = dataRepository.loadAntennaPositions() {
            // 現在のフロアマップに関連するアンテナ位置のみをフィルタ
            let filteredPositions = positions.filter { $0.floorMapId == floorMapId }
            self.antennaPositions = filteredPositions
        } else {
            self.antennaPositions = []
        }
    }

    /// キャリブレーション用の測定点をセットアップ
    private func setupCalibrationPoints() {
        // 既存のキャリブレーションデータをクリア
        self.calibrationUsecase.clearCalibrationData(for: self.selectedAntennaId)

        // 基準座標を測定点として追加
        // 注意: 実際の実装では、各基準座標に対応する測定座標を取得する必要があります
        // ここでは簡略化のため、基準座標をそのまま測定座標としています
        for referencePoint in self.referencePoints {
            self.calibrationUsecase.addCalibrationPoint(
                for: self.selectedAntennaId,
                referencePosition: referencePoint,
                measuredPosition: referencePoint  // 実際の実装では実測値を使用
            )
        }
    }

    /// キャリブレーション実行
    private func performCalibration() {
        Task {
            // プログレス更新のタイマーを開始
            self.startProgressTimer()

            // キャリブレーション実行
            await self.calibrationUsecase.performCalibration(for: self.selectedAntennaId)

            await MainActor.run {
                // タイマーを停止
                self.calibrationTimer?.invalidate()

                // 結果を取得
                if let result = calibrationUsecase.lastCalibrationResult {
                    self.calibrationResult = result
                    self.calibrationProgress = 1.0
                    self.isCalibrating = false

                    if result.success {
                        self.showSuccessAlert = true
                    } else {
                        self.showError(result.errorMessage ?? "キャリブレーションに失敗しました")
                    }
                } else {
                    self.isCalibrating = false
                    self.showError("キャリブレーション結果を取得できませんでした")
                }
            }
        }
    }

    /// プログレス更新タイマーを開始
    private func startProgressTimer() {
        self.calibrationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isCalibrating else { return }

                // プログレスをゆっくり更新（実際の処理進行度に合わせて調整）
                if self.calibrationProgress < 0.95 {
                    self.calibrationProgress += 0.02
                }
            }
        }
    }

    /// UserDefaultsの変更を監視してフロアマップデータを更新
    private func setupDataObserver() {
        // UserDefaultsの "currentFloorMapInfo" キーの変更を監視
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.loadCurrentFloorMapData()
                }
            }
            .store(in: &self.cancellables)
    }

    /// エラー表示
    private func showError(_ message: String) {
        self.errorMessage = message
        self.showErrorAlert = true
        self.isCalibrating = false
    }

    /// 包括的なエラーハンドリング
    private func handleError(_ message: String) {
        self.showError(message)
    }

    /// 安全な非同期タスク実行
    private func safeAsyncTask<T>(
        operation: @escaping () async throws -> T,
        onSuccess: @escaping (T) -> Void = { _ in },
        onFailure: @escaping (Error) -> Void = { _ in }
    ) {
        Task {
            do {
                let result = try await operation()
                await MainActor.run {
                    onSuccess(result)
                }
            } catch {
                await MainActor.run {
                    self.handleError(error.localizedDescription)
                    onFailure(error)
                }
            }
        }
    }
}
