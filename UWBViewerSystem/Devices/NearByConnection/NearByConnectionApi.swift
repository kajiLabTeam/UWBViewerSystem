//
//  NearByConnectionApi.swift
//  UWBViewerSystem
//
//  Created by はるちろ on R 7/07/08.
//

import Foundation

#if canImport(NearbyConnections)
    import NearbyConnections

    // MARK: - Data Models

    // ConnectionRequest、Message、ConnectedDeviceはCommonTypes.swiftで定義済み

    // グローバルの型を明示的に参照するためのtypealiasを追加
    typealias GlobalConnectionRequest = ConnectionRequest
    typealias GlobalMessage = Message

    protocol NearbyRepositoryCallback: AnyObject {
        // 検索とディスカバリー関連
        func onDiscoveryStateChanged(isDiscovering: Bool)
        func onDeviceFound(endpointId: String, name: String, isConnectable: Bool)
        func onDeviceLost(endpointId: String)

        // 接続関連
        func onConnectionRequest(
            endpointId: String, deviceName: String, context: Data, accept: @escaping (Bool) -> Void)
        func onConnectionResult(_ endpointId: String, _ success: Bool)
        func onDeviceConnected(endpointId: String, deviceName: String)
        func onDeviceDisconnected(endpointId: String)

        // データ通信関連
        func onConnectionStateChanged(state: String)
        func onDataReceived(endpointId: String, data: Data)

        // 古いコールバック（既存のViewModelとの互換性のため）
        func onDataReceived(data: String, fromEndpointId: String)
    }

    // デフォルト実装を提供（オプショナルメソッドに対して）
    extension NearbyRepositoryCallback {
        func onDiscoveryStateChanged(isDiscovering: Bool) {
            // デフォルトでは何もしない
        }

        func onDeviceFound(endpointId: String, name: String, isConnectable: Bool) {
            // デフォルトでは何もしない
        }

        func onDeviceLost(endpointId: String) {
            // デフォルトでは何もしない
        }

        func onConnectionResult(_ endpointId: String, _ success: Bool) {
            // デフォルトでは何もしない
        }

        // 互換性のための変換
        func onDataReceived(data: String, fromEndpointId: String) {
            // 新しい形式を使用している場合は、古いメソッドから新しいメソッドへ変換
            if let data = data.data(using: .utf8) {
                self.onDataReceived(endpointId: fromEndpointId, data: data)
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
        private var deviceNames: [String: String] = [:]  // endpointId -> deviceName
        private var isDiscovering = false  // Discovery状態を管理

        init(
            nickName: String = "harutiro",
            serviceId: String = "net.harutiro.UWBSystem"
        ) {
            self.nickName = nickName
            self.serviceId = serviceId
            super.init()

            self.connectionManager = ConnectionManager(
                serviceID: serviceId,
                strategy: .star
            )

            self.setupDelegates()
        }

        private func setupDelegates() {
            guard let connectionManager else { return }

            // Advertiser初期化
            self.advertiser = Advertiser(connectionManager: connectionManager)
            self.advertiser?.delegate = self

            // Discoverer初期化
            self.discoverer = Discoverer(connectionManager: connectionManager)
            self.discoverer?.delegate = self

            // ConnectionManager デリゲート設定
            connectionManager.delegate = self
        }

        func startAdvertise() {
            guard let advertiser else {
                self.callback?.onConnectionStateChanged(state: "Advertiser未初期化")
                return
            }

            let context = Data(nickName.utf8)
            advertiser.startAdvertising(using: context) { [weak self] error in
                Task { @MainActor [weak self] in
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
                self.callback?.onConnectionStateChanged(state: "Discoverer未初期化")
                return
            }

            // 既にDiscovery中の場合は何もしない
            if self.isDiscovering {
                self.callback?.onConnectionStateChanged(state: "既に検索中です")
                return
            }

            discoverer.startDiscovery { [weak self] error in
                Task { @MainActor [weak self] in
                    if let error {
                        self?.isDiscovering = false
                        self?.callback?.onConnectionStateChanged(state: "発見開始エラー: \(error.localizedDescription)")
                    } else {
                        self?.isDiscovering = true
                        self?.callback?.onConnectionStateChanged(state: "発見開始成功")
                        self?.callback?.onDiscoveryStateChanged(isDiscovering: true)
                    }
                }
            }
        }

        func stopDiscoveryOnly() {
            self.discoverer?.stopDiscovery()
            self.isDiscovering = false
            self.callback?.onConnectionStateChanged(state: "検索停止（接続は維持）")
            self.callback?.onDiscoveryStateChanged(isDiscovering: false)
        }

        func sendData(text: String) {
            print("=== NearbyRepository sendData開始 ===")
            print("送信データ: \(text)")

            guard let connectionManager else {
                print("エラー: ConnectionManager未初期化")
                self.callback?.onConnectionStateChanged(state: "ConnectionManager未初期化")
                return
            }

            guard !self.remoteEndpointIds.isEmpty else {
                print("エラー: 送信先なし")
                print("remoteEndpointIds: \(self.remoteEndpointIds)")
                print("connectedDevices: \(self.connectedDevices.keys)")
                self.callback?.onConnectionStateChanged(state: "送信先なし（接続端末: \(self.connectedDevices.count)台）")
                return
            }

            let data = Data(text.utf8)
            let endpointIds = Array(remoteEndpointIds)

            print("送信先エンドポイント:")
            for endpointId in endpointIds {
                let deviceName = self.deviceNames[endpointId] ?? "Unknown"
                print("- \(endpointId): \(deviceName)")
            }

            _ = connectionManager.send(data, to: endpointIds) { [weak self] error in
                Task { @MainActor [weak self] in
                    if let error {
                        print("データ送信エラー: \(error.localizedDescription)")
                        self?.callback?.onConnectionStateChanged(state: "データ送信エラー: \(error.localizedDescription)")
                    } else {
                        print("データ送信成功: \(text)")
                        self?.callback?.onConnectionStateChanged(state: "データ送信完了: \(text)")

                        // メッセージ履歴に追加
                        let message = Message(
                            content: text,
                            timestamp: Date(),
                            senderId: "self",
                            senderName: self?.nickName ?? "自分",
                            isOutgoing: true
                        )
                        self?.messages.append(message)
                    }
                }
            }

            print("=== NearbyRepository sendData終了 ===")
        }

        // 新しいメソッド
        func sendDataToDevice(text: String, toEndpointId: String) {
            guard let connectionManager else {
                self.callback?.onConnectionStateChanged(state: "ConnectionManager未初期化")
                return
            }

            guard self.remoteEndpointIds.contains(toEndpointId) else {
                self.callback?.onConnectionStateChanged(state: "指定された端末は接続されていません")
                return
            }

            let data = Data(text.utf8)

            _ = connectionManager.send(data, to: [toEndpointId]) { [weak self] error in
                Task { @MainActor [weak self] in
                    if let error {
                        self?.callback?.onConnectionStateChanged(state: "データ送信エラー: \(error.localizedDescription)")
                    } else {
                        let deviceName = self?.deviceNames[toEndpointId] ?? toEndpointId
                        self?.callback?.onConnectionStateChanged(state: "\(deviceName)にデータ送信完了: \(text)")

                        // メッセージ履歴に追加
                        let message = Message(
                            content: text,
                            timestamp: Date(),
                            senderId: "self",
                            senderName: self?.nickName ?? "自分",
                            isOutgoing: true
                        )
                        self?.messages.append(message)
                    }
                }
            }
        }

        func disconnectFromDevice(endpointId: String) {
            self.connectionManager?.disconnect(from: endpointId)
            self.remoteEndpointIds.remove(endpointId)
            self.connectedDevices.removeValue(forKey: endpointId)
            self.deviceNames.removeValue(forKey: endpointId)
            self.callback?.onDeviceDisconnected(endpointId: endpointId)
        }

        func disconnectAll() {
            for endpointId in self.remoteEndpointIds {
                self.connectionManager?.disconnect(from: endpointId)
            }
            self.remoteEndpointIds.removeAll()
            self.connectedDevices.removeAll()
            self.deviceNames.removeAll()
            self.callback?.onConnectionStateChanged(state: "全接続切断完了")
        }

        func resetAll() {
            self.disconnectAll()

            self.advertiser?.stopAdvertising()
            self.discoverer?.stopDiscovery()
            self.isDiscovering = false  // Discovery状態もリセット

            self.messages.removeAll()

            self.callback?.onConnectionStateChanged(state: "リセット完了")
        }

        // 新しいメソッド（AdvertiserViewModel用）
        func stopAdvertise() {
            self.advertiser?.stopAdvertising()
            self.callback?.onConnectionStateChanged(state: "広告停止")
        }

        func disconnect(_ endpointId: String) {
            self.disconnectFromDevice(endpointId: endpointId)
        }

        func sendMessage(_ content: String, to endpointId: String) {
            self.sendDataToDevice(text: content, toEndpointId: endpointId)
        }

        // 新しいメソッド
        func getConnectedDevices() -> [ConnectedDevice] {
            Array(self.connectedDevices.values)
        }

        func getMessages() -> [Message] {
            self.messages
        }

        func getCurrentDeviceName() -> String {
            self.nickName
        }

        func hasConnectedDevices() -> Bool {
            !self.connectedDevices.isEmpty
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
            self.deviceNames[endpointID] = deviceName

            // 新しいコールバック形式を呼び出し
            self.callback?.onConnectionRequest(
                endpointId: endpointID, deviceName: deviceName, context: context, accept: connectionRequestHandler)
            self.callback?.onConnectionStateChanged(state: "接続要求受信: \(deviceName) (\(endpointID))")
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
            self.deviceNames[endpointID] = deviceName

            // 発見したエンドポイントに自動で接続要求を送信
            let connectionContext = Data(nickName.utf8)
            discoverer.requestConnection(to: endpointID, using: connectionContext)
            self.callback?.onConnectionStateChanged(state: "エンドポイント発見: \(deviceName) (\(endpointID))")
            self.callback?.onDeviceFound(endpointId: endpointID, name: deviceName, isConnectable: true)
        }

        func discoverer(_ discoverer: Discoverer, didLose endpointID: String) {
            self.callback?.onConnectionStateChanged(state: "エンドポイント消失: \(endpointID)")
            self.callback?.onDeviceLost(endpointId: endpointID)
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
            self.remoteEndpointIds.insert(endpointID)

            // 接続済み端末として追加
            let deviceName = self.deviceNames[endpointID] ?? endpointID
            let device = ConnectedDevice(
                endpointId: endpointID,
                deviceName: deviceName,
                connectTime: Date()
            )
            self.connectedDevices[endpointID] = device

            self.callback?.onConnectionStateChanged(state: "接続成功: \(deviceName)")
            self.callback?.onConnectionResult(endpointID, true)
            self.callback?.onDeviceConnected(endpointId: endpointID, deviceName: deviceName)
        }

        func connectionManager(
            _ connectionManager: ConnectionManager,
            didReceive data: Data,
            withID payloadID: PayloadID,
            from endpointID: String
        ) {
            let receivedText = String(data: data, encoding: .utf8) ?? ""
            let deviceName = self.deviceNames[endpointID] ?? endpointID

            // 最終受信時刻を更新
            if var device = connectedDevices[endpointID] {
                device.lastMessageTime = Date()
                self.connectedDevices[endpointID] = device
            }

            // メッセージ履歴に追加
            let message = Message(
                content: receivedText,
                timestamp: Date(),
                senderId: endpointID,
                senderName: deviceName,
                isOutgoing: false
            )
            self.messages.append(message)

            // コールバック呼び出し
            self.callback?.onDataReceived(endpointId: endpointID, data: data)

            // 古いコールバック形式も維持（互換性のため）
            self.callback?.onDataReceived(data: receivedText, fromEndpointId: endpointID)
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
            self.callback?.onConnectionStateChanged(state: "ファイル受信開始: \(name) from \(endpointID)")

            // ファイル受信完了時の処理は別途実装
            // localURLにファイルが保存される
            let deviceName = self.deviceNames[endpointID] ?? endpointID

            // ファイルを適切な場所に移動・保存
            self.saveReceivedFile(from: localURL, originalName: name, fromDevice: deviceName, endpointID: endpointID)
        }

        // 受信したファイルを保存する処理
        private func saveReceivedFile(from tempURL: URL, originalName: String, fromDevice: String, endpointID: String) {
            let fileManager = FileManager.default

            // Documentsディレクトリ内にUWBFilesフォルダを作成
            guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                self.callback?.onConnectionStateChanged(state: "ファイル保存エラー: Documentsフォルダにアクセスできません")
                return
            }

            let uwbFilesDirectory = documentsDirectory.appendingPathComponent("UWBFiles")

            // ディレクトリが存在しない場合は作成
            if !fileManager.fileExists(atPath: uwbFilesDirectory.path) {
                do {
                    try fileManager.createDirectory(at: uwbFilesDirectory, withIntermediateDirectories: true)
                } catch {
                    self.callback?.onConnectionStateChanged(state: "ファイル保存エラー: フォルダ作成に失敗 - \(error.localizedDescription)")
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

                self.callback?.onConnectionStateChanged(state: "ファイル保存完了: \(finalFileName)")
                self.callback?.onConnectionStateChanged(state: "ファイル受信完了: \(finalFileName)")

            } catch {
                self.callback?.onConnectionStateChanged(state: "ファイル保存エラー: \(error.localizedDescription)")
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
            self.callback?.onConnectionStateChanged(state: "ファイル転送更新: \(endpointID)")

            // 進捗については後で実装
            // 一旦50%として固定値で通知
            // ファイル転送プログレス情報をconnectionStateChangedで通知
            self.callback?.onConnectionStateChanged(state: "ファイル転送中: 50%")
        }

        func connectionManager(
            _ connectionManager: ConnectionManager,
            didChangeTo state: ConnectionState,
            for endpointID: String
        ) {
            switch state {
            case .connecting:
                self.callback?.onConnectionStateChanged(state: "接続中: \(endpointID)")
            case .connected:
                // 接続完了時に接続情報を確実に登録
                self.remoteEndpointIds.insert(endpointID)

                let deviceName = self.deviceNames[endpointID] ?? endpointID
                let device = ConnectedDevice(
                    endpointId: endpointID,
                    deviceName: deviceName,
                    connectTime: Date()
                )
                self.connectedDevices[endpointID] = device

                // コールバックを呼び出し
                self.callback?.onConnectionStateChanged(state: "接続完了: \(deviceName)")
                self.callback?.onConnectionResult(endpointID, true)
                self.callback?.onDeviceConnected(endpointId: endpointID, deviceName: deviceName)
            case .disconnected:
                self.remoteEndpointIds.remove(endpointID)
                self.connectedDevices.removeValue(forKey: endpointID)
                self.deviceNames.removeValue(forKey: endpointID)

                // 新しいコールバック形式を呼び出し
                self.callback?.onDeviceDisconnected(endpointId: endpointID)

                // 古いコールバック形式も維持（互換性のため）
                self.callback?.onConnectionStateChanged(state: "切断: \(endpointID)")
                self.callback?.onDeviceDisconnected(endpointId: endpointID)
            case .rejected:
                self.callback?.onConnectionStateChanged(state: "接続拒否: \(endpointID)")
                self.callback?.onConnectionResult(endpointID, false)
            @unknown default:
                break
            }
        }
    }

#else
    // NearbyConnectionsが利用できない場合のダミー実装
    public class NearbyRepository {
        weak var callback: NearbyRepositoryCallback?

        public init() {}

        public func startAdvertising() {
            print("NearbyConnections not available - dummy implementation")
        }

        public func startAdvertise() {
            self.startAdvertising()
        }

        public func stopAdvertising() {}
        public func stopAdvertise() {
            self.stopAdvertising()
        }

        public func startDiscovery() {}
        public func stopDiscovery() {}
        public func connectTo(endpointId: String, deviceName: String) {}
        public func acceptConnection(endpointId: String) {}
        public func rejectConnection(endpointId: String) {}
        public func disconnect(endpointId: String) {}
        public func sendData(_ data: Data, to endpointId: String) {}
        public func sendMessage(_ message: String, to endpointIds: [String]) {}
        public func getConnectedEndpoints() -> [String] { [] }
    }

    public protocol NearbyRepositoryCallback: AnyObject {
        func onDiscoveryStateChanged(isDiscovering: Bool)
        func onDeviceFound(endpointId: String, name: String, isConnectable: Bool)
        func onDeviceLost(endpointId: String)
        func onConnectionRequest(
            endpointId: String, deviceName: String, context: Data, accept: @escaping (Bool) -> Void)
        func onConnectionResult(_ endpointId: String, _ success: Bool)
        func onConnectionStateChanged(state: String)
        func onDataReceived(endpointId: String, data: Data)
        func onDeviceConnected(endpointId: String, deviceName: String)
        func onDeviceDisconnected(endpointId: String)
    }

#endif
