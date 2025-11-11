import Foundation
import SwiftUI

// MARK: - Data Models for Flow Validation

// FloorMapInfoとSystemCalibrationResultは各ViewModelで定義済みのため削除

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

    private var router: NavigationRouterModel
    private let preferenceRepository: PreferenceRepositoryProtocol

    init(
        router: NavigationRouterModel? = nil,
        preferenceRepository: PreferenceRepositoryProtocol = PreferenceRepository()
    ) {
        self.router = router ?? NavigationRouterModel()
        self.preferenceRepository = preferenceRepository
        self.loadFlowState()
    }

    /// 外部からRouterを設定するメソッド
    func setRouter(_ router: NavigationRouterModel) {
        self.router = router
    }

    /// 現在のフロー進行状況を更新
    private func updateProgress() {
        let totalSteps = SensingFlowStep.allCases.count
        let currentIndex = SensingFlowStep.allCases.firstIndex(of: self.currentStep) ?? 0
        self.flowProgress = Double(currentIndex) / Double(totalSteps - 1)
    }

    /// 次のステップに進む
    func proceedToNextStep() {
        print("🚀 proceedToNextStep: Current step = \(self.currentStep.rawValue)")

        // 現在のステップの完了条件をチェック
        guard self.canProceedFromCurrentStep() else {
            self.lastError = self.currentStep.incompletionError
            print("❌ proceedToNextStep: Cannot proceed - \(self.currentStep.incompletionError)")
            return
        }

        print("✅ proceedToNextStep: Step completion check passed")

        // 現在のステップを完了済みとしてマーク
        self.markStepAsCompleted(self.currentStep)

        guard let currentIndex = SensingFlowStep.allCases.firstIndex(of: currentStep),
              currentIndex < SensingFlowStep.allCases.count - 1
        else {
            print("🎯 proceedToNextStep: Flow completed!")
            self.completeFlow()
            return
        }

        let nextStep = SensingFlowStep.allCases[currentIndex + 1]
        print("➡️ proceedToNextStep: Moving to next step = \(nextStep.rawValue)")

        // キャリブレーションステップをスキップする場合
        if nextStep == .systemCalibration && UserDefaults.standard.bool(forKey: "skipCalibration") {
            print("🔧 キャリブレーションスキップ設定が有効: キャリブレーションステップをスキップします")
            self.currentStep = nextStep
            self.markStepAsCompleted(nextStep)
            self.updateProgress()
            self.saveFlowState()

            // 再帰的に次のステップ（センシング実行）に進む
            self.proceedToNextStep()
            return
        }

        self.currentStep = nextStep
        self.updateProgress()
        self.saveFlowState()

        // ルーターを使用して実際の画面遷移を実行
        print("🔄 proceedToNextStep: Navigating to route = \(nextStep.route)")
        self.router.navigateTo(nextStep.route)
        print("✅ proceedToNextStep: Navigation completed")
    }

    /// 前のステップに戻る
    func goToPreviousStep() {
        guard let currentIndex = SensingFlowStep.allCases.firstIndex(of: currentStep),
              currentIndex > 0
        else {
            return
        }

        let previousStep = SensingFlowStep.allCases[currentIndex - 1]
        self.currentStep = previousStep
        self.updateProgress()

        self.router.navigateTo(previousStep.route)
    }

    /// 指定したステップに直接ジャンプ
    func jumpToStep(_ step: SensingFlowStep) {
        self.currentStep = step
        self.updateProgress()
        self.router.navigateTo(step.route)
    }

    /// フローを最初から開始
    func startNewFlow() {
        self.currentStep = .floorMapSetting
        self.isFlowCompleted = false
        self.updateProgress()
        self.router.navigateTo(self.currentStep.route)
    }

    /// フローを完了
    func completeFlow() {
        self.markStepAsCompleted(self.currentStep)
        self.isFlowCompleted = true
        self.currentStep = .dataViewer
        self.updateProgress()
        self.saveFlowState()

        // センシング完了の処理をここに追加
        // 例: 完了通知、データ保存確認など
    }

    /// フローをリセット
    func resetFlow() {
        self.currentStep = .floorMapSetting
        self.isFlowCompleted = false
        self.flowProgress = 0.0
        self.completedSteps.removeAll()
        self.lastError = nil
        self.saveFlowState()
    }

    // MARK: - Step Completion Management

    /// 指定されたステップを完了済みとしてマーク
    func markStepAsCompleted(_ step: SensingFlowStep) {
        self.completedSteps.insert(step)
        self.saveFlowState()
    }

    /// 指定されたステップが完了済みかどうかを判定
    func isStepCompleted(_ step: SensingFlowStep) -> Bool {
        self.completedSteps.contains(step)
    }

    /// 指定されたステップにアクセス可能かどうかを判定
    func canAccessStep(_ step: SensingFlowStep) -> Bool {
        guard let stepIndex = SensingFlowStep.allCases.firstIndex(of: step),
              let currentIndex = SensingFlowStep.allCases.firstIndex(of: currentStep)
        else {
            return false
        }

        // 現在のステップより前のステップには戻れる
        if stepIndex <= currentIndex {
            return true
        }

        // 次のステップには、前のステップがすべて完了している場合のみアクセス可能
        let previousSteps = Array(SensingFlowStep.allCases[0..<stepIndex])
        return previousSteps.allSatisfy { self.completedSteps.contains($0) }
    }

    /// 現在のステップから次のステップに進める条件を満たしているかをチェック
    private func canProceedFromCurrentStep() -> Bool {
        self.currentStep.completionCondition()
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

        UserDefaults.standard.set(self.isFlowCompleted, forKey: "sensingFlowCompleted")
    }

    /// フローの状態を復元
    private func loadFlowState() {
        let decoder = JSONDecoder()

        // 現在のステップを復元
        if let currentStepData = UserDefaults.standard.data(forKey: "sensingFlowCurrentStep"),
           let currentStepRaw = try? decoder.decode(String.self, from: currentStepData),
           let savedStep = SensingFlowStep(rawValue: currentStepRaw)
        {
            self.currentStep = savedStep
        }

        // 完了済みステップを復元
        if let completedStepsData = UserDefaults.standard.data(forKey: "sensingFlowCompletedSteps"),
           let completedStepsArray = try? decoder.decode([String].self, from: completedStepsData)
        {
            self.completedSteps = Set(completedStepsArray.compactMap { SensingFlowStep(rawValue: $0) })
        }

        // フロー完了状態を復元
        self.isFlowCompleted = UserDefaults.standard.bool(forKey: "sensingFlowCompleted")

        self.updateProgress()
    }

    /// 現在のステップが最初のステップかどうか
    var isFirstStep: Bool {
        self.currentStep == SensingFlowStep.allCases.first
    }

    /// 現在のステップが最後のステップかどうか
    var isLastStep: Bool {
        self.currentStep == SensingFlowStep.allCases.last
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
            return .pairingSettingPage
        case .systemCalibration:
            return .systemCalibration
        case .sensingExecution:
            return .dataCollectionPage
        case .dataViewer:
            return .dataDisplayPage
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
            return self.checkFloorMapSettingCompletion()
        case .antennaConfiguration:
            return self.checkAntennaConfigurationCompletion()
        case .devicePairing:
            return self.checkDevicePairingCompletion()
        case .systemCalibration:
            return self.checkSystemCalibrationCompletion()
        case .sensingExecution:
            return self.checkSensingExecutionCompletion()
        case .dataViewer:
            return true  // データ閲覧は常に完了とみなす
        }
    }

    // MARK: - Private Completion Check Functions

    private func checkFloorMapSettingCompletion() -> Bool {
        // UserDefaultsからフロアマップ設定を確認
        guard let data = UserDefaults.standard.data(forKey: "currentFloorMapInfo"),
              let _ = try? JSONDecoder().decode(FloorMapInfo.self, from: data)
        else {
            return false
        }
        return true
    }

    private func checkAntennaConfigurationCompletion() -> Bool {
        // UserDefaultsからアンテナ設定を確認
        guard let data = UserDefaults.standard.data(forKey: "configuredAntennaPositions"),
              let antennas = try? JSONDecoder().decode([AntennaPositionData].self, from: data)
        else {
            print("❌ checkAntennaConfigurationCompletion: No antenna position data found")
            return false
        }

        print("📍 checkAntennaConfigurationCompletion: Found \(antennas.count) antennas")

        // デフォルト位置(50,50)以外に配置されたアンテナを確認
        let positionedAntennas = antennas.filter { antenna in
            antenna.position.x != 50.0 || antenna.position.y != 50.0
        }

        print("📍 checkAntennaConfigurationCompletion: \(positionedAntennas.count) antennas are positioned")

        // 最低2つのアンテナが配置されている必要がある
        let hasEnoughAntennas = positionedAntennas.count >= 2

        if hasEnoughAntennas {
            print("✅ checkAntennaConfigurationCompletion: Antenna configuration is complete")
        } else {
            print(
                "❌ checkAntennaConfigurationCompletion: Need at least 2 positioned antennas, got \(positionedAntennas.count)"
            )
        }

        return hasEnoughAntennas
    }

    private func checkDevicePairingCompletion() -> Bool {
        // ペアリング済みデバイスを確認
        guard let data = UserDefaults.standard.data(forKey: "pairedDevices"),
              let devices = try? JSONDecoder().decode([String].self, from: data)
        else {
            return false
        }

        // 最低1つのデバイスがペアリング済み
        return devices.count >= 1
    }

    private func checkSystemCalibrationCompletion() -> Bool {
        // デバッグ設定でキャリブレーションをスキップする場合
        if UserDefaults.standard.bool(forKey: "skipCalibration") {
            print("🔧 キャリブレーションスキップ設定が有効: 自動的に完了とみなします")
            return true
        }

        // キャリブレーション結果を確認
        guard let data = UserDefaults.standard.data(forKey: "lastCalibrationResult"),
              let result = try? JSONDecoder().decode(SystemCalibrationResult.self, from: data)
        else {
            return false
        }

        // 1時間以内の成功したキャリブレーション
        return result.wasSuccessful && result.timestamp.timeIntervalSinceNow > -3600
    }

    private func checkSensingExecutionCompletion() -> Bool {
        // センシングセッション履歴を確認
        UserDefaults.standard.bool(forKey: "hasExecutedSensingSession")
    }
}
