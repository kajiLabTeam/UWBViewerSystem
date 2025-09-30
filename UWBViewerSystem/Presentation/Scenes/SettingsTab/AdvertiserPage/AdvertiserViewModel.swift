//
//  AdvertiserViewModel.swift
//  UWBViewerSystem
//
//  Created by はるちろ on R 7/07/08.
//

import CoreLocation
import Foundation
import os
import SwiftUI

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
        self.setupLocationManager()
        self.setupNearbyRepository()
        self.requestLocationPermission()
    }

    // MARK: - Setup Methods

    private func setupLocationManager() {
        self.locationManager.delegate = self
        self.locationPermissionStatus = self.locationManager.authorizationStatus
    }

    private func setupNearbyRepository() {
        self.nearbyRepository.callback = self
    }

    private func requestLocationPermission() {
        switch self.locationManager.authorizationStatus {
        case .notDetermined:
            #if os(macOS)
                self.locationManager.requestAlwaysAuthorization()
            #else
                self.locationManager.requestWhenInUseAuthorization()
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
            self.statusMessage = "位置情報の権限が必要です"
        @unknown default:
            break
        }
    }

    // MARK: - Public Methods

    func startAdvertising() {
        #if os(macOS)
            guard self.locationPermissionStatus == .authorizedAlways else {
                self.statusMessage = "位置情報権限が必要です"
                return
            }
        #else
            guard self.locationPermissionStatus == .authorizedWhenInUse || self.locationPermissionStatus == .authorizedAlways
            else {
                self.statusMessage = "位置情報権限が必要です"
                return
            }
        #endif

        self.logger.info("広告開始")
        self.nearbyRepository.startAdvertise()
        self.isAdvertising = true
        self.statusMessage = "広告中..."
    }

    func stopAdvertising() {
        self.logger.info("広告停止")
        self.nearbyRepository.stopAdvertise()
        self.isAdvertising = false
        self.statusMessage = "停止中"
        self.connectionRequests.removeAll()
        self.connectedDevices.removeAll()
    }

    func approveConnection(for request: ConnectionRequest) {
        self.logger.info("接続承認: \(request.endpointId)")
        request.responseHandler(true)

        // 承認されたリクエストをリストから削除
        self.connectionRequests.removeAll { $0.id == request.id }

        // 接続済みデバイスリストに追加
        let connectedDevice = ConnectedDevice(
            endpointId: request.endpointId,
            deviceName: request.deviceName,
            connectTime: Date(),
            lastMessageTime: nil,
            isActive: true
        )
        self.connectedDevices.append(connectedDevice)
    }

    func rejectConnection(for request: ConnectionRequest) {
        self.logger.info("接続拒否: \(request.endpointId)")
        request.responseHandler(false)

        // 拒否されたリクエストをリストから削除
        self.connectionRequests.removeAll { $0.id == request.id }
    }

    func disconnectDevice(_ device: ConnectedDevice) {
        self.logger.info("端末切断: \(device.endpointId)")
        self.nearbyRepository.disconnect(device.endpointId)
        self.connectedDevices.removeAll { $0.id == device.id }
    }

    func sendMessage() {
        guard !self.newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let messageContent = self.newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)

        // 接続済みの全デバイスにメッセージ送信
        for device in self.connectedDevices {
            self.nearbyRepository.sendMessage(messageContent, to: device.endpointId)
        }

        // メッセージ履歴に追加（送信者として）
        let message = Message(
            content: messageContent,
            timestamp: Date(),
            senderId: "self",
            senderName: "自分",
            isOutgoing: true
        )
        self.messages.append(message)

        // 入力をクリア
        self.newMessageText = ""

        self.logger.info("メッセージ送信: \(messageContent)")
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
        self.locationPermissionStatus = status
        switch status {
        #if os(macOS)
            case .authorizedAlways:
                self.statusMessage = "権限許可完了"
        #else
            case .authorizedWhenInUse, .authorizedAlways:
                self.statusMessage = "権限許可完了"
        #endif
        case .denied, .restricted:
            self.statusMessage = "位置情報の権限が拒否されました"
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
}

// MARK: - NearbyRepositoryCallback

extension AdvertiserViewModel: NearbyRepositoryCallback {

    func onDiscoveryStateChanged(isDiscovering: Bool) {
        // 広告者モードでは特に処理なし
    }

    func onDeviceFound(endpointId: String, name: String, isConnectable: Bool) {
        // 広告者モードでは特に処理なし
    }

    func onDeviceLost(endpointId: String) {
        // 広告者モードでは特に処理なし
    }

    func onConnectionRequest(endpointId: String, deviceName: String, context: Data, accept: @escaping (Bool) -> Void) {
        let request = ConnectionRequest(
            endpointId: endpointId,
            deviceName: deviceName,
            timestamp: Date(),
            context: context,
            responseHandler: accept
        )

        DispatchQueue.main.async {
            self.connectionRequests.append(request)
        }
    }

    func onConnectionResult(_ endpointId: String, _ success: Bool) {
        self.logger.info("接続結果: \(endpointId) -> \(success)")

        DispatchQueue.main.async {
            if !success {
                // 接続失敗時は接続済みリストから削除
                self.connectedDevices.removeAll { $0.endpointId == endpointId }
            }
        }
    }

    func onConnectionStateChanged(state: String) {
        self.statusMessage = state
    }

    func onDataReceived(endpointId: String, data: Data) {
        if let messageContent = String(data: data, encoding: .utf8) {
            // 送信者のデバイス名を取得
            let senderName = self.connectedDevices.first { $0.endpointId == endpointId }?.deviceName ?? "Unknown"

            // メッセージ履歴に追加
            let message = Message(
                content: messageContent,
                timestamp: Date(),
                senderId: endpointId,
                senderName: senderName,
                isOutgoing: false
            )
            self.messages.append(message)

            // 最終受信時刻を更新
            if let index = connectedDevices.firstIndex(where: { $0.endpointId == endpointId }) {
                self.connectedDevices[index].lastMessageTime = Date()
            }
        }
    }

    func onDeviceConnected(endpointId: String, deviceName: String) {
        self.logger.info("端末接続: \(endpointId) (\(deviceName))")

        let newDevice = ConnectedDevice(
            endpointId: endpointId,
            deviceName: deviceName,
            connectTime: Date(),
            isActive: true
        )

        DispatchQueue.main.async {
            self.connectedDevices.append(newDevice)
            self.statusMessage = "接続完了: \(deviceName)"
        }
    }

    func onDeviceDisconnected(endpointId: String) {
        self.logger.info("端末切断: \(endpointId)")

        DispatchQueue.main.async {
            self.connectedDevices.removeAll { $0.endpointId == endpointId }
            self.statusMessage = "端末切断: \(endpointId)"
        }
    }
}
