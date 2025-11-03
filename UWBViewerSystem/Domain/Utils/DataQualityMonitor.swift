import Foundation

/// データ品質監視
///
/// UWB観測データの品質を監視し、評価するクラスです。
/// 信号強度、RSSI、信頼度、誤差推定などの指標をチェックし、
/// データの品質を評価します。
public class DataQualityMonitor {
    private let qualityThreshold: Double = 0.5
    private let stabilityWindow: Int = 10

    public init() {}

    /// 観測データの品質を評価
    /// - Parameter observation: 観測データ点
    /// - Returns: 品質評価結果
    public func evaluate(_ observation: ObservationPoint) -> DataQualityEvaluation {
        var issues: [String] = []
        var isAcceptable = true

        // 信号強度チェック
        if observation.quality.strength < self.qualityThreshold {
            issues.append("信号強度が低い")
            isAcceptable = false
        }

        // RSSI チェック
        if observation.rssi < -75 {
            issues.append("RSSI値が低い")
        }

        // 信頼度チェック
        if observation.quality.confidenceLevel < 0.6 {
            issues.append("信頼度が低い")
            isAcceptable = false
        }

        // 誤差推定チェック
        if observation.quality.errorEstimate > 3.0 {
            issues.append("誤差推定値が大きい")
        }

        return DataQualityEvaluation(
            isAcceptable: isAcceptable,
            qualityScore: observation.quality.strength,
            issues: issues,
            recommendations: self.generateRecommendations(for: issues)
        )
    }

    /// nLoS（見通し線なし）状態の検出
    /// - Parameter observations: 観測データ配列
    /// - Returns: nLoS検出結果
    public func detectNLoS(_ observations: [ObservationPoint]) -> NLoSDetectionResult {
        let losCount = observations.filter { $0.quality.isLineOfSight }.count
        let losPercentage = observations.isEmpty ? 0.0 : Double(losCount) / Double(observations.count) * 100.0

        let isNLoSCondition = losPercentage < 50.0  // 見通し線が50%未満の場合
        let averageSignalStrength =
            observations.isEmpty
                ? 0.0 : observations.map { $0.quality.strength }.reduce(0, +) / Double(observations.count)

        return NLoSDetectionResult(
            isNLoSDetected: isNLoSCondition,
            lineOfSightPercentage: losPercentage,
            averageSignalStrength: averageSignalStrength,
            recommendation: isNLoSCondition ? "障害物を除去するか、アンテナ位置を調整してください" : "良好な測定環境です"
        )
    }

    /// 問題に応じた推奨事項を生成
    /// - Parameter issues: 検出された問題のリスト
    /// - Returns: 推奨事項のリスト
    private func generateRecommendations(for issues: [String]) -> [String] {
        var recommendations: [String] = []

        if issues.contains("信号強度が低い") {
            recommendations.append("アンテナ間の距離を短くしてください")
            recommendations.append("障害物を除去してください")
        }

        if issues.contains("RSSI値が低い") {
            recommendations.append("アンテナの向きを調整してください")
        }

        if issues.contains("信頼度が低い") {
            recommendations.append("測定環境を安定化してください")
        }

        return recommendations
    }
}
