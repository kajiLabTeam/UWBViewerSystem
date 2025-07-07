//
//  NearByConnectionApi.swift
//  UWBViewerSystem
//
//  Created by はるちろ on R 7/07/08.
//

import Foundation
import NearbyConnections

protocol NearbyRepositoryCallback: AnyObject {
    func onConnectionStateChanged(state: String)
    func onDataReceived(data: String, fromEndpointId: String)
}

class NearbyRepository: NSObject {
    weak var callback: NearbyRepositoryCallback?
    private let nickName: String
    private let serviceId: String
    private var remoteEndpointIds: Set<String> = []
    
    private var advertiser: Advertiser?
    private var discoverer: Discoverer?
    private var connectionManager: ConnectionManager?
    
    init(nickName: String = "harutiro",
         serviceId: String = "net.harutiro.nearbyconnectionsapitest") {
        self.nickName = nickName
        self.serviceId = serviceId
        super.init()
        
        self.connectionManager = ConnectionManager(
            serviceID: serviceId,
            strategy: .star
        )
        
        setupDelegates()
    }
    
    private func setupDelegates() {
        guard let connectionManager = connectionManager else { return }
        
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
        guard let advertiser = advertiser else {
            callback?.onConnectionStateChanged(state: "Advertiser未初期化")
            return
        }
        
        let context = Data(nickName.utf8)
        advertiser.startAdvertising(using: context) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.callback?.onConnectionStateChanged(state: "広告開始エラー: \(error.localizedDescription)")
                } else {
                    self?.callback?.onConnectionStateChanged(state: "広告開始成功")
                }
            }
        }
    }
    
    func startDiscovery() {
        guard let discoverer = discoverer else {
            callback?.onConnectionStateChanged(state: "Discoverer未初期化")
            return
        }
        
        discoverer.startDiscovery { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.callback?.onConnectionStateChanged(state: "発見開始エラー: \(error.localizedDescription)")
                } else {
                    self?.callback?.onConnectionStateChanged(state: "発見開始成功")
                }
            }
        }
    }
    
    func sendData(text: String) {
        guard let connectionManager = connectionManager else {
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
                if let error = error {
                    self?.callback?.onConnectionStateChanged(state: "データ送信エラー: \(error.localizedDescription)")
                } else {
                    self?.callback?.onConnectionStateChanged(state: "データ送信完了: \(text)")
                }
            }
        }
    }
    
    func disconnectAll() {
        for endpointId in remoteEndpointIds {
            connectionManager?.disconnect(from: endpointId)
        }
        remoteEndpointIds.removeAll()
        callback?.onConnectionStateChanged(state: "全接続切断完了")
    }
    
    func resetAll() {
        disconnectAll()
        
        advertiser?.stopAdvertising()
        discoverer?.stopDiscovery()
        
        callback?.onConnectionStateChanged(state: "リセット完了")
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
        // 自動で接続要求を受け入れ
        connectionRequestHandler(true)
        callback?.onConnectionStateChanged(state: "接続要求受信: \(endpointID)")
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
        callback?.onConnectionStateChanged(state: "接続成功: \(endpointID)")
    }
    
    func connectionManager(
        _ connectionManager: ConnectionManager,
        didReceive data: Data,
        withID payloadID: PayloadID,
        from endpointID: String
    ) {
        let receivedText = String(data: data, encoding: .utf8) ?? ""
        callback?.onDataReceived(data: receivedText, fromEndpointId: endpointID)
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
            callback?.onConnectionStateChanged(state: "接続完了: \(endpointID)")
        case .disconnected:
            remoteEndpointIds.remove(endpointID)
            callback?.onConnectionStateChanged(state: "切断: \(endpointID)")
        case .rejected:
            callback?.onConnectionStateChanged(state: "接続拒否: \(endpointID)")
        @unknown default:
            break
        }
    }
}
