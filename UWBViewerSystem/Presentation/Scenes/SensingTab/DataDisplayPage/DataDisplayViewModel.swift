import Combine
import Foundation
import SwiftUI

// MARK: - Data Models

struct DataDisplayFile: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let size: Int64
    let dateCreated: Date

    var isCSV: Bool {
        self.name.lowercased().hasSuffix(".csv")
    }

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        return formatter.string(fromByteCount: self.size)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: self.dateCreated)
    }
}

// MARK: - ViewModel

@MainActor
class DataDisplayViewModel: ObservableObject {
    @Published var realtimeData: [DeviceRealtimeData] = []
    @Published var historyData: [SensingSession] = []
    @Published var receivedFiles: [DataDisplayFile] = []
    @Published var fileTransferProgress: [String: Int] = [:]
    @Published var isConnected = false

    private var updateTimer: Timer?

    // DI対応: 必要なUseCaseを直接注入
    private let realtimeDataUsecase: RealtimeDataUsecase
    private let fileManagementUsecase: FileManagementUsecase
    private let connectionUsecase: ConnectionManagementUsecase
    private var swiftDataRepository: SwiftDataRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()

    init(
        swiftDataRepository: SwiftDataRepositoryProtocol,
        realtimeDataUsecase: RealtimeDataUsecase? = nil,
        fileManagementUsecase: FileManagementUsecase? = nil,
        connectionUsecase: ConnectionManagementUsecase? = nil
    ) {
        self.swiftDataRepository = swiftDataRepository
        self.realtimeDataUsecase = realtimeDataUsecase ?? RealtimeDataUsecase()
        self.fileManagementUsecase = fileManagementUsecase ?? FileManagementUsecase()
        self.connectionUsecase =
            connectionUsecase ?? ConnectionManagementUsecase.shared

        self.setupObservers()
        Task {
            await self.loadHistoryData()
        }
        self.loadReceivedFiles()
    }

    /// 実際のModelContextを使用してSwiftDataRepositoryを設定
    func setSwiftDataRepository(_ repository: SwiftDataRepositoryProtocol) {
        self.swiftDataRepository = repository
        Task {
            await self.loadHistoryData()
        }
    }

    deinit {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func setupObservers() {
        // 直接注入されたUsecaseからの状態を監視
        self.realtimeDataUsecase.$deviceRealtimeDataList
            .assign(to: &self.$realtimeData)

        self.fileManagementUsecase.$fileTransferProgress
            .assign(to: &self.$fileTransferProgress)

        self.fileManagementUsecase.$receivedFiles
            .map { files in
                files.map { fileName in
                    DataDisplayFile(
                        name: fileName.fileName,
                        path: fileName.fileURL.path,  // 正しいパスを取得
                        size: fileName.fileSize,  // 正しいサイズを取得
                        dateCreated: fileName.receivedAt
                    )
                }
            }
            .assign(to: &self.$receivedFiles)

        self.connectionUsecase.$connectedEndpoints
            .map { !$0.isEmpty }
            .assign(to: &self.$isConnected)
    }

    // MARK: - Realtime Updates

    func startRealtimeUpdates() {
        self.stopRealtimeUpdates()  // 既存のタイマーをクリア
        self.updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateRealtimeData()
            }
        }
    }

    func stopRealtimeUpdates() {
        self.updateTimer?.invalidate()
        self.updateTimer = nil
    }

    private func updateRealtimeData() {
        // HomeViewModelからデータを取得（既にObserverで設定済み）
        // 必要に応じて追加の処理
    }

    // MARK: - History Data

    func refreshHistoryData() {
        Task {
            await self.loadHistoryData()
        }
    }

    func loadSessionData(_ session: SensingSession) {
        // セッションの詳細データを読み込み
        // 実装に応じてファイルから読み込みなど
    }

    private func loadHistoryData() async {
        do {
            // SwiftDataからセンシングセッション履歴を読み込み
            let sessions = try await swiftDataRepository.loadAllSensingSessions()
            self.historyData = sessions
        } catch {
            print("Error loading history data: \(error)")
            self.historyData = []
        }
    }

    // MARK: - File Management

    func openStorageFolder() {
        self.fileManagementUsecase.openFileStorageFolder()
    }

    func openFile(_ file: DataDisplayFile) {
        // ファイルを開く処理
        // 実装に応じてFinderで開く、アプリ内で表示など
        let url = URL(fileURLWithPath: file.path)
        #if os(macOS)
            NSWorkspace.shared.open(url)
        #elseif os(iOS)
            // iOS実装は必要に応じて追加
            print("ファイルを開く: \(file.path)")
        #endif
    }

    private func loadReceivedFiles() {
        // 受信ファイル一覧を読み込み
        // HomeViewModelから取得（既にObserverで設定済み）
    }

    // MARK: - Data Analysis

    func exportDataAsCSV() {
        // リアルタイムデータをCSVとしてエクスポート
        let csvContent = self.generateCSVContent()
        self.saveCSVFile(content: csvContent)
    }

    private func generateCSVContent() -> String {
        var csv = "Device,Timestamp,Distance,Elevation,Azimuth,RSSI,NLOS,SeqCount\n"

        for deviceData in self.realtimeData {
            if let data = deviceData.latestData {
                csv +=
                    "\(deviceData.deviceName),\(data.timestamp),\(data.distance),\(data.elevation),\(data.azimuth),\(data.rssi),\(data.nlos),\(data.seqCount)\n"
            }
        }

        return csv
    }

    private func saveCSVFile(content: String) {
        #if os(macOS)
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.commaSeparatedText]
            savePanel.nameFieldStringValue = "uwb_data_\(Date().timeIntervalSince1970).csv"

            if savePanel.runModal() == .OK, let url = savePanel.url {
                try? content.write(to: url, atomically: true, encoding: .utf8)
            }
        #elseif os(iOS)
            // iOS実装
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileName = "uwb_data_\(Date().timeIntervalSince1970).csv"
            let url = documentsPath.appendingPathComponent(fileName)
            try? content.write(to: url, atomically: true, encoding: .utf8)
            print("CSVファイル保存: \(url.path)")
        #endif
    }

    // MARK: - Statistics

    var connectionStatistics: ConnectionStatistics {
        ConnectionStatistics(
            totalDevices: self.realtimeData.count,
            connectedDevices: self.realtimeData.compactMap { $0.latestData }.filter { $0.rssi > -100 }.count,
            averageDistance: self.realtimeData.compactMap { $0.latestData }.isEmpty
                ? 0
                : self.realtimeData.compactMap { $0.latestData }.map { $0.distance }.reduce(0, +)
                / Double(self.realtimeData.compactMap { $0.latestData }.count),
            averageRSSI: self.realtimeData.compactMap { $0.latestData }.isEmpty
                ? 0
                : self.realtimeData.compactMap { $0.latestData }.map { $0.rssi }.reduce(0, +)
                / Double(self.realtimeData.compactMap { $0.latestData }.count)
        )
    }
}

// MARK: - Dummy Repository for Initialization

// PairingSettingViewModelと同じDummySwiftDataRepositoryを使用
extension DataDisplayViewModel {
    /// テスト用またはプレースホルダー用の初期化
    convenience init() {
        self.init(
            swiftDataRepository: DummySwiftDataRepository(),
            realtimeDataUsecase: nil,
            fileManagementUsecase: nil,
            connectionUsecase: nil
        )
    }
}

// MARK: - Statistics Model

struct ConnectionStatistics {
    let totalDevices: Int
    let connectedDevices: Int
    let averageDistance: Double
    let averageRSSI: Double

    var connectionRate: Double {
        guard self.totalDevices > 0 else { return 0 }
        return Double(self.connectedDevices) / Double(self.totalDevices)
    }
}
