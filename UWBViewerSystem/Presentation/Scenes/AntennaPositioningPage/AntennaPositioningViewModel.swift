import SwiftUI
import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

@MainActor
class AntennaPositioningViewModel: ObservableObject {
    @Published var selectedDevices: [UWBDevice] = []
    @Published var antennaPositions: [AntennaPosition] = []
    @Published var canProceedValue: Bool = false
    
    #if os(macOS)
    var mapImage: NSImage?
    #elseif os(iOS)
    var mapImage: UIImage?
    #endif
    var mapData: IndoorMapData?
    
    private let colors: [Color] = [.red, .blue, .green, .orange, .purple, .pink, .cyan, .yellow]
    
    private func updateCanProceed() {
        let positionedAntennas = antennaPositions.filter { $0.position != CGPoint(x: 50, y: 50) }
        canProceedValue = positionedAntennas.count >= 3
    }
    
    func loadMapAndDevices() {
        loadSelectedDevices()
        loadMapData()
        createAntennaPositions()
    }
    
    private func loadSelectedDevices() {
        if let data = UserDefaults.standard.data(forKey: "SelectedUWBDevices"),
           let decoded = try? JSONDecoder().decode([UWBDevice].self, from: data) {
            selectedDevices = decoded
        }
    }
    
    private func loadMapData() {
        if let data = UserDefaults.standard.data(forKey: "CurrentIndoorMap"),
           let decoded = try? JSONDecoder().decode(IndoorMapData.self, from: data) {
            mapData = decoded
            #if os(macOS)
            mapImage = NSImage(contentsOfFile: decoded.filePath)
            #elseif os(iOS)
            if let data = try? Data(contentsOf: URL(fileURLWithPath: decoded.filePath)) {
                mapImage = UIImage(data: data)
            }
            #endif
        }
    }
    
    private func createAntennaPositions() {
        antennaPositions = selectedDevices.enumerated().map { index, device in
            AntennaPosition(
                id: device.id,
                deviceName: device.name,
                position: CGPoint(x: 50, y: 50), // デフォルト位置
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
    
    func getAntennaPosition(for deviceId: String) -> CGPoint? {
        return antennaPositions.first(where: { $0.id == deviceId })?.position
    }
    
    func isDevicePositioned(_ deviceId: String) -> Bool {
        if let position = getAntennaPosition(for: deviceId) {
            return position != CGPoint(x: 50, y: 50) // デフォルト位置以外に配置されているか
        }
        return false
    }
    
    func autoArrangeAntennas() {
        let canvasSize = CGSize(width: 400, height: 400) // マップキャンバスのサイズ
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
                CGPoint(x: availableWidth + margin, y: availableHeight + margin)
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
                CGPoint(x: availableWidth + margin, y: availableHeight + margin)
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
                deviceId: antenna.id,
                deviceName: antenna.deviceName,
                position: antenna.position,
                realWorldPosition: convertToRealWorldPosition(antenna.position)
            )
        }
        
        if let encoded = try? JSONEncoder().encode(positionData) {
            UserDefaults.standard.set(encoded, forKey: "AntennaPositions")
        }
    }
    
    private func convertToRealWorldPosition(_ screenPosition: CGPoint) -> RealWorldPosition {
        // マップの実際のサイズとスクリーン上のサイズの比率を計算
        guard let mapData = mapData else {
            return RealWorldPosition(x: Double(screenPosition.x), y: Double(screenPosition.y), z: 0)
        }
        
        let canvasSize = CGSize(width: 400, height: 400)
        let scaleX = mapData.realWidth / Double(canvasSize.width)
        let scaleY = mapData.realHeight / Double(canvasSize.height)
        
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
    let color: Color
}

struct AntennaPositionData: Codable {
    let deviceId: String
    let deviceName: String
    let position: CGPoint
    let realWorldPosition: RealWorldPosition
}

struct RealWorldPosition: Codable {
    let x: Double
    let y: Double
    let z: Double
}

