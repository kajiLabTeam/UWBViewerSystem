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

    // MARK: - Private Properties

    private var calibrationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

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

    init() {
        setupObservers()
        loadSettings()
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
        // 手動キャリブレーション画面への遷移
        // TODO: 手動キャリブレーション画面の実装
        showError("手動キャリブレーション機能は準備中です")
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
            guard let self = self else { return }

            if success {
                // ステップ完了
                self.completeStep(self.currentCalibrationStep)

                // 次のステップに進む
                if currentIndex < steps.count - 1 {
                    self.currentCalibrationStep = steps[currentIndex + 1]
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.executeCalibrationSteps()
                    }
                } else {
                    // 全ステップ完了
                    self.completeCalibration()
                }
            } else {
                // ステップ失敗
                self.failCalibration()
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
                let success = Double.random(in: 0 ... 1) > 0.1  // 90%の成功率
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
            completedSteps: Array(completedSteps),
            duration: overallProgress * Double(SystemCalibrationStep.totalEstimatedDuration)
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
        return allCases.reduce(0) { $0 + $1.estimatedDuration }
    }

    static var minimumRequiredSteps: Int {
        return 4  // 最低限必要なステップ数
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

struct SystemCalibrationResult: Codable {
    let timestamp: Date
    let wasSuccessful: Bool
    let completedSteps: [SystemCalibrationStep]
    let duration: TimeInterval
}
