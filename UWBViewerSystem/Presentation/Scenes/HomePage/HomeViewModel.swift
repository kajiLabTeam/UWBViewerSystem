//
//  HomeViewModel.swift
//  UWBViewerSystem
//
//  Created by はるちろ on R 7/04/07.
//

import Foundation
import SwiftUI

class HomeViewModel: ObservableObject {
    private let deviceConnectionUsecase: DeviceConnectionUsecase

    @Published var isLocationPermissionGranted: Bool = false
    @Published var connectState: String = ""
    @Published var receivedDataList: [(String, String)] = []

    init() {
        deviceConnectionUsecase = DeviceConnectionUsecase()
        updateFromUsecase()

        // DeviceConnectionUsecaseの状態を定期的に監視
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.updateFromUsecase()
        }
    }

    private func updateFromUsecase() {
        DispatchQueue.main.async {
            self.isLocationPermissionGranted = self.deviceConnectionUsecase.isLocationPermissionGranted
            self.connectState = self.deviceConnectionUsecase.connectState
            self.receivedDataList = self.deviceConnectionUsecase.receivedDataList
        }
    }

    func requestLocationPermission() {
        deviceConnectionUsecase.requestLocationPermission()
    }

    func startAdvertise() {
        deviceConnectionUsecase.startAdvertise()
    }

    func startDiscovery() {
        deviceConnectionUsecase.startDiscovery()
    }

    func sendData(text: String) {
        deviceConnectionUsecase.sendData(text: text)
    }

    func disconnectAll() {
        deviceConnectionUsecase.disconnectAll()
    }

    func resetAll() {
        deviceConnectionUsecase.resetAll()
    }
}
