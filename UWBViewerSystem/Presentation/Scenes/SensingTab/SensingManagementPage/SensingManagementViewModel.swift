import Combine
import Foundation
import SwiftUI

@MainActor
class SensingManagementViewModel: ObservableObject {
    @Published var antennaDevices: [AntennaDevice] = []
    @Published var realtimeData: [RealtimeData] = []
    @Published var isSensingActive = false
    @Published var isPaused = false
    @Published var sensingDuration = "00:00:00"
    @Published var dataPointCount = 0
    @Published var currentFileName = ""
    @Published var sensingFileName = ""
    @Published var sampleRate = 10
    @Published var autoSave = true

    // MARK: - Connection Recovery State

    /// 接続復旧画面を表示するかどうか
    @Published var showConnectionRecovery: Bool = false

    /// 再接続中かどうか（UIに表示用）
    @Published var isAttemptingReconnect: Bool = false

    /// 再接続試行回数
    @Published var reconnectAttemptCount: Int = 0

    /// 切断前の状態を保存
    private var wasSensingBeforeDisconnect: Bool = false
    private var wasPausedBeforeDisconnect: Bool = false
    private var sensingStartTimeBeforeDisconnect: Date?

    /// 最大再接続試行回数
    private let maxAutoReconnectAttempts: Int = 3

    /// 接続監視が設定済みかどうか
    private var isConnectionMonitoringSetup: Bool = false

    // DI対応: 必要なUseCaseとRepositoryを直接注入
    private let sensingControlUsecase: SensingControlUsecase
    private let realtimeDataUsecase: RealtimeDataUsecase
    private let preferenceRepository: PreferenceRepositoryProtocol
    private var swiftDataRepository: SwiftDataRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()
    private var sensingStartTime: Date?
    private var durationTimer: Timer?

    init(
        swiftDataRepository: SwiftDataRepositoryProtocol,
        sensingControlUsecase: SensingControlUsecase? = nil,
        realtimeDataUsecase: RealtimeDataUsecase? = nil,
        preferenceRepository: PreferenceRepositoryProtocol = PreferenceRepository()
    ) {
        self.swiftDataRepository = swiftDataRepository
        self.preferenceRepository = preferenceRepository
        self.sensingControlUsecase =
            sensingControlUsecase
                ?? SensingControlUsecase(
                    connectionUsecase: ConnectionManagementUsecase.shared
                )
        self.realtimeDataUsecase = realtimeDataUsecase ?? RealtimeDataUsecase()
        self.initialize()
    }

    /// 実際のModelContextを使用してSwiftDataRepositoryを設定
    func setSwiftDataRepository(_ repository: SwiftDataRepositoryProtocol) {
        self.swiftDataRepository = repository
        self.loadAntennaDevices()
    }

    var canStartSensing: Bool {
        !self.sensingFileName.isEmpty && self.antennaDevices.filter { $0.connectionStatus == .connected }.count >= 3
    }

    var hasDataToView: Bool {
        self.dataPointCount > 0 || !self.realtimeData.isEmpty
    }

    var canProceedToNext: Bool {
        self.hasDataToView
    }

    func initialize() {
        self.loadAntennaDevices()
        self.setupObservers()
        self.generateDefaultFileName()
    }

    private func loadAntennaDevices() {
        // SwiftDataからアンテナ位置データを読み込み
        Task {
            do {
                let positions = try await swiftDataRepository.loadAntennaPositions()

                self.antennaDevices = positions.map { position in
                    AntennaDevice(
                        id: position.id,
                        name: position.antennaName,
                        connectionStatus: .connected,  // 実際の実装では実際のステータスを取得
                        rssi: Int.random(in: -60...(-40)),
                        batteryLevel: Int.random(in: 70...100),
                        dataRate: self.sampleRate,
                        position: RealWorldPosition(
                            x: position.position.x,
                            y: position.position.y,
                            z: position.position.z
                        ),
                        lastUpdate: Date()
                    )
                }
            } catch {
                print("Error loading antenna positions: \(error)")
                self.antennaDevices = []
            }
        }
    }

    private func setupObservers() {
        // 直接注入されたUsecaseからの状態を監視
        self.sensingControlUsecase.$isSensingControlActive
            .assign(to: &self.$isSensingActive)

        // RealtimeDataUsecaseからのリアルタイムデータを監視
        self.realtimeDataUsecase.$deviceRealtimeDataList
            .map { deviceDataList in
                // デバイスリストから最新のリアルタイムデータを抽出
                deviceDataList.compactMap { deviceData in
                    deviceData.latestData
                }
            }
            .assign(to: &self.$realtimeData)

        // データポイント数を監視
        self.$realtimeData
            .map { $0.count }
            .assign(to: &self.$dataPointCount)

        // 接続エラー状態を監視
        self.setupConnectionErrorObserver()
    }

    // MARK: - Connection Recovery

    private func setupConnectionErrorObserver() {
        // 既に設定済みの場合はスキップ（重複実行防止）
        guard !self.isConnectionMonitoringSetup else {
            print("ℹ️ SensingManagement: 接続監視は既に設定済みです")
            return
        }
        self.isConnectionMonitoringSetup = true

        let connectionUsecase = ConnectionManagementUsecase.shared

        // 初期状態をチェック：既に接続エラーがある場合や、接続デバイスがない場合
        Task { @MainActor in
            // 少し待機して画面遷移を完了させる
            try? await Task.sleep(nanoseconds: 500_000_000)

            // 既に再接続中の場合はスキップ
            guard !self.isAttemptingReconnect else {
                print("ℹ️ SensingManagement: 既に再接続試行中のためスキップ")
                return
            }

            // 接続エラーがあるか、接続デバイスがない場合は再接続を試みる
            if connectionUsecase.hasConnectionError {
                print("🔴 SensingManagement: 初期化時に既存の接続エラーを検知")
                self.handleConnectionError()
            } else if !connectionUsecase.hasConnectedDevices() {
                print("🔴 SensingManagement: 初期化時に接続デバイスなしを検知")
                connectionUsecase.hasConnectionError = true
                self.handleConnectionError()
            }
        }

        // 継続的な接続エラー監視
        connectionUsecase.$hasConnectionError
            .dropFirst()  // 初期値をスキップ（上で処理済み）
            .sink { [weak self] hasError in
                guard let self else { return }
                if hasError {
                    print("🔴 SensingManagement: 接続エラーを検知")
                    self.handleConnectionError()
                }
            }
            .store(in: &self.cancellables)
    }

    /// 接続エラー時の処理
    private func handleConnectionError() {
        // 既に再接続中の場合はスキップ
        guard !self.isAttemptingReconnect else {
            print("ℹ️ SensingManagement: 既に再接続試行中のためスキップ")
            return
        }

        // センシング中の場合は状態を保存
        if self.isSensingActive {
            print("⚠️ センシング中に接続が切断されました")
            self.wasSensingBeforeDisconnect = true
            self.wasPausedBeforeDisconnect = self.isPaused
            self.sensingStartTimeBeforeDisconnect = self.sensingStartTime

            // センシングを一時停止（データ保持）
            if !self.isPaused {
                self.pauseSensing()
            }
        } else {
            self.wasSensingBeforeDisconnect = false
        }

        // 自動再接続を開始
        Task {
            await self.attemptAutoReconnect()
        }
    }

    /// 自動再接続を試行
    private func attemptAutoReconnect() async {
        self.isAttemptingReconnect = true
        self.reconnectAttemptCount = 0

        let connectionUsecase = ConnectionManagementUsecase.shared

        // 自動再接続中フラグを設定（アラート抑制用）
        connectionUsecase.isAutoReconnecting = true

        for attempt in 1...self.maxAutoReconnectAttempts {
            self.reconnectAttemptCount = attempt
            print("🔄 SensingManagement: 再接続試行 \(attempt)/\(self.maxAutoReconnectAttempts)")

            // 既存の接続をリセット
            connectionUsecase.resetAll()

            // 少し待機
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            // エラーフラグをクリアして再接続開始
            connectionUsecase.hasConnectionError = false
            connectionUsecase.lastDisconnectedDevice = nil
            connectionUsecase.startAdvertising()
            connectionUsecase.startDiscovery()

            // 接続確立を待機（最大8秒）
            for _ in 0..<16 {
                try? await Task.sleep(nanoseconds: 500_000_000)

                if connectionUsecase.hasConnectedDevices() {
                    print("✅ SensingManagement: 再接続成功")
                    self.isAttemptingReconnect = false
                    connectionUsecase.isAutoReconnecting = false

                    // センシング再開
                    await self.handleReconnectionSuccess()
                    return
                }
            }

            // バックオフ：次の試行まで待機時間を増やす
            let backoffSeconds = attempt * 2
            print("⏳ 次の再接続試行まで \(backoffSeconds) 秒待機...")
            try? await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
        }

        // すべての試行が失敗
        self.isAttemptingReconnect = false
        connectionUsecase.isAutoReconnecting = false
        self.showConnectionRecovery = true
        print("❌ SensingManagement: 自動再接続失敗")
    }

    /// 再接続成功時の処理
    private func handleReconnectionSuccess() async {
        print("🔄 SensingManagement: センシング状態を復元中...")

        // センシング中だった場合は再開
        if self.wasSensingBeforeDisconnect {
            // センシング開始時刻を復元
            if let savedStartTime = self.sensingStartTimeBeforeDisconnect {
                self.sensingStartTime = savedStartTime
            }

            // 少し待機してから再開
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            if self.wasPausedBeforeDisconnect {
                // 一時停止状態を維持
                print("⏸️ センシングは一時停止状態を維持")
            } else {
                // センシングを再開
                self.resumeSensing()
                print("▶️ センシングを再開しました")
            }
        }

        // 状態をクリア
        self.wasSensingBeforeDisconnect = false
        self.wasPausedBeforeDisconnect = false
        self.sensingStartTimeBeforeDisconnect = nil
    }

    /// 手動再接続用：保存状態をクリア
    func clearSavedState() {
        self.wasSensingBeforeDisconnect = false
        self.wasPausedBeforeDisconnect = false
        self.sensingStartTimeBeforeDisconnect = nil
        self.isAttemptingReconnect = false
    }

    private func generateDefaultFileName() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        self.sensingFileName = "sensing_\(formatter.string(from: Date()))"
    }

    func refreshAntennaStatus() {
        // 実際の実装ではデバイスから最新の状態を取得
        for index in self.antennaDevices.indices {
            self.antennaDevices[index].rssi = Int.random(in: -60...(-40))
            self.antennaDevices[index].batteryLevel = max(
                0, self.antennaDevices[index].batteryLevel - Int.random(in: 0...2))
            self.antennaDevices[index].lastUpdate = Date()

            // バッテリーレベルに基づいて接続状態を更新
            if self.antennaDevices[index].batteryLevel < 10 {
                self.antennaDevices[index].connectionStatus = .disconnected
            } else if self.antennaDevices[index].batteryLevel < 30 {
                self.antennaDevices[index].connectionStatus = .unstable
            } else {
                self.antennaDevices[index].connectionStatus = .connected
            }
        }
    }

    func startSensing() {
        guard self.canStartSensing else { return }

        self.currentFileName = self.sensingFileName
        self.sensingStartTime = Date()

        // 直接SensingControlUsecaseを使用してセンシング開始
        self.sensingControlUsecase.startRemoteSensing(fileName: self.currentFileName)

        // リアルタイム表示の準備
        print("🚀 センシング開始: UWBリアルタイムデータ受信準備完了")

        // 継続時間タイマーを開始
        self.startDurationTimer()

        // データレートを更新
        for index in self.antennaDevices.indices {
            self.antennaDevices[index].dataRate = self.sampleRate
        }

        // 次回のファイル名を生成
        self.generateDefaultFileName()
    }

    func stopSensing() {
        // 直接SensingControlUsecaseを使用してセンシング停止
        self.sensingControlUsecase.stopRemoteSensing()
        self.stopDurationTimer()

        // リアルタイムデータクリア
        print("🛑 センシング停止: リアルタイムデータをクリア")
        self.realtimeDataUsecase.clearAllRealtimeData()

        // センシング完了時の処理
        if self.autoSave {
            self.saveCurrentSession()
        }

        self.sensingStartTime = nil
        self.currentFileName = ""
        self.isPaused = false
    }

    func pauseSensing() {
        self.isPaused = true
        self.sensingControlUsecase.pauseRemoteSensing()
        self.stopDurationTimer()
    }

    func saveSensingSessionForFlow() -> Bool {
        // センシングセッションが実行されたかどうかを確認
        guard self.hasDataToView else {
            return false
        }

        // セッション実行フラグを保存
        self.preferenceRepository.setHasExecutedSensingSession(true)

        return true
    }

    func resumeSensing() {
        self.isPaused = false
        self.sensingControlUsecase.resumeRemoteSensing()
        self.startDurationTimer()
    }

    private func startDurationTimer() {
        self.durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateSensingDuration()
            }
        }
    }

    private func stopDurationTimer() {
        self.durationTimer?.invalidate()
        self.durationTimer = nil
    }

    private func updateSensingDuration() {
        guard let startTime = sensingStartTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)

        let hours = Int(elapsed) / 3600
        let minutes = Int(elapsed) / 60 % 60
        let seconds = Int(elapsed) % 60

        self.sensingDuration = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func saveCurrentSession() {
        guard let startTime = sensingStartTime else { return }

        let session = SensingSession(
            id: UUID().uuidString,
            name: self.currentFileName,
            startTime: startTime,
            endTime: Date(),
            isActive: false
        )

        // SwiftDataに保存
        Task {
            do {
                try await self.swiftDataRepository.saveSensingSession(session)
            } catch {
                print("Error saving sensing session: \(error)")
            }
        }
    }
}

// MARK: - Dummy Repository for Initialization

// PairingSettingViewModelと同じDummySwiftDataRepositoryを使用
extension SensingManagementViewModel {
    /// テスト用またはプレースホルダー用の初期化
    convenience init() {
        self.init(
            swiftDataRepository: DummySwiftDataRepository(),
            sensingControlUsecase: nil,
            realtimeDataUsecase: nil
        )
    }
}

// MARK: - Data Models

struct AntennaDevice: Identifiable {
    let id: String
    let name: String
    var connectionStatus: DeviceConnectionStatus
    var rssi: Int
    var batteryLevel: Int
    var dataRate: Int
    let position: RealWorldPosition
    var lastUpdate: Date?

    var rssiColor: Color {
        if self.rssi > -50 { return .green }
        if self.rssi > -70 { return .orange }
        return .red
    }

    var batteryColor: Color {
        if self.batteryLevel > 50 { return .green }
        if self.batteryLevel > 20 { return .orange }
        return .red
    }
}

enum DeviceConnectionStatus {
    case connected
    case disconnected
    case unstable

    var displayName: String {
        switch self {
        case .connected: return "接続済み"
        case .disconnected: return "未接続"
        case .unstable: return "不安定"
        }
    }

    var color: Color {
        switch self {
        case .connected: return .green
        case .disconnected: return .red
        case .unstable: return .orange
        }
    }
}

struct RealtimeDataPoint: Identifiable {
    let id: String
    let deviceName: String
    let distance: Double
    let rssi: Int
    let timestamp: Date
}
