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
    let id: UUID
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

// JSONパース用の構造体（Android側のデータ構造に合わせる）
struct RealtimeDataMessage: Codable {
    let type: String
    let deviceName: String
    let timestamp: TimeInterval
    let data: RealtimeDataPayload
    
    struct RealtimeDataPayload: Codable {
        let elevation: Double
        let azimuth: Double
        let distance: Int  // Androidから整数で送られる
        let nlos: Int
        let rssi: Double
        let seqCount: Int
        let elevationFom: Int?
        let pDoA1: Double?  // Androidから数値で送られる
        let pDoA2: Double?  // Androidから数値で送られる
    }
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
    static let shared = HomeViewModel()
    
    let nearByRepository: NearbyRepository
    private let locationManager = CLLocationManager()
    private var realtimeUpdateTimer: Timer?
    
    private override init() {
        nearByRepository = NearbyRepository()
        super.init()
        nearByRepository.callback = self
        setupLocationManager()
        requestLocationPermission()
        setupFileStoragePath()
    }
    
    @Published var connectState: String = ""
    @Published var receivedDataList: [(String, String)] = []
    @Published var isLocationPermissionGranted = false
    
    // センシング制御関連の状態
    @Published var sensingStatus: String = "停止中"
    @Published var isSensingControlActive = false
    @Published var sensingFileName: String = ""
    
    // センシング制御で使用するファイル名を保持
    @Published var currentSensingFileName: String = ""
    
    // リアルタイムデータ表示関連の状態
    @Published var deviceRealtimeDataList: [DeviceRealtimeData] = []
    @Published var isReceivingRealtimeData = false
    
    // 接続された端末の管理
    @Published var connectedDeviceNames: Set<String> = []
    @Published var connectedEndpoints: Set<String> = []
    
    // 接続制御の状態
    @Published var isAdvertising = false
    
    // ファイル受信関連の状態
    @Published var receivedFiles: [ReceivedFile] = []
    @Published var fileTransferProgress: [String: Int] = [:] // endpointId: progress
    @Published var fileStoragePath: String = ""
    
    
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
        nearByRepository.startAdvertise()
    }
    
    func startDiscovery() {
        guard isLocationPermissionGranted else {
            connectState = "位置情報の権限を許可してください"
            return
        }
        nearByRepository.startDiscovery()
    }
    
    func sendData(text: String) {
        nearByRepository.sendData(text: text)
    }
    
    // センシング制御コマンド送信機能
    func startRemoteSensing(fileName: String) {
        print("=== センシング開始処理開始 ===")
        print("ファイル名: \(fileName)")
        
        guard !fileName.isEmpty else {
            sensingStatus = "ファイル名を入力してください"
            print("エラー: ファイル名が空です")
            return
        }
        
        let hasConnected = nearByRepository.hasConnectedDevices()
        let connectedCount = connectedEndpoints.count
        let deviceNamesCount = connectedDeviceNames.count
        
        print("接続状態チェック:")
        print("- hasConnectedDevices: \(hasConnected)")
        print("- connectedEndpoints.count: \(connectedCount)")
        print("- connectedDeviceNames.count: \(deviceNamesCount)")
        print("- connectedEndpoints: \(connectedEndpoints)")
        print("- connectedDeviceNames: \(connectedDeviceNames)")
        
        guard hasConnected else {
            sensingStatus = "接続された端末がありません（\(connectedCount)台接続中）"
            print("エラー: 接続された端末がありません")
            return
        }
        
        let command = "SENSING_START:\(fileName)"
        print("送信するコマンド: \(command)")
        print("送信対象端末数: \(connectedCount)")
        
        nearByRepository.sendData(text: command)
        sensingStatus = "センシング開始コマンド送信: \(fileName)"
        isSensingControlActive = true
        sensingFileName = fileName
        
        // 現在のセンシングファイル名を保存
        currentSensingFileName = fileName
        
        // 接続状態も更新
        connectState = "センシング開始コマンド送信完了（\(connectedCount)台に送信）"
        
        // 送信確認のため、少し遅らせてテストメッセージも送信
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("=== フォローアップテストメッセージ送信 ===")
            self.nearByRepository.sendData(text: "SENSING_TEST_FOLLOW_UP")
        }
        
        print("=== センシング開始処理完了 ===")
    }
    
    func stopRemoteSensing() {
        guard nearByRepository.hasConnectedDevices() else {
            sensingStatus = "接続された端末がありません"
            return
        }
        
        let command = "SENSING_STOP"
        nearByRepository.sendData(text: command)
        sensingStatus = "センシング終了コマンド送信"
        isSensingControlActive = false
        sensingFileName = ""
        
        // センシングファイル名はファイル受信まで保持（後でクリア）
        
        // リアルタイムデータをクリア（接続は維持）
    }
    
    func pauseRemoteSensing() {
        guard nearByRepository.hasConnectedDevices() else {
            sensingStatus = "接続された端末がありません"
            return
        }
        
        let command = "SENSING_PAUSE"
        nearByRepository.sendData(text: command)
        sensingStatus = "センシング一時停止中"
    }
    
    func resumeRemoteSensing() {
        guard nearByRepository.hasConnectedDevices() else {
            sensingStatus = "接続された端末がありません"
            return
        }
        
        let command = "SENSING_RESUME"
        nearByRepository.sendData(text: command)
        sensingStatus = "センシング実行中"
        isSensingControlActive = true
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
        print("=== processRealtimeData開始 ===")
        print("処理対象データ: \(data)")
        
        // JSONデータかどうかチェック
        if data.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") &&
           data.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("}") {
            
            print("JSONフォーマット確認: OK")
            
            // JSONタイプを判定
            guard let jsonData = data.data(using: .utf8) else { 
                print("UTF8変換失敗")
                return 
            }
            
            print("UTF8データ変換: OK, サイズ: \(jsonData.count) bytes")
            
            do {
                if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    print("JSON解析成功")
                    
                    if let type = json["type"] as? String {
                        print("JSONタイプ: \(type)")
                        
                        switch type {
                        case "REALTIME_DATA":
                            print("リアルタイムデータ処理開始")
                            processRealtimeDataJSON(json, fromEndpointId: fromEndpointId)
                        case "PING":
                            print("Ping処理開始")
                            processPingMessage(json, fromEndpointId: fromEndpointId)
                        case "FILE_TRANSFER_START":
                            print("ファイル転送開始処理")
                            processFileTransferStart(json, fromEndpointId: fromEndpointId)
                        default:
                            print("未知のJSONタイプ: \(type)")
                            connectState = "受信: \(type) メッセージ"
                        }
                    } else {
                        print("JSONタイプフィールドが見つからない")
                        print("JSON内容: \(json)")
                    }
                } else {
                    print("JSONオブジェクトキャスト失敗")
                }
            } catch {
                print("JSON解析エラー: \(error)")
                print("生データ: \(data)")
            }
        } else {
            // 非JSONデータ（コマンドレスポンスなど）
            print("非JSONデータ: \(data)")
            connectState = "コマンドレスポンス: \(data)"
        }
        
        print("=== processRealtimeData終了 ===")
    }
    
    private func processRealtimeDataJSON(_ json: [String: Any], fromEndpointId: String) {
        print("=== 🔄 processRealtimeDataJSON開始 ===")
        print("🔄 受信エンドポイントID: \(fromEndpointId)")
        print("🔄 JSONキー: \(json.keys.sorted())")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: json)
            print("✅ JSON再シリアライズ成功: \(jsonData.count) bytes")
            
            let realtimeMessage = try JSONDecoder().decode(RealtimeDataMessage.self, from: jsonData)
            print("✅ RealtimeDataMessage デコード成功")
            print("📱 デバイス名: \(realtimeMessage.deviceName)")
            print("📐 Elevation: \(realtimeMessage.data.elevation)°")
            print("🧭 Azimuth: \(realtimeMessage.data.azimuth)°")
            print("📏 Distance: \(realtimeMessage.data.distance)m")
            print("📊 SeqCount: \(realtimeMessage.data.seqCount)")
            print("📡 RSSI: \(realtimeMessage.data.rssi)dBm")
            print("🚧 NLOS: \(realtimeMessage.data.nlos)")
            
            // リアルタイムデータリストに追加
            let realtimeData = RealtimeData(
                id: UUID(),
                deviceName: realtimeMessage.deviceName,
                timestamp: realtimeMessage.timestamp,
                elevation: realtimeMessage.data.elevation,
                azimuth: realtimeMessage.data.azimuth,
                distance: Double(realtimeMessage.data.distance), // IntからDoubleに変換
                nlos: realtimeMessage.data.nlos,
                rssi: realtimeMessage.data.rssi,
                seqCount: realtimeMessage.data.seqCount
            )
            
            print("RealtimeData オブジェクト作成成功")
            
            // デバイス別データ管理 - メインスレッドで確実にUI更新
            DispatchQueue.main.async {
                if let index = self.deviceRealtimeDataList.firstIndex(where: { $0.deviceName == realtimeMessage.deviceName }) {
                    // 既存デバイスのデータ更新
                    print("🟡 既存デバイス更新: \(realtimeMessage.deviceName) (インデックス: \(index))")
                    
                    // 配列の要素を直接更新してUI変更をトリガー
                    var updatedDevice = self.deviceRealtimeDataList[index]
                    updatedDevice.latestData = realtimeData
                    updatedDevice.dataHistory.append(realtimeData)
                    updatedDevice.lastUpdateTime = Date()
                    updatedDevice.isActive = true
                    
                    // 最新20件のデータのみ保持
                    if updatedDevice.dataHistory.count > 20 {
                        updatedDevice.dataHistory.removeFirst()
                    }
                    
                    // 配列を完全に再構築してUI更新をトリガー
                    var newList = self.deviceRealtimeDataList
                    newList[index] = updatedDevice
                    self.deviceRealtimeDataList = newList
                    
                    print("🟢 デバイスデータ更新完了: 履歴数=\(updatedDevice.dataHistory.count)")
                    print("🟢 最新データ: 距離=\(realtimeData.distance)m, 仰角=\(realtimeData.elevation)°, 方位=\(realtimeData.azimuth)°")
                    
                } else {
                    // 新しいデバイスのデータ追加
                    print("🆕 新デバイス追加: \(realtimeMessage.deviceName)")
                    let newDeviceData = DeviceRealtimeData(
                        deviceName: realtimeMessage.deviceName,
                        latestData: realtimeData,
                        dataHistory: [realtimeData],
                        lastUpdateTime: Date(),
                        isActive: true
                    )
                    self.deviceRealtimeDataList.append(newDeviceData)
                    print("🟢 デバイス追加完了: 総デバイス数=\(self.deviceRealtimeDataList.count)")
                }
                
                // 強制的に全体UI更新
                self.objectWillChange.send()
                print("🔄 UI更新通知送信完了")
            }
            
            isReceivingRealtimeData = true
            connectState = "リアルタイムデータ受信中 (\(deviceRealtimeDataList.count)台)"
            print("UI状態更新完了: isReceivingRealtimeData=\(isReceivingRealtimeData)")
            
            // 全デバイスの状況をログ出力
            print("=== 全デバイス状況 ===")
            for (index, device) in deviceRealtimeDataList.enumerated() {
                print("[\(index)] \(device.deviceName):")
                print("  - latestData: \(device.latestData != nil ? "あり" : "なし")")
                print("  - elevation: \(device.latestData?.elevation ?? 0.0)")
                print("  - azimuth: \(device.latestData?.azimuth ?? 0.0)")
                print("  - isActive: \(device.isActive)")
                print("  - lastUpdateTime: \(device.lastUpdateTime)")
            }
            print("=== 全デバイス状況終了 ===")
            
        } catch {
            print("リアルタイムデータ処理エラー: \(error)")
            if let decodingError = error as? DecodingError {
                print("デコードエラー詳細: \(decodingError)")
            }
            print("問題のあるJSON: \(json)")
        }
        
        print("=== processRealtimeDataJSON終了 ===")
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
        
        nearByRepository.sendData(text: pongMessage)
        print("Pong response sent to: \(fromDevice)")
    }
    
    private func processFileTransferStart(_ json: [String: Any], fromEndpointId: String) {
        let fileName = json["fileName"] as? String ?? "Unknown"
        let fileSize = json["fileSize"] as? Int64 ?? 0
        
        print("File transfer starting: \(fileName), size: \(fileSize)")
        connectState = "ファイル転送開始: \(fileName)"
    }
    
    func disconnectAll() {
        nearByRepository.disconnectAll()
        
        // リアルタイムデータをクリア
        deviceRealtimeDataList.removeAll()
        connectedDeviceNames.removeAll()
        isReceivingRealtimeData = false
        
        // ファイル関連もクリア
        fileTransferProgress.removeAll()
    }
    
    func resetAll() {
        nearByRepository.resetAll()
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
            print("=== Mac側データ受信開始 ===")
            print("EndpointID: \(fromEndpointId)")
            print("データ長: \(data.count) bytes")
            print("受信データ: \(data)")
            
            self.receivedDataList.append((fromEndpointId, data))
            
            // データ種別を判定
            let dataType = self.getDataType(data)
            print("データ種別: \(dataType)")
            
            // リアルタイムデータの処理（デバッグ出力追加）
            self.processRealtimeData(data, fromEndpointId: fromEndpointId)
            
            print("=== Mac側データ受信終了 ===")
        }
    }
    
    // データ種別を判定
    private func getDataType(_ data: String) -> String {
        if data.contains("\"type\":\"REALTIME_DATA\"") {
            return "リアルタイムデータ"
        } else if data.contains("\"type\":\"PING\"") {
            return "Ping"
        } else if data.contains("\"type\":\"PONG\"") {
            return "Pong"
        } else if data.contains("\"type\":\"FILE_TRANSFER_START\"") {
            return "ファイル転送開始"
        } else if data.hasPrefix("SENSING_START:") {
            return "センシング開始コマンド"
        } else if data == "SENSING_STOP" {
            return "センシング終了コマンド"
        } else if data == "SENSING_STARTED_OK" {
            return "センシング開始確認"
        } else if data == "SENSING_STOPPED_OK" {
            return "センシング停止確認"
        } else if data.hasPrefix("COMMAND_RECEIVED:") {
            return "コマンド受信確認"
        } else {
            return "その他 (\(String(data.prefix(20)))...)"
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
            self.connectedEndpoints.insert(device.endpointId)
            
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
                print("接続端末をリアルタイムデータリストに追加: \(device.deviceName)")
            }
            
            // 接続端末があればリアルタイムデータセクションを表示
            self.isReceivingRealtimeData = !self.deviceRealtimeDataList.isEmpty
            print("リアルタイムデータセクション表示状態: \(self.isReceivingRealtimeData)")
        }
    }
    
    func onDeviceDisconnected(endpointId: String) {
        DispatchQueue.main.async {
            self.connectState = "端末切断: \(endpointId)"
            
            // 切断された端末を接続リストから削除
            self.connectedEndpoints.remove(endpointId)
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
            print("🔵 Mac HomeViewModel: onMessageReceived")
            print("🔵 エンドポイント: \(String(describing: message.fromEndpointId))")
            print("🔵 デバイス名: \(message.fromDeviceName)")
            print("🔵 メッセージ長: \(message.content.count) 文字")
            print("🔵 メッセージ先頭: \(String(message.content.prefix(100)))")
            
            if message.content.contains("REALTIME_DATA") {
                print("🟢 REALTIME_DATAを検出 - 直接処理開始")
                // JSONデータを解析
                if let data = message.content.data(using: .utf8) {
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            print("🟢 JSON解析成功 - processRealtimeDataJSON呼び出し")
                            self.processRealtimeDataJSON(json, fromEndpointId: message.fromEndpointId ?? "unknown")
                        }
                    } catch {
                        print("🔴 JSON解析エラー: \(error)")
                    }
                }
            } else {
                print("🔴 非REALTIME_DATAメッセージ: \(message.content)")
                
                // メッセージの詳細分析
                if message.content.contains("SENSING") {
                    print("📡 センシング関連メッセージを受信")
                    if message.content.contains("START") {
                        print("🚀 Android側でセンシング開始 - REALTIME_DATA待機中...")
                    } else if message.content.contains("STOP") {
                        print("⏸️ Android側でセンシング停止")
                        self.clearRealtimeData()
                    } else if message.content.contains("TEST") || message.content.contains("FOLLOW_UP") {
                        print("🧪 テスト/フォローアップメッセージ - センシング状態確認要")
                    }
                } else {
                    print("❓ 不明なメッセージタイプ")
                }
            }
            
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
            
            // センシングファイル名をクリア（ファイル受信完了後）
            self.currentSensingFileName = ""
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
    
    // MARK: - ConnectionManagementViewModel用のメソッド
    
    func startAdvertising() {
        nearByRepository.startAdvertise()
        isAdvertising = true
    }
    
    func stopAdvertising() {
        nearByRepository.stopAdvertise()
        isAdvertising = false
    }
    
    
    func disconnectEndpoint(_ endpointId: String) {
        nearByRepository.disconnectFromDevice(endpointId: endpointId)
        connectedEndpoints.remove(endpointId)
        connectedDeviceNames = connectedDeviceNames.filter { $0 != endpointId }
    }
    
    func sendMessage(_ content: String, to endpointId: String) {
        nearByRepository.sendMessage(content, to: endpointId)
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
    
    // MARK: - Realtime Data Management
    
    // テスト機能は削除 - 実際のUWBデータのみ使用
    
    func clearRealtimeData() {
        print("🗑️ リアルタイムデータクリア")
        DispatchQueue.main.async {
            self.deviceRealtimeDataList.removeAll()
            self.isReceivingRealtimeData = false
            self.objectWillChange.send()
        }
    }
}
