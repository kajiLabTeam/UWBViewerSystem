//
//  AdvertiserViewModel.swift
//  UWBViewerSystem
//
//  Created by はるちろ on R 7/07/08.
//

import Foundation
import SwiftUI
import CoreLocation
import os

class AdvertiserViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    // MARK: - Published Properties
    @Published var isAdvertising = false
    @Published var statusMessage = "停止中"
    @Published var connectionRequests: [ConnectionRequest] = []
    @Published var connectedDevices: [ConnectedDevice] = []
    @Published var messages: [Message] = []
    @Published var newMessageText = ""
    @Published var locationPermissionStatus: CLAuthorizationStatus = .notDetermined
    
    // MARK: - Private Properties
    private let locationManager = CLLocationManager()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "AdvertiserViewModel")
    private let nearbyRepository: NearbyRepository
    
    // MARK: - Initialization
    override init() {
        self.nearbyRepository = NearbyRepository()
        super.init()
        setupLocationManager()
        setupNearbyRepository()
        requestLocationPermission()
    }
    
    // MARK: - Setup Methods
    private func setupLocationManager() {
        locationManager.delegate = self
        locationPermissionStatus = locationManager.authorizationStatus
    }
    
    private func setupNearbyRepository() {
        nearbyRepository.callback = self
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
            // すでに許可されている
            break
        #else
        case .authorizedWhenInUse, .authorizedAlways:
            // すでに許可されている
            break
        #endif
        case .denied, .restricted:
            statusMessage = "位置情報の権限が必要です"
        @unknown default:
            break
        }
    }
    
    // MARK: - Public Methods
    func startAdvertising() {
        #if os(macOS)
        guard locationPermissionStatus == .authorizedAlways else {
            statusMessage = "位置情報権限が必要です"
            return
        }
        #else
        guard locationPermissionStatus == .authorizedWhenInUse || locationPermissionStatus == .authorizedAlways else {
            statusMessage = "位置情報権限が必要です"
            return
        }
        #endif
        
        logger.info("広告開始")
        nearbyRepository.startAdvertise()
        isAdvertising = true
        statusMessage = "広告中..."
    }
    
    func stopAdvertising() {
        logger.info("広告停止")
        nearbyRepository.stopAdvertise()
        isAdvertising = false
        statusMessage = "停止中"
        connectionRequests.removeAll()
        connectedDevices.removeAll()
    }
    
    func approveConnection(for request: ConnectionRequest) {
        logger.info("接続承認: \(request.endpointId)")
        request.responseHandler(true)
        
        // 承認されたリクエストをリストから削除
        connectionRequests.removeAll { $0.id == request.id }
        
        // 接続済みデバイスリストに追加
        let connectedDevice = ConnectedDevice(
            endpointId: request.endpointId,
            deviceName: request.deviceName,
            connectTime: Date(),
            lastMessageTime: nil,
            isActive: true
        )
        connectedDevices.append(connectedDevice)
    }
    
    func rejectConnection(for request: ConnectionRequest) {
        logger.info("接続拒否: \(request.endpointId)")
        request.responseHandler(false)
        
        // 拒否されたリクエストをリストから削除
        connectionRequests.removeAll { $0.id == request.id }
    }
    
    func disconnectDevice(_ device: ConnectedDevice) {
        logger.info("端末切断: \(device.endpointId)")
        nearbyRepository.disconnect(device.endpointId)
        connectedDevices.removeAll { $0.id == device.id }
    }
    
    func sendMessage() {
        guard !newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let messageContent = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 接続済みの全デバイスにメッセージ送信
        for device in connectedDevices {
            nearbyRepository.sendMessage(messageContent, to: device.endpointId)
        }
        
        // メッセージ履歴に追加（送信者として）
        let message = Message(
            content: messageContent,
            fromEndpointId: nil, // 自分からの送信なのでnil
            fromDeviceName: "自分",
            timestamp: Date(),
            isOutgoing: true
        )
        messages.append(message)
        
        // 入力をクリア
        newMessageText = ""
        
        logger.info("メッセージ送信: \(messageContent)")
    }
    
    // MARK: - Helper Methods
    private func formatTimeInterval(_ timeInterval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: timeInterval) ?? ""
    }
    
    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        locationPermissionStatus = status
        switch status {
        #if os(macOS)
        case .authorizedAlways:
            statusMessage = "権限許可完了"
        #else
        case .authorizedWhenInUse, .authorizedAlways:
            statusMessage = "権限許可完了"
        #endif
        case .denied, .restricted:
            statusMessage = "位置情報の権限が拒否されました"
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
}

// MARK: - NearbyRepositoryCallback
extension AdvertiserViewModel: NearbyRepositoryCallback {
    func onConnectionInitiated(_ endpointId: String, _ deviceName: String, _ context: Data, _ responseHandler: @escaping (Bool) -> Void) {
        logger.info("接続要求受信: \(endpointId) from \(deviceName)")
        
        let request = ConnectionRequest(
            endpointId: endpointId,
            deviceName: deviceName,
            requestTime: Date(),
            context: context,
            responseHandler: responseHandler
        )
        
        DispatchQueue.main.async {
            self.connectionRequests.append(request)
        }
    }
    
    func onConnectionResult(_ endpointId: String, _ isSuccess: Bool) {
        logger.info("接続結果: \(endpointId) -> \(isSuccess)")
        
        DispatchQueue.main.async {
            if !isSuccess {
                // 接続失敗時は接続済みリストから削除
                self.connectedDevices.removeAll { $0.endpointId == endpointId }
            }
        }
    }
    
    func onDisconnected(_ endpointId: String) {
        logger.info("切断: \(endpointId)")
        
        DispatchQueue.main.async {
            self.connectedDevices.removeAll { $0.endpointId == endpointId }
        }
    }
    
    func onPayloadReceived(_ endpointId: String, _ payload: Data) {
        guard let messageContent = String(data: payload, encoding: .utf8) else {
            logger.warning("受信データのデコードに失敗: \(endpointId)")
            return
        }
        
        logger.info("メッセージ受信: \(messageContent) from \(endpointId)")
        
        DispatchQueue.main.async {
            // 送信者のデバイス名を取得
            let senderName = self.connectedDevices.first { $0.endpointId == endpointId }?.deviceName ?? endpointId
            
            // メッセージ履歴に追加
            let message = Message(
                content: messageContent,
                fromEndpointId: endpointId,
                fromDeviceName: senderName,
                timestamp: Date(),
                isOutgoing: false
            )
            self.messages.append(message)
            
            // 最終受信時刻を更新
            if let index = self.connectedDevices.firstIndex(where: { $0.endpointId == endpointId }) {
                self.connectedDevices[index].lastMessageTime = Date()
            }
        }
    }
    
    // MARK: - 古いコールバックメソッドのデフォルト実装（互換性のため）
    func onConnectionStateChanged(state: String) {
        DispatchQueue.main.async {
            self.statusMessage = state
        }
    }
    
    func onDataReceived(data: String, fromEndpointId: String) {
        // 新しい形式で処理済みなのでここでは何もしない
    }
    
    func onConnectionRequestReceived(request: ConnectionRequest) {
        // 新しい形式で処理済みなのでここでは何もしない
    }
    
    func onDeviceConnected(device: ConnectedDevice) {
        // 新しい形式で処理済みなのでここでは何もしない
    }
    
    func onDeviceDisconnected(endpointId: String) {
        // 新しい形式で処理済みなのでここでは何もしない
    }
    
    func onMessageReceived(message: Message) {
        // 新しい形式で処理済みなのでここでは何もしない
    }
} 