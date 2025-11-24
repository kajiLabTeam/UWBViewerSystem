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

    // 接続断検出用
    @Published var hasConnectionError = false
    @Published var lastDisconnectedDevice: String?

    // ペアリング情報管理（アンテナID → デバイス名）
    @Published public var antennaPairings: [String: String] = [:]

    private let locationManager = CLLocationManager()
    private let nearbyRepository: NearbyRepository

    // endpointId → deviceName のマッピング
    private var endpointToDeviceNameMap: [String: String] = [:]

    // RealtimeDataUsecaseへの参照を追加
    public weak var realtimeDataUsecase: RealtimeDataUsecase?

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
        // 全ての接続されたエンドポイントにメッセージを送信
        for endpointId in self.connectedEndpoints {
            self.nearbyRepository.sendDataToDevice(text: content, toEndpointId: endpointId)
            #if DEBUG
                print("📤 メッセージを送信: \(content) → エンドポイント: \(endpointId)")
            #endif
        }

        if self.connectedEndpoints.isEmpty {
            #if DEBUG
                print("⚠️ 送信先のエンドポイントがありません")
            #endif
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

    // MARK: - RealtimeDataUsecase Integration

    public func setRealtimeDataUsecase(_ usecase: RealtimeDataUsecase) {
        self.realtimeDataUsecase = usecase
        print("✅ RealtimeDataUsecaseを設定しました")
    }

    // MARK: - Pairing Management

    /// アンテナと端末のペアリングを登録
    public func pairAntennaWithDevice(antennaId: String, deviceName: String) {
        self.antennaPairings[antennaId] = deviceName
        print("🔗 ペアリング登録: \(antennaId) → \(deviceName)")
    }

    /// ペアリングを削除
    public func unpairAntenna(antennaId: String) {
        self.antennaPairings.removeValue(forKey: antennaId)
        print("✂️ ペアリング削除: \(antennaId)")
    }

    /// すべてのペアリングをクリア
    public func clearAllPairings() {
        self.antennaPairings.removeAll()
        print("🧹 すべてのペアリングをクリアしました")
    }

    /// 特定のアンテナに紐づくデバイス名を取得
    public func getDeviceName(for antennaId: String) -> String? {
        self.antennaPairings[antennaId]
    }

    /// ペアリングされているかつ接続中のアンテナIDリストを取得
    public func getConnectedAntennaIds() -> [String] {
        self.antennaPairings.compactMap { antennaId, deviceName in
            self.connectedDeviceNames.contains(deviceName) ? antennaId : nil
        }
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
            print("📱 Device found: \(name) (\(endpointId)), isConnectable: \(isConnectable)")

            // 接続可能な場合は自動的に接続リクエストを送信
            if isConnectable {
                print("📞 [ConnectionManagement] 自動接続リクエストを送信開始: \(name) (\(endpointId))")
                self.nearbyRepository.requestConnection(to: endpointId, deviceName: name)
                print("✅ [ConnectionManagement] 自動接続リクエスト送信完了")
            } else {
                print("⚠️ 接続不可のデバイス: \(name)")
            }
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
            print("📥 [ConnectionManagement] 接続リクエスト受信: \(deviceName) (\(endpointId))")
            // 自動的に接続を承認
            accept(true)
            print("✅ [ConnectionManagement] 接続リクエストを承認しました")
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

            // endpointId → deviceName のマッピングを保存
            self.endpointToDeviceNameMap[endpointId] = deviceName

            // 接続エラーフラグをクリア
            self.hasConnectionError = false
            self.lastDisconnectedDevice = nil

            // RealtimeDataUsecaseにデバイス接続を通知
            self.realtimeDataUsecase?.addConnectedDevice(deviceName)
            print("📱 RealtimeDataUsecaseに端末接続を通知: \(deviceName)")
        }
    }

    nonisolated public func onDeviceDisconnected(endpointId: String) {
        Task { @MainActor in
            print("Device disconnected: \(endpointId)")

            // endpointIdからdeviceNameを取得
            let deviceName = self.endpointToDeviceNameMap[endpointId]

            self.connectedEndpoints.remove(endpointId)
            self.connectState = "端末切断: \(deviceName ?? endpointId)"

            // 接続エラーフラグを設定
            self.hasConnectionError = true
            self.lastDisconnectedDevice = deviceName

            // RealtimeDataUsecaseに端末切断を通知
            if let deviceName {
                self.connectedDeviceNames.remove(deviceName)
                self.realtimeDataUsecase?.removeDisconnectedDevice(deviceName)
                print("📱 RealtimeDataUsecaseに端末切断を通知: \(deviceName)")

                // マッピングから削除
                self.endpointToDeviceNameMap.removeValue(forKey: endpointId)
            } else {
                print("⚠️ endpointId \(endpointId) に対応するdeviceNameが見つかりません")
            }
        }
    }

    nonisolated public func onDataReceived(endpointId: String, data: Data) {
        Task { @MainActor in
            print("📥 [Data版] データ受信 from \(endpointId)")
            print("  データサイズ: \(data.count) bytes")

            if let text = String(data: data, encoding: .utf8) {
                print("  データ内容: \(text)")

                // JSONが整形されている場合も考慮して、空白ありバージョンもチェック
                let hasRealtimeData =
                    text.contains("\"type\":\"REALTIME_DATA\"") || text.contains("\"type\": \"REALTIME_DATA\"")
                print("  検索対象文字列が含まれるか: \(hasRealtimeData)")

                // JSON形式のリアルタイムデータをパース
                if hasRealtimeData {
                    print("🎯 リアルタイムデータ検出 (Data版) - パース処理開始")
                    self.parseAndForwardRealtimeData(text, fromEndpointId: endpointId)
                } else {
                    print("ℹ️ リアルタイムデータではありません")
                    print("  先頭100文字: \(text.prefix(100))")
                }
            } else {
                print("⚠️ データをUTF-8文字列に変換できませんでした")
            }
        }
    }

    nonisolated public func onDataReceived(data: String, fromEndpointId: String) {
        Task { @MainActor in
            print("📥 [String版] データ受信 from \(fromEndpointId)")
            print("  データ長: \(data.count) 文字")
            print("  データ内容: \(data)")

            // JSONが整形されている場合も考慮して、空白ありバージョンもチェック
            let hasRealtimeData =
                data.contains("\"type\":\"REALTIME_DATA\"") || data.contains("\"type\": \"REALTIME_DATA\"")
            print("  検索対象文字列が含まれるか: \(hasRealtimeData)")

            // JSON形式のリアルタイムデータをパース
            if hasRealtimeData {
                print("🎯 リアルタイムデータ検出 (String版) - パース処理開始")
                self.parseAndForwardRealtimeData(data, fromEndpointId: fromEndpointId)
            } else {
                print("ℹ️ リアルタイムデータではありません")
                print("  先頭100文字: \(data.prefix(100))")
            }
        }
    }

    private func parseAndForwardRealtimeData(_ jsonString: String, fromEndpointId: String) {
        print("🔍 リアルタイムデータをパース開始: \(fromEndpointId)")

        guard let jsonData = jsonString.data(using: .utf8) else {
            print("❌ JSON文字列をDataに変換失敗")
            return
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                print("✅ JSONオブジェクトに変換成功")

                // RealtimeDataUsecaseに渡す
                if let realtimeUsecase = self.realtimeDataUsecase {
                    print("📤 RealtimeDataUsecaseにデータを転送: \(fromEndpointId)")
                    realtimeUsecase.processRealtimeDataMessage(json, fromEndpointId: fromEndpointId)
                } else {
                    print("⚠️ RealtimeDataUsecaseが設定されていません")
                }
            }
        } catch {
            print("❌ JSONパースエラー: \(error)")
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
