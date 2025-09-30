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

        // NearbyRepositoryのコールバックとして自身を設定
        nearbyRepository.callback = self

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
        nearbyRepository.disconnect(endpointId)
        connectedEndpoints.remove(endpointId)
        connectedDeviceNames = connectedDeviceNames.filter { $0 != endpointId }
    }

    public func disconnectAll() {
        // 各接続を個別に切断
        for endpoint in connectedEndpoints {
            nearbyRepository.disconnect(endpoint)
        }
        connectedDeviceNames.removeAll()
        connectedEndpoints.removeAll()
    }

    public func resetAll() {
        nearbyRepository.stopAdvertise()
        nearbyRepository.stopDiscoveryOnly()
        connectedDeviceNames.removeAll()
        connectedEndpoints.removeAll()
        isAdvertising = false
        connectState = "初期化完了"
    }

    // MARK: - Message Sending

    public func sendMessage(_ content: String) {
        if let firstEndpoint = connectedEndpoints.first {
            nearbyRepository.sendDataToDevice(text: content, toEndpointId: firstEndpoint)
        }
    }

    public func sendMessageToDevice(_ content: String, to endpointId: String) {
        nearbyRepository.sendDataToDevice(text: content, toEndpointId: endpointId)
    }

    // MARK: - Connection Status

    public func hasConnectedDevices() -> Bool {
        !connectedEndpoints.isEmpty
    }

    public func getConnectedDeviceCount() -> Int {
        connectedEndpoints.count
    }
}

// MARK: - NearbyRepositoryCallback

extension ConnectionManagementUsecase: NearbyRepositoryCallback {
    nonisolated public func onDiscoveryStateChanged(isDiscovering: Bool) {
        Task { @MainActor in
            print("Discovery state changed: \(isDiscovering)")
        }
    }

    nonisolated public func onConnectionStateChanged(state: String) {
        Task { @MainActor in
            print("Connection state changed: \(state)")
            connectState = state
        }
    }

    nonisolated public func onDeviceFound(endpointId: String, name: String, isConnectable: Bool) {
        Task { @MainActor in
            print("Device found: \(name) (\(endpointId))")
        }
    }

    nonisolated public func onDeviceLost(endpointId: String) {
        Task { @MainActor in
            print("Device lost: \(endpointId)")
        }
    }

    nonisolated public func onConnectionRequest(
        endpointId: String, deviceName: String, context: Data, accept: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            print("Connection request from: \(deviceName) (\(endpointId))")
            // 自動的に接続を承認
            accept(true)
        }
    }

    nonisolated public func onConnectionResult(_ endpointId: String, _ success: Bool) {
        Task { @MainActor in
            print("Connection result for \(endpointId): \(success)")
            if success {
                self.connectedEndpoints.insert(endpointId)
            }
        }
    }

    nonisolated public func onDeviceConnected(endpointId: String, deviceName: String) {
        Task { @MainActor in
            print("Device connected: \(deviceName) (\(endpointId))")
            self.connectedDeviceNames.insert(deviceName)
            self.connectedEndpoints.insert(endpointId)
            self.connectState = "端末接続: \(deviceName)"
        }
    }

    nonisolated public func onDeviceDisconnected(endpointId: String) {
        Task { @MainActor in
            print("Device disconnected: \(endpointId)")
            self.connectedEndpoints.remove(endpointId)
            self.connectState = "端末切断: \(endpointId)"
        }
    }

    nonisolated public func onDataReceived(endpointId: String, data: Data) {
        Task { @MainActor in
            if let text = String(data: data, encoding: .utf8) {
                print("Data received from \(endpointId): \(text)")
            }
        }
    }

    nonisolated public func onDataReceived(data: String, fromEndpointId: String) {
        Task { @MainActor in
            print("Data received from \(fromEndpointId): \(data)")
        }
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
