import Combine
import SwiftUI

// MARK: - Data Models
// Domain層のEntityを使用

// MARK: - ViewModel

@MainActor
class PairingSettingViewModel: ObservableObject {
    @Published var selectedAntennas: [AntennaInfo] = []
    @Published var availableDevices: [AndroidDevice] = []
    @Published var antennaPairings: [AntennaPairing] = []
    @Published var isScanning = false
    @Published var showingConnectionAlert = false
    @Published var alertMessage = ""
    @Published var isConnected = false
    @Published var statusMessage = ""

    private let navigationModel = NavigationRouterModel.shared
    private var cancellables = Set<AnyCancellable>()

    // DI対応: 必要なUseCaseを直接注入
    private let nearbyRepository: NearbyRepository
    private let connectionUsecase: ConnectionManagementUsecase
    private var swiftDataRepository: SwiftDataRepositoryProtocol

    // 接続要求ハンドラーを保存
    private var connectionRequestHandlers: [String: (Bool) -> Void] = [:]

    // アンテナペアリングの状態
    var hasCompletePairing: Bool {
        return !antennaPairings.isEmpty && antennaPairings.count >= min(selectedAntennas.count, 2)
    }

    var canProceedToNextStep: Bool {
        return hasCompletePairing && isConnected
    }

    var canProceedToNext: Bool {
        return !antennaPairings.isEmpty
    }

    init(
        swiftDataRepository: SwiftDataRepositoryProtocol,
        nearbyRepository: NearbyRepository? = nil,
        connectionUsecase: ConnectionManagementUsecase? = nil
    ) {
        // DI対応: 必要な依存関係を注入または生成
        self.nearbyRepository = nearbyRepository ?? NearbyRepository()
        self.connectionUsecase =
            connectionUsecase ?? ConnectionManagementUsecase(nearbyRepository: self.nearbyRepository)
        self.swiftDataRepository = swiftDataRepository

        // 複数のcallbackをサポートするために、一時的にcallbackを切り替える
        self.nearbyRepository.callback = self

        loadSampleAntennas()
        Task {
            await loadPairingData()
        }
    }

    /// 実際のModelContextを使用してSwiftDataRepositoryを設定
    func setSwiftDataRepository(_ repository: SwiftDataRepositoryProtocol) {
        self.swiftDataRepository = repository
        Task {
            await loadPairingData()
        }
    }

    // MARK: - Data Management

    private func loadSampleAntennas() {
        // FieldSettingViewModelから保存されたアンテナ設定を読み込み
        if let data = UserDefaults.standard.data(forKey: "FieldAntennaConfiguration") {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode([AntennaInfo].self, from: data) {
                selectedAntennas = decoded
                return
            }
        }

        // 保存データがない場合はデフォルトのアンテナを作成
        selectedAntennas = [
            AntennaInfo(id: "antenna_1", name: "アンテナ 1", coordinates: Point3D(x: 50, y: 100, z: 0)),
            AntennaInfo(id: "antenna_2", name: "アンテナ 2", coordinates: Point3D(x: 200, y: 100, z: 0)),
            AntennaInfo(id: "antenna_3", name: "アンテナ 3", coordinates: Point3D(x: 125, y: 200, z: 0)),
        ]
    }

    private func loadPairingData() async {
        do {
            // SwiftDataからペアリングデータを読み込み
            let pairings = try await swiftDataRepository.loadAntennaPairings()
            antennaPairings = pairings

            // ペアリング済みデバイスをavailableDevicesに追加
            for pairing in pairings {
                if !availableDevices.contains(where: { $0.id == pairing.device.id }) {
                    var restoredDevice = pairing.device
                    // 復元されたデバイスは一旦未接続状態として表示
                    restoredDevice.isConnected = false
                    availableDevices.append(restoredDevice)
                }
            }

            // 接続状態を復元（ペアリングがあるかどうかで判定）
            isConnected = !pairings.isEmpty
        } catch {
            print("Error loading pairing data: \(error)")
            // エラーの場合は空の配列を設定
            antennaPairings = []
            isConnected = false
        }
    }

    private func savePairingData() {
        Task {
            do {
                // 既存のペアリングデータを全て削除してから新しいデータを保存
                let existingPairings = try await swiftDataRepository.loadAntennaPairings()
                for existingPairing in existingPairings {
                    try await swiftDataRepository.deleteAntennaPairing(by: existingPairing.id)
                }

                // 現在のペアリングデータを保存
                for pairing in antennaPairings {
                    try await swiftDataRepository.saveAntennaPairing(pairing)
                }
            } catch {
                print("Error saving pairing data: \(error)")
            }
        }
    }

    // MARK: - Device Discovery

    func startDeviceDiscovery() {
        isScanning = true

        // 接続済みデバイスとペアリング済みデバイスのみ保持し、それ以外を削除
        availableDevices.removeAll { device in
            // 接続済みの場合は保持
            if device.isConnected {
                return false
            }
            // ペアリング済み（アンテナと紐付け済み）の場合も保持
            if antennaPairings.contains(where: { $0.device.id == device.id }) {
                return false
            }
            // それ以外（未接続かつ未ペアリング）は削除
            return true
        }

        // NearBy Connectionでデバイス検索を開始
        nearbyRepository.startDiscovery()

        // 10秒後に自動で検索を停止
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.stopDeviceDiscovery()
        }
    }

    func stopDeviceDiscovery() {
        isScanning = false
        // 検索のみを停止し、既存の接続は維持する
        nearbyRepository.stopDiscoveryOnly()
    }

    // MARK: - Antenna Pairing

    func pairAntennaWithDevice(antenna: AntennaInfo, device: AndroidDevice) {
        // 既存のペアリングをチェック
        if antennaPairings.contains(where: { $0.antenna.id == antenna.id }) {
            alertMessage = "このアンテナは既にペアリング済みです"
            showingConnectionAlert = true
            return
        }

        // 1対1対応: 同じアンテナまたは同じ端末が既にペアリングされているかチェック
        if antennaPairings.contains(where: { $0.antenna.id == antenna.id }) {
            alertMessage = "\(antenna.name)は既に他の端末とペアリング済みです"
            showingConnectionAlert = true
            return
        }

        if antennaPairings.contains(where: { $0.device.id == device.id }) {
            alertMessage = "\(device.name)は既に他のアンテナとペアリング済みです"
            showingConnectionAlert = true
            return
        }

        // デバイスがリストにあることを確認し、なければ追加
        if !availableDevices.contains(where: { $0.id == device.id }) {
            availableDevices.append(device)
        }

        // アンテナ紐付け時に実際のペアリング（接続）を実行
        if device.isNearbyDevice {
            // まずペアリング情報を作成・保存
            let pairing = AntennaPairing(antenna: antenna, device: device)
            antennaPairings.append(pairing)
            savePairingData()

            // 接続済みの場合の処理
            if device.isConnected {
                alertMessage = "\(antenna.name) と \(device.name) の紐付けが完了しました（既に接続済み）"
                // 接続済みデバイスには即座にペアリング情報を送信
                let pairingInfo = "PAIRING:\(antenna.id):\(antenna.name)"
                nearbyRepository.sendDataToDevice(text: pairingInfo, toEndpointId: device.id)
            } else {
                // 未接続の場合は、保存された接続要求ハンドラーでペアリング（接続）を実行
                if let handler = connectionRequestHandlers[device.id] {
                    handler(true)  // 接続を承認してペアリング完了
                    connectionRequestHandlers.removeValue(forKey: device.id)
                    alertMessage = "\(antenna.name) と \(device.name) の紐付け・接続を開始しました"
                } else {
                    // ハンドラーがない場合は、Mac側から能動的にペアリングを開始

                    // 1. まずDiscoveryを開始（Android側の再接続を促す）
                    if !isScanning {
                        nearbyRepository.startDiscovery()
                        isScanning = true

                        // 10秒後に自動停止
                        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                            self?.stopDeviceDiscovery()
                        }
                    }

                    // 2. Android側に再接続指示メッセージを送信（もし既に何らかの接続がある場合）
                    let reconnectCommand = "RECONNECT_REQUEST:\(device.id)"
                    // 他のAndroid端末経由で再接続指示を送る可能性もある
                    nearbyRepository.sendDataToDevice(text: reconnectCommand, toEndpointId: device.id)

                    alertMessage = "\(antenna.name) と \(device.name) の紐付けを作成し、接続を開始中..."
                }
            }
            showingConnectionAlert = true
        } else {
            // 従来のロジック（互換性のため）
            let pairing = AntennaPairing(antenna: antenna, device: device)
            antennaPairings.append(pairing)

            if let index = availableDevices.firstIndex(where: { $0.id == device.id }) {
                availableDevices[index].isConnected = true
            }

            isConnected = true
            savePairingData()

            alertMessage = "\(antenna.name) と \(device.name) のペアリングが完了しました"
            showingConnectionAlert = true
        }
    }

    func removePairing(_ pairing: AntennaPairing) {
        antennaPairings.removeAll { $0.id == pairing.id }

        // 1対1対応なので、ペアリング削除時は必ず接続を切断
        // デバイスの接続状態を更新
        if let index = availableDevices.firstIndex(where: { $0.id == pairing.device.id }) {
            availableDevices[index].isConnected = false
        }

        // NearBy Connection経由の場合は実際に切断
        if pairing.device.isNearbyDevice {
            nearbyRepository.disconnect(pairing.device.id)
        }

        // 保存されているハンドラーもクリーンアップ
        connectionRequestHandlers.removeValue(forKey: pairing.device.id)

        // 接続状態を更新
        isConnected = !antennaPairings.isEmpty
        savePairingData()
    }

    func removeAllPairings() {
        // NearBy Connection経由のデバイスは実際に切断
        for pairing in antennaPairings {
            if pairing.device.isNearbyDevice {
                nearbyRepository.disconnect(pairing.device.id)
            }
        }

        antennaPairings.removeAll()

        // すべてのデバイスの接続状態をリセット
        for i in availableDevices.indices {
            availableDevices[i].isConnected = false
        }

        // すべてのハンドラーをクリーンアップ
        connectionRequestHandlers.removeAll()

        isConnected = false
        savePairingData()
    }

    // MARK: - Navigation

    func proceedToNextStep() {
        guard canProceedToNextStep else {
            alertMessage = "少なくとも1つのアンテナをAndroid端末とペアリングしてください"
            showingConnectionAlert = true
            return
        }

        navigationModel.push(.dataCollectionPage)
    }

    func skipPairing() {
        navigationModel.push(.dataCollectionPage)
    }

    func savePairingForFlow() -> Bool {
        // ペアリング情報を保存（少なくとも1つのペアリング）
        guard !antennaPairings.isEmpty else {
            return false
        }

        // ペアリング済みデバイスのIDリストを保存
        let pairedDeviceIds = antennaPairings.map { $0.device.id }
        if let encoded = try? JSONEncoder().encode(pairedDeviceIds) {
            UserDefaults.standard.set(encoded, forKey: "pairedDevices")
        }

        return true
    }

    // MARK: - Connection Testing

    func testConnection(for pairing: AntennaPairing) {
        alertMessage = "\(pairing.antenna.name) と \(pairing.device.name) の接続をテスト中..."
        showingConnectionAlert = true

        if pairing.device.isNearbyDevice {
            // 実際のNearBy Connectionでテストメッセージを送信
            let testMessage = "UWB_TEST_\(Date().timeIntervalSince1970)"
            nearbyRepository.sendDataToDevice(text: testMessage, toEndpointId: pairing.device.id)

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.alertMessage = "接続テスト完了：テストメッセージを送信しました"
                self?.showingConnectionAlert = true
            }
        } else {
            // シミュレート（従来の動作）
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                let isSuccess = Bool.random()  // ランダムに成功/失敗を決定
                self?.alertMessage = isSuccess ? "接続テスト成功：正常に通信できています" : "接続テスト失敗：デバイスとの通信に問題があります"
                self?.showingConnectionAlert = true
            }
        }
    }
}

// MARK: - NearbyRepositoryCallback

extension PairingSettingViewModel: NearbyRepositoryCallback {
    nonisolated func onConnectionStateChanged(state: String) {
        Task { @MainActor in
            print("PairingSettingViewModel - Connection State: \(state)")

            // 重要な状態変更をアラートで表示
            if state.contains("接続成功") || state.contains("接続完了") {
                alertMessage = "接続状況: \(state)"
                showingConnectionAlert = true
            } else if state.contains("接続拒否") || state.contains("切断") {
                alertMessage = "接続状況: \(state)"
                showingConnectionAlert = true
            } else if state.contains("エラー") {
                alertMessage = "エラー: \(state)"
                showingConnectionAlert = true
            }
        }
    }

    nonisolated func onDataReceived(data: String, fromEndpointId: String) {
        Task { @MainActor in
            print("PairingSettingViewModel - Data Received: \(data) from \(fromEndpointId)")
        }
    }

    nonisolated func onConnectionInitiated(
        _ endpointId: String, _ deviceName: String, _ context: Data, _ responseHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            // 広告中のデバイスが発見された場合
            let device = AndroidDevice(
                id: endpointId,
                name: deviceName,
                isConnected: false,
                isNearbyDevice: true
            )

            // 既存のデバイスリストに追加または更新（端末名の更新のため）
            if let index = availableDevices.firstIndex(where: { $0.id == endpointId }) {
                // 既存デバイスの情報を更新（端末名が変更されている可能性があるため）
                availableDevices[index] = device
            } else {
                // 新しいデバイスを追加
                availableDevices.append(device)

                alertMessage = "端末を保存しました: \(deviceName)"
                showingConnectionAlert = true
            }

            // 接続要求ハンドラーを保存して後で使用（アンテナ紐付け時に使用）
            connectionRequestHandlers[endpointId] = responseHandler

            // 検索時も接続を承認するように変更
            alertMessage = "\(deviceName) からの接続要求を承認しました"
            showingConnectionAlert = true
            responseHandler(true)  // 接続を承認
            connectionRequestHandlers.removeValue(forKey: endpointId)

            print("端末発見・接続完了: \(deviceName) (ID: \(endpointId))")
        }
    }

    nonisolated func onConnectionResult(_ endpointId: String, _ isSuccess: Bool) {
        Task { @MainActor in
            if isSuccess {
                // 接続成功時の処理
                if let index = availableDevices.firstIndex(where: { $0.id == endpointId }) {
                    // デバイス情報を保持しつつ接続状態のみ更新
                    var updatedDevice = availableDevices[index]
                    updatedDevice.isConnected = true
                    availableDevices[index] = updatedDevice
                } else {
                    // デバイスが一覧にない場合は、デバイス名を不明として追加
                    let unknownDevice = AndroidDevice(
                        id: endpointId,
                        name: "接続済み端末 (\(endpointId.prefix(8))...)",
                        isConnected: true,
                        isNearbyDevice: true
                    )
                    availableDevices.append(unknownDevice)
                    print("接続成功したがデバイスが一覧にないため追加: \(endpointId)")
                }
                isConnected = true

                // 接続成功時、既にアンテナ紐付け済みの場合はペアリング情報を送信
                if let pairing = antennaPairings.first(where: { $0.device.id == endpointId }) {
                    let pairingInfo = "PAIRING:\(pairing.antenna.id):\(pairing.antenna.name)"
                    nearbyRepository.sendDataToDevice(text: pairingInfo, toEndpointId: endpointId)

                    alertMessage = "接続完了: \(pairing.device.name) にペアリング情報を送信しました"
                    showingConnectionAlert = true
                }
            } else {
                // 接続失敗時の処理
                print("接続失敗: \(endpointId)")
                // 接続要求ハンドラーをクリーンアップ
                connectionRequestHandlers.removeValue(forKey: endpointId)
            }
        }
    }

    nonisolated func onDisconnected(_ endpointId: String) {
        Task { @MainActor in
            if let index = availableDevices.firstIndex(where: { $0.id == endpointId }) {
                // デバイス情報を保持しつつ接続状態のみ更新
                var updatedDevice = availableDevices[index]
                updatedDevice.isConnected = false
                availableDevices[index] = updatedDevice
            }

            // ペアリング情報からも削除
            antennaPairings.removeAll { $0.device.id == endpointId }
            isConnected = !antennaPairings.isEmpty
            savePairingData()
        }
    }

    nonisolated func onPayloadReceived(_ endpointId: String, _ payload: Data) {
        Task { @MainActor in
            // ペイロード受信時の処理
            if let text = String(data: payload, encoding: .utf8) {
                print("PairingSettingViewModel - Payload Received: \(text) from \(endpointId)")
            }
        }
    }
    
    // NearbyRepositoryCallbackプロトコルの不足しているメソッドを追加
    nonisolated func onDiscoveryStateChanged(isDiscovering: Bool) {
        Task { @MainActor in
            self.isScanning = isDiscovering
            if !isDiscovering {
                statusMessage = "検索停止"
            }
        }
    }

    nonisolated func onDeviceFound(endpointId: String, name: String, isConnectable: Bool) {
        Task { @MainActor in
            let device = AndroidDevice(
                id: endpointId,
                name: name,
                isConnected: false,
                isNearbyDevice: true
            )
            
            if !availableDevices.contains(where: { $0.id == endpointId }) {
                availableDevices.append(device)
            }
        }
    }

    nonisolated func onDeviceLost(endpointId: String) {
        Task { @MainActor in
            availableDevices.removeAll { $0.id == endpointId && !$0.isConnected }
        }
    }

    nonisolated func onConnectionRequest(
        endpointId: String,
        deviceName: String,
        context: Data,
        accept: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            // 接続要求を自動承認（必要に応じて変更）
            accept(true)
        }
    }

    nonisolated func onDataReceived(endpointId: String, data: Data) {
        Task { @MainActor in
            let payload = data
            if let text = String(data: payload, encoding: .utf8) {
                print("PairingSettingViewModel - Payload Received: \(text) from \(endpointId)")
            }
        }
    }

    nonisolated func onDeviceConnected(endpointId: String, deviceName: String) {
        Task { @MainActor in
            let device = AndroidDevice(
                id: endpointId,
                name: deviceName,
                isConnected: true,
                isNearbyDevice: true
            )

            if let index = availableDevices.firstIndex(where: { $0.id == endpointId }) {
                availableDevices[index] = device
            } else {
                availableDevices.append(device)
                alertMessage = "接続完了: \(deviceName) が一覧に追加されました"
                showingConnectionAlert = true
            }

            isConnected = true
        }
    }

    nonisolated func onDeviceDisconnected(endpointId: String) {
        onDisconnected(endpointId)
    }
}

// MARK: - Dummy Repository for Initialization
extension PairingSettingViewModel {
    /// テスト用またはプレースホルダー用の初期化
    convenience init() {
        self.init(
            swiftDataRepository: DummySwiftDataRepository(),
            nearbyRepository: nil,
            connectionUsecase: nil
        )
    }
}
