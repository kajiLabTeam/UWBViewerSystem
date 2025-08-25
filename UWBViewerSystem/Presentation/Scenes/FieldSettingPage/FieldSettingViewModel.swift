import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - Data Models

enum AntennaColor: String, CaseIterable, Codable {
    case red = "red"
    case blue = "blue"
    case green = "green"
    case orange = "orange"
    case purple = "purple"
    case pink = "pink"
    case yellow = "yellow"
    case cyan = "cyan"
    
    var color: Color {
        switch self {
        case .red: return .red
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .pink: return .pink
        case .yellow: return .yellow
        case .cyan: return .cyan
        }
    }
}

struct AntennaInfo: Identifiable, Codable, Transferable {
    let id: String
    var name: String
    var coordinates: Point3D
    var antennaColor: AntennaColor
    var position: CGPoint
    
    var color: Color {
        antennaColor.color
    }
    
    init(id: String = UUID().uuidString, name: String, coordinates: Point3D, antennaColor: AntennaColor = .blue) {
        self.id = id
        self.name = name
        self.coordinates = coordinates
        self.antennaColor = antennaColor
        
        // Convert 3D coordinates to 2D position for display (normalized 0-1)
        self.position = CGPoint(
            x: coordinates.x / 10.0, // Assuming 10m field width
            y: coordinates.y / 10.0  // Assuming 10m field height
        )
    }
    
    // 後方互換性のため、Color を受け取る便利なinit
    init(id: String = UUID().uuidString, name: String, coordinates: Point3D, color: Color) {
        self.init(id: id, name: name, coordinates: coordinates, antennaColor: .blue) // デフォルトで青
    }
    
    // MARK: - Transferable
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .antennaInfo)
    }
}

extension UTType {
    static var antennaInfo: UTType {
        UTType(exportedAs: "com.uwbviewersystem.antennainfo")
    }
}

struct Point3D: Codable {
    var x: Double
    var y: Double
    var z: Double
}

// MARK: - ViewModel

@MainActor
class FieldSettingViewModel: ObservableObject {
    @Published var antennas: [AntennaInfo] = []
    @Published var fieldWidth: Double = 10.0 // meters
    @Published var fieldHeight: Double = 10.0 // meters
    
    private let navigationModel = NavigationRouterModel.shared
    
    init() {
        loadSavedConfiguration()
    }
    
    // MARK: - Antenna Management
    
    func addAntenna(_ antenna: AntennaInfo) {
        antennas.append(antenna)
        saveConfiguration()
    }
    
    func updateAntenna(_ updatedAntenna: AntennaInfo) {
        if let index = antennas.firstIndex(where: { $0.id == updatedAntenna.id }) {
            antennas[index] = updatedAntenna
            saveConfiguration()
        }
    }
    
    func removeAntenna(_ antenna: AntennaInfo) {
        antennas.removeAll { $0.id == antenna.id }
        saveConfiguration()
    }
    
    func updateAntennaPosition(_ antenna: AntennaInfo, position: CGPoint) {
        if let index = antennas.firstIndex(where: { $0.id == antenna.id }) {
            antennas[index].position = position
            // Update 3D coordinates based on new position
            antennas[index].coordinates = Point3D(
                x: position.x * fieldWidth,
                y: position.y * fieldHeight,
                z: antennas[index].coordinates.z
            )
            saveConfiguration()
        }
    }
    
    // MARK: - Field Management
    
    func resetField() {
        antennas.removeAll()
        saveConfiguration()
    }
    
    // MARK: - Configuration Persistence
    
    func saveConfiguration() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(antennas) {
            UserDefaults.standard.set(encoded, forKey: "FieldAntennaConfiguration")
        }
    }
    
    func loadConfiguration() {
        loadSavedConfiguration()
    }
    
    private func loadSavedConfiguration() {
        if let data = UserDefaults.standard.data(forKey: "FieldAntennaConfiguration") {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode([AntennaInfo].self, from: data) {
                antennas = decoded
            }
        }
    }
    
    // MARK: - Navigation
    
    func proceedToNextStep() {
        print("🚀 FieldSetting 次へボタンが押されました")
        print("🚀 navigationModel instance: \(ObjectIdentifier(navigationModel))")
        // Save configuration before navigating
        saveConfiguration()
        print("🚀 設定保存完了")
        // Navigate to pairing setting page
        print("🚀 pairingSettingPageに移動開始")
        navigationModel.push(.pairingSettingPage)
        print("🚀 push(.pairingSettingPage)実行完了")
    }
}

// MARK: - Color Codable Extension

extension Color: Codable {
    enum CodingKeys: String, CodingKey {
        case red, green, blue, opacity
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let red = try container.decode(Double.self, forKey: .red)
        let green = try container.decode(Double.self, forKey: .green)
        let blue = try container.decode(Double.self, forKey: .blue)
        let opacity = try container.decode(Double.self, forKey: .opacity)
        self.init(red: red, green: green, blue: blue, opacity: opacity)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Convert Color to NSColor to get RGB components
        let nsColor = NSColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        nsColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        try container.encode(Double(red), forKey: .red)
        try container.encode(Double(green), forKey: .green)
        try container.encode(Double(blue), forKey: .blue)
        try container.encode(Double(alpha), forKey: .opacity)
    }
}