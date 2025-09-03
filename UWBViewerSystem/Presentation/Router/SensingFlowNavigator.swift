import Foundation
import SwiftUI

/// 新しいセンシングフローのナビゲーション管理
///
/// フロー: フロアマップ設定 → アンテナ設定 → ペアリング → キャリブレーション → センシング → データ閲覧
@MainActor
class SensingFlowNavigator: ObservableObject {
    @Published var currentStep: SensingFlowStep = .floorMapSetting
    @Published var flowProgress: Double = 0.0
    @Published var isFlowCompleted: Bool = false
    @Published var completedSteps: Set<SensingFlowStep> = []
    @Published var lastError: String?

    private let router: NavigationRouterModel

    init(router: NavigationRouterModel = .shared) {
        self.router = router
        loadFlowState()
    }

    /// 現在のフロー進行状況を更新
    private func updateProgress() {
        let totalSteps = SensingFlowStep.allCases.count
        let currentIndex = SensingFlowStep.allCases.firstIndex(of: currentStep) ?? 0
        flowProgress = Double(currentIndex) / Double(totalSteps - 1)
    }

    /// 次のステップに進む
    func proceedToNextStep() {
        // 現在のステップの完了条件をチェック
        guard canProceedFromCurrentStep() else {
            lastError = currentStep.incompletionError
            return
        }
        
        // 現在のステップを完了済みとしてマーク
        markStepAsCompleted(currentStep)
        
        guard let currentIndex = SensingFlowStep.allCases.firstIndex(of: currentStep),
            currentIndex < SensingFlowStep.allCases.count - 1
        else {
            completeFlow()
            return
        }

        let nextStep = SensingFlowStep.allCases[currentIndex + 1]
        currentStep = nextStep
        updateProgress()
        saveFlowState()

        // ルーターを使用して実際の画面遷移を実行
        router.navigateTo(nextStep.route)
    }

    /// 前のステップに戻る
    func goToPreviousStep() {
        guard let currentIndex = SensingFlowStep.allCases.firstIndex(of: currentStep),
            currentIndex > 0
        else {
            return
        }

        let previousStep = SensingFlowStep.allCases[currentIndex - 1]
        currentStep = previousStep
        updateProgress()

        router.navigateTo(previousStep.route)
    }

    /// 指定したステップに直接ジャンプ
    func jumpToStep(_ step: SensingFlowStep) {
        currentStep = step
        updateProgress()
        router.navigateTo(step.route)
    }

    /// フローを最初から開始
    func startNewFlow() {
        currentStep = .floorMapSetting
        isFlowCompleted = false
        updateProgress()
        router.navigateTo(currentStep.route)
    }

    /// フローを完了
    private func completeFlow() {
        markStepAsCompleted(currentStep)
        isFlowCompleted = true
        currentStep = .dataViewer
        updateProgress()
        saveFlowState()

        // センシング完了の処理をここに追加
        // 例: 完了通知、データ保存確認など
    }

    /// フローをリセット
    func resetFlow() {
        currentStep = .floorMapSetting
        isFlowCompleted = false
        flowProgress = 0.0
        completedSteps.removeAll()
        lastError = nil
        saveFlowState()
    }

    // MARK: - Step Completion Management

    /// 指定されたステップを完了済みとしてマーク
    func markStepAsCompleted(_ step: SensingFlowStep) {
        completedSteps.insert(step)
        saveFlowState()
    }

    /// 指定されたステップが完了済みかどうかを判定
    func isStepCompleted(_ step: SensingFlowStep) -> Bool {
        return completedSteps.contains(step)
    }

    /// 指定されたステップにアクセス可能かどうかを判定
    func canAccessStep(_ step: SensingFlowStep) -> Bool {
        guard let stepIndex = SensingFlowStep.allCases.firstIndex(of: step),
              let currentIndex = SensingFlowStep.allCases.firstIndex(of: currentStep) else {
            return false
        }

        // 現在のステップより前のステップには戻れる
        if stepIndex <= currentIndex {
            return true
        }

        // 次のステップには、前のステップがすべて完了している場合のみアクセス可能
        let previousSteps = Array(SensingFlowStep.allCases[0..<stepIndex])
        return previousSteps.allSatisfy { completedSteps.contains($0) }
    }

    /// 現在のステップから次のステップに進める条件を満たしているかをチェック
    private func canProceedFromCurrentStep() -> Bool {
        return currentStep.completionCondition()
    }

    // MARK: - Persistent State Management

    /// フローの状態を保存
    private func saveFlowState() {
        let encoder = JSONEncoder()
        
        if let currentStepData = try? encoder.encode(currentStep.rawValue) {
            UserDefaults.standard.set(currentStepData, forKey: "sensingFlowCurrentStep")
        }
        
        let completedStepsArray = Array(completedSteps.map { $0.rawValue })
        if let completedStepsData = try? encoder.encode(completedStepsArray) {
            UserDefaults.standard.set(completedStepsData, forKey: "sensingFlowCompletedSteps")
        }
        
        UserDefaults.standard.set(isFlowCompleted, forKey: "sensingFlowCompleted")
    }

    /// フローの状態を復元
    private func loadFlowState() {
        let decoder = JSONDecoder()
        
        // 現在のステップを復元
        if let currentStepData = UserDefaults.standard.data(forKey: "sensingFlowCurrentStep"),
           let currentStepRaw = try? decoder.decode(String.self, from: currentStepData),
           let savedStep = SensingFlowStep(rawValue: currentStepRaw) {
            currentStep = savedStep
        }
        
        // 完了済みステップを復元
        if let completedStepsData = UserDefaults.standard.data(forKey: "sensingFlowCompletedSteps"),
           let completedStepsArray = try? decoder.decode([String].self, from: completedStepsData) {
            completedSteps = Set(completedStepsArray.compactMap { SensingFlowStep(rawValue: $0) })
        }
        
        // フロー完了状態を復元
        isFlowCompleted = UserDefaults.standard.bool(forKey: "sensingFlowCompleted")
        
        updateProgress()
    }

    /// 現在のステップが最初のステップかどうか
    var isFirstStep: Bool {
        currentStep == SensingFlowStep.allCases.first
    }

    /// 現在のステップが最後のステップかどうか
    var isLastStep: Bool {
        currentStep == SensingFlowStep.allCases.last
    }
}

/// センシングフローのステップを定義
enum SensingFlowStep: String, CaseIterable {
    case floorMapSetting = "フロアマップ設定"
    case antennaConfiguration = "アンテナ設定"
    case devicePairing = "デバイスペアリング"
    case systemCalibration = "キャリブレーション"
    case sensingExecution = "センシング実行"
    case dataViewer = "データ閲覧"

    /// 各ステップに対応するRoute
    var route: Route {
        switch self {
        case .floorMapSetting:
            return .floorMapSetting
        case .antennaConfiguration:
            return .antennaConfiguration
        case .devicePairing:
            return .devicePairing
        case .systemCalibration:
            return .systemCalibration
        case .sensingExecution:
            return .sensingExecution
        case .dataViewer:
            return .sensingDataViewer
        }
    }

    /// ステップの説明文
    var description: String {
        switch self {
        case .floorMapSetting:
            return "センシングを行うフロアの地図を設定します"
        case .antennaConfiguration:
            return "アンテナの位置と向きを設定します"
        case .devicePairing:
            return "Androidデバイスとアンテナをペアリングします"
        case .systemCalibration:
            return "システムのキャリブレーションを実行します"
        case .sensingExecution:
            return "実際のUWBセンシングを実行します"
        case .dataViewer:
            return "収集したセンシングデータを確認します"
        }
    }

    /// ステップのアイコン名（SF Symbol）
    var iconName: String {
        switch self {
        case .floorMapSetting:
            return "map.fill"
        case .antennaConfiguration:
            return "antenna.radiowaves.left.and.right"
        case .devicePairing:
            return "link"
        case .systemCalibration:
            return "gear"
        case .sensingExecution:
            return "location.fill"
        case .dataViewer:
            return "chart.bar.fill"
        }
    }

    /// ステップの推定所要時間（分）
    var estimatedDuration: Int {
        switch self {
        case .floorMapSetting:
            return 5
        case .antennaConfiguration:
            return 10
        case .devicePairing:
            return 3
        case .systemCalibration:
            return 5
        case .sensingExecution:
            return 15
        case .dataViewer:
            return 5
        }
    }
    
    /// ステップが完了していない場合のエラーメッセージ
    var incompletionError: String {
        switch self {
        case .floorMapSetting:
            return "フロアマップの設定が完了していません。フロア名、建物名、寸法を入力してください。"
        case .antennaConfiguration:
            return "アンテナの位置と向きが設定されていません。すべてのアンテナを配置してください。"
        case .devicePairing:
            return "デバイスとアンテナのペアリングが完了していません。必要なデバイスをペアリングしてください。"
        case .systemCalibration:
            return "システムキャリブレーションが完了していません。キャリブレーションを実行してください。"
        case .sensingExecution:
            return "センシングが実行されていません。センシングセッションを開始してください。"
        case .dataViewer:
            return "データが確認されていません。"
        }
    }
    
    /// ステップの完了条件をチェックする関数
    func completionCondition() -> Bool {
        switch self {
        case .floorMapSetting:
            return checkFloorMapSettingCompletion()
        case .antennaConfiguration:
            return checkAntennaConfigurationCompletion()
        case .devicePairing:
            return checkDevicePairingCompletion()
        case .systemCalibration:
            return checkSystemCalibrationCompletion()
        case .sensingExecution:
            return checkSensingExecutionCompletion()
        case .dataViewer:
            return true // データ閲覧は常に完了とみなす
        }
    }
    
    // MARK: - Private Completion Check Functions
    
    private func checkFloorMapSettingCompletion() -> Bool {
        // UserDefaultsからフロアマップ設定を確認
        guard let data = UserDefaults.standard.data(forKey: "currentFloorMapInfo"),
              let _ = try? JSONDecoder().decode(FloorMapInfo.self, from: data) else {
            return false
        }
        return true
    }
    
    private func checkAntennaConfigurationCompletion() -> Bool {
        // UserDefaultsからアンテナ設定を確認
        guard let data = UserDefaults.standard.data(forKey: "configuredAntennaPositions"),
              let antennas = try? JSONDecoder().decode([AntennaPositionData].self, from: data) else {
            return false
        }
        
        // 最低2つのアンテナが必要
        return antennas.count >= 2 && antennas.allSatisfy { antenna in
            antenna.rotation >= 0 && antenna.rotation <= 360
        }
    }
    
    private func checkDevicePairingCompletion() -> Bool {
        // ペアリング済みデバイスを確認
        guard let data = UserDefaults.standard.data(forKey: "pairedDevices"),
              let devices = try? JSONDecoder().decode([String].self, from: data) else {
            return false
        }
        
        // 最低1つのデバイスがペアリング済み
        return devices.count >= 1
    }
    
    private func checkSystemCalibrationCompletion() -> Bool {
        // キャリブレーション結果を確認
        guard let data = UserDefaults.standard.data(forKey: "lastCalibrationResult"),
              let result = try? JSONDecoder().decode(SystemCalibrationResult.self, from: data) else {
            return false
        }
        
        // 1時間以内の成功したキャリブレーション
        return result.wasSuccessful && result.timestamp.timeIntervalSinceNow > -3600
    }
    
    private func checkSensingExecutionCompletion() -> Bool {
        // センシングセッション履歴を確認
        return UserDefaults.standard.bool(forKey: "hasExecutedSensingSession")
    }
}
