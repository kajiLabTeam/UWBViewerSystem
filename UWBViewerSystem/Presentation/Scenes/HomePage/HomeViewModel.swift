//
//  HomeViewModel.swift
//  UWBViewerSystem
//
//  Created by はるちろ on R 7/04/07.
//

import CoreLocation
import Foundation
import SwiftUI

@MainActor
class HomeViewModel: NSObject, ObservableObject, @preconcurrency NearbyRepositoryCallback {

    // MARK: - Usecases

    let realtimeDataUsecase: RealtimeDataUsecase
    let connectionUsecase: ConnectionManagementUsecase
    let sensingControlUsecase: SensingControlUsecase
    let fileManagementUsecase: FileManagementUsecase

    let nearByRepository: NearbyRepository

    // MARK: - Dependency Injection対応のイニシャライザ

    public init(
        nearbyRepository: NearbyRepository? = nil,
        connectionUsecase: ConnectionManagementUsecase? = nil,
        realtimeDataUsecase: RealtimeDataUsecase? = nil,
        sensingControlUsecase: SensingControlUsecase? = nil,
        fileManagementUsecase: FileManagementUsecase? = nil
    ) {
        // 依存関係の注入または新規作成
        nearByRepository = nearbyRepository ?? NearbyRepository()
        self.connectionUsecase =
            connectionUsecase ?? ConnectionManagementUsecase(nearbyRepository: nearByRepository)
        self.realtimeDataUsecase = realtimeDataUsecase ?? RealtimeDataUsecase()
        self.sensingControlUsecase =
            sensingControlUsecase ?? SensingControlUsecase(connectionUsecase: self.connectionUsecase)
        self.fileManagementUsecase = fileManagementUsecase ?? FileManagementUsecase()

        super.init()
        nearByRepository.callback = self
    }

    // MARK: - Factory Method（従来互換性のため）

    /// 従来のsharedパターンと同じ動作をするファクトリーメソッド
    /// 新しいコードではDI対応のイニシャライザを使用することを推奨
    @available(*, deprecated, message: "Use dependency injection initializer instead")
    public static func createDefault() -> HomeViewModel {
        HomeViewModel()
    }

    // MARK: - Published Properties (プロパティのフォワード)

    @Published var receivedDataList: [(String, String)] = []

    // 接続管理関連
    var connectState: String {
        connectionUsecase.connectState
    }

    var isLocationPermissionGranted: Bool {
        connectionUsecase.isLocationPermissionGranted
    }

    var connectedDeviceNames: Set<String> {
        connectionUsecase.connectedDeviceNames
    }

    var connectedEndpoints: Set<String> {
        connectionUsecase.connectedEndpoints
    }

    var isAdvertising: Bool {
        connectionUsecase.isAdvertising
    }

    // センシング制御関連
    var sensingStatus: String {
        sensingControlUsecase.sensingStatus
    }

    var isSensingControlActive: Bool {
        sensingControlUsecase.isSensingControlActive
    }

    var sensingFileName: String {
        sensingControlUsecase.sensingFileName
    }

    var currentSensingFileName: String {
        sensingControlUsecase.currentSensingFileName
    }

    // リアルタイムデータ関連
    var deviceRealtimeDataList: [DeviceRealtimeData] {
        realtimeDataUsecase.deviceRealtimeDataList
    }

    var isReceivingRealtimeData: Bool {
        realtimeDataUsecase.isReceivingRealtimeData
    }

    // ファイル管理関連
    var receivedFiles: [ReceivedFile] {
        fileManagementUsecase.receivedFiles
    }

    var fileTransferProgress: [String: Int] {
        fileManagementUsecase.fileTransferProgress
    }

    var fileStoragePath: String {
        fileManagementUsecase.fileStoragePath
    }

    // MARK: - Public Methods

    func startAdvertise() {
        connectionUsecase.startAdvertising()
    }

    func startDiscovery() {
        connectionUsecase.startDiscovery()
    }

    func sendData(text: String) {
        connectionUsecase.sendMessage(text)
    }

    func startRemoteSensing(fileName: String) {
        sensingControlUsecase.startRemoteSensing(fileName: fileName)
    }

    func stopRemoteSensing() {
        sensingControlUsecase.stopRemoteSensing()
    }

    func pauseRemoteSensing() {
        sensingControlUsecase.pauseRemoteSensing()
    }

    func resumeRemoteSensing() {
        sensingControlUsecase.resumeRemoteSensing()
    }

    func disconnectAll() {
        connectionUsecase.disconnectAll()
        realtimeDataUsecase.clearAllRealtimeData()
        fileManagementUsecase.clearReceivedFiles()
    }

    func resetAll() {
        connectionUsecase.resetAll()
        receivedDataList = []
        realtimeDataUsecase.clearAllRealtimeData()
        fileManagementUsecase.clearReceivedFiles()
    }

    func clearRealtimeData() {
        realtimeDataUsecase.clearAllRealtimeData()
    }

    func openFileStorageFolder() {
        fileManagementUsecase.openFileStorageFolder()
    }

    // ConnectionManagementViewModel用のメソッド
    func startAdvertising() {
        connectionUsecase.startAdvertising()
    }

    func stopAdvertising() {
        connectionUsecase.stopAdvertising()
    }

    func disconnectEndpoint(_ endpointId: String) {
        connectionUsecase.disconnectFromDevice(endpointId: endpointId)
    }

    func sendMessage(_ content: String, to endpointId: String) {
        connectionUsecase.sendMessageToDevice(content, to: endpointId)
    }

    // MARK: - NearbyRepositoryCallback

    func onConnectionStateChanged(state: String) {
        DispatchQueue.main.async {
            self.connectionUsecase.onConnectionStateChanged(state: state)
        }
    }

    func onDataReceived(data: String, fromEndpointId: String) {
        DispatchQueue.main.async {
            print("=== Mac側データ受信開始 ===")
            print("EndpointID: \(fromEndpointId)")
            print("データ長: \(data.count) bytes")
            print("受信データ: \(data)")

            self.receivedDataList.append((fromEndpointId, data))

            // リアルタイムデータの処理
            self.processRealtimeData(data, fromEndpointId: fromEndpointId)

            print("=== Mac側データ受信終了 ===")
        }
    }

    func onConnectionRequestReceived(request: ConnectionRequest) {
        DispatchQueue.main.async {
            // HomeViewModelでは自動承認（基本画面なので）
            request.responseHandler(true)
            self.connectionUsecase.onConnectionStateChanged(state: "接続要求を自動承認: \(request.deviceName)")
        }
    }

    func onDeviceConnected(device: ConnectedDevice) {
        DispatchQueue.main.async {
            self.connectionUsecase.onDeviceConnected(device: device)
            self.realtimeDataUsecase.addConnectedDevice(device.deviceName)
        }
    }

    func onDeviceDisconnected(endpointId: String) {
        DispatchQueue.main.async {
            self.connectionUsecase.onDeviceDisconnected(endpointId: endpointId)
        }
    }

    func onMessageReceived(message: Message) {
        DispatchQueue.main.async {
            print("🔵 Mac HomeViewModel: onMessageReceived")
            print("🔵 エンドポイント: \(message.senderId)")
            print("🔵 デバイス名: \(message.senderName)")
            print("🔵 メッセージ長: \(message.content.count) 文字")
            print("🔵 メッセージ先頭: \(String(message.content.prefix(100)))")

            if message.content.contains("REALTIME_DATA") {
                print("🟢 REALTIME_DATAを検出 - 直接処理開始")
                if let data = message.content.data(using: .utf8) {
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            print("🟢 JSON解析成功 - processRealtimeDataJSON呼び出し")
                            self.realtimeDataUsecase.processRealtimeDataMessage(
                                json, fromEndpointId: message.senderId)
                        }
                    } catch {
                        print("🔴 JSON解析エラー: \(error)")
                    }
                }
            } else {
                print("🔴 非REALTIME_DATAメッセージ: \(message.content)")

                if message.content.contains("SENSING") {
                    print("📡 センシング関連メッセージを受信")
                    if message.content.contains("STOP") {
                        print("⏸️ Android側でセンシング停止")
                        self.realtimeDataUsecase.clearAllRealtimeData()
                    }
                }
            }

            self.receivedDataList.append((message.senderName, message.content))
        }
    }

    // ファイル受信のコールバック実装
    func onFileReceived(_ endpointId: String, _ fileURL: URL, _ fileName: String) {
        DispatchQueue.main.async {
            self.fileManagementUsecase.onFileReceived(
                endpointId: endpointId,
                fileURL: fileURL,
                fileName: fileName,
                deviceNames: self.connectionUsecase.connectedDeviceNames
            )

            self.connectionUsecase.onConnectionStateChanged(state: "ファイル受信完了: \(fileName)")
        }
    }

    func onFileTransferProgress(_ endpointId: String, _ progress: Int) {
        DispatchQueue.main.async {
            self.fileManagementUsecase.onFileTransferProgress(endpointId: endpointId, progress: progress)
        }
    }

    // 新しいコールバック（AdvertiserViewModelでの詳細な制御用）
    func onConnectionInitiated(
        _ endpointId: String, _ deviceName: String, _ context: Data, _ responseHandler: @escaping (Bool) -> Void
    ) {
        let request = ConnectionRequest(
            endpointId: endpointId,
            deviceName: deviceName,
            timestamp: Date(),
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

    // MARK: - Private Methods

    private func processRealtimeData(_ data: String, fromEndpointId: String = "") {
        print("=== processRealtimeData開始 ===")
        print("処理対象データ: \(data)")

        // JSONデータかどうかチェック
        if data.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{")
            && data.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("}")
        {

            print("JSONフォーマット確認: OK")

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
                            Task { @MainActor in
                                realtimeDataUsecase.processRealtimeDataMessage(json, fromEndpointId: fromEndpointId)
                            }
                        case "PING":
                            print("Ping処理開始")
                            processPingMessage(json, fromEndpointId: fromEndpointId)
                        case "FILE_TRANSFER_START":
                            print("ファイル転送開始処理")
                            Task { @MainActor in
                                fileManagementUsecase.processFileTransferStart(json, fromEndpointId: fromEndpointId)
                            }
                        default:
                            print("未知のJSONタイプ: \(type)")
                            Task { @MainActor in
                                connectionUsecase.onConnectionStateChanged(state: "受信: \(type) メッセージ")
                            }
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
            Task { @MainActor in
                connectionUsecase.onConnectionStateChanged(state: "コマンドレスポンス: \(data)")
            }
        }

        print("=== processRealtimeData終了 ===")
    }

    private func processPingMessage(_ json: [String: Any], fromEndpointId: String) {
        let fromDevice = json["from"] as? String ?? "Unknown"
        let timestamp = json["timestamp"] as? Int64 ?? 0

        print("Ping received from: \(fromDevice)")
        Task { @MainActor in
            connectionUsecase.onConnectionStateChanged(
                state: "Ping受信: \(fromDevice) at \(Date(timeIntervalSince1970: Double(timestamp) / 1000))")
        }

        // Pingに対するPong応答を送信
        let pongMessage = """
        {
            "type": "PONG",
            "timestamp": \(Int64(Date().timeIntervalSince1970 * 1000)),
            "from": "Mac",
            "responseTo": "\(fromDevice)"
        }
        """

        Task { @MainActor in
            connectionUsecase.sendMessage(pongMessage)
        }
        print("Pong response sent to: \(fromDevice)")
    }

    // MARK: - NearbyRepositoryCallback Protocol Implementation

    func onDiscoveryStateChanged(isDiscovering: Bool) {
        // デフォルトでは何もしない
    }

    func onDeviceFound(endpointId: String, name: String, isConnectable: Bool) {
        // デフォルトでは何もしない
    }

    func onDeviceLost(endpointId: String) {
        // デフォルトでは何もしない
    }

    func onConnectionRequest(endpointId: String, deviceName: String, context: Data, accept: @escaping (Bool) -> Void) {
        let request = ConnectionRequest(
            endpointId: endpointId,
            deviceName: deviceName,
            timestamp: Date(),
            context: context,
            responseHandler: accept
        )
        onConnectionRequestReceived(request: request)
    }

    func onDataReceived(endpointId: String, data: Data) {
        if let messageContent = String(data: data, encoding: .utf8) {
            let message = Message(
                content: messageContent,
                timestamp: Date(),
                senderId: endpointId,
                senderName: "Unknown",
                isOutgoing: false
            )
            onMessageReceived(message: message)
        }
    }

    func onDeviceConnected(endpointId: String, deviceName: String) {
        // デフォルトでは何もしない
    }
}
