import Combine
import CoreLocation
import Foundation

// MARK: - 接続管理 Usecase

@MainActor
public class ConnectionManagementUsecase: NSObject, ObservableObject {
    // シングルトンインスタンス
    public static let shared = ConnectionManagementUsecase(nearbyRepository: NearbyRepository.shared)

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
        nearbyRepository.addCallback(self)

        self.setupLocationManager()
        self.requestLocationPermission()
    }

    // MARK: - Location Permission

    private func setupLocationManager() {
        self.locationManager.delegate = self
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
                self.isLocationPermissionGranted = true
        #else
            case .authorizedWhenInUse, .authorizedAlways:
                self.isLocationPermissionGranted = true
        #endif
        case .denied, .restricted:
            self.connectState = "位置情報の権限が必要です"
        @unknown default:
            break
        }
    }

    // MARK: - Connection Management

    public func startAdvertising() {
        guard self.isLocationPermissionGranted else {
            self.connectState = "位置情報の権限を許可してください"
            return
        }
        self.nearbyRepository.startAdvertise()
        self.isAdvertising = true
    }

    public func stopAdvertising() {
        self.nearbyRepository.stopAdvertise()
        self.isAdvertising = false
    }

    public func startDiscovery() {
        guard self.isLocationPermissionGranted else {
            self.connectState = "位置情報の権限を許可してください"
            return
        }
        self.nearbyRepository.startDiscovery()
    }

    public func stopDiscovery() {
        self.nearbyRepository.stopDiscoveryOnly()
    }

    public func disconnectFromDevice(endpointId: String) {
        self.nearbyRepository.disconnect(endpointId)
        self.connectedEndpoints.remove(endpointId)
        self.connectedDeviceNames = self.connectedDeviceNames.filter { $0 != endpointId }
    }

    public func disconnectAll() {
        // 各接続を個別に切断
        for endpoint in self.connectedEndpoints {
            self.nearbyRepository.disconnect(endpoint)
        }
        self.connectedDeviceNames.removeAll()
        self.connectedEndpoints.removeAll()
    }

    public func resetAll() {
        print("🔄 ConnectionManagement.resetAll() 開始")
        print("📊 リセット前の状態: 接続端末数=\(self.connectedEndpoints.count), 広告中=\(self.isAdvertising)")

        // 既存の接続をすべて切断
        if !self.connectedEndpoints.isEmpty {
            print("🔌 \(self.connectedEndpoints.count)個の接続を切断します: \(self.connectedEndpoints)")
            for endpoint in self.connectedEndpoints {
                self.nearbyRepository.disconnect(endpoint)
                print("  ✂️ 切断: \(endpoint)")
            }
        }

        // 広告と検索を停止
        if self.isAdvertising {
            print("📡 広告を停止します")
            self.nearbyRepository.stopAdvertise()
        }
        print("🔍 検索を停止します")
        self.nearbyRepository.stopDiscoveryOnly()

        // 状態をクリア
        self.connectedDeviceNames.removeAll()
        self.connectedEndpoints.removeAll()
        self.isAdvertising = false
        self.connectState = "初期化完了"

        print("✅ ConnectionManagement.resetAll() 完了")
    }

    // MARK: - Message Sending

    public func sendMessage(_ content: String) {
        if let firstEndpoint = connectedEndpoints.first {
            self.nearbyRepository.sendDataToDevice(text: content, toEndpointId: firstEndpoint)
        }
    }

    public func sendMessageToDevice(_ content: String, to endpointId: String) {
        self.nearbyRepository.sendDataToDevice(text: content, toEndpointId: endpointId)
    }

    // MARK: - Connection Status

    public func hasConnectedDevices() -> Bool {
        !self.connectedEndpoints.isEmpty
    }

    public func getConnectedDeviceCount() -> Int {
        self.connectedEndpoints.count
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
            self.connectState = state
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
                    self.isLocationPermissionGranted = true
                    self.connectState = "権限許可完了"
            #else
                case .authorizedWhenInUse, .authorizedAlways:
                    self.isLocationPermissionGranted = true
                    self.connectState = "権限許可完了"
            #endif
            case .denied, .restricted:
                self.isLocationPermissionGranted = false
                self.connectState = "位置情報の権限が拒否されました"
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }
}
