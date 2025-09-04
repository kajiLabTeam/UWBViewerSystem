import Combine
import Foundation
import SwiftUI

// MARK: - ViewModel

@MainActor
class DataCollectionViewModel: ObservableObject {
    @Published var isSensingActive = false
    @Published var sensingStatus = "センシング停止中"
    @Published var currentFileName = ""
    @Published var dataPointCount = 0
    @Published var connectedDeviceCount = 0
    @Published var elapsedTime = "00:00"
    @Published var recentSessions: [SensingSession] = []
    @Published var deviceRealtimeDataList: [DeviceRealtimeData] = []

    private var currentSession: SensingSession?
    private var sensingTimer: Timer?
    private var startTime: Date?
    private var cancellables = Set<AnyCancellable>()

    // DI対応: 必要なUseCaseを直接注入
    private let sensingControlUsecase: SensingControlUsecase
    private let connectionUsecase: ConnectionManagementUsecase
    private let realtimeDataUsecase: RealtimeDataUsecase

    init(
        sensingControlUsecase: SensingControlUsecase? = nil,
        connectionUsecase: ConnectionManagementUsecase? = nil,
        realtimeDataUsecase: RealtimeDataUsecase? = nil
    ) {
        let nearbyRepository = NearbyRepository()
        let defaultConnectionUsecase =
            connectionUsecase ?? ConnectionManagementUsecase(nearbyRepository: nearbyRepository)

        self.connectionUsecase = defaultConnectionUsecase
        self.sensingControlUsecase =
            sensingControlUsecase ?? SensingControlUsecase(connectionUsecase: defaultConnectionUsecase)
        self.realtimeDataUsecase = realtimeDataUsecase ?? RealtimeDataUsecase()

        loadRecentSessions()
        setupObservers()
    }

    /// 従来との互換性を保つための静的インスタンス
    static let shared = DataCollectionViewModel()

    deinit {
        sensingTimer?.invalidate()
    }

    private func setupObservers() {
        // 直接注入されたUsecaseからの状態を監視
        sensingControlUsecase.$isSensingControlActive
            .assign(to: &$isSensingActive)

        sensingControlUsecase.$sensingStatus
            .assign(to: &$sensingStatus)

        connectionUsecase.$connectedEndpoints
            .map { $0.count }
            .assign(to: &$connectedDeviceCount)

        realtimeDataUsecase.$deviceRealtimeDataList
            .assign(to: &$deviceRealtimeDataList)

        realtimeDataUsecase.$deviceRealtimeDataList
            .map { $0.count }
            .assign(to: &$dataPointCount)
    }

    // MARK: - Sensing Control

    func startSensing(fileName: String) {
        guard !fileName.isEmpty else { return }

        currentFileName = fileName
        currentSession = SensingSession(name: fileName, dataPoints: 0)
        startTime = Date()

        // 直接SensingControlUsecaseを使用してセンシング開始
        sensingControlUsecase.startRemoteSensing(fileName: fileName)

        // タイマー開始
        startTimer()

        sensingStatus = "センシング実行中"
        isSensingActive = true
    }

    func stopSensing() {
        // 直接SensingControlUsecaseを使用してセンシング停止
        sensingControlUsecase.stopRemoteSensing()

        // セッションを完了
        if let session = currentSession, let _ = startTime {
            let endTime = Date()
            let completedSession = SensingSession(
                id: session.id,
                name: session.name,
                startTime: session.startTime,
                endTime: endTime,
                isActive: false,
                dataPoints: dataPointCount,
                createdAt: session.createdAt
            )

            // 最近のセッションに追加
            recentSessions.insert(completedSession, at: 0)
            if recentSessions.count > 10 {
                recentSessions.removeLast()
            }

            saveRecentSessions()
        }

        // 状態をリセット
        stopTimer()
        currentSession = nil
        currentFileName = ""
        sensingStatus = "センシング停止中"
        isSensingActive = false
    }

    func clearRealtimeData() {
        realtimeDataUsecase.clearAllRealtimeData()
    }

    // MARK: - Timer Management

    private func startTimer() {
        sensingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsedTime()
            }
        }
    }

    private func stopTimer() {
        sensingTimer?.invalidate()
        sensingTimer = nil
        elapsedTime = "00:00"
    }

    private func updateElapsedTime() {
        guard let startTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        elapsedTime = String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Data Persistence

    private func saveRecentSessions() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(recentSessions) {
            UserDefaults.standard.set(encoded, forKey: "RecentSensingSessions")
        }
    }

    private func loadRecentSessions() {
        if let data = UserDefaults.standard.data(forKey: "RecentSensingSessions") {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode([SensingSession].self, from: data) {
                recentSessions = decoded
            }
        }
    }
}
