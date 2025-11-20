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

    // フロアマップID
    private var floorMapId: String?

    // 接続要求ハンドラーを保存
    private var connectionRequestHandlers: [String: (Bool) -> Void] = [:]

    // アンテナペアリングの状態
    var hasCompletePairing: Bool {
        !self.antennaPairings.isEmpty && self.antennaPairings.count >= min(self.selectedAntennas.count, 2)
    }

    var canProceedToNextStep: Bool {
        self.hasCompletePairing && self.isConnected
    }

    var canProceedToNext: Bool {
        !self.antennaPairings.isEmpty
    }

    init(
        swiftDataRepository: SwiftDataRepositoryProtocol,
        nearbyRepository: NearbyRepository? = nil,
        connectionUsecase: ConnectionManagementUsecase? = nil,
        autoLoadData: Bool = true
    ) {
        // DI対応: 必要な依存関係を注入または生成
        self.nearbyRepository = nearbyRepository ?? NearbyRepository.shared
        self.connectionUsecase =
            connectionUsecase ?? ConnectionManagementUsecase.shared
        self.swiftDataRepository = swiftDataRepository

        // 複数のcallbackをサポートするために、コールバックリスナーを追加
        self.nearbyRepository.addCallback(self)

        self.loadSampleAntennas()
        if autoLoadData {
            Task {
                await self.loadPairingData()
            }
        }
    }

    /// 実際のModelContextを使用してSwiftDataRepositoryを設定
    func setSwiftDataRepository(_ repository: SwiftDataRepositoryProtocol) {
        self.swiftDataRepository = repository
        Task {
            await self.loadPairingData()
        }
    }

    /// 指定されたフロアマップ情報を読み込み
    func loadFloorMapInfo(floorMapId: String) {
        self.floorMapId = floorMapId
        Task {
            await self.loadFloorMapInfoById(floorMapId: floorMapId)
            // フロアマップ情報読み込み後、アンテナ情報を読み込み
            await self.loadAntennasFromPositionData()
        }
    }

    /// 指定されたIDのフロアマップ情報を読み込み
    private func loadFloorMapInfoById(floorMapId: String) async {
        do {
            if let floorMap = try await swiftDataRepository.loadFloorMap(by: floorMapId) {
                print("📍 フロアマップ情報読み込み完了: \(floorMap.name) (ID: \(floorMap.id))")
            } else {
                print("⚠️ フロアマップが見つかりません (ID: \(floorMapId))")
            }
        } catch {
            print("❌ フロアマップ情報の読み込みに失敗: \(error)")
        }
    }

    // MARK: - Data Management

    private func loadSampleAntennas() {
        // データがない場合は従来の方法で読み込む
        if self.selectedAntennas.isEmpty {
            // FieldSettingViewModelから保存されたアンテナ設定を読み込み
            if let data = UserDefaults.standard.data(forKey: "FieldAntennaConfiguration") {
                let decoder = JSONDecoder()
                if let decoded = try? decoder.decode([AntennaInfo].self, from: data) {
                    self.selectedAntennas = decoded
                    print("📱 FieldAntennaConfigurationからアンテナを読み込み: \(self.selectedAntennas.count)台")
                    return
                }
            }

            // 保存データがない場合はデフォルトのアンテナを作成
            self.selectedAntennas = [
                AntennaInfo(id: "antenna_1", name: "アンテナ 1", coordinates: Point3D(x: 50, y: 100, z: 0)),
                AntennaInfo(id: "antenna_2", name: "アンテナ 2", coordinates: Point3D(x: 200, y: 100, z: 0)),
                AntennaInfo(id: "antenna_3", name: "アンテナ 3", coordinates: Point3D(x: 125, y: 200, z: 0)),
            ]
            print("📱 デフォルトアンテナを作成: \(self.selectedAntennas.count)台")
        }
    }

    /// 保存されたアンテナ位置データから読み込む
    private func loadAntennasFromPositionData() async {
        do {
            // SwiftDataからアンテナ位置データを読み込み
            guard let floorMapId = self.floorMapId else {
                print("⚠️ floorMapIdが設定されていません")
                await MainActor.run {
                    self.loadAntennasFromUserDefaults()
                }
                return
            }

            let positionData = try await swiftDataRepository.loadAntennaPositions(for: floorMapId)

            await MainActor.run {
                self.selectedAntennas = positionData.map { position in
                    AntennaInfo(
                        id: position.antennaId,
                        name: position.antennaName,
                        coordinates: position.position
                    )
                }
                print("✅ SwiftDataからアンテナ位置情報を読み込み: \(self.selectedAntennas.count)台 (floorMapId: \(floorMapId))")
            }
        } catch {
            print("❌ アンテナ位置データの読み込みエラー: \(error)")
            await MainActor.run {
                self.loadAntennasFromUserDefaults()
            }
        }
    }

    /// UserDefaultsから従来の方法でアンテナを読み込み
    private func loadAntennasFromUserDefaults() {
        // configuredAntennaPositionsから読み込み
        if let data = UserDefaults.standard.data(forKey: "configuredAntennaPositions"),
           let positionData = try? JSONDecoder().decode([AntennaPositionData].self, from: data)
        {
            self.selectedAntennas = positionData.map { position in
                AntennaInfo(
                    id: position.antennaId,
                    name: position.antennaName,
                    coordinates: position.position
                )
            }
            print("📱 configuredAntennaPositionsからアンテナを読み込み: \(self.selectedAntennas.count)台")
            return
        }

        // FieldAntennaConfigurationから読み込み
        if let data = UserDefaults.standard.data(forKey: "FieldAntennaConfiguration"),
           let decoded = try? JSONDecoder().decode([AntennaInfo].self, from: data)
        {
            self.selectedAntennas = decoded
            print("📱 FieldAntennaConfigurationからアンテナを読み込み: \(self.selectedAntennas.count)台")
        }
    }

    /// 現在のフロアマップ情報を取得
    private func getCurrentFloorMapInfo() -> FloorMapInfo? {
        guard let data = UserDefaults.standard.data(forKey: "currentFloorMapInfo"),
              let info = try? JSONDecoder().decode(FloorMapInfo.self, from: data)
        else {
            return nil
        }
        return info
    }

    private func loadPairingData() async {
        // ペアリング情報はConnectionManagementUsecaseで管理されるため、
        // ここでは何もしない（互換性のため残す）
        self.isConnected = !self.connectionUsecase.antennaPairings.isEmpty
    }

    // MARK: - Device Discovery

    func startDeviceDiscovery() {
        print("🔍 ペアリング画面: デバイス検索開始")
        print("  📊 検索前のデバイス数: \(self.availableDevices.count)")
        self.isScanning = true

        // 新しい検索を開始する前に、すべてのデバイスリストをクリア
        self.availableDevices.removeAll()
        print("  🗑️ デバイスリストをクリアしました")

        // ペアリング画面では、iOS側がDiscoveryモード（Android側を検索する）
        print("  📡 Discoveryモードを開始（Android側のAdvertiseを検索）")
        self.nearbyRepository.startDiscovery()

        // 10秒後に自動で検索を停止
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            print("⏰ 10秒経過: Discoveryモードを自動停止")
            self?.stopDeviceDiscovery()
        }
    }

    func stopDeviceDiscovery() {
        self.isScanning = false
        // 検索を停止
        print("  📡 Discoveryモードを停止")
        self.nearbyRepository.stopDiscoveryOnly()
    }

    // MARK: - Antenna Pairing

    func pairAntennaWithDevice(antenna: AntennaInfo, device: AndroidDevice) {
        // 1対1対応: 同じアンテナまたは同じ端末が既にペアリングされているかチェック
        if self.antennaPairings.contains(where: { $0.antenna.id == antenna.id }) {
            self.alertMessage = "\(antenna.name)は既に他の端末とペアリング済みです"
            self.showingConnectionAlert = true
            return
        }

        if self.antennaPairings.contains(where: { $0.device.id == device.id }) {
            self.alertMessage = "\(device.name)は既に他のアンテナとペアリング済みです"
            self.showingConnectionAlert = true
            return
        }

        // デバイスがリストにあることを確認し、なければ追加
        if !self.availableDevices.contains(where: { $0.id == device.id }) {
            self.availableDevices.append(device)
        }

        // アンテナ紐付け時に実際のペアリング（接続）を実行
        if device.isNearbyDevice {
            // ペアリング情報を作成
            let pairing = AntennaPairing(antenna: antenna, device: device)
            self.antennaPairings.append(pairing)

            // ConnectionManagementUsecaseに登録
            self.connectionUsecase.pairAntennaWithDevice(antennaId: antenna.id, deviceName: device.name)

            // 接続済みの場合の処理
            if device.isConnected {
                self.alertMessage = "\(antenna.name) と \(device.name) の紐付けが完了しました（既に接続済み）"
                // 接続済みデバイスには即座にペアリング情報を送信
                let pairingInfo = "PAIRING:\(antenna.id):\(antenna.name)"
                self.nearbyRepository.sendDataToDevice(text: pairingInfo, toEndpointId: device.id)
            } else {
                // 未接続の場合は、保存された接続要求ハンドラーでペアリング（接続）を実行
                if let handler = connectionRequestHandlers[device.id] {
                    print("📞 [pairAntennaWithDevice] 接続要求ハンドラーを使用して接続承認")
                    handler(true)  // 接続を承認してペアリング完了
                    self.connectionRequestHandlers.removeValue(forKey: device.id)
                    self.alertMessage = "\(antenna.name) と \(device.name) の紐付け・接続を開始しました"
                } else {
                    // ハンドラーがない場合は、直接接続要求を送信
                    print("📞 [pairAntennaWithDevice] ハンドラーなし。直接接続要求を送信")
                    print("   デバイスID: \(device.id)")
                    print("   デバイス名: \(device.name)")

                    // 直接接続要求を送信
                    self.nearbyRepository.requestConnection(to: device.id, deviceName: device.name)

                    self.alertMessage = "\(antenna.name) と \(device.name) の紐付けを作成し、接続を開始中..."
                }
            }
            self.showingConnectionAlert = true
        } else {
            // 従来のロジック（互換性のため）
            let pairing = AntennaPairing(antenna: antenna, device: device)
            self.antennaPairings.append(pairing)

            // ConnectionManagementUsecaseに登録
            self.connectionUsecase.pairAntennaWithDevice(antennaId: antenna.id, deviceName: device.name)

            if let index = availableDevices.firstIndex(where: { $0.id == device.id }) {
                self.availableDevices[index].isConnected = true
            }

            self.isConnected = true

            self.alertMessage = "\(antenna.name) と \(device.name) のペアリングが完了しました"
            self.showingConnectionAlert = true
        }
    }

    func removePairing(_ pairing: AntennaPairing) {
        self.antennaPairings.removeAll { $0.id == pairing.id }

        // ConnectionManagementUsecaseからも削除
        self.connectionUsecase.unpairAntenna(antennaId: pairing.antenna.id)

        // 1対1対応なので、ペアリング削除時は必ず接続を切断
        // デバイスの接続状態を更新
        if let index = availableDevices.firstIndex(where: { $0.id == pairing.device.id }) {
            self.availableDevices[index].isConnected = false
        }

        // NearBy Connection経由の場合は実際に切断
        if pairing.device.isNearbyDevice {
            self.nearbyRepository.disconnect(pairing.device.id)
        }

        // 保存されているハンドラーもクリーンアップ
        self.connectionRequestHandlers.removeValue(forKey: pairing.device.id)

        // 接続状態を更新
        self.isConnected = !self.antennaPairings.isEmpty
    }

    func removeAllPairings() {
        // NearBy Connection経由のデバイスは実際に切断
        for pairing in self.antennaPairings {
            if pairing.device.isNearbyDevice {
                self.nearbyRepository.disconnect(pairing.device.id)
            }
        }

        self.antennaPairings.removeAll()

        // ConnectionManagementUsecaseからもすべて削除
        self.connectionUsecase.clearAllPairings()

        // すべてのデバイスの接続状態をリセット
        for i in self.availableDevices.indices {
            self.availableDevices[i].isConnected = false
        }

        // すべてのハンドラーをクリーンアップ
        self.connectionRequestHandlers.removeAll()

        self.isConnected = false
    }

    // MARK: - Navigation

    func proceedToNextStep() {
        guard self.canProceedToNextStep else {
            self.alertMessage = "少なくとも1つのアンテナをAndroid端末とペアリングしてください"
            self.showingConnectionAlert = true
            return
        }

        // ペアリング情報はConnectionManagementUsecaseに既に登録済み
        // UserDefaultsにも保存（互換性のため）
        _ = self.savePairingForFlow()

        // 画面遷移
        if let floorMapId = self.floorMapId {
            self.navigationModel.push(.systemCalibration(floorMapId: floorMapId))
        }
    }

    /// フローナビゲーターで次へ進む
    func saveAndProceedToNextStep(flowNavigator: SensingFlowNavigator) {
        guard self.canProceedToNext else {
            return
        }

        // ペアリング情報はConnectionManagementUsecaseに既に登録済み
        // UserDefaultsにも保存（互換性のため）
        _ = self.savePairingForFlow()

        // 画面遷移 - floorMapIdを明示的に渡す
        flowNavigator.proceedToNextStep(floorMapId: self.floorMapId)
    }

    func savePairingForFlow() -> Bool {
        // ペアリング情報を保存（少なくとも1つのペアリング）
        guard !self.antennaPairings.isEmpty else {
            return false
        }

        // ペアリング済みデバイスのIDリストを保存
        let pairedDeviceIds = self.antennaPairings.map { $0.device.id }
        if let encoded = try? JSONEncoder().encode(pairedDeviceIds) {
            UserDefaults.standard.set(encoded, forKey: "pairedDevices")
        }

        // ペアリング済みデバイス一覧をSelectedUWBDevicesとしても保存（AntennaPositioningViewModelとの互換性確保）
        let pairedDevices = self.antennaPairings.map { $0.device }
        if let deviceData = try? JSONEncoder().encode(pairedDevices) {
            UserDefaults.standard.set(deviceData, forKey: "SelectedUWBDevices")
            print("💾 ペアリング済みデバイス一覧をSelectedUWBDevicesに保存: \(pairedDevices.count)台")
        }

        // アンテナ情報もFieldAntennaConfigurationとして保存
        let antennaInfos = self.antennaPairings.map { $0.antenna }
        if let antennaData = try? JSONEncoder().encode(antennaInfos) {
            UserDefaults.standard.set(antennaData, forKey: "FieldAntennaConfiguration")
            print("💾 アンテナ情報をFieldAntennaConfigurationに保存: \(antennaInfos.count)台")
        }

        return true
    }

    // MARK: - Connection Testing

    func testConnection(for pairing: AntennaPairing) {
        self.alertMessage = "\(pairing.antenna.name) と \(pairing.device.name) の接続をテスト中..."
        self.showingConnectionAlert = true

        if pairing.device.isNearbyDevice {
            // 実際のNearBy Connectionでテストメッセージを送信
            let testMessage = "UWB_TEST_\(Date().timeIntervalSince1970)"
            self.nearbyRepository.sendDataToDevice(text: testMessage, toEndpointId: pairing.device.id)

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
                self.alertMessage = "接続状況: \(state)"
                self.showingConnectionAlert = true
            } else if state.contains("接続拒否") || state.contains("切断") {
                self.alertMessage = "接続状況: \(state)"
                self.showingConnectionAlert = true
            } else if state.contains("エラー") {
                self.alertMessage = "エラー: \(state)"
                self.showingConnectionAlert = true
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
                self.availableDevices[index] = device
            } else {
                // 新しいデバイスを追加
                self.availableDevices.append(device)

                self.alertMessage = "端末を保存しました: \(deviceName)"
                self.showingConnectionAlert = true
            }

            // 接続要求ハンドラーを保存して後で使用（アンテナ紐付け時に使用）
            self.connectionRequestHandlers[endpointId] = responseHandler

            // 検索時も接続を承認するように変更
            self.alertMessage = "\(deviceName) からの接続要求を承認しました"
            self.showingConnectionAlert = true
            responseHandler(true)  // 接続を承認
            self.connectionRequestHandlers.removeValue(forKey: endpointId)

            print("端末発見・接続完了: \(deviceName) (ID: \(endpointId))")
        }
    }

    nonisolated func onConnectionResult(_ endpointId: String, _ isSuccess: Bool) {
        Task { @MainActor in
            if isSuccess {
                // 接続成功時の処理
                if let index = availableDevices.firstIndex(where: { $0.id == endpointId }) {
                    // デバイス情報を保持しつつ接続状態のみ更新
                    var updatedDevice = self.availableDevices[index]
                    updatedDevice.isConnected = true
                    self.availableDevices[index] = updatedDevice
                } else {
                    // デバイスが一覧にない場合は、デバイス名を不明として追加
                    let unknownDevice = AndroidDevice(
                        id: endpointId,
                        name: "接続済み端末 (\(endpointId.prefix(8))...)",
                        isConnected: true,
                        isNearbyDevice: true
                    )
                    self.availableDevices.append(unknownDevice)
                    print("接続成功したがデバイスが一覧にないため追加: \(endpointId)")
                }
                self.isConnected = true

                // 接続成功時、既にアンテナ紐付け済みの場合はペアリング情報を送信
                if let pairing = antennaPairings.first(where: { $0.device.id == endpointId }) {
                    let pairingInfo = "PAIRING:\(pairing.antenna.id):\(pairing.antenna.name)"
                    self.nearbyRepository.sendDataToDevice(text: pairingInfo, toEndpointId: endpointId)

                    self.alertMessage = "接続完了: \(pairing.device.name) にペアリング情報を送信しました"
                    self.showingConnectionAlert = true
                }
            } else {
                // 接続失敗時の処理
                print("接続失敗: \(endpointId)")
                // 接続要求ハンドラーをクリーンアップ
                self.connectionRequestHandlers.removeValue(forKey: endpointId)
            }
        }
    }

    nonisolated func onDisconnected(_ endpointId: String) {
        Task { @MainActor in
            if let index = availableDevices.firstIndex(where: { $0.id == endpointId }) {
                // デバイス情報を保持しつつ接続状態のみ更新
                var updatedDevice = self.availableDevices[index]
                updatedDevice.isConnected = false
                self.availableDevices[index] = updatedDevice
            }

            // ペアリング情報からも削除
            self.antennaPairings.removeAll { $0.device.id == endpointId }
            self.isConnected = !self.antennaPairings.isEmpty

            // ConnectionManagementUsecaseからも削除
            if let pairing = self.antennaPairings.first(where: { $0.device.id == endpointId }) {
                self.connectionUsecase.unpairAntenna(antennaId: pairing.antenna.id)
            }
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
                self.statusMessage = "検索停止"
            }
        }
    }

    nonisolated func onDeviceFound(endpointId: String, name: String, isConnectable: Bool) {
        Task { @MainActor in
            print("📱 [PairingSettingViewModel] デバイス発見: \(name) (ID: \(endpointId), 接続可能: \(isConnectable))")
            let device = AndroidDevice(
                id: endpointId,
                name: name,
                isConnected: false,
                isNearbyDevice: true
            )

            if !self.availableDevices.contains(where: { $0.id == endpointId }) {
                self.availableDevices.append(device)
                print("  ✅ デバイスリストに追加しました。現在のデバイス数: \(self.availableDevices.count)")
                print("  📋 現在のデバイスリスト: \(self.availableDevices.map { "\($0.name)(\($0.id))" }.joined(separator: ", "))")

                // Android側に合わせて手動で接続要求を送信
                if isConnectable {
                    print("  📞 [PairingSettingViewModel] 手動接続要求を送信開始: \(name)")
                    print("     endpointId=\(endpointId), deviceName=\(name)")
                    self.nearbyRepository.requestConnection(to: endpointId, deviceName: name)
                    print("  ✅ [PairingSettingViewModel] 手動接続要求を送信完了")
                } else {
                    print("  ⚠️ [PairingSettingViewModel] 接続不可のデバイス: \(name)")
                }
            } else {
                print("  ⚠️ すでにリストに存在します")
            }
        }
    }

    nonisolated func onDeviceLost(endpointId: String) {
        Task { @MainActor in
            print("📉 デバイス消失: ID=\(endpointId)")
            let beforeCount = self.availableDevices.count
            self.availableDevices.removeAll { $0.id == endpointId && !$0.isConnected }
            let afterCount = self.availableDevices.count
            if beforeCount != afterCount {
                print("  ✅ リストから削除しました。デバイス数: \(beforeCount) → \(afterCount)")
            } else {
                print("  ⚠️ リストに変更なし（接続済みまたは存在しない）")
            }
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
            print("🔗 デバイス接続完了: \(deviceName) (ID: \(endpointId))")
            let device = AndroidDevice(
                id: endpointId,
                name: deviceName,
                isConnected: true,
                isNearbyDevice: true
            )

            if let index = availableDevices.firstIndex(where: { $0.id == endpointId }) {
                print("  📝 既存デバイスの接続状態を更新")
                self.availableDevices[index] = device
            } else {
                print("  ➕ 新しいデバイスとして追加")
                self.availableDevices.append(device)
                self.alertMessage = "接続完了: \(deviceName) が一覧に追加されました"
                self.showingConnectionAlert = true
            }

            self.isConnected = true
            print(
                "  📋 接続後のデバイスリスト: \(self.availableDevices.map { "\($0.name)(\($0.id), 接続:\($0.isConnected))" }.joined(separator: ", "))"
            )
        }
    }

    nonisolated func onDeviceDisconnected(endpointId: String) {
        self.onDisconnected(endpointId)
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
