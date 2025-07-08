//
//  HomeViewModel.swift
//  UWBViewerSystem
//
//  Created by はるちろ on R 7/04/07.
//

import Foundation
import SwiftUI
import CoreLocation

// リアルタイムデータの構造体
struct RealtimeData: Identifiable, Codable {
    let id = UUID()
    let deviceName: String
    let timestamp: TimeInterval
    let elevation: Double
    let azimuth: Double
    let distance: Double
    let nlos: Int
    let rssi: Double
    let seqCount: Int
    
    var formattedTime: String {
        let date = Date(timeIntervalSince1970: timestamp / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

// デバイス別リアルタイムデータ
class DeviceRealtimeData: Identifiable, ObservableObject {
    let id = UUID()
    let deviceName: String
    @Published var latestData: RealtimeData?
    @Published var dataHistory: [RealtimeData] = []
    @Published var lastUpdateTime: Date = Date()
    @Published var isActive: Bool = true
    
    var isRecentlyUpdated: Bool {
        Date().timeIntervalSince(lastUpdateTime) < 5.0 // 5秒以内の更新
    }
    
    // データがあるかどうかの判定
    var hasData: Bool {
        latestData != nil
    }
    
    // データが古いかどうかの判定（10秒以上前）
    var isDataStale: Bool {
        guard let latestData = latestData else { return true }
        let dataTime = Date(timeIntervalSince1970: latestData.timestamp / 1000)
        return Date().timeIntervalSince(dataTime) > 10.0
    }
    
    // 問題があるかどうかの総合判定
    var hasIssue: Bool {
        !hasData || isDataStale || !isRecentlyUpdated
    }
    
    init(deviceName: String, latestData: RealtimeData? = nil, dataHistory: [RealtimeData] = [], lastUpdateTime: Date = Date(), isActive: Bool = true) {
        self.deviceName = deviceName
        self.latestData = latestData
        self.dataHistory = dataHistory
        self.lastUpdateTime = lastUpdateTime
        self.isActive = isActive
    }
    
    func addData(_ data: RealtimeData) {
        latestData = data
        dataHistory.append(data)
        lastUpdateTime = Date()
        isActive = true
        
        // 最新20件のデータのみ保持
        if dataHistory.count > 20 {
            dataHistory.removeFirst()
        }
    }
}

// JSONパース用の構造体
struct RealtimeDataMessage: Codable {
    let type: String
    let deviceName: String
    let timestamp: TimeInterval
    let elevation: Double
    let azimuth: Double
    let distance: Double
    let nlos: Int
    let rssi: Double
    let seqCount: Int
}

// 受信ファイルの構造体
struct ReceivedFile: Identifiable {
    let id = UUID()
    let fileName: String
    let fileURL: URL
    let deviceName: String
    let receivedAt: Date
    let fileSize: Int64
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: receivedAt)
    }
}

class HomeViewModel: NSObject, ObservableObject, NearbyRepositoryCallback {
    private let repository: NearbyRepository
    private let locationManager = CLLocationManager()
    
    @Published var connectState: String = ""
    @Published var receivedDataList: [(String, String)] = []
    @Published var isLocationPermissionGranted = false
    
    // センシング制御関連の状態
    @Published var sensingStatus: String = "停止中"
    @Published var isSensingControlActive = false
    @Published var sensingFileName: String = ""
    
    // リアルタイムデータ表示関連の状態
    @Published var deviceRealtimeDataList: [DeviceRealtimeData] = []
    @Published var isReceivingRealtimeData = false
    
    // 接続された端末の管理
    @Published var connectedDeviceNames: Set<String> = []
    
    // ファイル受信関連の状態
    @Published var receivedFiles: [ReceivedFile] = []
    @Published var fileTransferProgress: [String: Int] = [:] // endpointId: progress
    @Published var fileStoragePath: String = ""
    
    override init() {
        self.repository = NearbyRepository()
        super.init()
        self.repository.callback = self
        setupLocationManager()
        requestLocationPermission()
        setupFileStoragePath()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
    }
    
    private func requestLocationPermission() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            #if os(macOS)
            locationManager.requestAlwaysAuthorization()
            #else
            locationManager.requestWhenInUseAuthorization()
            #endif
        #if os(macOS)
        case .authorizedAlways:
            isLocationPermissionGranted = true
        #else
        case .authorizedWhenInUse, .authorizedAlways:
            isLocationPermissionGranted = true
        #endif
        case .denied, .restricted:
            connectState = "位置情報の権限が必要です"
        @unknown default:
            break
        }
    }
    
    func startAdvertise() {
        guard isLocationPermissionGranted else {
            connectState = "位置情報の権限を許可してください"
            return
        }
        repository.startAdvertise()
    }
    
    func startDiscovery() {
        guard isLocationPermissionGranted else {
            connectState = "位置情報の権限を許可してください"
            return
        }
        repository.startDiscovery()
    }
    
    func sendData(text: String) {
        repository.sendData(text: text)
    }
    
    // センシング制御コマンド送信機能
    func startRemoteSensing(fileName: String) {
        guard !fileName.isEmpty else {
            sensingStatus = "ファイル名を入力してください"
            return
        }
        
        guard repository.hasConnectedDevices() else {
            sensingStatus = "接続された端末がありません"
            return
        }
        
        let command = "SENSING_START:\(fileName)"
        repository.sendData(text: command)
        sensingStatus = "センシング開始コマンド送信: \(fileName)"
        isSensingControlActive = true
        sensingFileName = fileName
        
        // 接続状態も更新
        connectState = "センシング開始コマンド送信完了"
    }
    
    func stopRemoteSensing() {
        guard repository.hasConnectedDevices() else {
            sensingStatus = "接続された端末がありません"
            return
        }
        
        let command = "SENSING_STOP"
        repository.sendData(text: command)
        sensingStatus = "センシング終了コマンド送信"
        isSensingControlActive = false
        sensingFileName = ""
        
        // リアルタイムデータをクリア（接続は維持）
        for deviceData in deviceRealtimeDataList {
            deviceData.latestData = nil
            deviceData.dataHistory.removeAll()
            deviceData.lastUpdateTime = Date.distantPast
        }
        
        // データ受信状態を維持（接続された端末は表示）
        isReceivingRealtimeData = !deviceRealtimeDataList.isEmpty
        
        // ファイル転送進捗もクリア
        fileTransferProgress.removeAll()
        
        // 接続状態も更新
        connectState = "センシング終了コマンド送信完了"
    }
    
    // リアルタイムデータ処理（デバッグ強化版）
    private func processRealtimeData(_ data: String, fromEndpointId: String = "") {
        print("Processing data from endpoint \(fromEndpointId): \(data)")
        
        // JSONデータかどうかチェック
        if data.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") &&
           data.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("}") {
            
            // JSONタイプを判定
            guard let jsonData = data.data(using: .utf8) else { 
                print("Failed to convert data to UTF8")
                return 
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let type = json["type"] as? String {
                    
                    switch type {
                    case "REALTIME_DATA":
                        processRealtimeDataJSON(json, fromEndpointId: fromEndpointId)
                    case "PING":
                        processPingMessage(json, fromEndpointId: fromEndpointId)
                    case "FILE_TRANSFER_START":
                        processFileTransferStart(json, fromEndpointId: fromEndpointId)
                    default:
                        print("Unknown JSON message type: \(type)")
                        connectState = "受信: \(type) メッセージ"
                    }
                }
            } catch {
                print("JSON parsing error: \(error)")
            }
        } else {
            // 非JSONデータ（コマンドレスポンスなど）
            print("Non-JSON data received: \(data)")
            connectState = "コマンドレスポンス: \(data)"
        }
    }
    
    private func processRealtimeDataJSON(_ json: [String: Any], fromEndpointId: String) {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: json)
            let realtimeMessage = try JSONDecoder().decode(RealtimeDataMessage.self, from: jsonData)
            print("Successfully parsed realtime data for device: \(realtimeMessage.deviceName)")
            
            // リアルタイムデータリストに追加
            let realtimeData = RealtimeData(
                deviceName: realtimeMessage.deviceName,
                timestamp: realtimeMessage.timestamp,
                elevation: realtimeMessage.elevation,
                azimuth: realtimeMessage.azimuth,
                distance: realtimeMessage.distance,
                nlos: realtimeMessage.nlos,
                rssi: realtimeMessage.rssi,
                seqCount: realtimeMessage.seqCount
            )
            
            // デバイス別データ管理
            if let index = deviceRealtimeDataList.firstIndex(where: { $0.deviceName == realtimeMessage.deviceName }) {
                // 既存デバイスのデータ更新
                print("Updating existing device: \(realtimeMessage.deviceName)")
                let deviceData = deviceRealtimeDataList[index]
                deviceData.latestData = realtimeData
                deviceData.dataHistory.append(realtimeData)
                deviceData.lastUpdateTime = Date()
                deviceData.isActive = true
                
                // 最新20件のデータのみ保持
                if deviceData.dataHistory.count > 20 {
                    deviceData.dataHistory.removeFirst()
                }
            } else {
                // 新しいデバイスのデータ追加
                print("Adding new device: \(realtimeMessage.deviceName)")
                let newDeviceData = DeviceRealtimeData(
                    deviceName: realtimeMessage.deviceName,
                    latestData: realtimeData,
                    dataHistory: [realtimeData],
                    lastUpdateTime: Date(),
                    isActive: true
                )
                deviceRealtimeDataList.append(newDeviceData)
            }
            
            isReceivingRealtimeData = true
            connectState = "リアルタイムデータ受信中 (\(deviceRealtimeDataList.count)台)"
            
        } catch {
            print("Realtime data JSON parsing error: \(error)")
        }
    }
    
    private func processPingMessage(_ json: [String: Any], fromEndpointId: String) {
        let fromDevice = json["from"] as? String ?? "Unknown"
        let timestamp = json["timestamp"] as? Int64 ?? 0
        
        print("Ping received from: \(fromDevice)")
        connectState = "Ping受信: \(fromDevice) at \(Date(timeIntervalSince1970: Double(timestamp) / 1000))"
        
        // Pingに対するPong応答を送信
        let pongMessage = """
        {
            "type": "PONG",
            "timestamp": \(Int64(Date().timeIntervalSince1970 * 1000)),
            "from": "Mac",
            "responseTo": "\(fromDevice)"
        }
        """
        
        repository.sendData(text: pongMessage)
        print("Pong response sent to: \(fromDevice)")
    }
    
    private func processFileTransferStart(_ json: [String: Any], fromEndpointId: String) {
        let fileName = json["fileName"] as? String ?? "Unknown"
        let fileSize = json["fileSize"] as? Int64 ?? 0
        
        print("File transfer starting: \(fileName), size: \(fileSize)")
        connectState = "ファイル転送開始: \(fileName)"
    }
    
    func disconnectAll() {
        repository.disconnectAll()
        
        // リアルタイムデータをクリア
        deviceRealtimeDataList.removeAll()
        connectedDeviceNames.removeAll()
        isReceivingRealtimeData = false
        
        // ファイル関連もクリア
        fileTransferProgress.removeAll()
    }
    
    func resetAll() {
        repository.resetAll()
        receivedDataList = []
        
        // リアルタイムデータをクリア
        deviceRealtimeDataList.removeAll()
        connectedDeviceNames.removeAll()
        isReceivingRealtimeData = false
        
        // ファイル関連をクリア
        receivedFiles.removeAll()
        fileTransferProgress.removeAll()
        
        // センシング制御状態もリセット
        isSensingControlActive = false
        sensingFileName = ""
        sensingStatus = "停止中"
    }
    
    // MARK: - NearbyRepositoryCallback
    func onConnectionStateChanged(state: String) {
        DispatchQueue.main.async {
            self.connectState = state
        }
    }
    
    func onDataReceived(data: String, fromEndpointId: String) {
        DispatchQueue.main.async {
            self.receivedDataList.append((fromEndpointId, data))
            
            // リアルタイムデータの処理（デバッグ出力追加）
            self.processRealtimeData(data, fromEndpointId: fromEndpointId)
        }
    }
    
    // 新しく追加されたコールバックメソッド
    func onConnectionRequestReceived(request: ConnectionRequest) {
        DispatchQueue.main.async {
            // HomeViewModelでは自動承認（基本画面なので）
            request.responseHandler(true)
            self.connectState = "接続要求を自動承認: \(request.deviceName)"
        }
    }
    
    func onDeviceConnected(device: ConnectedDevice) {
        DispatchQueue.main.async {
            self.connectState = "端末接続: \(device.deviceName)"
            
            // 接続された端末を追跡
            self.connectedDeviceNames.insert(device.deviceName)
            
            // データがない場合でも端末を表示リストに追加
            if !self.deviceRealtimeDataList.contains(where: { $0.deviceName == device.deviceName }) {
                let newDeviceData = DeviceRealtimeData(
                    deviceName: device.deviceName,
                    latestData: nil,
                    dataHistory: [],
                    lastUpdateTime: Date(),
                    isActive: true
                )
                self.deviceRealtimeDataList.append(newDeviceData)
            }
            
            self.isReceivingRealtimeData = true
        }
    }
    
    func onDeviceDisconnected(endpointId: String) {
        DispatchQueue.main.async {
            self.connectState = "端末切断: \(endpointId)"
            
            // 切断された端末を接続リストから削除
            // endpointIdから端末名を特定するのが難しいため、既存のロジックを活用
            if let deviceData = self.deviceRealtimeDataList.first(where: { $0.deviceName.contains(endpointId) || endpointId.contains($0.deviceName) }) {
                self.connectedDeviceNames.remove(deviceData.deviceName)
                
                // 切断されたデバイスは無効状態にする
                deviceData.isActive = false
                deviceData.lastUpdateTime = Date.distantPast
            }
        }
    }
    
    func onMessageReceived(message: Message) {
        DispatchQueue.main.async {
            self.receivedDataList.append((message.fromDeviceName, message.content))
        }
    }
    
    // ファイル受信のコールバック実装
    func onFileReceived(_ endpointId: String, _ fileURL: URL, _ fileName: String) {
        DispatchQueue.main.async {
            // ファイルサイズを取得
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
            
            // デバイス名を取得（endpointIdから推定）
            let deviceName = self.connectedDeviceNames.first { $0.contains(endpointId) } ?? endpointId
            
            let receivedFile = ReceivedFile(
                fileName: fileName,
                fileURL: fileURL,
                deviceName: deviceName,
                receivedAt: Date(),
                fileSize: fileSize
            )
            
            self.receivedFiles.append(receivedFile)
            self.connectState = "ファイル受信完了: \(fileName) (\(receivedFile.formattedSize))"
            
            // 進捗を削除
            self.fileTransferProgress.removeValue(forKey: endpointId)
        }
    }
    
    func onFileTransferProgress(_ endpointId: String, _ progress: Int) {
        DispatchQueue.main.async {
            self.fileTransferProgress[endpointId] = progress
        }
    }
    
    // 新しいコールバック（AdvertiserViewModelでの詳細な制御用）
    func onConnectionInitiated(_ endpointId: String, _ deviceName: String, _ context: Data, _ responseHandler: @escaping (Bool) -> Void) {
        // HomeViewModelでは古い形式を使用
        let request = ConnectionRequest(
            endpointId: endpointId,
            deviceName: deviceName,
            requestTime: Date(),
            context: context,
            responseHandler: responseHandler
        )
        onConnectionRequestReceived(request: request)
    }
    
    func onConnectionResult(_ endpointId: String, _ isSuccess: Bool) {
        // デフォルトでは何もしない
    }
    
    func onDisconnected(_ endpointId: String) {
        onDeviceDisconnected(endpointId: endpointId)
    }
    
    func onPayloadReceived(_ endpointId: String, _ payload: Data) {
        if let text = String(data: payload, encoding: .utf8) {
            onDataReceived(data: text, fromEndpointId: endpointId)
        }
    }
    
    // ファイル保存場所の設定
    private func setupFileStoragePath() {
        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let uwbFilesDirectory = documentsDirectory.appendingPathComponent("UWBFiles")
            fileStoragePath = uwbFilesDirectory.path
        }
    }
    
    // ファイル保存フォルダーを開く
    func openFileStorageFolder() {
        guard !fileStoragePath.isEmpty else { return }
        
        let url = URL(fileURLWithPath: fileStoragePath)
        
        // フォルダーが存在しない場合は作成
        if !FileManager.default.fileExists(atPath: fileStoragePath) {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                connectState = "フォルダー作成エラー: \(error.localizedDescription)"
                return
            }
        }
        
        NSWorkspace.shared.open(url)
    }
}

// MARK: - CLLocationManagerDelegate
extension HomeViewModel: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        #if os(macOS)
        case .authorizedAlways:
            isLocationPermissionGranted = true
            connectState = "権限許可完了"
        #else
        case .authorizedWhenInUse, .authorizedAlways:
            isLocationPermissionGranted = true
            connectState = "権限許可完了"
        #endif
        case .denied, .restricted:
            isLocationPermissionGranted = false
            connectState = "位置情報の権限が拒否されました"
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
}
