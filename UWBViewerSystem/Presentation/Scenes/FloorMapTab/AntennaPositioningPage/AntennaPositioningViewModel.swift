import Foundation
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

    private let colors: [Color] = [.red, .blue, .green, .orange, .purple, .pink, .cyan, .yellow]

    private func updateCanProceed() {
        let positionedAntennas = antennaPositions.filter { $0.position != CGPoint(x: 50, y: 50) }
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
        if let data = UserDefaults.standard.data(forKey: "SelectedUWBDevices"),
           let decoded = try? JSONDecoder().decode([AndroidDevice].self, from: data)
        {
            selectedDevices = decoded
        }
    }

    private func loadMapData() {
        // IndoorMapDataは現在利用できないため、一時的にコメントアウト
        /*
         if let data = UserDefaults.standard.data(forKey: "CurrentIndoorMap"),
             let decoded = try? JSONDecoder().decode(IndoorMapData.self, from: data)
         {
             mapData = decoded
             #if os(macOS)
                 mapImage = NSImage(contentsOfFile: decoded.filePath)
             #elseif os(iOS)
                 if let data = try? Data(contentsOf: URL(fileURLWithPath: decoded.filePath)) {
                     mapImage = UIImage(data: data)
                 }
             #endif
         }
         */
    }

    private func createAntennaPositions() {
        antennaPositions = selectedDevices.enumerated().map { index, device in
            AntennaPosition(
                id: device.id,
                deviceName: device.name,
                position: CGPoint(x: 50, y: 50),  // デフォルト位置
                rotation: 0.0,
                color: colors[index % colors.count]
            )
        }
        updateCanProceed()
    }

    func updateAntennaPosition(_ antennaId: String, position: CGPoint) {
        if let index = antennaPositions.firstIndex(where: { $0.id == antennaId }) {
            antennaPositions[index].position = position
            updateCanProceed()
        }
    }

    func updateAntennaRotation(_ antennaId: String, rotation: Double) {
        if let index = antennaPositions.firstIndex(where: { $0.id == antennaId }) {
            antennaPositions[index].rotation = rotation
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
        let canvasSize = CGSize(width: 400, height: 400)  // マップキャンバスのサイズ
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
                antennaPositions[index].position = CGPoint(x: x, y: y)
            }
        }
        updateCanProceed()
    }

    func resetPositions() {
        for index in antennaPositions.indices {
            antennaPositions[index].position = CGPoint(x: 50, y: 50)
        }
        updateCanProceed()
    }

    func saveAntennaPositions() {
        let positionData = antennaPositions.map { antenna in
            AntennaPositionData(
                antennaId: antenna.id,
                antennaName: antenna.deviceName,
                position: Point3D(x: antenna.position.x, y: antenna.position.y, z: 0.0),
                rotation: antenna.rotation
            )
        }

        if let encoded = try? JSONEncoder().encode(positionData) {
            UserDefaults.standard.set(encoded, forKey: "configuredAntennaPositions")
            print("💾 アンテナ位置データを保存しました: \(positionData.count)台")
        }
    }

    func saveAntennaPositionsForFlow() -> Bool {
        // 配置されたアンテナの数をチェック
        let positionedAntennas = antennaPositions.filter { $0.position != CGPoint(x: 50, y: 50) }
        guard positionedAntennas.count >= 2 else {
            return false
        }

        // 回転角度が設定されているかチェック（必須ではないが、推奨）
        let _ = positionedAntennas.filter { $0.rotation != 0.0 }

        // データを保存
        saveAntennaPositions()

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
}

// MARK: - Data Models

struct AntennaPosition: Identifiable {
    let id: String
    let deviceName: String
    var position: CGPoint
    var rotation: Double = 0.0
    let color: Color
}

// Domain層のAntennaPositionDataとRealWorldPositionを使用
