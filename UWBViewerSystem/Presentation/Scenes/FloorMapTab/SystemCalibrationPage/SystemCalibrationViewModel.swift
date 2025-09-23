import Combine
import Foundation
import SwiftUI

/// システムキャリブレーション画面のViewModel
@MainActor
class SystemCalibrationViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var calibrationStatus: SystemCalibrationStatus = .idle
    @Published var currentCalibrationStep: SystemCalibrationStep = .deviceConnection
    @Published var overallProgress: Double = 0.0
    @Published var isAutoCalibrationEnabled: Bool = false
    @Published var calibrationInterval: CalibrationInterval = .every10Minutes

    @Published var showErrorAlert: Bool = false
    @Published var showSuccessAlert: Bool = false
    @Published var errorMessage: String = ""
    @Published var isLoading: Bool = false

    // キャリブレーションステップの完了状況
    @Published private var completedSteps: Set<SystemCalibrationStep> = []

    // MARK: - 新しいキャリブレーション機能

    @Published var calibrationUsecase: CalibrationUsecase
    @Published var selectedAntennaId: String = ""
    @Published var availableAntennas: [AntennaInfo] = []
    @Published var showManualCalibrationSheet: Bool = false
    @Published var showMapBasedCalibrationSheet: Bool = false
    @Published var calibrationPoints: [CalibrationPoint] = []
    @Published var currentCalibrationData: CalibrationData?
    @Published var calibrationStatistics: CalibrationStatistics?

    // MARK: - 統合キャリブレーションワークフロー

    @Published var calibrationDataFlow: CalibrationDataFlow?
    @Published var observationUsecase: ObservationDataUsecase?
    @Published var showIntegratedCalibrationSheet: Bool = false
    @Published var workflowProgress: Double = 0.0
    @Published var workflowStatus: CalibrationWorkflowStatus = .idle
    @Published var referencePointsCount: Int = 0
    @Published var observationSessionsCount: Int = 0
    @Published var isObservationCollecting: Bool = false

    // 手動キャリブレーション用
    @Published var referenceX: String = ""
    @Published var referenceY: String = ""
    @Published var referenceZ: String = "0"
    @Published var measuredX: String = ""
    @Published var measuredY: String = ""
    @Published var measuredZ: String = "0"

    // MARK: - Private Properties

    private var calibrationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let dataRepository: DataRepositoryProtocol

    // MARK: - Computed Properties

    var canProceedToNext: Bool {
        calibrationStatus == .completed
            || (calibrationStatus == .idle && completedSteps.count >= SystemCalibrationStep.minimumRequiredSteps)
    }

    var currentStepTitle: String {
        currentCalibrationStep.title
    }

    var currentStepDescription: String {
        currentCalibrationStep.description
    }

    var currentStepIcon: String {
        switch calibrationStatus {
        case .idle:
            return "clock"
        case .running:
            return "gearshape.fill"
        case .paused:
            return "pause.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    // MARK: - Initialization

    init(dataRepository: DataRepositoryProtocol = DataRepository()) {
        self.dataRepository = dataRepository
        calibrationUsecase = CalibrationUsecase(dataRepository: dataRepository)
        setupObservers()
        loadSettings()
        loadAvailableAntennas()
        setupIntegratedCalibration()
    }

    deinit {
        calibrationTimer?.invalidate()
    }

    // MARK: - Public Methods

    func initialize() {
        loadCalibrationHistory()
        updateProgress()
    }

    func startCalibration() {
        calibrationStatus = .running
        currentCalibrationStep = .deviceConnection
        overallProgress = 0.0
        completedSteps.removeAll()

        executeCalibrationSteps()
    }

    func pauseCalibration() {
        calibrationStatus = .paused
        calibrationTimer?.invalidate()
    }

    func resumeCalibration() {
        calibrationStatus = .running
        executeCalibrationSteps()
    }

    func cancelCalibration() {
        calibrationStatus = .idle
        calibrationTimer?.invalidate()
        overallProgress = 0.0
        currentCalibrationStep = .deviceConnection
    }

    func selectStep(_ step: SystemCalibrationStep) {
        guard isStepEnabled(step) else { return }
        currentCalibrationStep = step
    }

    func isStepCompleted(_ step: SystemCalibrationStep) -> Bool {
        completedSteps.contains(step)
    }

    func isStepEnabled(_ step: SystemCalibrationStep) -> Bool {
        // 前のステップが完了しているかチェック
        let stepIndex = SystemCalibrationStep.allCases.firstIndex(of: step) ?? 0
        if stepIndex == 0 { return true }

        let previousStep = SystemCalibrationStep.allCases[stepIndex - 1]
        return completedSteps.contains(previousStep)
    }

    func openManualCalibration() {
        if !selectedAntennaId.isEmpty {
            loadCalibrationDataForSelectedAntenna()
            showManualCalibrationSheet = true
        } else {
            showError("アンテナを選択してください")
        }
    }

    func openMapBasedCalibration() {
        if !selectedAntennaId.isEmpty {
            // フロアマップIDを取得
            guard getCurrentFloorMapId() != nil else {
                showError("フロアマップが設定されていません")
                return
            }
            showMapBasedCalibrationSheet = true
        } else {
            showError("アンテナを選択してください")
        }
    }

    func getCurrentFloorMapId() -> String? {
        guard let data = UserDefaults.standard.data(forKey: "currentFloorMapInfo"),
              let floorMapInfo = try? JSONDecoder().decode(FloorMapInfo.self, from: data) else {
            return nil
        }
        return floorMapInfo.id
    }

    // MARK: - 新しいキャリブレーション機能メソッド

    func loadAvailableAntennas() {
        // データリポジトリからアンテナ情報を読み込み
        availableAntennas = dataRepository.loadFieldAntennaConfiguration() ?? []
        if !availableAntennas.isEmpty && selectedAntennaId.isEmpty {
            selectedAntennaId = availableAntennas.first?.id ?? ""
        }
        updateCalibrationStatistics()
    }

    func loadCalibrationDataForSelectedAntenna() {
        guard !selectedAntennaId.isEmpty else { return }
        currentCalibrationData = calibrationUsecase.getCalibrationData(for: selectedAntennaId)
        calibrationPoints = currentCalibrationData?.calibrationPoints ?? []
    }

    func addCalibrationPoint() {
        guard !selectedAntennaId.isEmpty,
              let refX = Double(referenceX),
              let refY = Double(referenceY),
              let refZ = Double(referenceZ),
              let measX = Double(measuredX),
              let measY = Double(measuredY),
              let measZ = Double(measuredZ) else {
            showError("座標値を正しく入力してください")
            return
        }

        let referencePosition = Point3D(x: refX, y: refY, z: refZ)
        let measuredPosition = Point3D(x: measX, y: measY, z: measZ)

        calibrationUsecase.addCalibrationPoint(
            for: selectedAntennaId,
            referencePosition: referencePosition,
            measuredPosition: measuredPosition
        )

        // 入力フィールドをクリア
        clearInputFields()

        // データを再読み込み
        loadCalibrationDataForSelectedAntenna()

        // 統計情報を更新
        updateCalibrationStatistics()
    }

    func removeCalibrationPoint(pointId: String) {
        calibrationUsecase.removeCalibrationPoint(for: selectedAntennaId, pointId: pointId)
        loadCalibrationDataForSelectedAntenna()
        updateCalibrationStatistics()
    }

    func performLeastSquaresCalibration() {
        guard !selectedAntennaId.isEmpty else {
            showError("アンテナを選択してください")
            return
        }

        guard let calibrationData = currentCalibrationData,
              calibrationData.calibrationPoints.count >= 3 else {
            showError("キャリブレーションには最低3つの測定点が必要です")
            return
        }

        isLoading = true

        Task {
            await calibrationUsecase.performCalibration(for: selectedAntennaId)

            await MainActor.run {
                isLoading = false

                if let result = calibrationUsecase.lastCalibrationResult {
                    if result.success {
                        showSuccessAlert = true
                        loadCalibrationDataForSelectedAntenna()
                        updateCalibrationStatistics()
                    } else {
                        showError(result.errorMessage ?? "キャリブレーションに失敗しました")
                    }
                }
            }
        }
    }

    func performAllCalibrations() {
        guard !availableAntennas.isEmpty else {
            showError("アンテナが設定されていません")
            return
        }

        isLoading = true

        Task {
            await calibrationUsecase.performAllCalibrations()

            await MainActor.run {
                isLoading = false
                updateCalibrationStatistics()

                if calibrationUsecase.calibrationStatus == .completed {
                    showSuccessAlert = true
                } else if calibrationUsecase.calibrationStatus == .failed {
                    showError(calibrationUsecase.errorMessage ?? "キャリブレーションに失敗しました")
                }
            }
        }
    }

    func clearCalibrationData() {
        calibrationUsecase.clearCalibrationData(for: selectedAntennaId)
        loadCalibrationDataForSelectedAntenna()
        updateCalibrationStatistics()
    }

    func clearAllCalibrationData() {
        calibrationUsecase.clearCalibrationData()
        loadCalibrationDataForSelectedAntenna()
        updateCalibrationStatistics()
    }

    func updateCalibrationStatistics() {
        calibrationStatistics = calibrationUsecase.getCalibrationStatistics()
    }

    private func clearInputFields() {
        referenceX = ""
        referenceY = ""
        referenceZ = "0"
        measuredX = ""
        measuredY = ""
        measuredZ = "0"
    }

    // MARK: - 統合キャリブレーションワークフロー

    /// 統合キャリブレーション機能のセットアップ
    private func setupIntegratedCalibration() {
        let uwbManager = UWBDataManager()
        observationUsecase = ObservationDataUsecase(dataRepository: dataRepository, uwbManager: uwbManager)

        guard let observationUsecase else { return }

        calibrationDataFlow = CalibrationDataFlow(
            dataRepository: dataRepository,
            calibrationUsecase: calibrationUsecase,
            observationUsecase: observationUsecase
        )

        // データフローの状態を監視
        setupDataFlowObservers()
    }

    /// データフローオブザーバーのセットアップ
    private func setupDataFlowObservers() {
        guard let calibrationDataFlow,
              let observationUsecase else { return }

        // ワークフローの進行状況を監視
        calibrationDataFlow.$workflowProgress
            .receive(on: DispatchQueue.main)
            .assign(to: \.workflowProgress, on: self)
            .store(in: &cancellables)

        calibrationDataFlow.$currentWorkflow
            .receive(on: DispatchQueue.main)
            .assign(to: \.workflowStatus, on: self)
            .store(in: &cancellables)

        calibrationDataFlow.$referencePoints
            .map { $0.count }
            .receive(on: DispatchQueue.main)
            .assign(to: \.referencePointsCount, on: self)
            .store(in: &cancellables)

        calibrationDataFlow.$observationSessions
            .map { $0.count }
            .receive(on: DispatchQueue.main)
            .assign(to: \.observationSessionsCount, on: self)
            .store(in: &cancellables)

        // 観測データ収集状態を監視
        observationUsecase.$isCollecting
            .receive(on: DispatchQueue.main)
            .assign(to: \.isObservationCollecting, on: self)
            .store(in: &cancellables)
    }

    /// 統合キャリブレーションワークフローを開始
    func startIntegratedCalibration() {
        guard !selectedAntennaId.isEmpty else {
            showError("アンテナを選択してください")
            return
        }

        showIntegratedCalibrationSheet = true
    }

    /// マップから基準座標を設定
    func setReferencePointsFromMap(_ points: [MapCalibrationPoint]) {
        calibrationDataFlow?.collectReferencePoints(from: points)
    }

    /// 手動で基準座標を追加
    func addManualReferencePoint() {
        guard let refX = Double(referenceX),
              let refY = Double(referenceY),
              let refZ = Double(referenceZ) else {
            showError("基準座標を正しく入力してください")
            return
        }

        let position = Point3D(x: refX, y: refY, z: refZ)
        calibrationDataFlow?.addReferencePoint(position: position, name: "手動設定_\(Date().timeIntervalSince1970)")

        // 入力フィールドをクリア
        referenceX = ""
        referenceY = ""
        referenceZ = "0"
    }

    /// 観測データ収集を開始
    func startObservationCollection() {
        guard !selectedAntennaId.isEmpty else {
            showError("アンテナを選択してください")
            return
        }

        Task {
            await calibrationDataFlow?.startObservationData(for: selectedAntennaId)
        }
    }

    /// 観測データ収集を停止
    func stopObservationCollection() {
        guard !selectedAntennaId.isEmpty else { return }

        Task {
            await calibrationDataFlow?.stopObservationData(for: selectedAntennaId)
        }
    }

    /// 完全なキャリブレーションワークフローを実行
    func executeIntegratedCalibration() {
        isLoading = true

        Task {
            // まず観測データと基準データをマッピング
            let mappings = calibrationDataFlow?.mapObservationsToReferences() ?? []
            print("📊 作成されたマッピング数: \(mappings.count)")

            // キャリブレーション実行
            if let result = await calibrationDataFlow?.executeCalibration() {
                await MainActor.run {
                    isLoading = false

                    if result.success {
                        showSuccessAlert = true
                        // キャリブレーション統計を更新
                        updateCalibrationStatistics()
                        print("✅ 統合キャリブレーション完了")
                    } else {
                        showError(result.errorMessage ?? "統合キャリブレーションに失敗しました")
                        print("❌ 統合キャリブレーション失敗: \(result.errorMessage ?? "不明なエラー")")
                    }
                }
            } else {
                await MainActor.run {
                    isLoading = false
                    showError("キャリブレーションデータフローが初期化されていません")
                }
            }
        }
    }

    /// ワークフローの状態検証
    func validateWorkflowState() -> CalibrationWorkflowValidation? {
        calibrationDataFlow?.validateCurrentState()
    }

    /// ワークフローをリセット
    func resetIntegratedCalibration() {
        calibrationDataFlow?.resetWorkflow()
        workflowProgress = 0.0
        workflowStatus = .idle
        referencePointsCount = 0
        observationSessionsCount = 0
        isObservationCollecting = false
    }

    /// 現在のワークフロー状態を取得
    var workflowStatusText: String {
        workflowStatus.displayText
    }

    /// ワークフローが実行可能かチェック
    var canExecuteWorkflow: Bool {
        let validation = validateWorkflowState()
        return validation?.canProceed ?? false
    }

    /// ワークフローの進行状況テキスト
    var workflowProgressText: String {
        let percentage = Int(workflowProgress * 100)
        return "\(percentage)% 完了"
    }

    // MARK: - Private Methods

    private func setupObservers() {
        // 自動キャリブレーション設定の変更を監視
        $isAutoCalibrationEnabled
            .sink { [weak self] enabled in
                self?.saveSettings()
            }
            .store(in: &cancellables)

        $calibrationInterval
            .sink { [weak self] _ in
                self?.saveSettings()
            }
            .store(in: &cancellables)
    }

    private func executeCalibrationSteps() {
        guard calibrationStatus == .running else { return }

        let steps = SystemCalibrationStep.allCases
        let currentIndex = steps.firstIndex(of: currentCalibrationStep) ?? 0

        // 現在のステップを実行
        executeStep(currentCalibrationStep) { [weak self] success in
            guard let self else { return }

            if success {
                // ステップ完了
                completeStep(currentCalibrationStep)

                // 次のステップに進む
                if currentIndex < steps.count - 1 {
                    currentCalibrationStep = steps[currentIndex + 1]
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.executeCalibrationSteps()
                    }
                } else {
                    // 全ステップ完了
                    completeCalibration()
                }
            } else {
                // ステップ失敗
                failCalibration()
            }
        }
    }

    private func executeStep(_ step: SystemCalibrationStep, completion: @escaping (Bool) -> Void) {
        isLoading = true

        // ステップ実行のシミュレーション
        let duration = step.estimatedDuration

        calibrationTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
            DispatchQueue.main.async {
                self.isLoading = false

                // 成功率をシミュレート（実際の実装では実際の処理結果を使用）
                let success = Double.random(in: 0...1) > 0.1  // 90%の成功率
                completion(success)
            }
        }
    }

    private func completeStep(_ step: SystemCalibrationStep) {
        completedSteps.insert(step)
        updateProgress()
    }

    private func completeCalibration() {
        calibrationStatus = .completed
        overallProgress = 1.0
        showSuccessAlert = true
        saveCalibrationResult()
    }

    private func failCalibration() {
        calibrationStatus = .failed
        showError("キャリブレーションに失敗しました。再度お試しください。")
    }

    private func updateProgress() {
        let totalSteps = SystemCalibrationStep.allCases.count
        let completedCount = completedSteps.count
        overallProgress = Double(completedCount) / Double(totalSteps)
    }

    private func loadSettings() {
        isAutoCalibrationEnabled = UserDefaults.standard.bool(forKey: "autoCalibrationEnabled")

        if let intervalRawValue = UserDefaults.standard.object(forKey: "calibrationInterval") as? String,
           let interval = CalibrationInterval(rawValue: intervalRawValue)
        {
            calibrationInterval = interval
        }
    }

    private func saveSettings() {
        UserDefaults.standard.set(isAutoCalibrationEnabled, forKey: "autoCalibrationEnabled")
        UserDefaults.standard.set(calibrationInterval.rawValue, forKey: "calibrationInterval")
    }

    private func loadCalibrationHistory() {
        // 過去のキャリブレーション結果を読み込む
        if let data = UserDefaults.standard.data(forKey: "lastCalibrationResult"),
           let result = try? JSONDecoder().decode(SystemCalibrationResult.self, from: data)
        {

            // 最近のキャリブレーションが成功していれば一部ステップをスキップ
            if result.wasSuccessful && result.timestamp.timeIntervalSinceNow > -3600 {  // 1時間以内
                completedSteps.insert(.deviceConnection)
                completedSteps.insert(.systemCheck)
                updateProgress()
            }
        }
    }

    private func saveCalibrationResult() {
        let result = SystemCalibrationResult(
            timestamp: Date(),
            wasSuccessful: calibrationStatus == .completed,
            calibrationData: [:],
            errorMessage: calibrationStatus == .failed ? "キャリブレーションが失敗しました" : nil
        )

        if let data = try? JSONEncoder().encode(result) {
            UserDefaults.standard.set(data, forKey: "lastCalibrationResult")
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }
}

// MARK: - Supporting Types

enum SystemCalibrationStatus {
    case idle
    case running
    case paused
    case completed
    case failed

    var displayText: String {
        switch self {
        case .idle:
            return "待機中"
        case .running:
            return "実行中"
        case .paused:
            return "一時停止"
        case .completed:
            return "完了"
        case .failed:
            return "失敗"
        }
    }
}

enum SystemCalibrationStep: String, CaseIterable, Codable {
    case deviceConnection = "deviceConnection"
    case systemCheck = "systemCheck"
    case antennaCalibration = "antennaCalibration"
    case distanceCalibration = "distanceCalibration"
    case accuracyTest = "accuracyTest"
    case finalValidation = "finalValidation"

    var title: String {
        switch self {
        case .deviceConnection:
            return "デバイス接続確認"
        case .systemCheck:
            return "システムチェック"
        case .antennaCalibration:
            return "アンテナキャリブレーション"
        case .distanceCalibration:
            return "距離キャリブレーション"
        case .accuracyTest:
            return "精度テスト"
        case .finalValidation:
            return "最終検証"
        }
    }

    var description: String {
        switch self {
        case .deviceConnection:
            return "接続されたデバイスの動作状態を確認します"
        case .systemCheck:
            return "UWBシステム全体の動作を確認します"
        case .antennaCalibration:
            return "各アンテナの信号品質を調整します"
        case .distanceCalibration:
            return "距離測定の精度を調整します"
        case .accuracyTest:
            return "キャリブレーション結果の精度をテストします"
        case .finalValidation:
            return "全設定が正常に動作することを確認します"
        }
    }

    var estimatedDuration: TimeInterval {
        switch self {
        case .deviceConnection:
            return 3.0
        case .systemCheck:
            return 5.0
        case .antennaCalibration:
            return 8.0
        case .distanceCalibration:
            return 10.0
        case .accuracyTest:
            return 7.0
        case .finalValidation:
            return 4.0
        }
    }

    static var totalEstimatedDuration: TimeInterval {
        allCases.reduce(0) { $0 + $1.estimatedDuration }
    }

    static var minimumRequiredSteps: Int {
        4  // 最低限必要なステップ数
    }
}

enum CalibrationInterval: String, CaseIterable {
    case every5Minutes = "5min"
    case every10Minutes = "10min"
    case every30Minutes = "30min"
    case everyHour = "1hour"

    var displayText: String {
        switch self {
        case .every5Minutes:
            return "5分毎"
        case .every10Minutes:
            return "10分毎"
        case .every30Minutes:
            return "30分毎"
        case .everyHour:
            return "1時間毎"
        }
    }

    var timeInterval: TimeInterval {
        switch self {
        case .every5Minutes:
            return 300
        case .every10Minutes:
            return 600
        case .every30Minutes:
            return 1800
        case .everyHour:
            return 3600
        }
    }
}
