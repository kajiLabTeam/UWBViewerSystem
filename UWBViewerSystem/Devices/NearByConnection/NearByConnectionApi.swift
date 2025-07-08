//
//  NearByConnectionApi.swift
//  UWBViewerSystem
//
//  Created by はるちろ on R 7/07/08.
//

import Foundation
import NearbyConnections

// MARK: - Data Models

/// 接続要求の情報
struct ConnectionRequest: Identifiable, Equatable {
    let id = UUID()
    let endpointId: String
    let deviceName: String
    let requestTime: Date
    let context: Data
    let responseHandler: (Bool) -> Void
    
    static func == (lhs: ConnectionRequest, rhs: ConnectionRequest) -> Bool {
        return lhs.id == rhs.id &&
               lhs.endpointId == rhs.endpointId &&
               lhs.deviceName == rhs.deviceName &&
               lhs.requestTime == rhs.requestTime &&
               lhs.context == rhs.context
        // responseHandlerは比較から除外（関数は比較できないため）
    }
}

/// 接続済み端末の情報
struct ConnectedDevice: Identifiable, Equatable {
    let id = UUID()
    let endpointId: String
    let deviceName: String
    let connectTime: Date
    var lastMessageTime: Date?
    var isActive: Bool = true
    
    static func == (lhs: ConnectedDevice, rhs: ConnectedDevice) -> Bool {
        return lhs.id == rhs.id &&
               lhs.endpointId == rhs.endpointId &&
               lhs.deviceName == rhs.deviceName &&
               lhs.connectTime == rhs.connectTime &&
               lhs.lastMessageTime == rhs.lastMessageTime &&
               lhs.isActive == rhs.isActive
    }
}

/// メッセージの情報
struct Message: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let fromEndpointId: String?
    let fromDeviceName: String
    let timestamp: Date
    let isOutgoing: Bool
    
    static func == (lhs: Message, rhs: Message) -> Bool {
        return lhs.id == rhs.id &&
               lhs.content == rhs.content &&
               lhs.fromEndpointId == rhs.fromEndpointId &&
               lhs.fromDeviceName == rhs.fromDeviceName &&
               lhs.timestamp == rhs.timestamp &&
               lhs.isOutgoing == rhs.isOutgoing
    }
}

protocol NearbyRepositoryCallback: AnyObject {
    // 古いコールバック（HomeViewModelとの互換性のため）
    func onConnectionStateChanged(state: String)
    func onDataReceived(data: String, fromEndpointId: String)
    
    // 新しいコールバック（AdvertiserViewModelでの詳細な制御用）
    func onConnectionInitiated(_ endpointId: String, _ deviceName: String, _ context: Data, _ responseHandler: @escaping (Bool) -> Void)
    func onConnectionResult(_ endpointId: String, _ isSuccess: Bool)
    func onDisconnected(_ endpointId: String)
    func onPayloadReceived(_ endpointId: String, _ payload: Data)
    
    // 従来のコールバック（デフォルト実装で互換性を保つ）
    func onConnectionRequestReceived(request: ConnectionRequest)
    func onDeviceConnected(device: ConnectedDevice)
    func onDeviceDisconnected(endpointId: String)
    func onMessageReceived(message: Message)
}

// デフォルト実装を提供（既存のViewModelとの互換性のため）
extension NearbyRepositoryCallback {
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
}

class NearbyRepository: NSObject {
    weak var callback: NearbyRepositoryCallback?
    private let nickName: String
    private let serviceId: String
    private var remoteEndpointIds: Set<String> = []

    private var advertiser: Advertiser?
    private var discoverer: Discoverer?
    private var connectionManager: ConnectionManager?
    
    // 新しいプロパティ
    private var connectedDevices: [String: ConnectedDevice] = [:]
    private var messages: [Message] = []
    private var deviceNames: [String: String] = [:] // endpointId -> deviceName

    init(nickName: String = "harutiro",
         serviceId: String = "net.harutiro.UWBSystem") {
        self.nickName = nickName
        self.serviceId = serviceId
        super.init()

        connectionManager = ConnectionManager(
            serviceID: serviceId,
            strategy: .star
        )

        setupDelegates()
    }

    private func setupDelegates() {
        guard let connectionManager else { return }

        // Advertiser初期化
        advertiser = Advertiser(connectionManager: connectionManager)
        advertiser?.delegate = self

        // Discoverer初期化
        discoverer = Discoverer(connectionManager: connectionManager)
        discoverer?.delegate = self

        // ConnectionManager デリゲート設定
        connectionManager.delegate = self
    }

    func startAdvertise() {
        guard let advertiser else {
            callback?.onConnectionStateChanged(state: "Advertiser未初期化")
            return
        }

        let context = Data(nickName.utf8)
        advertiser.startAdvertising(using: context) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.callback?.onConnectionStateChanged(state: "広告開始エラー: \(error.localizedDescription)")
                } else {
                    self?.callback?.onConnectionStateChanged(state: "広告開始成功")
                }
            }
        }
    }

    func startDiscovery() {
        guard let discoverer else {
            callback?.onConnectionStateChanged(state: "Discoverer未初期化")
            return
        }

        discoverer.startDiscovery { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.callback?.onConnectionStateChanged(state: "発見開始エラー: \(error.localizedDescription)")
                } else {
                    self?.callback?.onConnectionStateChanged(state: "発見開始成功")
                }
            }
        }
    }

    func sendData(text: String) {
        guard let connectionManager else {
            callback?.onConnectionStateChanged(state: "ConnectionManager未初期化")
            return
        }

        guard !remoteEndpointIds.isEmpty else {
            callback?.onConnectionStateChanged(state: "送信先なし")
            return
        }

        let data = Data(text.utf8)
        let endpointIds = Array(remoteEndpointIds)

        _ = connectionManager.send(data, to: endpointIds) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.callback?.onConnectionStateChanged(state: "データ送信エラー: \(error.localizedDescription)")
                } else {
                    self?.callback?.onConnectionStateChanged(state: "データ送信完了: \(text)")
                    
                    // メッセージ履歴に追加
                    let message = Message(
                        content: text,
                        fromEndpointId: nil,
                        fromDeviceName: self?.nickName ?? "自分",
                        timestamp: Date(),
                        isOutgoing: true
                    )
                    self?.messages.append(message)
                    self?.callback?.onMessageReceived(message: message)
                }
            }
        }
    }
    
    // 新しいメソッド
    func sendDataToDevice(text: String, toEndpointId: String) {
        guard let connectionManager else {
            callback?.onConnectionStateChanged(state: "ConnectionManager未初期化")
            return
        }
        
        guard remoteEndpointIds.contains(toEndpointId) else {
            callback?.onConnectionStateChanged(state: "指定された端末は接続されていません")
            return
        }
        
        let data = Data(text.utf8)
        
        _ = connectionManager.send(data, to: [toEndpointId]) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.callback?.onConnectionStateChanged(state: "データ送信エラー: \(error.localizedDescription)")
                } else {
                    let deviceName = self?.deviceNames[toEndpointId] ?? toEndpointId
                    self?.callback?.onConnectionStateChanged(state: "\(deviceName)にデータ送信完了: \(text)")
                    
                    // メッセージ履歴に追加
                    let message = Message(
                        content: text,
                        fromEndpointId: nil,
                        fromDeviceName: self?.nickName ?? "自分",
                        timestamp: Date(),
                        isOutgoing: true
                    )
                    self?.messages.append(message)
                    self?.callback?.onMessageReceived(message: message)
                }
            }
        }
    }
    
    func disconnectFromDevice(endpointId: String) {
        connectionManager?.disconnect(from: endpointId)
        remoteEndpointIds.remove(endpointId)
        connectedDevices.removeValue(forKey: endpointId)
        deviceNames.removeValue(forKey: endpointId)
        callback?.onDeviceDisconnected(endpointId: endpointId)
    }

    func disconnectAll() {
        for endpointId in remoteEndpointIds {
            connectionManager?.disconnect(from: endpointId)
        }
        remoteEndpointIds.removeAll()
        connectedDevices.removeAll()
        deviceNames.removeAll()
        callback?.onConnectionStateChanged(state: "全接続切断完了")
    }

    func resetAll() {
        disconnectAll()

        advertiser?.stopAdvertising()
        discoverer?.stopDiscovery()
        
        messages.removeAll()

        callback?.onConnectionStateChanged(state: "リセット完了")
    }
    
    // 新しいメソッド（AdvertiserViewModel用）
    func stopAdvertise() {
        advertiser?.stopAdvertising()
        callback?.onConnectionStateChanged(state: "広告停止")
    }
    
    func disconnect(_ endpointId: String) {
        disconnectFromDevice(endpointId: endpointId)
    }
    
    func sendMessage(_ content: String, to endpointId: String) {
        sendDataToDevice(text: content, toEndpointId: endpointId)
    }
    
    // 新しいメソッド
    func getConnectedDevices() -> [ConnectedDevice] {
        return Array(connectedDevices.values)
    }
    
    func getMessages() -> [Message] {
        return messages
    }
    
    func getCurrentDeviceName() -> String {
        return nickName
    }
}

// MARK: - AdvertiserDelegate

extension NearbyRepository: AdvertiserDelegate {
    func advertiser(
        _ advertiser: Advertiser,
        didReceiveConnectionRequestFrom endpointID: String,
        with context: Data,
        connectionRequestHandler: @escaping (Bool) -> Void
    ) {
        // 手動承認のためにコールバックに通知
        let deviceName = String(data: context, encoding: .utf8) ?? endpointID
        
        // デバイス名を保存
        deviceNames[endpointID] = deviceName
        
        // 新しいコールバック形式を呼び出し
        callback?.onConnectionInitiated(endpointID, deviceName, context, connectionRequestHandler)
        callback?.onConnectionStateChanged(state: "接続要求受信: \(deviceName) (\(endpointID))")
    }
}

// MARK: - DiscovererDelegate

extension NearbyRepository: DiscovererDelegate {
    func discoverer(
        _ discoverer: Discoverer,
        didFind endpointID: String,
        with context: Data
    ) {
        // 発見したエンドポイントに自動で接続要求を送信
        let connectionContext = Data(nickName.utf8)
        discoverer.requestConnection(to: endpointID, using: connectionContext)
        callback?.onConnectionStateChanged(state: "エンドポイント発見: \(endpointID)")
    }

    func discoverer(_ discoverer: Discoverer, didLose endpointID: String) {
        callback?.onConnectionStateChanged(state: "エンドポイント消失: \(endpointID)")
    }
}

// MARK: - ConnectionManagerDelegate

extension NearbyRepository: ConnectionManagerDelegate {
    func connectionManager(
        _ connectionManager: ConnectionManager,
        didReceive verificationCode: String,
        from endpointID: String,
        verificationHandler: @escaping (Bool) -> Void
    ) {
        // 自動で認証を承認
        verificationHandler(true)
        remoteEndpointIds.insert(endpointID)
        
        // 接続済み端末として追加
        let deviceName = deviceNames[endpointID] ?? endpointID
        let device = ConnectedDevice(
            endpointId: endpointID,
            deviceName: deviceName,
            connectTime: Date()
        )
        connectedDevices[endpointID] = device
        
        callback?.onConnectionStateChanged(state: "接続成功: \(deviceName)")
        callback?.onConnectionResult(endpointID, true)
        callback?.onDeviceConnected(device: device)
    }

    func connectionManager(
        _ connectionManager: ConnectionManager,
        didReceive data: Data,
        withID payloadID: PayloadID,
        from endpointID: String
    ) {
        let receivedText = String(data: data, encoding: .utf8) ?? ""
        let deviceName = deviceNames[endpointID] ?? endpointID
        
        // 最終受信時刻を更新
        if var device = connectedDevices[endpointID] {
            device.lastMessageTime = Date()
            connectedDevices[endpointID] = device
        }
        
        // メッセージ履歴に追加
        let message = Message(
            content: receivedText,
            fromEndpointId: endpointID,
            fromDeviceName: deviceName,
            timestamp: Date(),
            isOutgoing: false
        )
        messages.append(message)
        
        // 新しいコールバック形式を呼び出し
        callback?.onPayloadReceived(endpointID, data)
        
        // 古いコールバック形式も維持（互換性のため）
        callback?.onDataReceived(data: receivedText, fromEndpointId: endpointID)
        callback?.onMessageReceived(message: message)
    }

    func connectionManager(
        _ connectionManager: ConnectionManager,
        didReceive stream: InputStream,
        withID payloadID: PayloadID,
        from endpointID: String,
        cancellationToken token: CancellationToken
    ) {
        // ストリーム受信の処理（今回は使用しない）
    }

    func connectionManager(
        _ connectionManager: ConnectionManager,
        didStartReceivingResourceWithID payloadID: PayloadID,
        from endpointID: String,
        at localURL: URL,
        withName name: String,
        cancellationToken token: CancellationToken
    ) {
        // ファイル受信の処理（今回は使用しない）
    }

    func connectionManager(
        _ connectionManager: ConnectionManager,
        didReceiveTransferUpdate update: TransferUpdate,
        from endpointID: String,
        forPayload payloadID: PayloadID
    ) {
        // 転送状況の更新処理
        // TransferUpdateの詳細処理は実際のAPIに合わせて後で実装
        callback?.onConnectionStateChanged(state: "データ転送更新: \(endpointID)")
    }

    func connectionManager(
        _ connectionManager: ConnectionManager,
        didChangeTo state: ConnectionState,
        for endpointID: String
    ) {
        switch state {
        case .connecting:
            callback?.onConnectionStateChanged(state: "接続中: \(endpointID)")
        case .connected:
            let deviceName = deviceNames[endpointID] ?? endpointID
            callback?.onConnectionStateChanged(state: "接続完了: \(deviceName)")
        case .disconnected:
            remoteEndpointIds.remove(endpointID)
            connectedDevices.removeValue(forKey: endpointID)
            deviceNames.removeValue(forKey: endpointID)
            
            // 新しいコールバック形式を呼び出し
            callback?.onDisconnected(endpointID)
            
            // 古いコールバック形式も維持（互換性のため）
            callback?.onConnectionStateChanged(state: "切断: \(endpointID)")
            callback?.onDeviceDisconnected(endpointId: endpointID)
        case .rejected:
            callback?.onConnectionStateChanged(state: "接続拒否: \(endpointID)")
            callback?.onConnectionResult(endpointID, false)
        @unknown default:
            break
        }
    }
}
