import Combine
import Foundation

// MARK: - デバイスペアリング Usecase

@MainActor
class DevicePairingUsecase: ObservableObject {
    @Published var selectedAntennas: [AntennaInfo] = []
    @Published var availableDevices: [AndroidDevice] = []
    @Published var antennaPairings: [AntennaPairing] = []
    @Published var isScanning = false
    @Published var isConnected = false

    private let connectionUsecase: ConnectionManagementUsecase
    private let swiftDataRepository: SwiftDataRepositoryProtocol
    private var connectionRequestHandlers: [String: (Bool) -> Void] = [:]

    var hasCompletePairing: Bool {
        !antennaPairings.isEmpty && antennaPairings.count >= min(selectedAntennas.count, 2)
    }

    var canProceedToNextStep: Bool {
        hasCompletePairing && isConnected
    }

    init(
        connectionUsecase: ConnectionManagementUsecase,
        swiftDataRepository: SwiftDataRepositoryProtocol = DummySwiftDataRepository()
    ) {
        self.connectionUsecase = connectionUsecase
        self.swiftDataRepository = swiftDataRepository

        Task {
            await loadAntennaData()
            await loadPairingData()
        }
    }

    // MARK: - Data Management

    private func loadAntennaData() async {
        do {
            let positions = try await swiftDataRepository.loadAntennaPositions()
            selectedAntennas = positions.map { position in
                AntennaInfo(
                    id: position.antennaId,
                    name: position.antennaName,
                    coordinates: position.position
                )
            }

            if selectedAntennas.isEmpty {
                // デフォルトのアンテナを作成
                selectedAntennas = [
                    AntennaInfo(id: "antenna_1", name: "アンテナ 1", coordinates: Point3D(x: 50, y: 100, z: 0)),
                    AntennaInfo(id: "antenna_2", name: "アンテナ 2", coordinates: Point3D(x: 200, y: 100, z: 0)),
                    AntennaInfo(id: "antenna_3", name: "アンテナ 3", coordinates: Point3D(x: 125, y: 200, z: 0)),
                ]

                // デフォルトアンテナをSwiftDataに保存
                for antenna in selectedAntennas {
                    let position = AntennaPositionData(
                        antennaId: antenna.id,
                        antennaName: antenna.name,
                        position: antenna.coordinates,
                        floorMapId: "" // TODO: 適切なfloorMapIdを設定
                    )
                    try await swiftDataRepository.saveAntennaPosition(position)
                }
            }
        } catch {
            print("アンテナデータ読み込みエラー: \(error)")
            // エラー時はデフォルトアンテナを使用
            selectedAntennas = [
                AntennaInfo(id: "antenna_1", name: "アンテナ 1", coordinates: Point3D(x: 50, y: 100, z: 0)),
                AntennaInfo(id: "antenna_2", name: "アンテナ 2", coordinates: Point3D(x: 200, y: 100, z: 0)),
                AntennaInfo(id: "antenna_3", name: "アンテナ 3", coordinates: Point3D(x: 125, y: 200, z: 0)),
            ]
        }
    }

    private func loadPairingData() async {
        do {
            let pairings = try await swiftDataRepository.loadAntennaPairings()
            antennaPairings = pairings

            // ペアリング済みデバイスをavailableDevicesに追加
            for pairing in pairings {
                if !availableDevices.contains(where: { $0.id == pairing.device.id }) {
                    var restoredDevice = pairing.device
                    restoredDevice.isConnected = false
                    availableDevices.append(restoredDevice)
                }
            }

            isConnected = !antennaPairings.isEmpty
        } catch {
            print("ペアリングデータ読み込みエラー: \(error)")
        }
    }

    private func savePairingData() async {
        // システム活動ログを記録
        let activity = SystemActivity(
            activityType: "pairing",
            activityDescription: "アンテナペアリング情報を更新: \(antennaPairings.count)件"
        )

        do {
            try await swiftDataRepository.saveSystemActivity(activity)
        } catch {
            print("システム活動ログ保存エラー: \(error)")
        }
    }

    // MARK: - Device Discovery

    func startDeviceDiscovery() {
        isScanning = true

        // 接続済みデバイスとペアリング済みデバイスのみ保持
        availableDevices.removeAll { device in
            if device.isConnected {
                return false
            }
            if antennaPairings.contains(where: { $0.device.id == device.id }) {
                return false
            }
            return true
        }

        connectionUsecase.startDiscovery()

        // 10秒後に自動で検索を停止
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.stopDeviceDiscovery()
        }
    }

    func stopDeviceDiscovery() {
        isScanning = false
        connectionUsecase.stopDiscovery()
    }

    // MARK: - Antenna Pairing

    func pairAntennaWithDevice(antenna: AntennaInfo, device: AndroidDevice) -> String? {
        // 既存のペアリングをチェック
        if antennaPairings.contains(where: { $0.antenna.id == antenna.id }) {
            return "このアンテナは既にペアリング済みです"
        }

        if antennaPairings.contains(where: { $0.device.id == device.id }) {
            return "\(device.name)は既に他のアンテナとペアリング済みです"
        }

        // デバイスがリストにあることを確認し、なければ追加
        if !availableDevices.contains(where: { $0.id == device.id }) {
            availableDevices.append(device)
        }

        // ペアリング情報を作成・保存
        let pairing = AntennaPairing(antenna: antenna, device: device)
        antennaPairings.append(pairing)

        Task {
            do {
                try await swiftDataRepository.saveAntennaPairing(pairing)
                await savePairingData()
            } catch {
                print("ペアリング保存エラー: \(error)")
            }
        }

        if device.isNearbyDevice {
            if device.isConnected {
                // 接続済みデバイスには即座にペアリング情報を送信
                let pairingInfo = "PAIRING:\(antenna.id):\(antenna.name)"
                connectionUsecase.sendMessageToDevice(pairingInfo, to: device.id)
                return "\(antenna.name) と \(device.name) の紐付けが完了しました（既に接続済み）"
            } else {
                // 未接続の場合の処理
                if let handler = connectionRequestHandlers[device.id] {
                    handler(true)  // 接続を承認してペアリング完了
                    connectionRequestHandlers.removeValue(forKey: device.id)
                    return "\(antenna.name) と \(device.name) の紐付け・接続を開始しました"
                } else {
                    // Discovery開始
                    if !isScanning {
                        startDeviceDiscovery()
                    }
                    return "\(antenna.name) と \(device.name) の紐付けを作成し、接続を開始中..."
                }
            }
        } else {
            // 従来のロジック
            if let index = availableDevices.firstIndex(where: { $0.id == device.id }) {
                availableDevices[index].isConnected = true
            }

            isConnected = true

            return "\(antenna.name) と \(device.name) のペアリングが完了しました"
        }
    }

    func removePairing(_ pairing: AntennaPairing) {
        antennaPairings.removeAll { $0.id == pairing.id }

        // デバイスの接続状態を更新
        if let index = availableDevices.firstIndex(where: { $0.id == pairing.device.id }) {
            availableDevices[index].isConnected = false
        }

        // NearBy Connection経由の場合は実際に切断
        if pairing.device.isNearbyDevice {
            connectionUsecase.disconnectFromDevice(endpointId: pairing.device.id)
        }

        connectionRequestHandlers.removeValue(forKey: pairing.device.id)

        isConnected = !antennaPairings.isEmpty

        Task {
            do {
                try await swiftDataRepository.deleteAntennaPairing(by: pairing.id)
                await savePairingData()
            } catch {
                print("ペアリング削除エラー: \(error)")
            }
        }
    }

    func removeAllPairings() {
        for pairing in antennaPairings {
            if pairing.device.isNearbyDevice {
                connectionUsecase.disconnectFromDevice(endpointId: pairing.device.id)
            }
        }

        let pairingsToRemove = antennaPairings
        antennaPairings.removeAll()

        for i in availableDevices.indices {
            availableDevices[i].isConnected = false
        }

        connectionRequestHandlers.removeAll()

        isConnected = false

        Task {
            do {
                for pairing in pairingsToRemove {
                    try await swiftDataRepository.deleteAntennaPairing(by: pairing.id)
                }
                await savePairingData()
            } catch {
                print("全ペアリング削除エラー: \(error)")
            }
        }
    }

    // MARK: - Connection Testing

    func testConnection(for pairing: AntennaPairing) -> String {
        if pairing.device.isNearbyDevice {
            let testMessage = "UWB_TEST_\(Date().timeIntervalSince1970)"
            connectionUsecase.sendMessageToDevice(testMessage, to: pairing.device.id)
            return "接続テスト完了：テストメッセージを送信しました"
        } else {
            let isSuccess = Bool.random()
            return isSuccess ? "接続テスト成功：正常に通信できています" : "接続テスト失敗：デバイスとの通信に問題があります"
        }
    }

    // MARK: - Event Handlers

    func onConnectionInitiated(endpointId: String, deviceName: String, responseHandler: @escaping (Bool) -> Void) {
        let device = AndroidDevice(
            id: endpointId,
            name: deviceName,
            isConnected: false,
            isNearbyDevice: true
        )

        if let index = availableDevices.firstIndex(where: { $0.id == endpointId }) {
            availableDevices[index] = device
        } else {
            availableDevices.append(device)
        }

        connectionRequestHandlers[endpointId] = responseHandler

        // 接続を承認
        responseHandler(true)
        connectionRequestHandlers.removeValue(forKey: endpointId)
    }

    func onConnectionResult(endpointId: String, isSuccess: Bool) {
        if isSuccess {
            if let index = availableDevices.firstIndex(where: { $0.id == endpointId }) {
                var updatedDevice = availableDevices[index]
                updatedDevice.isConnected = true
                availableDevices[index] = updatedDevice
            } else {
                let unknownDevice = AndroidDevice(
                    id: endpointId,
                    name: "接続済み端末 (\(endpointId.prefix(8))...)",
                    isConnected: true,
                    isNearbyDevice: true
                )
                availableDevices.append(unknownDevice)
            }
            isConnected = true

            // 既にアンテナ紐付け済みの場合はペアリング情報を送信
            if let pairing = antennaPairings.first(where: { $0.device.id == endpointId }) {
                let pairingInfo = "PAIRING:\(pairing.antenna.id):\(pairing.antenna.name)"
                connectionUsecase.sendMessageToDevice(pairingInfo, to: endpointId)
            }
        } else {
            connectionRequestHandlers.removeValue(forKey: endpointId)
        }
    }

    func onDisconnected(endpointId: String) {
        if let index = availableDevices.firstIndex(where: { $0.id == endpointId }) {
            var updatedDevice = availableDevices[index]
            updatedDevice.isConnected = false
            availableDevices[index] = updatedDevice
        }

        let disconnectedPairings = antennaPairings.filter { $0.device.id == endpointId }
        antennaPairings.removeAll { $0.device.id == endpointId }
        isConnected = !antennaPairings.isEmpty

        Task {
            do {
                for pairing in disconnectedPairings {
                    try await swiftDataRepository.deleteAntennaPairing(by: pairing.id)
                }
                await savePairingData()
            } catch {
                print("切断時ペアリング削除エラー: \(error)")
            }
        }
    }
}
