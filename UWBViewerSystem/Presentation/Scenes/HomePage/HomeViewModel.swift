//
//  HomeViewModel.swift
//  UWBViewerSystem
//
//  Created by はるちろ on R 7/04/07.
//

import Foundation
import SwiftUI
import CoreLocation

class HomeViewModel: NSObject, ObservableObject, NearbyRepositoryCallback {
    private let repository: NearbyRepository
    private let locationManager = CLLocationManager()
    
    @Published var connectState: String = ""
    @Published var receivedDataList: [(String, String)] = []
    @Published var isLocationPermissionGranted = false
    
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
    
    func disconnectAll() {
        repository.disconnectAll()
    }
    
    func resetAll() {
        repository.resetAll()
        receivedDataList = []
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
