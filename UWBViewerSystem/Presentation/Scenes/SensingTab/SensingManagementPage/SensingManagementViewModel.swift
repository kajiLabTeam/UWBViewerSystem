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
                    connectionUsecase: ConnectionManagementUsecase(nearbyRepository: NearbyRepository())
                )
        self.realtimeDataUsecase = realtimeDataUsecase ?? RealtimeDataUsecase()
        initialize()
    }

    /// 実際のModelContextを使用してSwiftDataRepositoryを設定
    func setSwiftDataRepository(_ repository: SwiftDataRepositoryProtocol) {
        swiftDataRepository = repository
        loadAntennaDevices()
    }

    var canStartSensing: Bool {
        !sensingFileName.isEmpty && antennaDevices.filter { $0.connectionStatus == .connected }.count >= 3
    }

    var hasDataToView: Bool {
        dataPointCount > 0 || !realtimeData.isEmpty
    }

    var canProceedToNext: Bool {
        hasDataToView
    }

    func initialize() {
        loadAntennaDevices()
        setupObservers()
        generateDefaultFileName()
    }

    private func loadAntennaDevices() {
        // SwiftDataからアンテナ位置データを読み込み
        Task {
            do {
                let positions = try await swiftDataRepository.loadAntennaPositions()

                antennaDevices = positions.map { position in
                    AntennaDevice(
                        id: position.id,
                        name: position.antennaName,
                        connectionStatus: .connected,  // 実際の実装では実際のステータスを取得
                        rssi: Int.random(in: -60...(-40)),
                        batteryLevel: Int.random(in: 70...100),
                        dataRate: sampleRate,
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
                antennaDevices = []
            }
        }
    }

    private func setupObservers() {
        // 直接注入されたUsecaseからの状態を監視
        sensingControlUsecase.$isSensingControlActive
            .assign(to: &$isSensingActive)

        // RealtimeDataUsecaseからのリアルタイムデータを監視
        realtimeDataUsecase.$deviceRealtimeDataList
            .map { deviceDataList in
                // デバイスリストから最新のリアルタイムデータを抽出
                deviceDataList.compactMap { deviceData in
                    deviceData.latestData
                }
            }
            .assign(to: &$realtimeData)

        // データポイント数を監視
        $realtimeData
            .map { $0.count }
            .assign(to: &$dataPointCount)
    }

    private func generateDefaultFileName() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        sensingFileName = "sensing_\(formatter.string(from: Date()))"
    }

    func refreshAntennaStatus() {
        // 実際の実装ではデバイスから最新の状態を取得
        for index in antennaDevices.indices {
            antennaDevices[index].rssi = Int.random(in: -60...(-40))
            antennaDevices[index].batteryLevel = max(0, antennaDevices[index].batteryLevel - Int.random(in: 0...2))
            antennaDevices[index].lastUpdate = Date()

            // バッテリーレベルに基づいて接続状態を更新
            if antennaDevices[index].batteryLevel < 10 {
                antennaDevices[index].connectionStatus = .disconnected
            } else if antennaDevices[index].batteryLevel < 30 {
                antennaDevices[index].connectionStatus = .unstable
            } else {
                antennaDevices[index].connectionStatus = .connected
            }
        }
    }

    func startSensing() {
        guard canStartSensing else { return }

        currentFileName = sensingFileName
        sensingStartTime = Date()

        // 直接SensingControlUsecaseを使用してセンシング開始
        sensingControlUsecase.startRemoteSensing(fileName: currentFileName)

        // リアルタイム表示の準備
        print("🚀 センシング開始: UWBリアルタイムデータ受信準備完了")

        // 継続時間タイマーを開始
        startDurationTimer()

        // データレートを更新
        for index in antennaDevices.indices {
            antennaDevices[index].dataRate = sampleRate
        }

        // 次回のファイル名を生成
        generateDefaultFileName()
    }

    func stopSensing() {
        // 直接SensingControlUsecaseを使用してセンシング停止
        sensingControlUsecase.stopRemoteSensing()
        stopDurationTimer()

        // リアルタイムデータクリア
        print("🛑 センシング停止: リアルタイムデータをクリア")
        realtimeDataUsecase.clearAllRealtimeData()

        // センシング完了時の処理
        if autoSave {
            saveCurrentSession()
        }

        sensingStartTime = nil
        currentFileName = ""
        isPaused = false
    }

    func pauseSensing() {
        isPaused = true
        sensingControlUsecase.pauseRemoteSensing()
        stopDurationTimer()
    }

    func saveSensingSessionForFlow() -> Bool {
        // センシングセッションが実行されたかどうかを確認
        guard hasDataToView else {
            return false
        }

        // セッション実行フラグを保存
        preferenceRepository.setHasExecutedSensingSession(true)

        return true
    }

    func resumeSensing() {
        isPaused = false
        sensingControlUsecase.resumeRemoteSensing()
        startDurationTimer()
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateSensingDuration()
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func updateSensingDuration() {
        guard let startTime = sensingStartTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)

        let hours = Int(elapsed) / 3600
        let minutes = Int(elapsed) / 60 % 60
        let seconds = Int(elapsed) % 60

        sensingDuration = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func saveCurrentSession() {
        guard let startTime = sensingStartTime else { return }

        let session = SensingSession(
            id: UUID().uuidString,
            name: currentFileName,
            startTime: startTime,
            endTime: Date(),
            isActive: false
        )

        // SwiftDataに保存
        Task {
            do {
                try await swiftDataRepository.saveSensingSession(session)
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
        if rssi > -50 { return .green }
        if rssi > -70 { return .orange }
        return .red
    }

    var batteryColor: Color {
        if batteryLevel > 50 { return .green }
        if batteryLevel > 20 { return .orange }
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
