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

    // 共通コンポーネント用のcurrentFloorMapInfoプロパティ
    var currentFloorMapInfo: FloorMapInfo? {
        return floorMapInfo
    }

    // フロアマップの情報を取得
    var floorMapInfo: FloorMapInfo? {
        guard let data = UserDefaults.standard.data(forKey: "currentFloorMapInfo"),
              let info = try? JSONDecoder().decode(FloorMapInfo.self, from: data) else {
            return nil
        }
        return info
    }

    // フロアマップのアスペクト比（width/depth）
    var floorMapAspectRatio: Double {
        guard let info = floorMapInfo else { return 1.0 }
        return info.width / info.depth
    }

    // フロアマップのスケール（メートル/ピクセル）
    var mapScale: Double {
        // UserDefaultsからフロアマップ情報を取得
        guard let info = floorMapInfo else {
            return 0.01 // デフォルト値: 1ピクセル = 1cm
        }

        // マップキャンバスのサイズは400x400ピクセル
        let canvasSize: Double = 400.0

        // より大きい辺を基準にスケールを計算（アスペクト比を考慮）
        let maxRealSize = max(info.width, info.depth)
        let scale = maxRealSize / canvasSize

        print("🗺️ MapScale calculation: width=\(info.width)m, depth=\(info.depth)m, maxSize=\(maxRealSize)m, canvasSize=\(canvasSize)px, scale=\(scale)m/px")

        return scale
    }

    private let colors: [Color] = [.red, .blue, .green, .orange, .purple, .pink, .cyan, .yellow]

    // 初期化
    func setModelContext(_ context: ModelContext) {
        modelContext = context
        if #available(macOS 14, iOS 17, *) {
            swiftDataRepository = SwiftDataRepository(modelContext: context)
        }
        // SwiftDataRepository設定後にデータを再読み込み
        loadMapAndDevices()
        // loadAntennaPositionsFromSwiftDataはcreateAntennaPositions内で呼び出すため、ここでは呼ばない
    }

    private func updateCanProceed() {
        // 初期位置（正規化座標で0.125, 0.125）から移動されたアンテナをカウント
        let positionedAntennas = antennaPositions.filter {
            $0.normalizedPosition != CGPoint(x: 0.125, y: 0.125)
        }
        canProceedValue = positionedAntennas.count >= 3
    }

    func getDevicePosition(_ deviceId: String) -> CGPoint {
        antennaPositions.first { $0.id == deviceId }?.position ?? CGPoint(x: 50, y: 50)
    }

    func getDeviceRotation(_ deviceId: String) -> Double {
        antennaPositions.first { $0.id == deviceId }?.rotation ?? 0.0
    }

    func loadMapAndDevices() {
        loadSelectedDevices()
        loadMapData()
        createAntennaPositions()
    }

    private func loadSelectedDevices() {
        // まず、ペアリング情報から選択されたデバイスを読み込む
        loadDevicesFromPairingData()

        // フォールバック: 従来のSelectedUWBDevicesから読み込む
        if selectedDevices.isEmpty {
            if let data = UserDefaults.standard.data(forKey: "SelectedUWBDevices"),
               let decoded = try? JSONDecoder().decode([AndroidDevice].self, from: data)
            {
                selectedDevices = decoded
                print("📱 フォールバック: SelectedUWBDevicesからデバイスを読み込み: \(selectedDevices.count)台")
            }
        }
    }

    /// ペアリング情報からデバイス一覧を構築
    private func loadDevicesFromPairingData() {
        guard let repository = swiftDataRepository else {
            print("❌ SwiftDataRepository が利用できません")
            return
        }

        Task {
            do {
                // まずペアリング情報を試行
                let pairings = try await repository.loadAntennaPairings()
                print("📱 SwiftDataからペアリング情報を読み込み: \(pairings.count)件")

                if !pairings.isEmpty {
                    await MainActor.run {
                        // 既存のリストをクリア
                        selectedDevices.removeAll()

                        // ペアリング済みデバイスを selectedDevices に設定
                        selectedDevices = pairings.map { pairing in
                            var device = pairing.device
                            // アンテナ情報も含めてデバイス名を更新（アンテナ名があれば使用）
                            device.name = pairing.antenna.name.isEmpty ? device.name : pairing.antenna.name
                            return device
                        }

                        print("✅ ペアリング情報から \(selectedDevices.count) 台のデバイスを読み込みました")

                        // アンテナ位置を再作成
                        createAntennaPositions()
                    }
                } else {
                    // ペアリング情報がない場合はアンテナ位置データから構築
                    await loadDevicesFromAntennaPositions(repository: repository)
                }
            } catch {
                print("❌ ペアリング情報の読み込みエラー: \(error)")
                await MainActor.run {
                    // エラーの場合は従来の方法にフォールバック
                    loadSelectedDevicesFromUserDefaults()
                }
            }
        }
    }

    /// アンテナ位置データからデバイス一覧を構築
    private func loadDevicesFromAntennaPositions(repository: SwiftDataRepository) async {
        guard let floorMapInfo else {
            await MainActor.run {
                loadSelectedDevicesFromUserDefaults()
            }
            return
        }

        do {
            let antennaPositions = try await repository.loadAntennaPositions(for: floorMapInfo.id)
            print("📱 アンテナ位置データからデバイス一覧を構築: \(antennaPositions.count)件")

            await MainActor.run {
                // 既存のリストをクリア
                selectedDevices.removeAll()

                // アンテナ位置データからデバイスを構築
                selectedDevices = antennaPositions.map { position in
                    AndroidDevice(
                        id: position.antennaId,
                        name: position.antennaName,
                        isConnected: false,
                        isNearbyDevice: false
                    )
                }

                print("✅ アンテナ位置データから \(selectedDevices.count) 台のデバイスを構築しました")

                // アンテナ位置を再作成
                createAntennaPositions()
            }
        } catch {
            print("❌ アンテナ位置データの読み込みエラー: \(error)")
            await MainActor.run {
                loadSelectedDevicesFromUserDefaults()
            }
        }
    }

    /// UserDefaultsから従来の方法でデバイスを読み込み
    private func loadSelectedDevicesFromUserDefaults() {
        if let data = UserDefaults.standard.data(forKey: "SelectedUWBDevices"),
           let decoded = try? JSONDecoder().decode([AndroidDevice].self, from: data)
        {
            selectedDevices = decoded
            print("📱 UserDefaultsからデバイスを読み込み: \(selectedDevices.count)台")
        }
    }

    private func loadMapData() {
        print("📍 AntennaPositioningViewModel: loadMapData called")

        // currentFloorMapInfoから読み込む
        if let data = UserDefaults.standard.data(forKey: "currentFloorMapInfo"),
           let floorMapInfo = try? JSONDecoder().decode(FloorMapInfo.self, from: data) {
            print("📍 AntennaPositioningViewModel: FloorMapInfo loaded - \(floorMapInfo.name)")

            // 保存された画像を読み込む
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let imageURL = documentsDirectory.appendingPathComponent("\(floorMapInfo.id).jpg")

            print("📍 AntennaPositioningViewModel: Looking for image at: \(imageURL.path)")

            // 新しいFloorMapInfo構造を使用して画像を読み込む
            mapImage = floorMapInfo.image
            if mapImage != nil {
                print("✅ AntennaPositioningViewModel: Map image loaded successfully")
            } else {
                print("❌ AntennaPositioningViewModel: Failed to load map image")
            }
        } else {
            print("❌ AntennaPositioningViewModel: No FloorMapInfo found in UserDefaults")
        }
    }

    private func createAntennaPositions() {
        antennaPositions = selectedDevices.enumerated().map { index, device in
            AntennaPosition(
                id: device.id,
                deviceName: device.name,
                position: CGPoint(x: 50, y: 50),  // デフォルト位置（後で保存データで上書き）
                rotation: 0.0,
                color: colors[index % colors.count],
                baseCanvasSize: CGSize(width: 400, height: 400) // 基準キャンバスサイズ
            )
        }
        updateCanProceed()

        // アンテナ位置作成後に保存データを適用
        loadAntennaPositionsFromSwiftData()
    }

    func updateAntennaPosition(_ antennaId: String, position: CGPoint) {
        if let index = antennaPositions.firstIndex(where: { $0.id == antennaId }) {
            antennaPositions[index].position = position
            updateCanProceed()

            // UserDefaultsに保存
            saveAntennaPositions()

            // SwiftDataに自動保存
            saveAntennaPositionToSwiftData(antennaPositions[index])

            print("🎯 アンテナ[\(antennaId)]の位置を更新: (\(position.x), \(position.y))")
        }
    }

    // 正規化座標を使用した位置更新メソッド
    func updateAntennaPosition(_ antennaId: String, normalizedPosition: CGPoint) {
        if let index = antennaPositions.firstIndex(where: { $0.id == antennaId }) {
            antennaPositions[index].normalizedPosition = normalizedPosition
            // 基準キャンバスサイズ(400x400)での位置を更新
            antennaPositions[index].position = CGPoint(
                x: normalizedPosition.x * 400,
                y: normalizedPosition.y * 400
            )
            updateCanProceed()

            // UserDefaultsに保存
            saveAntennaPositions()

            // SwiftDataに自動保存
            saveAntennaPositionToSwiftData(antennaPositions[index])

            print("🎯 アンテナ[\(antennaId)]の正規化位置を更新: (\(normalizedPosition.x), \(normalizedPosition.y))")
        }
    }

    func updateAntennaRotation(_ antennaId: String, rotation: Double) {
        if let index = antennaPositions.firstIndex(where: { $0.id == antennaId }) {
            antennaPositions[index].rotation = rotation

            // UserDefaultsに保存
            saveAntennaPositions()

            // SwiftDataに自動保存
            saveAntennaPositionToSwiftData(antennaPositions[index])

            print("🎯 アンテナ[\(antennaId)]の向きを更新: \(rotation)°")
        }
    }

    func getAntennaPosition(for deviceId: String) -> CGPoint? {
        antennaPositions.first(where: { $0.id == deviceId })?.position
    }

    func isDevicePositioned(_ deviceId: String) -> Bool {
        if let position = getAntennaPosition(for: deviceId) {
            return position != CGPoint(x: 50, y: 50)  // デフォルト位置以外に配置されているか
        }
        return false
    }

    func autoArrangeAntennas() {
        // フロアマップのアスペクト比を考慮した基準キャンバスサイズを設定
        let baseSize: CGFloat = 400
        let aspectRatio = floorMapAspectRatio

        let canvasSize: CGSize
        if aspectRatio > 1.0 {
            // 横長
            canvasSize = CGSize(width: baseSize, height: baseSize / aspectRatio)
        } else {
            // 縦長または正方形
            canvasSize = CGSize(width: baseSize * aspectRatio, height: baseSize)
        }

        let margin: CGFloat = 60
        let availableWidth = canvasSize.width - (margin * 2)
        let availableHeight = canvasSize.height - (margin * 2)

        let deviceCount = antennaPositions.count

        if deviceCount <= 0 { return }

        // 三角形、四角形、その他の形状で自動配置
        if deviceCount == 3 {
            // 三角形配置
            let positions = [
                CGPoint(x: canvasSize.width / 2, y: margin),
                CGPoint(x: margin, y: availableHeight + margin),
                CGPoint(x: availableWidth + margin, y: availableHeight + margin),
            ]
            for (index, position) in positions.enumerated() {
                if index < antennaPositions.count {
                    antennaPositions[index].position = position
                    antennaPositions[index].normalizedPosition = CGPoint(
                        x: position.x / canvasSize.width,
                        y: position.y / canvasSize.height
                    )
                }
            }
        } else if deviceCount == 4 {
            // 四角形配置
            let positions = [
                CGPoint(x: margin, y: margin),
                CGPoint(x: availableWidth + margin, y: margin),
                CGPoint(x: margin, y: availableHeight + margin),
                CGPoint(x: availableWidth + margin, y: availableHeight + margin),
            ]
            for (index, position) in positions.enumerated() {
                if index < antennaPositions.count {
                    antennaPositions[index].position = position
                    antennaPositions[index].normalizedPosition = CGPoint(
                        x: position.x / canvasSize.width,
                        y: position.y / canvasSize.height
                    )
                }
            }
        } else {
            // 円形配置
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let radius = min(availableWidth, availableHeight) / 2

            for (index, _) in antennaPositions.enumerated() {
                let angle = (2 * Double.pi * Double(index)) / Double(deviceCount)
                let x = center.x + CGFloat(cos(angle)) * radius
                let y = center.y + CGFloat(sin(angle)) * radius
                let position = CGPoint(x: x, y: y)
                antennaPositions[index].position = position
                antennaPositions[index].normalizedPosition = CGPoint(
                    x: position.x / canvasSize.width,
                    y: position.y / canvasSize.height
                )
            }
        }
        updateCanProceed()
    }

    func resetPositions() {
        for index in antennaPositions.indices {
            let resetPosition = CGPoint(x: 50, y: 50)
            antennaPositions[index].position = resetPosition
            antennaPositions[index].normalizedPosition = CGPoint(x: 0.125, y: 0.125) // 50/400 = 0.125
            antennaPositions[index].rotation = 0.0

            // SwiftDataの位置もリセット
            saveAntennaPositionToSwiftData(antennaPositions[index])
        }
        updateCanProceed()
        print("🔄 全てのアンテナ位置をリセットしました")
    }

    func addNewDevice(name: String) {
        print("🔄 addNewDevice: Starting to add device '\(name)'")

        let newDevice = AndroidDevice(
            id: UUID().uuidString,
            name: name,
            isConnected: false,
            isNearbyDevice: false
        )
        print("🔄 addNewDevice: AndroidDevice created successfully")

        selectedDevices.append(newDevice)
        print("🔄 addNewDevice: Device added to selectedDevices, count: \(selectedDevices.count)")

        let newAntennaPosition = AntennaPosition(
            id: newDevice.id,
            deviceName: newDevice.name,
            position: CGPoint(x: 50, y: 50),
            rotation: 0.0,
            color: colors[antennaPositions.count % colors.count],
            baseCanvasSize: CGSize(width: 400, height: 400)
        )
        print("🔄 addNewDevice: AntennaPosition created with normalized position: \(newAntennaPosition.normalizedPosition)")

        antennaPositions.append(newAntennaPosition)
        print("🔄 addNewDevice: AntennaPosition added to array, count: \(antennaPositions.count)")

        saveSelectedDevices()
        print("🔄 addNewDevice: Selected devices saved to UserDefaults")

        updateCanProceed()
        print("🔄 addNewDevice: updateCanProceed called, canProceedValue: \(canProceedValue)")

        print("✅ 新しいデバイスを追加しました: \(name)")
    }

    func removeDevice(_ deviceId: String) {
        selectedDevices.removeAll { $0.id == deviceId }
        antennaPositions.removeAll { $0.id == deviceId }

        saveSelectedDevices()
        updateCanProceed()

        // SwiftDataからも削除
        deleteAntennaPositionFromSwiftData(deviceId)

        print("🗑️ デバイスを削除しました: \(deviceId)")
    }

    /// すべてのデバイスを削除
    func removeAllDevices() {
        print("🗑️ 全てのデバイスを削除開始")

        // ローカルデータを削除
        selectedDevices.removeAll()
        antennaPositions.removeAll()

        saveSelectedDevices()
        updateCanProceed()

        // SwiftDataからも全て削除
        deleteAllAntennaPositionsFromSwiftData()

        print("🗑️ 全てのデバイスを削除しました")
    }

    /// SwiftDataからアンテナ位置を削除
    private func deleteAntennaPositionFromSwiftData(_ antennaId: String) {
        guard let repository = swiftDataRepository else {
            print("❌ SwiftDataRepository が利用できません（deleteAntennaPositionFromSwiftData）")
            return
        }

        Task {
            do {
                try await repository.deleteAntennaPosition(by: antennaId)
                print("🗑️ SwiftDataからアンテナ位置を削除しました: \(antennaId)")
            } catch {
                print("❌ SwiftDataからのアンテナ位置削除エラー: \(error)")
            }
        }
    }

    /// すべてのアンテナ位置をSwiftDataから削除
    private func deleteAllAntennaPositionsFromSwiftData() {
        guard let repository = swiftDataRepository,
              let floorMapInfo else {
            print("❌ SwiftDataRepository または FloorMapInfo が利用できません（deleteAllAntennaPositionsFromSwiftData）")
            return
        }

        Task {
            do {
                // 現在のフロアマップのアンテナ位置を全て削除
                let positions = try await repository.loadAntennaPositions(for: floorMapInfo.id)
                print("🗑️ 現在のフロアマップのアンテナ位置を全削除: \(positions.count)件")

                for position in positions {
                    try await repository.deleteAntennaPosition(by: position.antennaId)
                }

                print("🗑️ SwiftDataから全アンテナ位置を削除完了")
            } catch {
                print("❌ SwiftDataからの全アンテナ位置削除エラー: \(error)")
            }
        }
    }

    // MARK: - SwiftData関連メソッド

    private func loadAntennaPositionsFromSwiftData() {
        guard let repository = swiftDataRepository else {
            print("❌ SwiftDataRepository が利用できません（loadAntennaPositionsFromSwiftData）")
            return
        }

        guard let floorMapInfo else {
            print("❌ FloorMapInfo が取得できません（loadAntennaPositionsFromSwiftData）")
            return
        }

        print("🔄 SwiftDataからアンテナ位置を読み込み開始: floorMapId=\(floorMapInfo.id)")

        Task {
            do {
                let positions = try await repository.loadAntennaPositions(for: floorMapInfo.id)
                print("📱 SwiftDataからアンテナ位置データを取得: \(positions.count)件")

                await MainActor.run {
                    var appliedCount = 0

                    // SwiftDataから読み込んだ位置情報を現在のantennaPositionsに適用
                    for position in positions {
                        if let index = antennaPositions.firstIndex(where: { $0.id == position.antennaId }) {
                            // スケール変換: 実世界座標からピクセル座標へ
                            let pixelX = CGFloat(position.position.x / mapScale)
                            let pixelY = CGFloat(position.position.y / mapScale)

                            // 基準キャンバスサイズでの位置を設定
                            antennaPositions[index].position = CGPoint(x: pixelX, y: pixelY)
                            // 正規化座標も更新
                            antennaPositions[index].normalizedPosition = CGPoint(
                                x: pixelX / 400.0,
                                y: pixelY / 400.0
                            )
                            antennaPositions[index].rotation = position.rotation

                            appliedCount += 1
                            print("✅ アンテナ[\(position.antennaId)]の位置を復元: (\(pixelX), \(pixelY))")
                        } else {
                            print("⚠️ アンテナID[\(position.antennaId)]が現在のリストに見つかりません")
                        }
                    }
                    updateCanProceed()
                    print("📱 SwiftDataからアンテナ位置を読み込み完了: \(appliedCount)/\(positions.count)件適用 for floorMap: \(floorMapInfo.id)")

                    // デバッグ情報: 現在のantennaPositions状態
                    print("🔍 現在のantennaPositions状態:")
                    for (index, antenna) in antennaPositions.enumerated() {
                        print("  [\(index)] \(antenna.deviceName): (\(antenna.position.x), \(antenna.position.y)) - normalized: (\(antenna.normalizedPosition.x), \(antenna.normalizedPosition.y))")
                    }
                }
            } catch {
                print("❌ SwiftDataからの読み込みエラー: \(error)")
                await MainActor.run {
                    // SwiftDataが失敗した場合はUserDefaultsからフォールバック読み込み
                    loadAntennaPositionsFromUserDefaults()
                }
            }
        }
    }

    /// UserDefaultsからアンテナ位置を読み込む（フォールバック）
    private func loadAntennaPositionsFromUserDefaults() {
        print("🔄 UserDefaultsからアンテナ位置を読み込み開始")

        if let data = UserDefaults.standard.data(forKey: "configuredAntennaPositions"),
           let positionData = try? JSONDecoder().decode([AntennaPositionData].self, from: data) {

            var appliedCount = 0

            for position in positionData {
                if let index = antennaPositions.firstIndex(where: { $0.id == position.antennaId }) {
                    // UserDefaultsから直接ピクセル座標として読み込み（スケール変換なし）
                    let pixelX = CGFloat(position.position.x)
                    let pixelY = CGFloat(position.position.y)

                    antennaPositions[index].position = CGPoint(x: pixelX, y: pixelY)
                    antennaPositions[index].normalizedPosition = CGPoint(
                        x: pixelX / 400.0,
                        y: pixelY / 400.0
                    )
                    antennaPositions[index].rotation = position.rotation

                    appliedCount += 1
                    print("✅ UserDefaults: アンテナ[\(position.antennaId)]の位置を復元: (\(pixelX), \(pixelY))")
                }
            }

            updateCanProceed()
            print("📱 UserDefaultsからアンテナ位置を読み込み完了: \(appliedCount)/\(positionData.count)件適用")
        } else {
            print("❌ UserDefaultsにconfiguredAntennaPositionsが見つかりません")
        }
    }

    private func saveAntennaPositionToSwiftData(_ antennaPosition: AntennaPosition) {
        guard let repository = swiftDataRepository,
              let floorMapInfo else { return }

        Task {
            do {
                // ピクセル座標を実世界座標に変換
                let realWorldX = Double(antennaPosition.position.x) * mapScale
                let realWorldY = Double(antennaPosition.position.y) * mapScale

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
                print("💾 SwiftDataにアンテナ位置を保存: \(antennaPosition.deviceName) for floorMap: \(floorMapInfo.id)")
            } catch {
                print("❌ SwiftDataへの保存エラー: \(error)")
            }
        }
    }

    private func saveSelectedDevices() {
        if let encoded = try? JSONEncoder().encode(selectedDevices) {
            UserDefaults.standard.set(encoded, forKey: "SelectedUWBDevices")
            print("💾 選択デバイス一覧を保存しました: \(selectedDevices.count)台")
        }
    }

    func saveAntennaPositions() {
        guard let floorMapInfo else { return }

        let positionData = antennaPositions.map { antenna in
            AntennaPositionData(
                antennaId: antenna.id,
                antennaName: antenna.deviceName,
                position: Point3D(x: antenna.position.x, y: antenna.position.y, z: 0.0),
                rotation: antenna.rotation,
                floorMapId: floorMapInfo.id
            )
        }

        if let encoded = try? JSONEncoder().encode(positionData) {
            UserDefaults.standard.set(encoded, forKey: "configuredAntennaPositions")
            print("💾 アンテナ位置データを保存しました: \(positionData.count)台")
        }
    }

    func saveAntennaPositionsForFlow() -> Bool {
        print("🔄 saveAntennaPositionsForFlow: Starting save process")
        print("🔄 saveAntennaPositionsForFlow: Total antennas = \(antennaPositions.count)")

        // 配置されたアンテナの数をチェック
        let positionedAntennas = antennaPositions.filter { $0.position != CGPoint(x: 50, y: 50) }
        print("🔄 saveAntennaPositionsForFlow: Positioned antennas = \(positionedAntennas.count)")

        for (index, antenna) in antennaPositions.enumerated() {
            print("🔄 Antenna \(index): \(antenna.deviceName) at (\(antenna.position.x), \(antenna.position.y))")
        }

        guard positionedAntennas.count >= 2 else {
            print("❌ saveAntennaPositionsForFlow: Need at least 2 positioned antennas, got \(positionedAntennas.count)")
            return false
        }

        // 回転角度が設定されているかチェック（必須ではないが、推奨）
        let _ = positionedAntennas.filter { $0.rotation != 0.0 }

        // データを保存
        print("💾 saveAntennaPositionsForFlow: Saving antenna positions")
        saveAntennaPositions()

        // プロジェクト進行状況を更新
        updateProjectProgress(toStep: .antennaConfiguration)

        print("✅ saveAntennaPositionsForFlow: Save completed successfully")
        return true
    }

    private func convertToRealWorldPosition(_ screenPosition: CGPoint) -> RealWorldPosition {
        // マップの実際のサイズとスクリーン上のサイズの比率を計算
        // UserDefaultsからフロアマップ情報を取得
        guard let mapData = UserDefaults.standard.data(forKey: "currentFloorMapInfo"),
              let floorMapData = try? JSONDecoder().decode(FloorMapInfo.self, from: mapData) else {
            return RealWorldPosition(x: Double(screenPosition.x), y: Double(screenPosition.y), z: 0)
        }

        let canvasSize = CGSize(width: 400, height: 400)
        let scaleX = floorMapData.width / Double(canvasSize.width)
        let scaleY = floorMapData.depth / Double(canvasSize.height)

        let realX = Double(screenPosition.x) * scaleX
        let realY = Double(screenPosition.y) * scaleY

        return RealWorldPosition(x: realX, y: realY, z: 0)
    }

    // MARK: - プロジェクト進行状況更新

    private func updateProjectProgress(toStep step: SetupStep) {
        guard let repository = swiftDataRepository,
              let floorMapInfo else { return }

        Task {
            do {
                // 既存の進行状況を取得
                var projectProgress = try await repository.loadProjectProgress(for: floorMapInfo.id)

                if projectProgress == nil {
                    // 進行状況が存在しない場合は新規作成
                    projectProgress = ProjectProgress(
                        floorMapId: floorMapInfo.id,
                        currentStep: step
                    )
                } else {
                    // 既存の進行状況を更新
                    projectProgress!.currentStep = step
                    projectProgress!.completedSteps.insert(step)
                    projectProgress!.updatedAt = Date()
                }

                try await repository.updateProjectProgress(projectProgress!)
                print("✅ プロジェクト進行状況を更新: \(step.displayName)")

            } catch {
                print("❌ プロジェクト進行状況の更新エラー: \(error)")
            }
        }
    }
}

// MARK: - Data Models

struct AntennaPosition: Identifiable {
    let id: String
    let deviceName: String
    var position: CGPoint           // 表示用の実際の座標（キャンバスサイズ依存）
    var normalizedPosition: CGPoint // 正規化された座標（0-1の範囲、キャンバスサイズ非依存）
    var rotation: Double = 0.0
    let color: Color

    // 初期化時に正規化座標を基準キャンバスサイズから計算
    init(id: String, deviceName: String, position: CGPoint, rotation: Double = 0.0, color: Color, baseCanvasSize: CGSize = CGSize(width: 400, height: 400)) {
        self.id = id
        self.deviceName = deviceName
        self.position = position
        normalizedPosition = CGPoint(
            x: position.x / baseCanvasSize.width,
            y: position.y / baseCanvasSize.height
        )
        self.rotation = rotation
        self.color = color
    }

    // 正規化座標から初期化
    init(id: String, deviceName: String, normalizedPosition: CGPoint, rotation: Double = 0.0, color: Color, canvasSize: CGSize) {
        self.id = id
        self.deviceName = deviceName
        self.normalizedPosition = normalizedPosition
        position = CGPoint(
            x: normalizedPosition.x * canvasSize.width,
            y: normalizedPosition.y * canvasSize.height
        )
        self.rotation = rotation
        self.color = color
    }

    // ViewでAntennaPosition作成用の初期化（位置と正規化位置を直接指定）
    init(id: String, deviceName: String, position: CGPoint, normalizedPosition: CGPoint, rotation: Double = 0.0, color: Color) {
        self.id = id
        self.deviceName = deviceName
        self.position = position
        self.normalizedPosition = normalizedPosition
        self.rotation = rotation
        self.color = color
    }
}

// Domain層のAntennaPositionDataとRealWorldPositionを使用
