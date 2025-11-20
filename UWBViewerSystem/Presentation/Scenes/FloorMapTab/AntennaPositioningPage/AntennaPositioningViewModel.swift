import Foundation
import SwiftData
import SwiftUI

#if os(macOS)
    import AppKit
#elseif os(iOS)
    import UIKit
#endif

@MainActor
class AntennaPositioningViewModel: ObservableObject {
    @Published var selectedDevices: [AndroidDevice] = []
    @Published var antennaPositions: [AntennaPosition] = []
    @Published var canProceedValue: Bool = false
    @Published var calibrationData: [MapCalibrationData] = []

    // キャリブレーション可視化用のデータ
    @Published var showCalibrationResult: Bool = false
    @Published var calibrationResultData: CalibrationResultData?

    // キャリブレーション可視化用のデータ構造
    struct CalibrationResultData {
        let tagPositions: [TagPosition]
        let initialAntennaPositions: [AntennaCalibrationPosition]
        let calibratedAntennaPositions: [AntennaCalibrationPosition]
    }

    #if os(macOS)
        var mapImage: NSImage?
    #elseif os(iOS)
        var mapImage: UIImage?
    #endif
    // mapData: IndoorMapDataは現在利用できないため、一時的にコメントアウト
    // var mapData: IndoorMapData?

    // SwiftData関連
    private var modelContext: ModelContext?
    private var swiftDataRepository: SwiftDataRepository?
    private var floorMapId: String?

    // フロアマップ情報を保持（SwiftDataから読み込み）
    @Published private var loadedFloorMapInfo: FloorMapInfo?

    // 共通コンポーネント用のcurrentFloorMapInfoプロパティ
    var currentFloorMapInfo: FloorMapInfo? {
        self.floorMapInfo
    }

    // フロアマップの情報を取得（SwiftDataから優先的に取得）
    var floorMapInfo: FloorMapInfo? {
        // SwiftDataから読み込んだ情報を優先
        if let loaded = loadedFloorMapInfo {
            return loaded
        }

        // フォールバック: UserDefaultsから取得
        guard let data = UserDefaults.standard.data(forKey: "currentFloorMapInfo"),
              let info = try? JSONDecoder().decode(FloorMapInfo.self, from: data)
        else {
            return nil
        }
        return info
    }

    // フロアマップのアスペクト比（width/depth）
    var floorMapAspectRatio: Double {
        guard let info = floorMapInfo else { return 1.0 }
        return info.width / info.depth
    }

    // キャリブレーションデータが存在するかを確認
    var hasCalibrationData: Bool {
        !self.calibrationData.isEmpty && self.calibrationData.contains { !$0.calibrationPoints.isEmpty }
    }

    // フロアマップのスケール（メートル/ピクセル）
    var mapScale: Double {
        // UserDefaultsからフロアマップ情報を取得
        guard let info = floorMapInfo else {
            return 0.01  // デフォルト値: 1ピクセル = 1cm
        }

        // マップキャンバスのサイズは400x400ピクセル
        let canvasSize: Double = 400.0

        // より大きい辺を基準にスケールを計算（アスペクト比を考慮）
        let maxRealSize = max(info.width, info.depth)
        let scale = maxRealSize / canvasSize

        #if DEBUG
            print(
                "🗺️ MapScale calculation: width=\(info.width)m, depth=\(info.depth)m, maxSize=\(maxRealSize)m, canvasSize=\(canvasSize)px, scale=\(scale)m/px"
            )
        #endif

        return scale
    }

    private let colors: [Color] = [.red, .blue, .green, .orange, .purple, .pink, .cyan, .yellow]

    // 初期化
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        if #available(macOS 14, iOS 17, *) {
            swiftDataRepository = SwiftDataRepository(modelContext: context)
        }
    }

    /// フロアマップIDを設定
    func setFloorMapId(_ floorMapId: String) {
        self.floorMapId = floorMapId
    }

    private func updateCanProceed() {
        // 初期位置（正規化座標で0.125, 0.125）から移動されたアンテナをカウント
        let positionedAntennas = self.antennaPositions.filter {
            $0.normalizedPosition != CGPoint(x: 0.125, y: 0.125)
        }
        self.canProceedValue = positionedAntennas.count >= 3
    }

    func getDevicePosition(_ deviceId: String) -> CGPoint? {
        guard let antenna = self.antennaPositions.first(where: { $0.id == deviceId }) else {
            return nil
        }
        // デフォルト位置(0.125, 0.125)の場合は未配置とみなす
        if antenna.normalizedPosition == CGPoint(x: 0.125, y: 0.125) {
            return nil
        }

        // 正規化座標から実世界座標に変換
        guard let floorMapInfo else {
            #if DEBUG
                print("⚠️ FloorMapInfo が設定されていません。デバイス位置の取得に失敗しました。")
            #endif
            return nil
        }

        // 実世界座標に変換（Y座標を反転）
        let realX = antenna.normalizedPosition.x * floorMapInfo.width
        let realY = (1.0 - antenna.normalizedPosition.y) * floorMapInfo.depth
        return CGPoint(x: realX, y: realY)
    }

    func getDeviceRotation(_ deviceId: String) -> Double? {
        guard let antenna = self.antennaPositions.first(where: { $0.id == deviceId }) else {
            return nil
        }
        // デフォルト位置の場合は角度も返さない
        let position = antenna.position
        if position == CGPoint(x: 50, y: 50) {
            return nil
        }
        return antenna.rotation
    }

    func loadMapAndDevices(floorMapId: String) {
        // SwiftDataからフロアマップ情報とキャリブレーションデータを非同期でロード
        Task { @MainActor in
            await self.loadFloorMapInfoFromSwiftData(floorMapId: floorMapId)
            await self.loadCalibrationDataAsync()
            // フロアマップ情報ロード後にデバイスを読み込み
            self.loadSelectedDevices()
        }
    }

    /// SwiftDataから指定されたフロアマップ情報を読み込み
    private func loadFloorMapInfoFromSwiftData(floorMapId: String) async {
        guard let repository = swiftDataRepository else {
            #if DEBUG
                print("❌ SwiftDataRepository が利用できません")
            #endif
            return
        }

        do {
            if let floorMap = try await repository.loadFloorMap(by: floorMapId) {
                await MainActor.run {
                    self.loadedFloorMapInfo = floorMap

                    // フロアマップ画像を読み込み
                    #if canImport(UIKit)
                        #if os(iOS)
                            self.mapImage = floorMap.image
                        #elseif os(macOS)
                            self.mapImage = floorMap.image
                        #endif
                    #elseif canImport(AppKit)
                        self.mapImage = floorMap.image
                    #endif
                }
                #if DEBUG
                    print("✅ フロアマップ情報を読み込みました: \(floorMap.name), サイズ: \(floorMap.width)x\(floorMap.depth)m, 画像: \(self.mapImage != nil ? "あり" : "なし")")
                #endif
            } else {
                #if DEBUG
                    print("⚠️ フロアマップが見つかりません (ID: \(floorMapId))")
                #endif
            }
        } catch {
            print("❌ フロアマップ情報の読み込みに失敗: \(error)")
        }
    }

    private func loadCalibrationDataAsync() async {
        guard let repository = swiftDataRepository else {
            await MainActor.run {
                self.calibrationData = []
            }
            return
        }

        do {
            let allCalibrationData = try await repository.loadMapCalibrationData()
            await MainActor.run {
                self.calibrationData = allCalibrationData
            }
            #if DEBUG
                print("✅ キャリブレーションデータを読み込みました: \(allCalibrationData.count)件")
            #endif
        } catch {
            print("❌ キャリブレーションデータの読み込みに失敗: \(error)")
            await MainActor.run {
                self.calibrationData = []
            }
        }
    }

    private func loadSelectedDevices() {
        // まず、ペアリング情報から選択されたデバイスを読み込む
        self.loadDevicesFromPairingData()

        // フォールバック: 従来のSelectedUWBDevicesから読み込む
        if self.selectedDevices.isEmpty {
            if let data = UserDefaults.standard.data(forKey: "SelectedUWBDevices"),
               let decoded = try? JSONDecoder().decode([AndroidDevice].self, from: data)
            {
                self.selectedDevices = decoded
                #if DEBUG
                    print("📱 フォールバック: SelectedUWBDevicesからデバイスを読み込み: \(self.selectedDevices.count)台")
                #endif
            }
        }
    }

    /// ペアリング情報からデバイス一覧を構築
    /// ペアリング情報からデバイス一覧を構築
    private func loadDevicesFromPairingData() {
        guard let repository = swiftDataRepository else {
            #if DEBUG
                print("❌ SwiftDataRepository が利用できません")
            #endif
            self.handleError("データベースへの接続に失敗しました")
            return
        }

        Task {
            do {
                // まずペアリング情報を試行
                let pairings = try await repository.loadAntennaPairings()
                #if DEBUG
                    print("📱 SwiftDataからペアリング情報を読み込み: \(pairings.count)件")
                #endif

                if !pairings.isEmpty {
                    await MainActor.run {
                        // 既存のリストをクリア
                        self.selectedDevices.removeAll()

                        // ペアリング済みデバイスを selectedDevices に設定
                        self.selectedDevices = pairings.compactMap { pairing in
                            // データの妥当性をチェック
                            guard !pairing.device.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                  !pairing.device.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            else {
                                #if DEBUG
                                    print("⚠️ 無効なペアリングデータをスキップ: \(pairing)")
                                #endif
                                return nil
                            }

                            var device = pairing.device
                            // アンテナ情報も含めてデバイス名を更新（アンテナ名があれば使用）
                            device.name = pairing.antenna.name.isEmpty ? device.name : pairing.antenna.name
                            return device
                        }

                        #if DEBUG
                            print("✅ ペアリング情報から \(self.selectedDevices.count) 台のデバイスを読み込みました")
                        #endif

                        // アンテナ位置を再作成
                        self.createAntennaPositions()
                    }
                } else {
                    // ペアリング情報がない場合はアンテナ位置データから構築
                    await self.loadDevicesFromAntennaPositions(repository: repository)
                }
            } catch {
                #if DEBUG
                    print("❌ ペアリング情報の読み込みエラー: \(error)")
                #endif
                await MainActor.run {
                    self.handleError("ペアリング情報の読み込みに失敗しました: \(error.localizedDescription)")
                    // エラーの場合は従来の方法にフォールバック
                    self.loadSelectedDevicesFromUserDefaults()
                }
            }
        }
    }

    /// アンテナ位置データからデバイス一覧を構築
    private func loadDevicesFromAntennaPositions(repository: SwiftDataRepository) async {
        guard let floorMapInfo else {
            await MainActor.run {
                self.loadSelectedDevicesFromUserDefaults()
            }
            return
        }

        do {
            let antennaPositions = try await repository.loadAntennaPositions(for: floorMapInfo.id)
            #if DEBUG
                print("📱 アンテナ位置データからデバイス一覧を構築: \(antennaPositions.count)件")
            #endif

            await MainActor.run {
                // 既存のリストをクリア
                self.selectedDevices.removeAll()

                // アンテナ位置データからデバイスを構築
                self.selectedDevices = antennaPositions.map { position in
                    AndroidDevice(
                        id: position.antennaId,
                        name: position.antennaName,
                        isConnected: false,
                        isNearbyDevice: false
                    )
                }

                #if DEBUG
                    print("✅ アンテナ位置データから \(self.selectedDevices.count) 台のデバイスを構築しました")
                #endif

                // アンテナ位置を再作成
                self.createAntennaPositions()
            }
        } catch {
            #if DEBUG
                print("❌ アンテナ位置データの読み込みエラー: \(error)")
            #endif
            await MainActor.run {
                self.loadSelectedDevicesFromUserDefaults()
            }
        }
    }

    /// UserDefaultsから従来の方法でデバイスを読み込み
    private func loadSelectedDevicesFromUserDefaults() {
        if let data = UserDefaults.standard.data(forKey: "SelectedUWBDevices"),
           let decoded = try? JSONDecoder().decode([AndroidDevice].self, from: data)
        {
            self.selectedDevices = decoded
            #if DEBUG
                print("📱 UserDefaultsからデバイスを読み込み: \(self.selectedDevices.count)台")
            #endif
        }
    }

    private func loadMapData() {

        // currentFloorMapInfoから読み込む
        if let data = UserDefaults.standard.data(forKey: "currentFloorMapInfo"),
           let floorMapInfo = try? JSONDecoder().decode(FloorMapInfo.self, from: data)
        {

            // 保存された画像を読み込む
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            _ = documentsDirectory.appendingPathComponent("\(floorMapInfo.id).jpg")

            // 新しいFloorMapInfo構造を使用して画像を読み込む
            self.mapImage = floorMapInfo.image
            if self.mapImage != nil {
            } else {
                #if DEBUG
                    print("❌ AntennaPositioningViewModel: Failed to load map image")
                #endif
            }
        } else {
            #if DEBUG
                print("❌ AntennaPositioningViewModel: No FloorMapInfo found in UserDefaults")
            #endif
        }
    }

    private func createAntennaPositions() {
        self.antennaPositions = self.selectedDevices.enumerated().map { index, device in
            AntennaPosition(
                id: device.id,
                deviceName: device.name,
                position: CGPoint(x: 50, y: 50),  // デフォルト位置（後で保存データで上書き）
                rotation: 0.0,
                color: self.colors[index % self.colors.count],
                baseCanvasSize: CGSize(width: 400, height: 400)  // 基準キャンバスサイズ
            )
        }
        self.updateCanProceed()

        // アンテナ位置作成後に保存データを適用
        self.loadAntennaPositionsFromSwiftData()
    }

    func updateAntennaPosition(_ antennaId: String, position: CGPoint) {
        if let index = antennaPositions.firstIndex(where: { $0.id == antennaId }) {
            self.antennaPositions[index].position = position
            self.updateCanProceed()

            // UserDefaultsに保存
            self.saveAntennaPositions()

            // SwiftDataに自動保存
            self.saveAntennaPositionToSwiftData(self.antennaPositions[index])
        }
    }

    // 正規化座標を使用した位置更新メソッド
    func updateAntennaPosition(_ antennaId: String, normalizedPosition: CGPoint) {
        if let index = antennaPositions.firstIndex(where: { $0.id == antennaId }) {
            self.antennaPositions[index].normalizedPosition = normalizedPosition
            // 基準キャンバスサイズ(400x400)での位置を更新
            self.antennaPositions[index].position = CGPoint(
                x: normalizedPosition.x * 400,
                y: normalizedPosition.y * 400
            )
            self.updateCanProceed()

            // UserDefaultsに保存
            self.saveAntennaPositions()

            // SwiftDataに自動保存
            self.saveAntennaPositionToSwiftData(self.antennaPositions[index])
        }
    }

    func updateAntennaRotation(_ antennaId: String, rotation: Double) {
        if let index = antennaPositions.firstIndex(where: { $0.id == antennaId }) {
            self.antennaPositions[index].rotation = rotation

            // UserDefaultsに保存
            self.saveAntennaPositions()

            // SwiftDataに自動保存
            self.saveAntennaPositionToSwiftData(self.antennaPositions[index])
        }
    }

    func getAntennaPosition(for deviceId: String) -> CGPoint? {
        self.antennaPositions.first(where: { $0.id == deviceId })?.position
    }

    func isDevicePositioned(_ deviceId: String) -> Bool {
        if let position = getAntennaPosition(for: deviceId) {
            return position != CGPoint(x: 50, y: 50)  // デフォルト位置以外に配置されているか
        }
        return false
    }

    func addNewDevice(name: String) {

        let newDevice = AndroidDevice(
            id: UUID().uuidString,
            name: name,
            isConnected: false,
            isNearbyDevice: false
        )

        self.selectedDevices.append(newDevice)

        let newAntennaPosition = AntennaPosition(
            id: newDevice.id,
            deviceName: newDevice.name,
            position: CGPoint(x: 50, y: 50),
            rotation: 0.0,
            color: self.colors[self.antennaPositions.count % self.colors.count],
            baseCanvasSize: CGSize(width: 400, height: 400)
        )

        self.antennaPositions.append(newAntennaPosition)

        self.saveSelectedDevices()

        self.updateCanProceed()
    }

    func removeDevice(_ deviceId: String) {
        self.selectedDevices.removeAll { $0.id == deviceId }
        self.antennaPositions.removeAll { $0.id == deviceId }

        self.saveSelectedDevices()
        self.updateCanProceed()

        // SwiftDataからも削除
        self.deleteAntennaPositionFromSwiftData(deviceId)
    }

    /// すべてのデバイスを削除
    func removeAllDevices() {

        // ローカルデータを削除
        self.selectedDevices.removeAll()
        self.antennaPositions.removeAll()

        self.saveSelectedDevices()
        self.updateCanProceed()

        // SwiftDataからも全て削除
        self.deleteAllAntennaPositionsFromSwiftData()
    }

    /// SwiftDataからアンテナ位置を削除
    private func deleteAntennaPositionFromSwiftData(_ antennaId: String) {
        guard let repository = swiftDataRepository else {
            #if DEBUG
                print("❌ SwiftDataRepository が利用できません（deleteAntennaPositionFromSwiftData）")
            #endif
            return
        }

        Task {
            do {
                try await repository.deleteAntennaPosition(by: antennaId)
            } catch {
                #if DEBUG
                    print("❌ SwiftDataからのアンテナ位置削除エラー: \(error)")
                #endif
            }
        }
    }

    /// すべてのアンテナ位置をSwiftDataから削除
    private func deleteAllAntennaPositionsFromSwiftData() {
        guard let repository = swiftDataRepository,
              let floorMapInfo
        else {
            #if DEBUG
                print("❌ SwiftDataRepository または FloorMapInfo が利用できません（deleteAllAntennaPositionsFromSwiftData）")
            #endif
            return
        }

        Task {
            do {
                // 現在のフロアマップのアンテナ位置を全て削除
                let positions = try await repository.loadAntennaPositions(for: floorMapInfo.id)

                for position in positions {
                    try await repository.deleteAntennaPosition(by: position.antennaId)
                }

            } catch {
                #if DEBUG
                    print("❌ SwiftDataからの全アンテナ位置削除エラー: \(error)")
                #endif
            }
        }
    }

    // MARK: - SwiftData関連メソッド

    private func loadAntennaPositionsFromSwiftData() {
        guard let repository = swiftDataRepository else {
            #if DEBUG
                print("❌ SwiftDataRepository が利用できません（loadAntennaPositionsFromSwiftData）")
            #endif
            return
        }

        guard let floorMapInfo else {
            #if DEBUG
                print("❌ FloorMapInfo が取得できません（loadAntennaPositionsFromSwiftData）")
            #endif
            return
        }

        Task {
            do {
                let positions = try await repository.loadAntennaPositions(for: floorMapInfo.id)
                #if DEBUG
                    print("📱 SwiftDataからアンテナ位置データを取得: \(positions.count)件")
                #endif

                await MainActor.run {
                    var appliedCount = 0

                    // SwiftDataから読み込んだ位置情報を現在のantennaPositionsに適用
                    for position in positions {
                        if let index = antennaPositions.firstIndex(where: { $0.id == position.antennaId }) {
                            // 実世界座標から正規化座標に変換
                            // 実世界座標: 左下原点(0,0)、メートル単位、Y軸上向き
                            // normalizedPosition: 左上原点(0,0)、範囲0-1、Y軸下向き
                            let normalizedX = CGFloat(position.position.x / floorMapInfo.width)
                            let normalizedY = CGFloat(1.0 - (position.position.y / floorMapInfo.depth))

                            // 正規化座標を設定
                            self.antennaPositions[index].normalizedPosition = CGPoint(
                                x: normalizedX,
                                y: normalizedY
                            )
                            // ピクセル座標も更新（400x400基準）
                            self.antennaPositions[index].position = CGPoint(
                                x: normalizedX * 400.0,
                                y: normalizedY * 400.0
                            )
                            self.antennaPositions[index].rotation = position.rotation

                            appliedCount += 1
                        } else {
                            #if DEBUG
                                print("⚠️ アンテナID[\(position.antennaId)]が現在のリストに見つかりません")
                            #endif
                        }
                    }
                    self.updateCanProceed()
                    #if DEBUG
                        print(
                            "📱 SwiftDataからアンテナ位置を読み込み完了: \(appliedCount)/\(positions.count)件適用 for floorMap: \(floorMapInfo.id)"
                        )
                    #endif
                }
            } catch {
                #if DEBUG
                    print("❌ SwiftDataからの読み込みエラー: \(error)")
                #endif
                await MainActor.run {
                    // SwiftDataが失敗した場合はUserDefaultsからフォールバック読み込み
                    self.loadAntennaPositionsFromUserDefaults()
                }
            }
        }
    }

    /// UserDefaultsからアンテナ位置を読み込む（フォールバック）
    private func loadAntennaPositionsFromUserDefaults() {

        if let data = UserDefaults.standard.data(forKey: "configuredAntennaPositions"),
           let positionData = try? JSONDecoder().decode([AntennaPositionData].self, from: data)
        {

            var appliedCount = 0

            for position in positionData {
                if let index = antennaPositions.firstIndex(where: { $0.id == position.antennaId }) {
                    // UserDefaultsから直接ピクセル座標として読み込み（スケール変換なし）
                    let pixelX = CGFloat(position.position.x)
                    let pixelY = CGFloat(position.position.y)

                    self.antennaPositions[index].position = CGPoint(x: pixelX, y: pixelY)
                    self.antennaPositions[index].normalizedPosition = CGPoint(
                        x: pixelX / 400.0,
                        y: pixelY / 400.0
                    )
                    self.antennaPositions[index].rotation = position.rotation

                    appliedCount += 1
                }
            }

            self.updateCanProceed()
            #if DEBUG
                print("📱 UserDefaultsからアンテナ位置を読み込み完了: \(appliedCount)/\(positionData.count)件適用")
            #endif
        } else {
            #if DEBUG
                print("❌ UserDefaultsにconfiguredAntennaPositionsが見つかりません")
            #endif
        }
    }

    private func saveAntennaPositionToSwiftData(_ antennaPosition: AntennaPosition) {
        guard let repository = swiftDataRepository,
              let floorMapInfo
        else { return }

        Task {
            do {
                // 正規化座標から実世界座標に変換
                // normalizedPosition: 左上原点(0,0)、範囲0-1、Y軸下向き
                // 実世界座標: 左下原点(0,0)、メートル単位、Y軸上向き
                let realWorldX = Double(antennaPosition.normalizedPosition.x) * floorMapInfo.width
                let realWorldY = (1.0 - Double(antennaPosition.normalizedPosition.y)) * floorMapInfo.depth

                let positionData = AntennaPositionData(
                    id: antennaPosition.id,
                    antennaId: antennaPosition.id,
                    antennaName: antennaPosition.deviceName,
                    position: Point3D(x: realWorldX, y: realWorldY, z: 0.0),
                    rotation: antennaPosition.rotation,
                    floorMapId: floorMapInfo.id
                )

                // 既存のレコードがあるかチェックして更新 or 新規作成
                try await repository.saveAntennaPosition(positionData)
            } catch {
                #if DEBUG
                    print("❌ SwiftDataへの保存エラー: \(error)")
                #endif
            }
        }
    }

    private func saveSelectedDevices() {
        if let encoded = try? JSONEncoder().encode(selectedDevices) {
            UserDefaults.standard.set(encoded, forKey: "SelectedUWBDevices")
        }
    }

    func saveAntennaPositions() {
        guard let floorMapInfo else { return }

        let positionData = self.antennaPositions.map { antenna in
            // 正規化座標から実世界座標に変換
            // normalizedPosition: 左上原点(0,0)、範囲0-1、Y軸下向き
            // 実世界座標: 左下原点(0,0)、メートル単位、Y軸上向き
            let realWorldX = Double(antenna.normalizedPosition.x) * floorMapInfo.width
            let realWorldY = (1.0 - Double(antenna.normalizedPosition.y)) * floorMapInfo.depth

            return AntennaPositionData(
                antennaId: antenna.id,
                antennaName: antenna.deviceName,
                position: Point3D(x: realWorldX, y: realWorldY, z: 0.0),
                rotation: antenna.rotation,
                floorMapId: floorMapInfo.id
            )
        }

        if let encoded = try? JSONEncoder().encode(positionData) {
            UserDefaults.standard.set(encoded, forKey: "configuredAntennaPositions")
        }
    }

    func saveAntennaPositionsForFlow() -> Bool {

        // 配置されたアンテナの数をチェック
        let positionedAntennas = self.antennaPositions.filter { $0.position != CGPoint(x: 50, y: 50) }

        guard positionedAntennas.count >= 2 else {
            #if DEBUG
                print(
                    "❌ saveAntennaPositionsForFlow: Need at least 2 positioned antennas, got \(positionedAntennas.count)"
                )
            #endif
            return false
        }

        // 回転角度が設定されているかチェック（必須ではないが、推奨）
        let _ = positionedAntennas.filter { $0.rotation != 0.0 }

        // データを保存
        self.saveAntennaPositions()

        return true
    }

    private func convertToRealWorldPosition(_ screenPosition: CGPoint) -> RealWorldPosition {
        // マップの実際のサイズとスクリーン上のサイズの比率を計算
        // UserDefaultsからフロアマップ情報を取得
        guard let mapData = UserDefaults.standard.data(forKey: "currentFloorMapInfo"),
              let floorMapData = try? JSONDecoder().decode(FloorMapInfo.self, from: mapData)
        else {
            return RealWorldPosition(x: Double(screenPosition.x), y: Double(screenPosition.y), z: 0)
        }

        let canvasSize = CGSize(width: 400, height: 400)
        let scaleX = floorMapData.width / Double(canvasSize.width)
        let scaleY = floorMapData.depth / Double(canvasSize.height)

        let realX = Double(screenPosition.x) * scaleX
        let realY = Double(screenPosition.y) * scaleY

        return RealWorldPosition(x: realX, y: realY, z: 0)
    }

    // MARK: - エラーハンドリング

    /// エラーハンドリング用のメソッド
    private func handleError(_ message: String) {
        #if DEBUG
            print("❌ AntennaPositioningViewModel Error: \(message)")
        #endif
        // TODO: エラー状態をUIに反映する仕組みを追加
        // 例: @Published var errorMessage: String? = nil
        // errorMessage = message
    }

    /// 安全な非同期タスク実行
    private func safeAsyncTask<T>(
        operation: @escaping () async throws -> T,
        onSuccess: @escaping (T) -> Void = { _ in },
        onFailure: @escaping (Error) -> Void = { _ in }
    ) {
        Task {
            do {
                let result = try await operation()
                await MainActor.run {
                    onSuccess(result)
                }
            } catch {
                await MainActor.run {
                    self.handleError(error.localizedDescription)
                    onFailure(error)
                }
            }
        }
    }
}

// MARK: - Data Models

struct AntennaPosition: Identifiable {
    let id: String
    let deviceName: String
    var position: CGPoint  // 表示用の実際の座標（キャンバスサイズ依存）
    var normalizedPosition: CGPoint  // 正規化された座標（0-1の範囲、キャンバスサイズ非依存）
    var rotation: Double = 0.0
    let color: Color

    // 初期化時に正規化座標を基準キャンバスサイズから計算
    init(
        id: String, deviceName: String, position: CGPoint, rotation: Double = 0.0, color: Color,
        baseCanvasSize: CGSize = CGSize(width: 400, height: 400)
    ) {
        self.id = id
        self.deviceName = deviceName
        self.position = position
        self.normalizedPosition = CGPoint(
            x: position.x / baseCanvasSize.width,
            y: position.y / baseCanvasSize.height
        )
        self.rotation = rotation
        self.color = color
    }

    // 正規化座標から初期化
    init(
        id: String, deviceName: String, normalizedPosition: CGPoint, rotation: Double = 0.0, color: Color,
        canvasSize: CGSize
    ) {
        self.id = id
        self.deviceName = deviceName
        self.normalizedPosition = normalizedPosition
        self.position = CGPoint(
            x: normalizedPosition.x * canvasSize.width,
            y: normalizedPosition.y * canvasSize.height
        )
        self.rotation = rotation
        self.color = color
    }

    // ViewでAntennaPosition作成用の初期化（位置と正規化位置を直接指定）
    init(
        id: String, deviceName: String, position: CGPoint, normalizedPosition: CGPoint, rotation: Double = 0.0,
        color: Color
    ) {
        self.id = id
        self.deviceName = deviceName
        self.position = position
        self.normalizedPosition = normalizedPosition
        self.rotation = rotation
        self.color = color
    }
}

// Domain層のAntennaPositionDataとRealWorldPositionを使用
