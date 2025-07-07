//
//  LocationApi.swift
//  UWBViewerSystem
//
//  Created by はるちろ on R 7/07/08.
//

import CoreLocation

protocol LocationPermissionDelegate: AnyObject {
    func locationPermissionChanged(isGranted: Bool, message: String)
}

class LocationApi: NSObject {
    private let locationManager = CLLocationManager()
    weak var delegate: LocationPermissionDelegate?

    var isLocationPermissionGranted: Bool {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        default:
            return false
        }
    }

    override init() {
        super.init()
        setupLocationManager()
    }

    private func setupLocationManager() {
        locationManager.delegate = self
    }

    func requestLocationPermission() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            delegate?.locationPermissionChanged(isGranted: true, message: "位置情報の権限が許可されています")
        case .denied, .restricted:
            delegate?.locationPermissionChanged(isGranted: false, message: "位置情報の権限が拒否されています")
        @unknown default:
            delegate?.locationPermissionChanged(isGranted: false, message: "位置情報の権限状態が不明です")
        }
    }

    func checkLocationPermission() -> (isGranted: Bool, message: String) {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return (true, "位置情報の権限が許可されています")
        case .denied, .restricted:
            return (false, "位置情報の権限が拒否されています")
        case .notDetermined:
            return (false, "位置情報の権限が未設定です")
        @unknown default:
            return (false, "位置情報の権限状態が不明です")
        }
    }
}

extension LocationApi: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            delegate?.locationPermissionChanged(isGranted: true, message: "位置情報の権限が許可されました")
        case .denied, .restricted:
            delegate?.locationPermissionChanged(isGranted: false, message: "位置情報の権限が拒否されました")
        case .notDetermined:
            delegate?.locationPermissionChanged(isGranted: false, message: "位置情報の権限が未設定です")
        @unknown default:
            delegate?.locationPermissionChanged(isGranted: false, message: "位置情報の権限状態が不明です")
        }
    }
}