import Combine
import CoreLocation
import Foundation

// MARK: - 接続管理 Usecase

@MainActor
public class ConnectionManagementUsecase: NSObject, ObservableObject {
    @Published var connectState: String = ""
    @Published var isLocationPermissionGranted = false
    @Published var connectedDeviceNames: Set<String> = []
    @Published var connectedEndpoints: Set<String> = []
    @Published var isAdvertising = false

    private let locationManager = CLLocationManager()
    private let nearbyRepository: NearbyRepository

    init(nearbyRepository: NearbyRepository) {
        self.nearbyRepository = nearbyRepository
        super.init()
        setupLocationManager()
        requestLocationPermission()
    }

    // MARK: - Location Permission

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

    // MARK: - Connection Management

    public func startAdvertising() {
        guard isLocationPermissionGranted else {
            connectState = "位置情報の権限を許可してください"
            return
        }
        nearbyRepository.startAdvertise()
        isAdvertising = true
    }

    public func stopAdvertising() {
        nearbyRepository.stopAdvertise()
        isAdvertising = false
    }

    public func startDiscovery() {
        guard isLocationPermissionGranted else {
            connectState = "位置情報の権限を許可してください"
            return
        }
        nearbyRepository.startDiscovery()
    }

    public func stopDiscovery() {
        nearbyRepository.stopDiscoveryOnly()
    }

    public func disconnectFromDevice(endpointId: String) {
        nearbyRepository.disconnectFromDevice(endpointId: endpointId)
        connectedEndpoints.remove(endpointId)
        connectedDeviceNames = connectedDeviceNames.filter { $0 != endpointId }
    }

    public func disconnectAll() {
        nearbyRepository.disconnectAll()
        connectedDeviceNames.removeAll()
        connectedEndpoints.removeAll()
    }

    public func resetAll() {
        nearbyRepository.resetAll()
        connectedDeviceNames.removeAll()
        connectedEndpoints.removeAll()
        isAdvertising = false
        connectState = "初期化完了"
    }

    // MARK: - Message Sending

    public func sendMessage(_ content: String) {
        nearbyRepository.sendData(text: content)
    }

    public func sendMessageToDevice(_ content: String, to endpointId: String) {
        nearbyRepository.sendDataToDevice(text: content, toEndpointId: endpointId)
    }

    // MARK: - Connection Status

    public func hasConnectedDevices() -> Bool {
        return nearbyRepository.hasConnectedDevices()
    }

    public func getConnectedDeviceCount() -> Int {
        return connectedEndpoints.count
    }

    // MARK: - Event Handlers

    func onDeviceConnected(device: ConnectedDevice) {
        connectedDeviceNames.insert(device.deviceName)
        connectedEndpoints.insert(device.endpointId)
        connectState = "端末接続: \(device.deviceName)"
    }

    func onDeviceDisconnected(endpointId: String) {
        connectedEndpoints.remove(endpointId)
        // endpointIdから端末名を特定するのが難しいため、必要に応じて追加処理
        connectState = "端末切断: \(endpointId)"
    }

    func onConnectionStateChanged(state: String) {
        connectState = state
    }
}

// MARK: - CLLocationManagerDelegate

extension ConnectionManagementUsecase: CLLocationManagerDelegate {
    nonisolated public func locationManager(
        _ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus
    ) {
        Task { @MainActor in
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
}
