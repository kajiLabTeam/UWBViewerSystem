import Foundation

// MARK: - Connection Management Protocol

/// 接続管理機能のインターフェース
/// RealtimeDataUsecaseからの依存を抽象化するために使用
@MainActor
public protocol ConnectionManagementProtocol: AnyObject {
    func sendMessage(_ content: String)
    func sendMessageToDevice(_ content: String, to endpointId: String)
    func hasConnectedDevices() -> Bool
    func getConnectedDeviceCount() -> Int
}

// MARK: - Realtime Data Handler Protocol

/// リアルタイムデータ処理のインターフェース
/// ConnectionManagementUsecaseからの依存を抽象化するために使用
@MainActor
public protocol RealtimeDataHandlerProtocol: AnyObject {
    func processRealtimeDataMessage(_ json: [String: Any], fromEndpointId: String)
    func addConnectedDevice(_ deviceName: String)
    func removeDisconnectedDevice(_ deviceName: String)
}

// MARK: - Realtime Data Persistence Protocol

/// リアルタイムデータ永続化のインターフェース
/// SensingControlUsecaseからの依存を抽象化するために使用
@MainActor
public protocol RealtimeDataPersistenceProtocol: AnyObject {
    func saveRealtimeData(_ data: RealtimeData) async
}
