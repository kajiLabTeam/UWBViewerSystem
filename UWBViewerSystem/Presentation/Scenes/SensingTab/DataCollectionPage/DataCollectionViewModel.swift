import Combine
import Foundation
import SwiftData
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

    // フロアマップ表示用
    @Published var currentFloorMapInfo: FloorMapInfo?
    @Published var allAntennaPositions: [AntennaPositionData] = []
    @Published var globalCoordinates: [String: Point3D] = [:]

    #if canImport(UIKit)
        #if os(iOS)
            @Published var floorMapImage: UIImage?
        #endif
    #endif

    #if os(macOS)
        @Published var floorMapImage: NSImage?
    #endif

    private var currentSession: SensingSession?
    private var sensingTimer: Timer?
    private var startTime: Date?
    private var cancellables = Set<AnyCancellable>()

    // DI対応: 必要なUseCaseとRepositoryを直接注入
    private var sensingControlUsecase: SensingControlUsecase
    private let connectionUsecase: ConnectionManagementUsecase
    private let realtimeDataUsecase: RealtimeDataUsecase
    private let preferenceRepository: PreferenceRepositoryProtocol
    private var swiftDataRepository: SwiftDataRepository?

    init(
        sensingControlUsecase: SensingControlUsecase? = nil,
        connectionUsecase: ConnectionManagementUsecase? = nil,
        realtimeDataUsecase: RealtimeDataUsecase? = nil,
        preferenceRepository: PreferenceRepositoryProtocol = PreferenceRepository(),
        swiftDataRepository: SwiftDataRepository? = nil
    ) {
        let defaultConnectionUsecase =
            connectionUsecase ?? ConnectionManagementUsecase.shared

        self.connectionUsecase = defaultConnectionUsecase
        self.sensingControlUsecase =
            sensingControlUsecase ?? SensingControlUsecase(connectionUsecase: defaultConnectionUsecase)
        self.realtimeDataUsecase = realtimeDataUsecase ?? RealtimeDataUsecase()
        self.preferenceRepository = preferenceRepository
        self.swiftDataRepository = swiftDataRepository

        self.loadRecentSessions()
        self.setupObservers()
    }

    /// 従来との互換性を保つための静的インスタンス
    static let shared = DataCollectionViewModel()

    deinit {
        sensingTimer?.invalidate()
    }

    private func setupObservers() {
        // 既存の購読をクリア
        self.cancellables.removeAll()

        // 直接注入されたUsecaseからの状態を監視
        self.sensingControlUsecase.$isSensingControlActive
            .sink { [weak self] value in
                self?.isSensingActive = value
            }
            .store(in: &self.cancellables)

        self.sensingControlUsecase.$sensingStatus
            .sink { [weak self] value in
                self?.sensingStatus = value
            }
            .store(in: &self.cancellables)

        self.connectionUsecase.$connectedEndpoints
            .map { $0.count }
            .sink { [weak self] value in
                self?.connectedDeviceCount = value
            }
            .store(in: &self.cancellables)

        self.realtimeDataUsecase.$deviceRealtimeDataList
            .sink { [weak self] value in
                self?.deviceRealtimeDataList = value
            }
            .store(in: &self.cancellables)

        self.realtimeDataUsecase.$deviceRealtimeDataList
            .map { $0.count }
            .sink { [weak self] value in
                self?.dataPointCount = value
            }
            .store(in: &self.cancellables)

        // グローバル座標の購読
        self.realtimeDataUsecase.$globalCoordinates
            .sink { [weak self] value in
                self?.globalCoordinates = value
            }
            .store(in: &self.cancellables)
    }

    /// SwiftDataRepositoryを設定（ViewのonAppearから呼ばれる）
    func setupSwiftDataRepository(modelContext: ModelContext) {
        if self.swiftDataRepository == nil {
            let repository = SwiftDataRepository(modelContext: modelContext)
            self.swiftDataRepository = repository

            // SensingControlUsecaseを新しく作成（正しいSwiftDataRepositoryを使用）
            self.sensingControlUsecase = SensingControlUsecase(
                connectionUsecase: self.connectionUsecase,
                swiftDataRepository: repository
            )
            print("✅ SensingControlUsecaseに正しいSwiftDataRepositoryを設定しました")

            // RealtimeDataUsecaseにSwiftDataRepositoryを設定
            self.realtimeDataUsecase.updateSwiftDataRepository(repository)

            // RealtimeDataUsecaseにSensingControlUsecaseを設定（データ永続化に必要）
            self.realtimeDataUsecase.setSensingControlUsecase(self.sensingControlUsecase)
            print("✅ RealtimeDataUsecaseにSensingControlUsecaseを設定しました")

            // ConnectionManagementUsecaseにRealtimeDataUsecaseを設定
            self.connectionUsecase.realtimeDataUsecase = self.realtimeDataUsecase
            print("✅ ConnectionManagementUsecaseにRealtimeDataUsecaseを設定しました")

            // Observersを再設定（新しいSensingControlUsecaseのイベントを購読）
            self.setupObservers()

            self.loadInitialData()
        }
    }

    /// 初期データの読み込み（非推奨：loadFloorMapInfo(floorMapId:)を使用すること）
    private func loadInitialData() {
        Task {
            // フロアマップは画面遷移時に明示的に指定されるため、ここでは読み込まない
            await self.loadAntennaPositions()
        }
    }

    /// 指定されたフロアマップ情報を読み込み
    func loadFloorMapInfo(floorMapId: String) {
        Task {
            await self.loadFloorMapInfoById(floorMapId: floorMapId)
            await self.loadAntennaPositions()
        }
    }

    /// 指定されたIDのフロアマップ情報を読み込み
    private func loadFloorMapInfoById(floorMapId: String) async {
        guard let repository = swiftDataRepository else {
            print("⚠️ SwiftDataRepositoryが利用できません")
            return
        }

        do {
            if let floorMap = try await repository.loadFloorMap(by: floorMapId) {
                self.currentFloorMapInfo = floorMap

                // フロアマップIDをRealtimeDataUsecaseに設定
                self.realtimeDataUsecase.setFloorMapId(floorMap.id)

                // フロアマップ画像を読み込み
                #if canImport(UIKit)
                    #if os(iOS)
                        self.floorMapImage = floorMap.image
                        if self.floorMapImage != nil {
                            print("📍 フロアマップ画像読み込み成功: \(floorMap.name)")
                        } else {
                            print("⚠️ フロアマップ画像が見つかりません: \(floorMap.name)")
                        }
                    #endif
                #endif

                #if os(macOS)
                    self.floorMapImage = floorMap.image
                    if self.floorMapImage != nil {
                        print("📍 フロアマップ画像読み込み成功: \(floorMap.name)")
                    } else {
                        print("⚠️ フロアマップ画像が見つかりません: \(floorMap.name)")
                    }
                #endif

                print("📍 フロアマップ情報読み込み完了: \(floorMap.name) (ID: \(floorMap.id))")
            } else {
                print("⚠️ フロアマップが見つかりません (ID: \(floorMapId))")
            }
        } catch {
            print("❌ フロアマップ情報の読み込みに失敗: \(error)")
        }
    }

    /// アンテナ位置情報を読み込み
    private func loadAntennaPositions() async {
        guard let repository = swiftDataRepository,
              let floorMapId = currentFloorMapInfo?.id
        else {
            return
        }

        do {
            let positions = try await repository.loadAntennaPositions(for: floorMapId)
            self.allAntennaPositions = positions
            print("📍 アンテナ位置情報読み込み完了: \(positions.count)件")
        } catch {
            print("❌ アンテナ位置情報の読み込みに失敗: \(error)")
        }
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

        // センシングデータをCSVとしてエクスポート
        Task {
            // SwiftDataの永続化完了を待つため少し待機
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒待機

            await self.exportSensingDataToCSV()

            // CSV出力完了後にSensingControlUsecaseのセッションIDをクリア
            await MainActor.run {
                // SensingControlUsecaseのcurrentSessionIdをクリア
                // これにより次のセンシングセッションで新しいIDが使用される
            }
        }

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

    // MARK: - CSV Export

    /// センシングデータをCSVとしてエクスポート
    ///
    /// 生データとグローバル座標変換後のデータの両方をエクスポートします
    private func exportSensingDataToCSV() async {
        print("📊 CSVエクスポート開始")
        print("   デバイス数: \(self.deviceRealtimeDataList.count)")

        // SensingControlUsecaseの実際のセッションIDを使用
        guard let sessionId = sensingControlUsecase.activeSessionId else {
            print("⚠️ アクティブなセッションIDが見つかりません")
            return
        }
        print("   使用するセッションID: \(sessionId)")

        guard let sessionStartTime = self.startTime else {
            print("⚠️ セッション開始時刻が見つかりません")
            return
        }

        do {
            // SwiftDataから全リアルタイムデータを読み込み
            let allRealtimeData = try await swiftDataRepository?.loadRealtimeData(for: sessionId) ?? []

            print("   SwiftDataから読み込んだデータ数: \(allRealtimeData.count)")

            guard !allRealtimeData.isEmpty else {
                print("⚠️ エクスポートするデータがありません")
                return
            }

            // タイムスタンプでソート
            let sortedData = allRealtimeData.sorted { $0.timestamp < $1.timestamp }

            // 全データ（生データ、グローバル座標、フィルタリング後）をエクスポート
            let processor = SensorDataProcessor()
            let result = try SensingDataCSVExporter.exportAllData(
                realtimeDataList: sortedData,
                globalCoordinates: self.globalCoordinates,
                startTime: sessionStartTime,
                processor: processor
            )

            print("✅ センシングデータのCSVエクスポート成功")
            print("   総データポイント数: \(sortedData.count)")
            print("   セッションディレクトリ: \(result.sessionDirectory.path)")
            print("   生データ: \(result.rawDataURL.lastPathComponent)")
            print("   グローバル座標データ: \(result.globalCoordinateURL.lastPathComponent)")
            print("   フィルタリング後データ: \(result.filteredDataURL.lastPathComponent)")
        } catch {
            print("❌ CSVエクスポートエラー: \(error.localizedDescription)")
        }
    }
}
