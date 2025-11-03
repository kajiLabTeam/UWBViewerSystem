import Combine
import Foundation

/// UWBデータ管理（モックとして実装）
///
/// UWBデバイスとの通信を管理し、観測データの収集を行うクラスです。
/// 現在はシミュレーションデータを生成していますが、実際のUWBデバイスとの通信に置き換え可能です。
@MainActor
public class UWBDataManager: ObservableObject {
    @Published public var connectionStatus: UWBConnectionStatus = .disconnected
    @Published public var latestObservation: ObservationPoint?

    private var activeSessions: Set<String> = []
    private var simulationTimer: Timer?

    public init() {}

    /// データ収集を開始
    /// - Parameters:
    ///   - antennaId: 対象アンテナID
    ///   - sessionId: セッションID
    public func startDataCollection(for antennaId: String, sessionId: String) async throws {
        self.activeSessions.insert(sessionId)
        self.connectionStatus = .connected

        // シミュレーション用タイマー開始
        self.startSimulation(for: antennaId, sessionId: sessionId)
        print("📡 UWBデータ収集開始: \(antennaId)")
    }

    /// データ収集を停止
    /// - Parameter sessionId: セッションID
    public func stopDataCollection(sessionId: String) async throws {
        self.activeSessions.remove(sessionId)
        if self.activeSessions.isEmpty {
            self.simulationTimer?.invalidate()
            self.simulationTimer = nil
        }
        print("📡 UWBデータ収集停止: \(sessionId)")
    }

    /// データ収集を一時停止
    /// - Parameter sessionId: セッションID
    public func pauseDataCollection(sessionId: String) async throws {
        // 実装は省略
    }

    /// データ収集を再開
    /// - Parameter sessionId: セッションID
    public func resumeDataCollection(sessionId: String) async throws {
        // 実装は省略
    }

    /// 最新の観測データを取得
    /// - Parameter sessionId: セッションID
    /// - Returns: 観測データの配列
    public func getLatestObservations(for sessionId: String) async -> [ObservationPoint] {
        // 実際の実装では、UWBデバイスから最新データを取得
        []
    }

    /// シミュレーションを開始
    /// - Parameters:
    ///   - antennaId: アンテナID
    ///   - sessionId: セッションID
    private func startSimulation(for antennaId: String, sessionId: String) {
        self.simulationTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.generateSimulatedObservation(antennaId: antennaId, sessionId: sessionId)
            }
        }
    }

    /// シミュレーション用の観測データを生成
    /// - Parameters:
    ///   - antennaId: アンテナID
    ///   - sessionId: セッションID
    private func generateSimulatedObservation(antennaId: String, sessionId: String) {
        let observation = ObservationPoint(
            antennaId: antennaId,
            position: Point3D(
                x: Double.random(in: -10...10),
                y: Double.random(in: -10...10),
                z: Double.random(in: 0...3)
            ),
            quality: SignalQuality(
                strength: Double.random(in: 0.3...1.0),
                isLineOfSight: Bool.random(),
                confidenceLevel: Double.random(in: 0.5...1.0),
                errorEstimate: Double.random(in: 0.1...2.0)
            ),
            distance: Double.random(in: 1...20),
            rssi: Double.random(in: -80...(-30)),
            sessionId: sessionId
        )

        self.latestObservation = observation
    }
}
