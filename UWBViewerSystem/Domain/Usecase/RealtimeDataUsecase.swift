import Combine
import Foundation
import os.log

// MARK: - リアルタイムデータ管理 Usecase

@MainActor
public class RealtimeDataUsecase: ObservableObject {
    @Published var deviceRealtimeDataList: [DeviceRealtimeData] = []
    @Published var isReceivingRealtimeData = false
    @Published var globalCoordinates: [String: Point3D] = [:]  // デバイス名 → グローバル座標

    // 複数アンテナ対応のプロパティ
    @Published var antennaDataMap: [String: [DeviceRealtimeData]] = [:] // アンテナID別のデータ
    @Published var activeAntennaIds = Set<String>() // アクティブなアンテナIDのセット
    @Published var totalDataPointCount = 0 // 全アンテナの総データポイント数

    private var cancellables = Set<AnyCancellable>()
    private var swiftDataRepository: SwiftDataRepositoryProtocol
    private weak var sensingControlUsecase: SensingControlUsecase?
    private let logger = Logger(subsystem: "com.uwbviewer.system", category: "realtime-data")
    private var coordinateTransformUsecase: RealtimeCoordinateTransformUsecase?
    private var currentFloorMapId: String?

    public init(
        swiftDataRepository: SwiftDataRepositoryProtocol = DummySwiftDataRepository(),
        sensingControlUsecase: SensingControlUsecase? = nil
    ) {
        self.swiftDataRepository = swiftDataRepository
        self.sensingControlUsecase = sensingControlUsecase

        // SwiftDataRepositoryが有効な場合は座標変換Usecaseを初期化
        if let swiftDataRepo = swiftDataRepository as? SwiftDataRepository {
            self.coordinateTransformUsecase = RealtimeCoordinateTransformUsecase(
                swiftDataRepository: swiftDataRepo
            )
        }
    }

    /// SwiftDataRepositoryを更新（ViewModelから呼ばれる）
    public func updateSwiftDataRepository(_ repository: SwiftDataRepository) {
        self.swiftDataRepository = repository
        self.coordinateTransformUsecase = RealtimeCoordinateTransformUsecase(
            swiftDataRepository: repository
        )
        print("✅ RealtimeDataUsecase: SwiftDataRepositoryを更新しました")
    }

    /// フロアマップIDを設定（座標変換に必要）
    public func setFloorMapId(_ floorMapId: String) {
        self.currentFloorMapId = floorMapId
        print("📍 RealtimeDataUsecase: FloorMapIDを設定しました: \(floorMapId)")
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

            // デバイス名から対応するアンテナIDを取得
            let antennaId = self.getAntennaId(for: realtimeMessage.deviceName)

            let realtimeData = RealtimeData(
                id: UUID(),
                deviceName: realtimeMessage.deviceName,
                timestamp: realtimeMessage.timestamp,
                elevation: realtimeMessage.data.elevation,
                azimuth: realtimeMessage.data.azimuth,
                distance: distanceInMeters,
                nlos: realtimeMessage.data.nlos,
                rssi: realtimeMessage.data.rssi,
                seqCount: realtimeMessage.data.seqCount,
                antennaId: antennaId
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
        // 統合座標履歴もクリア
        self.integratedCoordinateHistory.removeAll()
        objectWillChange.send()
    }

    /// 統合座標履歴をクリア
    public func clearIntegratedCoordinateHistory() {
        self.integratedCoordinateHistory.removeAll()
        #if DEBUG
            print("🗑️ 統合座標履歴をクリア")
        #endif
    }

    /// 統合座標履歴を取得
    public func getIntegratedCoordinateHistory() -> [IntegratedCoordinateRecord] {
        self.integratedCoordinateHistory
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
            #if DEBUG
                print("💾 SensingControlUsecaseにデータ保存を依頼: \(data.deviceName)")
            #endif
            Task {
                await sensingControl.saveRealtimeData(data)
            }
        } else {
            #if DEBUG
                print("⚠️ sensingControlUsecaseがnilのためデータ保存スキップ")
            #endif
        }

        // アンテナIDをアクティブリストに追加
        if !data.antennaId.isEmpty {
            self.activeAntennaIds.insert(data.antennaId)
            #if DEBUG
                print("📡 アクティブアンテナ追加: \(data.antennaId) (総数: \(self.activeAntennaIds.count))")
            #endif
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

        // アンテナ別データマップを更新
        if !data.antennaId.isEmpty {
            if self.antennaDataMap[data.antennaId] == nil {
                self.antennaDataMap[data.antennaId] = []
            }

            // 該当アンテナのデバイスリストを更新
            if let deviceData = deviceRealtimeDataList.first(where: { $0.deviceName == data.deviceName }) {
                if let existingIndex = antennaDataMap[data.antennaId]?.firstIndex(where: { $0.deviceName == data.deviceName }) {
                    self.antennaDataMap[data.antennaId]?[existingIndex] = deviceData
                } else {
                    self.antennaDataMap[data.antennaId]?.append(deviceData)
                }
            }
        }

        // 総データポイント数を更新
        self.totalDataPointCount = self.deviceRealtimeDataList.reduce(0) { $0 + $1.dataHistory.count }

        self.isReceivingRealtimeData = true
        objectWillChange.send()

        // 座標変換を実行
        self.performCoordinateTransform(for: data)

        // デバイス状況をログ出力
        self.logDeviceStatus()
    }

    /// デバイス名から対応するアンテナIDを取得
    ///
    /// ConnectionManagementUsecaseのペアリング情報から逆引きでアンテナIDを取得します。
    private func getAntennaId(for deviceName: String) -> String {
        let antennaPairings = ConnectionManagementUsecase.shared.antennaPairings

        // アンテナID → デバイス名のマッピングから逆引き
        for (antennaId, pairedDeviceName) in antennaPairings {
            if pairedDeviceName == deviceName {
                #if DEBUG
                    print("🔗 デバイス \(deviceName) はアンテナ \(antennaId) に紐づいています")
                #endif
                return antennaId
            }
        }

        #if DEBUG
            print("⚠️ デバイス \(deviceName) に対応するアンテナIDが見つかりません")
        #endif
        return ""
    }

    /// リアルタイムデータのグローバル座標変換を実行
    private func performCoordinateTransform(for data: RealtimeData) {
        guard let transformUsecase = coordinateTransformUsecase,
              let floorMapId = currentFloorMapId
        else {
            #if DEBUG
                print("⚠️ 座標変換がスキップされました: transformUsecase=\(self.coordinateTransformUsecase != nil), floorMapId=\(self.currentFloorMapId ?? "nil")")
            #endif
            return
        }

        // antennaIdが空の場合は変換不可
        guard !data.antennaId.isEmpty else {
            #if DEBUG
                print("⚠️ antennaIdが空のため座標変換をスキップ: deviceName=\(data.deviceName)")
            #endif
            return
        }

        // 距離が0の場合でも座標変換は実行（個別表示用）
        // ただし、重心と統合位置の計算からは除外される
        Task {
            if let globalCoord = await transformUsecase.transformToGlobalCoordinate(
                distance: data.distance,
                elevation: data.elevation,
                azimuth: data.azimuth,
                antennaId: data.antennaId,
                floorMapId: floorMapId
            ) {
                // 個別表示用: NLOS/LOS、有効/無効に関係なく全て保存
                self.globalCoordinates[data.deviceName] = globalCoord
                #if DEBUG
                    let isValid = self.isValidCoordinate(globalCoord) && self.isValidDistance(data.distance)
                    print("📍 グローバル座標変換成功: \(data.deviceName) → (\(globalCoord.x), \(globalCoord.y), \(globalCoord.z)) [有効=\(isValid)]")
                #endif

                // 重心座標と統合位置を更新（ここで無効データは除外される）
                self.calculateCentroid()
                self.updateIntegratedTagPositions()
            }
        }
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

    // MARK: - Centroid Calculation

    /// 全デバイスの重心座標（LOSを優先、フィルター適用後）
    @Published var centroidCoordinate: Point3D?

    /// タグごとの統合座標（複数アンテナからの観測を統合）
    @Published var integratedTagCoordinates: [String: IntegratedTagPosition] = [:]

    /// 統合座標の履歴（CSV出力用）
    @Published private(set) var integratedCoordinateHistory: [IntegratedCoordinateRecord] = []

    /// ローパスフィルター用の前回値（重心用）
    private var previousFilteredCentroid: Point3D?

    /// ローパスフィルター用の前回値（統合タグ用）
    private var previousFilteredIntegratedPosition: Point3D?

    /// ローパスフィルターの平滑化係数（0.0〜1.0、小さいほど滑らか）
    private let smoothingFactor: Double = 0.3

    /// 重心座標を計算（LOSを優先、NLOSはLOSがない場合のみ使用）
    private func calculateCentroid() {
        guard !self.globalCoordinates.isEmpty else {
            self.centroidCoordinate = nil
            self.previousFilteredCentroid = nil
            return
        }

        // 有効な座標を持つデバイスをLOSとNLOSに分類
        var losCoordinates: [(deviceName: String, coordinate: Point3D)] = []
        var nlosCoordinates: [(deviceName: String, coordinate: Point3D)] = []

        for (deviceName, coordinate) in self.globalCoordinates {
            // 座標が(0, 0, 0)の場合はスキップ
            guard self.isValidCoordinate(coordinate) else {
                #if DEBUG
                    print("⚠️ 重心計算: (0,0,0)座標をスキップ: \(deviceName)")
                #endif
                continue
            }

            // 距離が0mの場合はスキップ
            let deviceData = self.deviceRealtimeDataList.first { $0.deviceName == deviceName }
            guard let latestData = deviceData?.latestData, self.isValidDistance(latestData.distance) else {
                #if DEBUG
                    print("⚠️ 重心計算: 距離0mをスキップ: \(deviceName)")
                #endif
                continue
            }

            let isNLOS = latestData.nlos == 1

            if isNLOS {
                nlosCoordinates.append((deviceName, coordinate))
            } else {
                losCoordinates.append((deviceName, coordinate))
            }
        }

        // LOSが1つでもあればLOSのみを使用、なければNLOSを使用
        let targetCoordinates = losCoordinates.isEmpty ? nlosCoordinates : losCoordinates
        let usingNLOS = losCoordinates.isEmpty

        guard !targetCoordinates.isEmpty else {
            self.centroidCoordinate = nil
            self.previousFilteredCentroid = nil
            return
        }

        // 単純な重心を計算（選択された座標群のみ）
        var totalX = 0.0
        var totalY = 0.0
        var totalZ = 0.0

        for (_, coordinate) in targetCoordinates {
            totalX += coordinate.x
            totalY += coordinate.y
            totalZ += coordinate.z
        }

        let count = Double(targetCoordinates.count)
        let rawCentroid = Point3D(
            x: totalX / count,
            y: totalY / count,
            z: totalZ / count
        )

        // ローパスフィルターを適用
        let filteredCentroid = self.applyLowPassFilter(newValue: rawCentroid)
        self.centroidCoordinate = filteredCentroid

        #if DEBUG
            print("📍 重心座標計算: (\(filteredCentroid.x), \(filteredCentroid.y), \(filteredCentroid.z)) [LOS=\(losCoordinates.count), NLOS=\(nlosCoordinates.count), 使用=\(usingNLOS ? "NLOS" : "LOS")]")
        #endif
    }

    /// ローパスフィルター（指数移動平均）を適用
    private func applyLowPassFilter(newValue: Point3D) -> Point3D {
        guard let previous = previousFilteredCentroid else {
            // 初回は新しい値をそのまま使用
            self.previousFilteredCentroid = newValue
            return newValue
        }

        // 指数移動平均: filtered = α * new + (1 - α) * previous
        let filtered = Point3D(
            x: self.smoothingFactor * newValue.x + (1 - self.smoothingFactor) * previous.x,
            y: self.smoothingFactor * newValue.y + (1 - self.smoothingFactor) * previous.y,
            z: self.smoothingFactor * newValue.z + (1 - self.smoothingFactor) * previous.z
        )

        self.previousFilteredCentroid = filtered
        return filtered
    }

    /// 統合タグ位置を更新
    /// 全てのアンテナからの観測を1つのタグとして統合し、重心座標を計算する
    /// NLOSの観測は除外し、NLOSしかない場合のみNLOSを使用する
    /// 距離が0mまたは座標が(0,0,0)の観測は除外する
    private func updateIntegratedTagPositions() {
        // 全ての観測を1つのタグとしてまとめる（有効なデータのみ）
        var allObservations: [TagObservation] = []
        let integratedTagId = "integrated_tag"

        for (deviceName, coordinate) in self.globalCoordinates {
            let deviceData = self.deviceRealtimeDataList.first { $0.deviceName == deviceName }

            // 距離が0mの場合はスキップ
            guard let latestData = deviceData?.latestData, self.isValidDistance(latestData.distance) else {
                #if DEBUG
                    print("⚠️ 統合位置計算: 距離0mをスキップ: \(deviceName)")
                #endif
                continue
            }

            // 座標が(0,0,0)の場合はスキップ
            guard self.isValidCoordinate(coordinate) else {
                #if DEBUG
                    print("⚠️ 統合位置計算: (0,0,0)座標をスキップ: \(deviceName)")
                #endif
                continue
            }

            let isNLOS = latestData.nlos == 1
            let antennaId = latestData.antennaId

            let observation = TagObservation(
                antennaId: antennaId,
                deviceName: deviceName,
                coordinate: coordinate,
                isNLOS: isNLOS,
                timestamp: deviceData?.lastUpdateTime ?? Date()
            )

            allObservations.append(observation)
        }

        guard !allObservations.isEmpty else {
            self.integratedTagCoordinates = [:]
            self.previousFilteredIntegratedPosition = nil
            return
        }

        // 統合位置を計算（NLOSを除外、NLOSのみの場合はNLOSを使用）
        let integrated = self.calculateIntegratedPosition(for: allObservations)

        // ローパスフィルターを適用
        let filteredCoordinate = self.applyIntegratedPositionFilter(newValue: integrated.coordinate)

        let integratedPosition = IntegratedTagPosition(
            tagId: integratedTagId,
            integratedCoordinate: filteredCoordinate,
            confidence: integrated.confidence,
            observations: allObservations,
            hasNLOSOnly: allObservations.allSatisfy { $0.isNLOS }
        )

        self.integratedTagCoordinates = [integratedTagId: integratedPosition]

        // 履歴に追加（タイムスタンプは最新の観測データから取得）
        let currentTimestamp = Date().timeIntervalSince1970 * 1000
        let record = IntegratedCoordinateRecord(from: integratedPosition, timestamp: currentTimestamp)
        self.integratedCoordinateHistory.append(record)

        #if DEBUG
            let losCount = allObservations.filter { !$0.isNLOS }.count
            let nlosCount = allObservations.filter { $0.isNLOS }.count
            print("📍 統合タグ位置更新: LOS=\(losCount), NLOS=\(nlosCount), 座標=(\(filteredCoordinate.x), \(filteredCoordinate.y), \(filteredCoordinate.z))")
        #endif
    }

    /// 統合タグ位置用のローパスフィルターを適用
    private func applyIntegratedPositionFilter(newValue: Point3D) -> Point3D {
        // 無効な座標の場合はフィルターをリセット
        guard self.isValidCoordinate(newValue) else {
            self.previousFilteredIntegratedPosition = nil
            return newValue
        }

        guard let previous = previousFilteredIntegratedPosition else {
            // 初回は新しい値をそのまま使用
            self.previousFilteredIntegratedPosition = newValue
            return newValue
        }

        // 指数移動平均: filtered = α * new + (1 - α) * previous
        let filtered = Point3D(
            x: self.smoothingFactor * newValue.x + (1 - self.smoothingFactor) * previous.x,
            y: self.smoothingFactor * newValue.y + (1 - self.smoothingFactor) * previous.y,
            z: self.smoothingFactor * newValue.z + (1 - self.smoothingFactor) * previous.z
        )

        self.previousFilteredIntegratedPosition = filtered
        return filtered
    }

    /// デバイス名からタグIDを抽出
    private func extractTagId(from deviceName: String) -> String {
        deviceName
    }

    /// 座標が有効かどうかをチェック（0, 0, 0の場合は無効）
    private func isValidCoordinate(_ coordinate: Point3D) -> Bool {
        !(coordinate.x == 0 && coordinate.y == 0 && coordinate.z == 0)
    }

    /// 距離が有効かどうかをチェック（0mの場合は無効）
    private func isValidDistance(_ distance: Double) -> Bool {
        distance > 0
    }

    /// 複数観測から統合位置を計算
    /// NLOSの観測は使用しない。NLOSしかない場合のみNLOSを使用する。
    /// 座標が(0, 0, 0)の観測は除外する。
    private func calculateIntegratedPosition(
        for observations: [TagObservation]
    ) -> (coordinate: Point3D, confidence: Double) {
        guard !observations.isEmpty else {
            return (Point3D.zero, 0.0)
        }

        // 座標が(0, 0, 0)の観測を除外
        let validObservations = observations.filter { self.isValidCoordinate($0.coordinate) }

        guard !validObservations.isEmpty else {
            #if DEBUG
                print("⚠️ 有効な座標を持つ観測がありません（全て0,0,0）")
            #endif
            return (Point3D.zero, 0.0)
        }

        // LOSの観測のみをフィルタリング
        let losObservations = validObservations.filter { !$0.isNLOS }

        // NLOSしかない場合はNLOSを使用、それ以外はLOSのみを使用
        let targetObservations = losObservations.isEmpty ? validObservations : losObservations
        let usingNLOSOnly = losObservations.isEmpty

        var totalX = 0.0
        var totalY = 0.0
        var totalZ = 0.0
        let count = Double(targetObservations.count)

        // 全ての観測に同じ重み（1.0）を使用して単純な重心を計算
        for obs in targetObservations {
            totalX += obs.coordinate.x
            totalY += obs.coordinate.y
            totalZ += obs.coordinate.z
        }

        let coordinate = Point3D(
            x: totalX / count,
            y: totalY / count,
            z: totalZ / count
        )

        // 信頼度の計算
        // LOSのみを使用している場合は高い信頼度、NLOSのみの場合は低い信頼度
        let baseConfidence = usingNLOSOnly ? 0.2 : 0.8
        let observationBonus = Double(min(targetObservations.count, 4)) / 4.0 * 0.2
        let confidence = baseConfidence + observationBonus

        #if DEBUG
            let skippedCount = observations.count - validObservations.count
            print("📊 統合位置計算: 使用観測数=\(targetObservations.count), スキップ(0,0,0)=\(skippedCount), NLOSのみ=\(usingNLOSOnly), 信頼度=\(confidence)")
        #endif

        return (coordinate, min(confidence, 1.0))
    }
}
