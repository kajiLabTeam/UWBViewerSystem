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
struct DeviceRealtimeData: Identifiable {
    let id = UUID()
    let deviceName: String
    var latestData: RealtimeData?
    var dataHistory: [RealtimeData] = []
    var lastUpdateTime: Date = Date()
    var isActive: Bool = true
    
    var isRecentlyUpdated: Bool {
        Date().timeIntervalSince(lastUpdateTime) < 5.0 // 5秒以内の更新
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
    
    override init() {
        self.repository = NearbyRepository()
        super.init()
        self.repository.callback = self
        setupLocationManager()
        requestLocationPermission()
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
        
        // リアルタイムデータをクリア
        deviceRealtimeDataList.removeAll()
        isReceivingRealtimeData = false
        
        // 接続状態も更新
        connectState = "センシング終了コマンド送信完了"
    }
    
    // リアルタイムデータ処理
    private func processRealtimeData(_ data: String) {
        // JSONデータかどうかチェック
        guard data.contains("\"type\"") && data.contains("\"REALTIME_DATA\"") else {
            return
        }
        
        // JSONパース
        guard let jsonData = data.data(using: .utf8) else { return }
        
        do {
            let realtimeMessage = try JSONDecoder().decode(RealtimeDataMessage.self, from: jsonData)
            
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
                var deviceData = deviceRealtimeDataList[index]
                deviceData.latestData = realtimeData
                deviceData.dataHistory.append(realtimeData)
                deviceData.lastUpdateTime = Date()
                deviceData.isActive = true
                
                // 最新20件のデータのみ保持
                if deviceData.dataHistory.count > 20 {
                    deviceData.dataHistory.removeFirst()
                }
                
                deviceRealtimeDataList[index] = deviceData
            } else {
                // 新しいデバイスのデータ追加
                var newDeviceData = DeviceRealtimeData(
                    deviceName: realtimeMessage.deviceName,
                    latestData: realtimeData,
                    dataHistory: [realtimeData],
                    lastUpdateTime: Date(),
                    isActive: true
                )
                deviceRealtimeDataList.append(newDeviceData)
            }
            
            isReceivingRealtimeData = true
            
        } catch {
            // JSONパースエラーは無視（通常のメッセージの可能性）
            print("JSON parse error (ignored): \(error)")
        }
    }
    
    func disconnectAll() {
        repository.disconnectAll()
        
        // リアルタイムデータをクリア
        deviceRealtimeDataList.removeAll()
        isReceivingRealtimeData = false
    }
    
    func resetAll() {
        repository.resetAll()
        receivedDataList = []
        
        // リアルタイムデータをクリア
        deviceRealtimeDataList.removeAll()
        isReceivingRealtimeData = false
        
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
            
            // リアルタイムデータの処理
            self.processRealtimeData(data)
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
        }
    }
    
    func onDeviceDisconnected(endpointId: String) {
        DispatchQueue.main.async {
            self.connectState = "端末切断: \(endpointId)"
        }
    }
    
    func onMessageReceived(message: Message) {
        DispatchQueue.main.async {
            self.receivedDataList.append((message.fromDeviceName, message.content))
        }
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
