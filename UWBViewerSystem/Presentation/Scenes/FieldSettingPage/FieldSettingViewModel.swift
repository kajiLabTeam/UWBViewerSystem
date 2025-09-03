import Combine
import SwiftUI
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

// FieldSetting固有のAntennaInfo拡張
struct FieldAntennaInfo: Identifiable, Codable, Transferable {
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
            x: coordinates.x / 10.0,  // Assuming 10m field width
            y: coordinates.y / 10.0  // Assuming 10m field height
        )
    }

    // 後方互換性のため、Color を受け取る便利なinit
    init(id: String = UUID().uuidString, name: String, coordinates: Point3D, color: Color) {
        self.init(id: id, name: name, coordinates: coordinates, antennaColor: .blue)  // デフォルトで青
    }

    // Domain層のAntennaInfoから変換
    init(from domainEntity: AntennaInfo, antennaColor: AntennaColor = .blue) {
        self.id = domainEntity.id
        self.name = domainEntity.name
        self.coordinates = domainEntity.coordinates
        self.antennaColor = antennaColor
        self.position = CGPoint(
            x: domainEntity.coordinates.x / 10.0,
            y: domainEntity.coordinates.y / 10.0
        )
    }

    // Domain層のAntennaInfoに変換
    func toDomainEntity() -> AntennaInfo {
        return AntennaInfo(
            id: id,
            name: name,
            coordinates: coordinates
        )
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

// MARK: - ViewModel

@MainActor
class FieldSettingViewModel: ObservableObject {
    @Published var antennas: [FieldAntennaInfo] = []
    @Published var fieldWidth: Double = 10.0  // meters
    @Published var fieldHeight: Double = 10.0  // meters

    private let navigationModel = NavigationRouterModel.shared
    private let dataRepository: DataRepositoryProtocol

    init(dataRepository: DataRepositoryProtocol = DataRepository()) {
        self.dataRepository = dataRepository
        loadSavedConfiguration()
    }

    // MARK: - Antenna Management

    func addAntenna(_ antenna: FieldAntennaInfo) {
        antennas.append(antenna)
        saveConfiguration()
    }

    func updateAntenna(_ updatedAntenna: FieldAntennaInfo) {
        if let index = antennas.firstIndex(where: { $0.id == updatedAntenna.id }) {
            antennas[index] = updatedAntenna
            saveConfiguration()
        }
    }

    func removeAntenna(_ antenna: FieldAntennaInfo) {
        antennas.removeAll { $0.id == antenna.id }
        saveConfiguration()
    }

    func updateAntennaPosition(_ antenna: FieldAntennaInfo, position: CGPoint) {
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
        let domainAntennas = antennas.map { $0.toDomainEntity() }
        dataRepository.saveFieldAntennaConfiguration(domainAntennas)
    }

    func loadConfiguration() {
        loadSavedConfiguration()
    }

    private func loadSavedConfiguration() {
        if let savedAntennas = dataRepository.loadFieldAntennaConfiguration() {
            antennas = savedAntennas.map { FieldAntennaInfo(from: $0) }
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

        // Convert Color to UIColor to get RGB components
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        try container.encode(Double(red), forKey: .red)
        try container.encode(Double(green), forKey: .green)
        try container.encode(Double(blue), forKey: .blue)
        try container.encode(Double(alpha), forKey: .opacity)
    }
}
