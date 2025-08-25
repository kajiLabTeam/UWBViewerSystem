import SwiftUI
import Foundation
import Combine

@MainActor
class DeviceSelectionViewModel: ObservableObject {
    @Published var availableDevices: [UWBDevice] = []
    @Published var selectedDevices: Set<String> = []
    @Published var isScanning = false
    
    private var homeViewModel = HomeViewModel.shared
    private var cancellables = Set<AnyCancellable>()
    
    var canProceed: Bool {
        selectedDevices.count >= 3
    }
    
    init() {
        setupObservers()
    }
    
    private func setupObservers() {
        // HomeViewModelからのデバイス情報を監視（モック実装）
        // 実際の実装では HomeViewModel からの実際のデバイス情報を使用
        availableDevices = []
    }
    
    func startScanning() {
        isScanning = true
        homeViewModel.startAdvertising()
        
        // モックデータを追加（実際の実装では削除）
        addMockDevices()
        
        // 10秒後にスキャンを停止
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.isScanning = false
        }
    }
    
    func stopScanning() {
        isScanning = false
        homeViewModel.stopAdvertising()
    }
    
    func toggleDeviceSelection(_ deviceId: String) {
        if selectedDevices.contains(deviceId) {
            selectedDevices.remove(deviceId)
        } else {
            selectedDevices.insert(deviceId)
        }
    }
    
    func getSelectedDevices() -> [UWBDevice] {
        return availableDevices.filter { selectedDevices.contains($0.id) }
    }
    
    func saveSelectedDevices() {
        let selectedDeviceData = getSelectedDevices()
        if let encoded = try? JSONEncoder().encode(selectedDeviceData) {
            UserDefaults.standard.set(encoded, forKey: "SelectedUWBDevices")
        }
    }
    
    // MARK: - Mock Data (実際の実装では削除)
    private func addMockDevices() {
        let mockDevices = [
            UWBDevice(
                id: "device_001",
                name: "UWBアンテナ #1",
                identifier: "AA:BB:CC:DD:EE:01",
                rssi: -45,
                connectionStatus: .connected
            ),
            UWBDevice(
                id: "device_002",
                name: "UWBアンテナ #2",
                identifier: "AA:BB:CC:DD:EE:02",
                rssi: -52,
                connectionStatus: .connected
            ),
            UWBDevice(
                id: "device_003",
                name: "UWBアンテナ #3",
                identifier: "AA:BB:CC:DD:EE:03",
                rssi: -48,
                connectionStatus: .connecting
            ),
            UWBDevice(
                id: "device_004",
                name: "UWBアンテナ #4",
                identifier: "AA:BB:CC:DD:EE:04",
                rssi: -55,
                connectionStatus: .disconnected
            ),
            UWBDevice(
                id: "device_005",
                name: "UWBアンテナ #5",
                identifier: "AA:BB:CC:DD:EE:05",
                rssi: -41,
                connectionStatus: .connected
            )
        ]
        
        availableDevices = mockDevices
    }
}

// MARK: - Data Models
struct UWBDevice: Identifiable, Codable {
    let id: String
    let name: String
    let identifier: String
    let rssi: Int
    let connectionStatus: ConnectionStatus
}

enum ConnectionStatus: String, Codable, CaseIterable {
    case connected = "connected"
    case connecting = "connecting"
    case disconnected = "disconnected"
    
    var displayName: String {
        switch self {
        case .connected:
            return "接続済み"
        case .connecting:
            return "接続中"
        case .disconnected:
            return "未接続"
        }
    }
    
    var color: Color {
        switch self {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return .red
        }
    }
}