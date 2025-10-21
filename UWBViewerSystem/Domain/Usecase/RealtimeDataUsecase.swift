import Combine
import Foundation
import os.log

// MARK: - リアルタイムデータ管理 Usecase

@MainActor
public class RealtimeDataUsecase: ObservableObject {
    @Published var deviceRealtimeDataList: [DeviceRealtimeData] = []
    @Published var isReceivingRealtimeData = false

    private var cancellables = Set<AnyCancellable>()
    private let swiftDataRepository: SwiftDataRepositoryProtocol
    private weak var sensingControlUsecase: SensingControlUsecase?
    private let logger = Logger(subsystem: "com.uwbviewer.system", category: "realtime-data")

    public init(
        swiftDataRepository: SwiftDataRepositoryProtocol = DummySwiftDataRepository(),
        sensingControlUsecase: SensingControlUsecase? = nil
    ) {
        self.swiftDataRepository = swiftDataRepository
        self.sensingControlUsecase = sensingControlUsecase
    }

    // MARK: - Public Methods

    public func processRealtimeDataMessage(_ json: [String: Any], fromEndpointId: String) {
        #if DEBUG
            print("=== 🔄 processRealtimeDataMessage開始 ===")
            print("🔄 受信エンドポイントID: \(fromEndpointId)")
            print("🔄 JSONキー: \(json.keys.sorted())")
        #endif

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: json)
            #if DEBUG
                print("✅ JSON再シリアライズ成功: \(jsonData.count) bytes")
            #endif

            let realtimeMessage = try JSONDecoder().decode(RealtimeDataMessage.self, from: jsonData)
            #if DEBUG
                print("✅ RealtimeDataMessage デコード成功")
                print("📱 デバイス名: \(realtimeMessage.deviceName)")
                print("📐 Elevation: \(realtimeMessage.data.elevation)°")
                print("🧭 Azimuth: \(realtimeMessage.data.azimuth)°")
                print("📏 Distance: \(realtimeMessage.data.distance)m")
                print("📊 SeqCount: \(realtimeMessage.data.seqCount)")
                print("📡 RSSI: \(realtimeMessage.data.rssi)dBm")
                print("🚧 NLOS: \(realtimeMessage.data.nlos)")
            #endif

            // 距離をcmからmに変換
            let distanceInMeters = Double(realtimeMessage.data.distance) / 100.0

            let realtimeData = RealtimeData(
                id: UUID(),
                deviceName: realtimeMessage.deviceName,
                timestamp: realtimeMessage.timestamp,
                elevation: realtimeMessage.data.elevation,
                azimuth: realtimeMessage.data.azimuth,
                distance: distanceInMeters,
                nlos: realtimeMessage.data.nlos,
                rssi: realtimeMessage.data.rssi,
                seqCount: realtimeMessage.data.seqCount
            )

            self.addDataToDevice(realtimeData)

        } catch {
            #if DEBUG
                print("リアルタイムデータ処理エラー: \(error)")
                if let decodingError = error as? DecodingError {
                    print("デコードエラー詳細: \(decodingError)")
                }
                print("問題のあるJSON: \(json)")
            #endif
        }

        #if DEBUG
            print("=== processRealtimeDataMessage終了 ===")
        #endif
    }

    public func addConnectedDevice(_ deviceName: String) {
        if !self.deviceRealtimeDataList.contains(where: { $0.deviceName == deviceName }) {
            let newDeviceData = DeviceRealtimeData(
                deviceName: deviceName,
                latestData: nil,
                dataHistory: [],
                lastUpdateTime: Date(),
                isActive: true
            )
            self.deviceRealtimeDataList.append(newDeviceData)
            #if DEBUG
                print("接続端末をリアルタイムデータリストに追加: \(deviceName)")
            #endif
        }

        self.isReceivingRealtimeData = !self.deviceRealtimeDataList.isEmpty
    }

    public func removeDisconnectedDevice(_ deviceName: String) {
        if let index = deviceRealtimeDataList.firstIndex(where: { $0.deviceName == deviceName }) {
            self.deviceRealtimeDataList[index].isActive = false
            self.deviceRealtimeDataList[index].lastUpdateTime = Date.distantPast
        }
    }

    public func clearAllRealtimeData() {
        #if DEBUG
            print("🗑️ リアルタイムデータクリア")
        #endif
        self.deviceRealtimeDataList.removeAll()
        self.isReceivingRealtimeData = false
        objectWillChange.send()
    }

    public func clearRealtimeDataForSensing() {
        for deviceData in self.deviceRealtimeDataList {
            deviceData.clearData()
        }
        objectWillChange.send()
    }

    public func loadRealtimeDataHistory(for sessionId: String) async -> [RealtimeData] {
        do {
            return try await self.swiftDataRepository.loadRealtimeData(for: sessionId)
        } catch {
            #if DEBUG
                print("リアルタイムデータ履歴読み込みエラー: \(error)")
            #endif
            return []
        }
    }

    public func setSensingControlUsecase(_ usecase: SensingControlUsecase) {
        self.sensingControlUsecase = usecase
    }

    // MARK: - Private Methods

    private func addDataToDevice(_ data: RealtimeData) {
        // SensingControlUsecaseがアクティブな場合は永続化
        if let sensingControl = sensingControlUsecase {
            Task {
                await sensingControl.saveRealtimeData(data)
            }
        }

        if let index = deviceRealtimeDataList.firstIndex(where: { $0.deviceName == data.deviceName }) {
            // 既存デバイスのデータ更新
            #if DEBUG
                print("🟡 既存デバイス更新: \(data.deviceName) (インデックス: \(index))")
            #endif

            let updatedDevice = self.deviceRealtimeDataList[index]
            updatedDevice.latestData = data
            updatedDevice.dataHistory.append(data)
            updatedDevice.lastUpdateTime = Date()
            updatedDevice.isActive = true

            // 最新20件のデータのみ保持
            if updatedDevice.dataHistory.count > 20 {
                updatedDevice.dataHistory.removeFirst()
            }

            self.deviceRealtimeDataList[index] = updatedDevice

            #if DEBUG
                print("🟢 デバイスデータ更新完了: 履歴数=\(updatedDevice.dataHistory.count)")
                print("🟢 最新データ: 距離=\(data.distance)m, 仰角=\(data.elevation)°, 方位=\(data.azimuth)°")
            #endif

        } else {
            // 新しいデバイスのデータ追加
            #if DEBUG
                print("🆕 新デバイス追加: \(data.deviceName)")
            #endif
            let newDeviceData = DeviceRealtimeData(
                deviceName: data.deviceName,
                latestData: data,
                dataHistory: [data],
                lastUpdateTime: Date(),
                isActive: true
            )
            self.deviceRealtimeDataList.append(newDeviceData)
            #if DEBUG
                print("🟢 デバイス追加完了: 総デバイス数=\(self.deviceRealtimeDataList.count)")
            #endif
        }

        self.isReceivingRealtimeData = true
        objectWillChange.send()

        // デバイス状況をログ出力
        self.logDeviceStatus()
    }

    private func logDeviceStatus() {
        #if DEBUG
            print("=== 全デバイス状況 ===")
            for (index, device) in self.deviceRealtimeDataList.enumerated() {
                print("[\(index)] \(device.deviceName):")
                print("  - latestData: \(device.latestData != nil ? "あり" : "なし")")
                print("  - elevation: \(device.latestData?.elevation ?? 0.0)")
                print("  - azimuth: \(device.latestData?.azimuth ?? 0.0)")
                print("  - isActive: \(device.isActive)")
                print("  - lastUpdateTime: \(device.lastUpdateTime)")
            }
            print("=== 全デバイス状況終了 ===")
        #endif
    }
}
