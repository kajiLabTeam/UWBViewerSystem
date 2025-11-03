import Foundation

// MARK: - UWB Connection Status

/// UWB接続状態
public enum UWBConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    public var displayText: String {
        switch self {
        case .disconnected:
            return "未接続"
        case .connecting:
            return "接続中"
        case .connected:
            return "接続済み"
        case .error(let message):
            return "エラー: \(message)"
        }
    }
}

// MARK: - Data Quality Evaluation

/// データ品質評価結果
public struct DataQualityEvaluation {
    public let isAcceptable: Bool
    public let qualityScore: Double
    public let issues: [String]
    public let recommendations: [String]

    public init(isAcceptable: Bool, qualityScore: Double, issues: [String], recommendations: [String]) {
        self.isAcceptable = isAcceptable
        self.qualityScore = qualityScore
        self.issues = issues
        self.recommendations = recommendations
    }
}

// MARK: - NLoS Detection Result

/// nLoS検出結果
public struct NLoSDetectionResult {
    public let isNLoSDetected: Bool
    public let lineOfSightPercentage: Double
    public let averageSignalStrength: Double
    public let recommendation: String

    public init(
        isNLoSDetected: Bool, lineOfSightPercentage: Double, averageSignalStrength: Double, recommendation: String
    ) {
        self.isNLoSDetected = isNLoSDetected
        self.lineOfSightPercentage = lineOfSightPercentage
        self.averageSignalStrength = averageSignalStrength
        self.recommendation = recommendation
    }
}
