import SwiftUI
import Foundation
import Combine

// MARK: - Data Models

struct DataDisplayFile: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let size: Int64
    let dateCreated: Date
    
    var isCSV: Bool {
        name.lowercased().hasSuffix(".csv")
    }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        return formatter.string(fromByteCount: size)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: dateCreated)
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
    private var homeViewModel: HomeViewModel?
    
    init() {
        setupObservers()
        loadHistoryData()
        loadReceivedFiles()
    }
    
    deinit {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    private func setupObservers() {
        // HomeViewModelのインスタンスを安全に取得
        homeViewModel = HomeViewModel.shared
        
        guard let viewModel = homeViewModel else { return }
        
        // HomeViewModelからの状態を監視
        viewModel.$deviceRealtimeDataList
            .assign(to: &$realtimeData)
        
        viewModel.$fileTransferProgress
            .assign(to: &$fileTransferProgress)
        
        viewModel.$receivedFiles
            .map { files in
                files.map { fileName in
                    DataDisplayFile(
                        name: fileName.fileName,
                        path: fileName.fileURL.path, // 正しいパスを取得
                        size: fileName.fileSize,  // 正しいサイズを取得
                        dateCreated: fileName.receivedAt
                    )
                }
            }
            .assign(to: &$receivedFiles)
        
        viewModel.$connectedEndpoints
            .map { !$0.isEmpty }
            .assign(to: &$isConnected)
    }
    
    // MARK: - Realtime Updates
    
    func startRealtimeUpdates() {
        stopRealtimeUpdates() // 既存のタイマーをクリア
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateRealtimeData()
            }
        }
    }
    
    func stopRealtimeUpdates() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    private func updateRealtimeData() {
        // HomeViewModelからデータを取得（既にObserverで設定済み）
        // 必要に応じて追加の処理
    }
    
    // MARK: - History Data
    
    func refreshHistoryData() {
        loadHistoryData()
    }
    
    func loadSessionData(_ session: SensingSession) {
        // セッションの詳細データを読み込み
        // 実装に応じてファイルから読み込みなど
    }
    
    private func loadHistoryData() {
        // DataCollectionViewModelで保存されたセッション履歴を読み込み
        if let data = UserDefaults.standard.data(forKey: "RecentSensingSessions") {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode([SensingSession].self, from: data) {
                historyData = decoded
            }
        }
    }
    
    // MARK: - File Management
    
    func openStorageFolder() {
        homeViewModel?.openFileStorageFolder()
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
        let csvContent = generateCSVContent()
        saveCSVFile(content: csvContent)
    }
    
    private func generateCSVContent() -> String {
        var csv = "Device,Timestamp,Distance,Elevation,Azimuth,RSSI,NLOS,SeqCount\n"
        
        for deviceData in realtimeData {
            if let data = deviceData.latestData {
                csv += "\(deviceData.deviceName),\(data.timestamp),\(data.distance),\(data.elevation),\(data.azimuth),\(data.rssi),\(data.nlos),\(data.seqCount)\n"
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
            totalDevices: realtimeData.count,
            connectedDevices: realtimeData.compactMap { $0.latestData }.filter { $0.rssi > -100 }.count,
            averageDistance: realtimeData.compactMap { $0.latestData }.isEmpty ? 0 : realtimeData.compactMap { $0.latestData }.map { $0.distance }.reduce(0, +) / Double(realtimeData.compactMap { $0.latestData }.count),
            averageRSSI: realtimeData.compactMap { $0.latestData }.isEmpty ? 0 : realtimeData.compactMap { $0.latestData }.map { $0.rssi }.reduce(0, +) / Double(realtimeData.compactMap { $0.latestData }.count)
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
        guard totalDevices > 0 else { return 0 }
        return Double(connectedDevices) / Double(totalDevices)
    }
}