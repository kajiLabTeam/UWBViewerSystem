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
    
    // ファイル受信のコールバック
    func onFileReceived(_ endpointId: String, _ fileURL: URL, _ fileName: String)
    func onFileTransferProgress(_ endpointId: String, _ progress: Int)
    
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
    
    // ファイル受信のデフォルト実装
    func onFileReceived(_ endpointId: String, _ fileURL: URL, _ fileName: String) {
        // デフォルトではconnectionStateChangedに通知
        onConnectionStateChanged(state: "ファイル受信完了: \(fileName)")
    }
    
    func onFileTransferProgress(_ endpointId: String, _ progress: Int) {
        // デフォルトではconnectionStateChangedに通知
        onConnectionStateChanged(state: "ファイル転送中: \(progress)%")
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
    private var isDiscovering = false // Discovery状態を管理

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
        
        // 既にDiscovery中の場合は何もしない
        if isDiscovering {
            callback?.onConnectionStateChanged(state: "既に検索中です")
            return
        }

        discoverer.startDiscovery { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.isDiscovering = false
                    self?.callback?.onConnectionStateChanged(state: "発見開始エラー: \(error.localizedDescription)")
                } else {
                    self?.isDiscovering = true
                    self?.callback?.onConnectionStateChanged(state: "発見開始成功")
                }
            }
        }
    }
    
    func stopDiscoveryOnly() {
        discoverer?.stopDiscovery()
        isDiscovering = false
        callback?.onConnectionStateChanged(state: "検索停止（接続は維持）")
    }

    func sendData(text: String) {
        print("=== NearbyRepository sendData開始 ===")
        print("送信データ: \(text)")
        
        guard let connectionManager else {
            print("エラー: ConnectionManager未初期化")
            callback?.onConnectionStateChanged(state: "ConnectionManager未初期化")
            return
        }

        guard !remoteEndpointIds.isEmpty else {
            print("エラー: 送信先なし")
            print("remoteEndpointIds: \(remoteEndpointIds)")
            print("connectedDevices: \(connectedDevices.keys)")
            callback?.onConnectionStateChanged(state: "送信先なし（接続端末: \(connectedDevices.count)台）")
            return
        }

        let data = Data(text.utf8)
        let endpointIds = Array(remoteEndpointIds)
        
        print("送信先エンドポイント:")
        for endpointId in endpointIds {
            let deviceName = deviceNames[endpointId] ?? "Unknown"
            print("- \(endpointId): \(deviceName)")
        }

        _ = connectionManager.send(data, to: endpointIds) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    print("データ送信エラー: \(error.localizedDescription)")
                    self?.callback?.onConnectionStateChanged(state: "データ送信エラー: \(error.localizedDescription)")
                } else {
                    print("データ送信成功: \(text)")
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
        
        print("=== NearbyRepository sendData終了 ===")
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
        isDiscovering = false // Discovery状態もリセット
        
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
    
    func hasConnectedDevices() -> Bool {
        return !connectedDevices.isEmpty
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
        // 接続要求のcontextからデバイス名を取得（送信側が名前を送信）
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
        // Android側から送信されたAdvertising情報（端末名を含む）を取得
        let deviceName = String(data: context, encoding: .utf8) ?? endpointID
        
        // デバイス名を保存
        deviceNames[endpointID] = deviceName
        
        // 発見したエンドポイントに自動で接続要求を送信
        let connectionContext = Data(nickName.utf8)
        discoverer.requestConnection(to: endpointID, using: connectionContext)
        callback?.onConnectionStateChanged(state: "エンドポイント発見: \(deviceName) (\(endpointID))")
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
        // ファイル受信開始の処理
        callback?.onConnectionStateChanged(state: "ファイル受信開始: \(name) from \(endpointID)")
        
        // ファイル受信完了時の処理は別途実装
        // localURLにファイルが保存される
        let deviceName = deviceNames[endpointID] ?? endpointID
        
        // ファイルを適切な場所に移動・保存
        saveReceivedFile(from: localURL, originalName: name, fromDevice: deviceName, endpointID: endpointID)
    }
    
    // 受信したファイルを保存する処理
    private func saveReceivedFile(from tempURL: URL, originalName: String, fromDevice: String, endpointID: String) {
        let fileManager = FileManager.default
        
        // Documentsディレクトリ内にUWBFilesフォルダを作成
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            callback?.onConnectionStateChanged(state: "ファイル保存エラー: Documentsフォルダにアクセスできません")
            return
        }
        
        let uwbFilesDirectory = documentsDirectory.appendingPathComponent("UWBFiles")
        
        // ディレクトリが存在しない場合は作成
        if !fileManager.fileExists(atPath: uwbFilesDirectory.path) {
            do {
                try fileManager.createDirectory(at: uwbFilesDirectory, withIntermediateDirectories: true)
            } catch {
                callback?.onConnectionStateChanged(state: "ファイル保存エラー: フォルダ作成に失敗 - \(error.localizedDescription)")
                return
            }
        }
        
        // タイムスタンプを作成
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timeString = dateFormatter.string(from: Date())
        
        // 元のファイル名から拡張子を分離
        let originalNameWithoutExtension = (originalName as NSString).deletingPathExtension
        let originalExtension = (originalName as NSString).pathExtension
        
        // 最終的なファイル名を構成: タイムスタンプ_デバイス名_Mac側ファイル名.csv
        // originalNameWithoutExtensionには既にMac側で入力したファイル名が含まれている
        let finalFileName: String
        if originalExtension.lowercased() == "csv" || originalExtension.isEmpty {
            // CSVファイルまたは拡張子なしの場合、CSV拡張子を確実に追加
            finalFileName = "\(timeString)_\(fromDevice)_\(originalNameWithoutExtension).csv"
        } else {
            // 他の拡張子の場合も、CSVとして保存
            finalFileName = "\(timeString)_\(fromDevice)_\(originalName).csv"
        }
        
        let destinationURL = uwbFilesDirectory.appendingPathComponent(finalFileName)
        
        print("ファイル保存処理:")
        print("- 受信した元ファイル名: \(originalName)")
        print("- 拡張子なしファイル名: \(originalNameWithoutExtension)")
        print("- 元拡張子: \(originalExtension)")
        print("- 送信デバイス名: \(fromDevice)")
        print("- 最終ファイル名: \(finalFileName)")
        print("- 保存先: \(destinationURL.path)")
        
        do {
            // 既存ファイルがある場合は削除
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            
            // ファイルを移動
            try fileManager.moveItem(at: tempURL, to: destinationURL)
            
            callback?.onConnectionStateChanged(state: "ファイル保存完了: \(finalFileName)")
            callback?.onFileReceived(endpointID, destinationURL, finalFileName)
            
        } catch {
            callback?.onConnectionStateChanged(state: "ファイル保存エラー: \(error.localizedDescription)")
        }
    }

    func connectionManager(
        _ connectionManager: ConnectionManager,
        didReceiveTransferUpdate update: TransferUpdate,
        from endpointID: String,
        forPayload payloadID: PayloadID
    ) {
        // 転送状況の更新処理
        // 実際のTransferUpdateの構造に合わせて修正が必要
        // 現在は基本的な通知のみ実装
        callback?.onConnectionStateChanged(state: "ファイル転送更新: \(endpointID)")
        
        // 進捗については後で実装
        // 一旦50%として固定値で通知
        callback?.onFileTransferProgress(endpointID, 50)
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
