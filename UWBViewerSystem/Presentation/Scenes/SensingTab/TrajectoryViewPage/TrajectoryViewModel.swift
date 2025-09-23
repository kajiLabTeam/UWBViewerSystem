import Combine
import Foundation
import SwiftUI

#if os(macOS)
    import AppKit
#elseif os(iOS)
    import UIKit
#endif

@MainActor
class TrajectoryViewModel: ObservableObject {
    @Published var availableSessions: [SensingSession] = []
    @Published var selectedSession: SensingSession?
    @Published var trajectoryPoints: [TrajectoryPoint] = []
    @Published var antennaPositions: [AntennaVisualization] = []
    #if os(macOS)
        @Published var mapImage: NSImage?
    #elseif os(iOS)
        @Published var mapImage: UIImage?
    #endif
    @Published var currentPosition: CGPoint?
    @Published var selectedDataPoint: TrajectoryPoint?

    // Playback controls
    @Published var isPlaying = false
    @Published var currentTimeIndex: Double = 0
    @Published var playbackSpeed: Double = 1.0

    // Display settings
    @Published var showTrajectory = true
    @Published var showAntennas = true
    @Published var showDataPoints = false
    @Published var trajectoryColor = Color.blue

    // Filtering
    @Published var minAccuracy: Double = 0.0
    @Published var startTimeFilter = Date()
    @Published var endTimeFilter = Date()

    // Analysis data
    @Published var totalDistance: Double = 0
    @Published var averageSpeed: Double = 0
    @Published var maxSpeed: Double = 0

    private var playbackTimer: Timer?
    // mapData: IndoorMapDataは現在利用できないため、一時的にコメントアウト
    // private var mapData: IndoorMapData?
    private var allTrajectoryPoints: [TrajectoryPoint] = []  // フィルタリング前の全データ
    private let preferenceRepository: PreferenceRepositoryProtocol

    init(preferenceRepository: PreferenceRepositoryProtocol = PreferenceRepository()) {
        self.preferenceRepository = preferenceRepository
        loadInitialData()
    }

    private func loadInitialData() {
        loadAvailableSessions()
        loadAntennaPositions()
    }

    var hasTrajectoryData: Bool {
        !trajectoryPoints.isEmpty
    }

    var currentTimeString: String {
        guard hasTrajectoryData, currentTimeIndex < Double(trajectoryPoints.count) else {
            return "00:00:00"
        }

        let point = trajectoryPoints[Int(currentTimeIndex)]
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: point.timestamp)
    }

    var totalTimeString: String {
        guard let lastPoint = trajectoryPoints.last,
            let firstPoint = trajectoryPoints.first
        else {
            return "00:00:00"
        }

        let duration = lastPoint.timestamp.timeIntervalSince(firstPoint.timestamp)
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60

        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    func initialize() {
        loadAvailableSessions()
        loadMapData()
        loadAntennaPositions()

        // 最新のセッションを自動選択
        if let latestSession = availableSessions.first {
            selectSession(latestSession)
        }
    }

    private func loadAvailableSessions() {
        if let sessions = preferenceRepository.getData([SensingSession].self, forKey: "RecentSensingSessions") {
            availableSessions = sessions
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

    private func loadAntennaPositions() {
        if let positions = preferenceRepository.getData([AntennaPositionData].self, forKey: "AntennaPositions") {

            let colors: [Color] = [.red, .blue, .green, .orange, .purple, .pink]

            antennaPositions = positions.enumerated().map { index, position in
                AntennaVisualization(
                    id: position.antennaId,
                    name: position.antennaName,
                    screenPosition: convertToScreenPosition(
                        RealWorldPosition(x: position.position.x, y: position.position.y, z: position.position.z)),
                    color: colors[index % colors.count]
                )
            }
        }
    }

    func selectSession(_ session: SensingSession) {
        selectedSession = session
        loadTrajectoryData(for: session)
    }

    private func loadTrajectoryData(for session: SensingSession) {
        // 実際の実装では保存されたセンシングデータを読み込み
        // ここではモックデータを生成
        generateMockTrajectoryData()
        applyFilters()
        calculateAnalytics()

        // 再生位置をリセット
        currentTimeIndex = 0
        updateCurrentPosition()
    }

    private func generateMockTrajectoryData() {
        let startTime = Date()
        var points: [TrajectoryPoint] = []

        // サンプル軌跡データを生成
        let pathPoints = [
            RealWorldPosition(x: 2.0, y: 2.0, z: 0),
            RealWorldPosition(x: 3.5, y: 2.5, z: 0),
            RealWorldPosition(x: 5.0, y: 4.0, z: 0),
            RealWorldPosition(x: 6.5, y: 5.5, z: 0),
            RealWorldPosition(x: 8.0, y: 6.0, z: 0),
            RealWorldPosition(x: 9.0, y: 7.5, z: 0),
            RealWorldPosition(x: 8.5, y: 9.0, z: 0),
            RealWorldPosition(x: 7.0, y: 10.0, z: 0),
            RealWorldPosition(x: 5.5, y: 9.5, z: 0),
            RealWorldPosition(x: 4.0, y: 8.0, z: 0),
            RealWorldPosition(x: 3.0, y: 6.5, z: 0),
            RealWorldPosition(x: 2.5, y: 4.5, z: 0),
            RealWorldPosition(x: 2.0, y: 2.0, z: 0),
        ]

        for (index, position) in pathPoints.enumerated() {
            let timestamp = startTime.addingTimeInterval(Double(index * 5))  // 5秒間隔
            let accuracy = Double.random(in: 0.7 ... 0.95)  // 70-95%の精度

            let point = TrajectoryPoint(
                id: UUID().uuidString,
                timestamp: timestamp,
                position: position,
                screenPosition: convertToScreenPosition(position),
                accuracy: accuracy,
                speed: index > 0
                    ? calculateSpeed(
                        from: pathPoints[index - 1],
                        to: position,
                        timeInterval: 5.0
                    ) : 0
            )

            points.append(point)
        }

        allTrajectoryPoints = points
    }

    private func calculateSpeed(from: RealWorldPosition, to: RealWorldPosition, timeInterval: Double) -> Double {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let distance = sqrt(dx * dx + dy * dy)
        return distance / timeInterval
    }

    private func convertToScreenPosition(_ realPosition: RealWorldPosition) -> CGPoint {
        // PreferenceRepositoryからフロアマップ情報を取得
        guard let floorMapInfo = preferenceRepository.loadCurrentFloorMapInfo() else {
            return CGPoint(x: 50, y: 50)
        }

        let canvasSize = CGSize(width: 500, height: 500)  // マップキャンバスのサイズ
        let scaleX = Double(canvasSize.width) / floorMapInfo.width
        let scaleY = Double(canvasSize.height) / floorMapInfo.depth

        let screenX = realPosition.x * scaleX
        let screenY = realPosition.y * scaleY

        return CGPoint(x: screenX, y: screenY)
    }

    private func applyFilters() {
        trajectoryPoints = allTrajectoryPoints.filter { point in
            point.accuracy >= minAccuracy && point.timestamp >= startTimeFilter && point.timestamp <= endTimeFilter
        }
    }

    private func calculateAnalytics() {
        guard !trajectoryPoints.isEmpty else {
            totalDistance = 0
            averageSpeed = 0
            maxSpeed = 0
            return
        }

        // 総移動距離を計算
        totalDistance = 0
        for i in 1 ..< trajectoryPoints.count {
            let prev = trajectoryPoints[i - 1]
            let curr = trajectoryPoints[i]

            let dx = curr.position.x - prev.position.x
            let dy = curr.position.y - prev.position.y
            let distance = sqrt(dx * dx + dy * dy)

            totalDistance += distance
        }

        // 平均速度と最大速度を計算
        let speeds = trajectoryPoints.map { $0.speed }
        averageSpeed = speeds.reduce(0, +) / Double(speeds.count)
        maxSpeed = speeds.max() ?? 0
    }

    func startPlayback() {
        guard hasTrajectoryData else { return }

        isPlaying = true

        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1 / playbackSpeed, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePlayback()
            }
        }
    }

    func pausePlayback() {
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    func stopPlayback() {
        isPlaying = false
        currentTimeIndex = 0
        playbackTimer?.invalidate()
        playbackTimer = nil
        updateCurrentPosition()
    }

    private func updatePlayback() {
        guard hasTrajectoryData else { return }

        currentTimeIndex += 1

        if currentTimeIndex >= Double(trajectoryPoints.count) {
            stopPlayback()
            return
        }

        updateCurrentPosition()
    }

    private func updateCurrentPosition() {
        guard hasTrajectoryData,
            currentTimeIndex < Double(trajectoryPoints.count)
        else {
            currentPosition = nil
            return
        }

        let index = Int(currentTimeIndex)
        currentPosition = trajectoryPoints[index].screenPosition
    }

    func handleMapTap(at location: CGPoint) {
        guard hasTrajectoryData else { return }

        // タップ位置に最も近いデータポイントを見つける
        var closestPoint: TrajectoryPoint?
        var closestDistance: Double = Double.infinity

        for point in trajectoryPoints {
            let dx = point.screenPosition.x - location.x
            let dy = point.screenPosition.y - location.y
            let distance = sqrt(dx * dx + dy * dy)

            if distance < closestDistance && distance < 20 {  // 20px以内
                closestDistance = distance
                closestPoint = point
            }
        }

        selectedDataPoint = closestPoint
    }

    func resetView() {
        selectedDataPoint = nil
        stopPlayback()
        currentTimeIndex = 0
        updateCurrentPosition()
    }

    func exportTrajectoryData() {
        guard let selectedSession else { return }

        #if os(macOS)
            let panel = NSSavePanel()
            panel.title = "軌跡データをエクスポート"
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "\(selectedSession.name)_trajectory.csv"

            if panel.runModal() == .OK, let url = panel.url {
                let csvContent = generateCSVContent()
                try? csvContent.write(to: url, atomically: true, encoding: .utf8)
            }
        #elseif os(iOS)
            // iOSでは Documents ディレクトリに保存
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileName = "\(selectedSession.name)_trajectory.csv"
            let url = documentsPath.appendingPathComponent(fileName)

            let csvContent = generateCSVContent()
            try? csvContent.write(to: url, atomically: true, encoding: .utf8)

            // 保存完了をユーザーに通知（実際にはViewで通知を表示）
            print("軌跡データを保存しました: \(url.path)")
        #endif
    }

    private func generateCSVContent() -> String {
        var csv = "Timestamp,X,Y,Z,Accuracy,Speed\n"

        for point in trajectoryPoints {
            let timestamp = ISO8601DateFormatter().string(from: point.timestamp)
            csv +=
                "\(timestamp),\(point.position.x),\(point.position.y),\(point.position.z),\(point.accuracy),\(point.speed)\n"
        }

        return csv
    }
}

// MARK: - Data Models

struct TrajectoryPoint: Identifiable {
    let id: String
    let timestamp: Date
    let position: RealWorldPosition
    let screenPosition: CGPoint
    let accuracy: Double
    let speed: Double
}

struct AntennaVisualization: Identifiable {
    let id: String
    let name: String
    let screenPosition: CGPoint
    let color: Color
}
