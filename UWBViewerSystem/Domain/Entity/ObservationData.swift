import Foundation

// MARK: - 観測データ関連のエンティティ

/// UWBアンテナからの観測データ点
public struct ObservationPoint: Codable, Identifiable, Equatable {
    public let id: String
    public let antennaId: String
    public let position: Point3D
    public let timestamp: Date
    public let quality: SignalQuality
    public let distance: Double
    public let rssi: Double
    public let sessionId: String

    public init(
        id: String = UUID().uuidString,
        antennaId: String,
        position: Point3D,
        timestamp: Date = Date(),
        quality: SignalQuality,
        distance: Double,
        rssi: Double,
        sessionId: String
    ) {
        self.id = id
        self.antennaId = antennaId
        self.position = position
        self.timestamp = timestamp
        self.quality = quality
        self.distance = distance
        self.rssi = rssi
        self.sessionId = sessionId
    }
}

/// 信号品質の評価
public struct SignalQuality: Codable, Equatable {
    public let strength: Double  // 0.0-1.0
    public let isLineOfSight: Bool
    public let confidenceLevel: Double  // 0.0-1.0
    public let errorEstimate: Double  // メートル単位

    public init(
        strength: Double,
        isLineOfSight: Bool,
        confidenceLevel: Double,
        errorEstimate: Double
    ) {
        self.strength = max(0.0, min(1.0, strength))
        self.isLineOfSight = isLineOfSight
        self.confidenceLevel = max(0.0, min(1.0, confidenceLevel))
        self.errorEstimate = max(0.0, errorEstimate)
    }

    /// 品質レベルを文字列で表現
    public var qualityLevel: String {
        switch strength {
        case 0.8 ... 1.0:
            return "優秀"
        case 0.6 ..< 0.8:
            return "良好"
        case 0.4 ..< 0.6:
            return "普通"
        case 0.2 ..< 0.4:
            return "低"
        default:
            return "非常に低い"
        }
    }
}

/// 観測セッション情報
public struct ObservationSession: Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let startTime: Date
    public var endTime: Date?
    public let antennaId: String
    public let floorMapId: String?
    public var observations: [ObservationPoint]
    public var status: ObservationStatus

    public init(
        id: String = UUID().uuidString,
        name: String,
        startTime: Date = Date(),
        antennaId: String,
        floorMapId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.startTime = startTime
        endTime = nil
        self.antennaId = antennaId
        self.floorMapId = floorMapId
        observations = []
        status = .recording
    }

    /// セッションの継続時間
    public var duration: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }

    /// セッションの品質統計
    public var qualityStatistics: ObservationQualityStatistics {
        let validObservations = observations.filter { $0.quality.strength > 0.3 }
        let avgQuality =
            validObservations.isEmpty
            ? 0.0 : validObservations.map { $0.quality.strength }.reduce(0, +) / Double(validObservations.count)
        let losCount = observations.filter { $0.quality.isLineOfSight }.count
        let losPercentage = observations.isEmpty ? 0.0 : Double(losCount) / Double(observations.count) * 100.0

        return ObservationQualityStatistics(
            totalPoints: observations.count,
            validPoints: validObservations.count,
            averageQuality: avgQuality,
            lineOfSightPercentage: losPercentage,
            averageErrorEstimate: validObservations.isEmpty
                ? 0.0
                : validObservations.map { $0.quality.errorEstimate }.reduce(0, +) / Double(validObservations.count)
        )
    }
}

/// 観測セッションの状態
public enum ObservationStatus: String, Codable, CaseIterable {
    case recording = "recording"
    case paused = "paused"
    case completed = "completed"
    case failed = "failed"

    public var displayText: String {
        switch self {
        case .recording:
            return "記録中"
        case .paused:
            return "一時停止"
        case .completed:
            return "完了"
        case .failed:
            return "失敗"
        }
    }
}

/// 観測データの品質統計
public struct ObservationQualityStatistics: Codable, Equatable {
    public let totalPoints: Int
    public let validPoints: Int
    public let averageQuality: Double
    public let lineOfSightPercentage: Double
    public let averageErrorEstimate: Double

    public init(
        totalPoints: Int,
        validPoints: Int,
        averageQuality: Double,
        lineOfSightPercentage: Double,
        averageErrorEstimate: Double
    ) {
        self.totalPoints = totalPoints
        self.validPoints = validPoints
        self.averageQuality = averageQuality
        self.lineOfSightPercentage = lineOfSightPercentage
        self.averageErrorEstimate = averageErrorEstimate
    }

    /// データ品質の評価
    public var qualityAssessment: String {
        switch averageQuality {
        case 0.8 ... 1.0:
            return "優秀 - キャリブレーションに最適"
        case 0.6 ..< 0.8:
            return "良好 - キャリブレーション可能"
        case 0.4 ..< 0.6:
            return "普通 - 要注意"
        case 0.2 ..< 0.4:
            return "低品質 - 改善が必要"
        default:
            return "不適切 - データ収集をやり直してください"
        }
    }
}

/// 基準座標と観測データのマッピング
public struct ReferenceObservationMapping: Codable, Identifiable, Equatable {
    public let id: String
    public let referencePosition: Point3D
    public let observations: [ObservationPoint]
    public let timestamp: Date
    public let mappingQuality: Double

    public init(
        id: String = UUID().uuidString,
        referencePosition: Point3D,
        observations: [ObservationPoint],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.referencePosition = referencePosition
        self.observations = observations
        self.timestamp = timestamp

        // マッピング品質を計算（観測データの品質と一貫性から）
        if observations.isEmpty {
            mappingQuality = 0.0
        } else {
            let avgQuality = observations.map { $0.quality.strength }.reduce(0, +) / Double(observations.count)
            let positionVariance = calculatePositionVariance(observations.map { $0.position })
            mappingQuality = avgQuality * (1.0 - min(positionVariance / 10.0, 1.0))  // 10m以上の分散で品質0
        }
    }

    /// 観測データの重心座標
    public var centroidPosition: Point3D {
        guard !observations.isEmpty else {
            return Point3D(x: 0, y: 0, z: 0)
        }

        let totalX = observations.map { $0.position.x }.reduce(0, +)
        let totalY = observations.map { $0.position.y }.reduce(0, +)
        let totalZ = observations.map { $0.position.z }.reduce(0, +)
        let count = Double(observations.count)

        return Point3D(
            x: totalX / count,
            y: totalY / count,
            z: totalZ / count
        )
    }

    /// 基準座標との誤差
    public var positionError: Double {
        let centroid = centroidPosition
        return referencePosition.distance(to: centroid)
    }
}

// MARK: - Helper Functions

/// 位置データの分散を計算
private func calculatePositionVariance(_ positions: [Point3D]) -> Double {
    guard positions.count > 1 else { return 0.0 }

    let avgX = positions.map { $0.x }.reduce(0, +) / Double(positions.count)
    let avgY = positions.map { $0.y }.reduce(0, +) / Double(positions.count)
    let avgZ = positions.map { $0.z }.reduce(0, +) / Double(positions.count)

    let variance =
        positions.map { position in
            let dx = position.x - avgX
            let dy = position.y - avgY
            let dz = position.z - avgZ
            return dx * dx + dy * dy + dz * dz
        }.reduce(0, +) / Double(positions.count)

    return sqrt(variance)
}
