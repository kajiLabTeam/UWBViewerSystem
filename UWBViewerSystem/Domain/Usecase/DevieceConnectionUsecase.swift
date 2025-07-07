//
//  DevieceConnectionUsecase.swift
//  UWBViewerSystem
//
//  Created by はるちろ on R 7/07/08.
//

import Foundation

class DeviceConnectionUsecase: NearbyRepositoryCallback, LocationPermissionDelegate {
    private let repository: NearbyRepository
    private let locationApi: LocationApi

    var isLocationPermissionGranted: Bool {
        locationApi.isLocationPermissionGranted
    }
    var connectState = ""
    var receivedDataList: [(String, String)] = []

    init() {
        repository = NearbyRepository()
        locationApi = LocationApi()

        repository.callback = self
        locationApi.delegate = self

        // 初期化時に位置情報の権限状態を確認
        let permissionStatus = locationApi.checkLocationPermission()
        connectState = permissionStatus.message

        // 権限が未設定の場合は自動でリクエスト
        if !permissionStatus.isGranted {
            locationApi.requestLocationPermission()
        }
    }

    func requestLocationPermission() {
        locationApi.requestLocationPermission()
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

    // MARK: - LocationPermissionDelegate

    func locationPermissionChanged(isGranted: Bool, message: String) {
        DispatchQueue.main.async {
            self.connectState = message
        }
    }
}
