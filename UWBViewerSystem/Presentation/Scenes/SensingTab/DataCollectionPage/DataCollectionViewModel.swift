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

    // DI対応: 必要なUseCaseとRepositoryを直接注入
    private let sensingControlUsecase: SensingControlUsecase
    private let connectionUsecase: ConnectionManagementUsecase
    private let realtimeDataUsecase: RealtimeDataUsecase
    private let preferenceRepository: PreferenceRepositoryProtocol

    init(
        sensingControlUsecase: SensingControlUsecase? = nil,
        connectionUsecase: ConnectionManagementUsecase? = nil,
        realtimeDataUsecase: RealtimeDataUsecase? = nil,
        preferenceRepository: PreferenceRepositoryProtocol = PreferenceRepository()
    ) {
        let defaultConnectionUsecase =
            connectionUsecase ?? ConnectionManagementUsecase.shared

        self.connectionUsecase = defaultConnectionUsecase
        self.sensingControlUsecase =
            sensingControlUsecase ?? SensingControlUsecase(connectionUsecase: defaultConnectionUsecase)
        self.realtimeDataUsecase = realtimeDataUsecase ?? RealtimeDataUsecase()
        self.preferenceRepository = preferenceRepository

        self.loadRecentSessions()
        self.setupObservers()
    }

    /// 従来との互換性を保つための静的インスタンス
    static let shared = DataCollectionViewModel()

    deinit {
        sensingTimer?.invalidate()
    }

    private func setupObservers() {
        // 直接注入されたUsecaseからの状態を監視
        self.sensingControlUsecase.$isSensingControlActive
            .assign(to: &self.$isSensingActive)

        self.sensingControlUsecase.$sensingStatus
            .assign(to: &self.$sensingStatus)

        self.connectionUsecase.$connectedEndpoints
            .map { $0.count }
            .assign(to: &self.$connectedDeviceCount)

        self.realtimeDataUsecase.$deviceRealtimeDataList
            .assign(to: &self.$deviceRealtimeDataList)

        self.realtimeDataUsecase.$deviceRealtimeDataList
            .map { $0.count }
            .assign(to: &self.$dataPointCount)
    }

    // MARK: - Sensing Control

    func startSensing(fileName: String) {
        guard !fileName.isEmpty else { return }

        self.currentFileName = fileName
        self.currentSession = SensingSession(name: fileName, dataPoints: 0)
        self.startTime = Date()

        // 直接SensingControlUsecaseを使用してセンシング開始
        self.sensingControlUsecase.startRemoteSensing(fileName: fileName)

        // タイマー開始
        self.startTimer()

        self.sensingStatus = "センシング実行中"
        self.isSensingActive = true
    }

    func stopSensing() {
        // 直接SensingControlUsecaseを使用してセンシング停止
        self.sensingControlUsecase.stopRemoteSensing()

        // セッションを完了
        if let session = currentSession, let _ = startTime {
            let endTime = Date()
            let completedSession = SensingSession(
                id: session.id,
                name: session.name,
                startTime: session.startTime,
                endTime: endTime,
                isActive: false,
                dataPoints: self.dataPointCount,
                createdAt: session.createdAt
            )

            // 最近のセッションに追加
            self.recentSessions.insert(completedSession, at: 0)
            if self.recentSessions.count > 10 {
                self.recentSessions.removeLast()
            }

            self.saveRecentSessions()
        }

        // 状態をリセット
        self.stopTimer()
        self.currentSession = nil
        self.currentFileName = ""
        self.sensingStatus = "センシング停止中"
        self.isSensingActive = false
    }

    func clearRealtimeData() {
        self.realtimeDataUsecase.clearAllRealtimeData()
    }

    // MARK: - Timer Management

    private func startTimer() {
        self.sensingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsedTime()
            }
        }
    }

    private func stopTimer() {
        self.sensingTimer?.invalidate()
        self.sensingTimer = nil
        self.elapsedTime = "00:00"
    }

    private func updateElapsedTime() {
        guard let startTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        self.elapsedTime = String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Data Persistence

    private func saveRecentSessions() {
        do {
            try self.preferenceRepository.setData(self.recentSessions, forKey: "RecentSensingSessions")
        } catch {
            print("❌ セッションデータの保存に失敗: \(error)")
        }
    }

    private func loadRecentSessions() {
        if let sessions = preferenceRepository.getData([SensingSession].self, forKey: "RecentSensingSessions") {
            self.recentSessions = sessions
        }
    }
}
