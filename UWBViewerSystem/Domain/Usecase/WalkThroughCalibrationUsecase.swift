//
//  WalkThroughCalibrationUsecase.swift
//  UWBViewerSystem
//
//  Walk-throughキャリブレーション管理
//  IMU（歩行軌跡）とUWB観測データを組み合わせてアンテナキャリブレーションを実行
//

import Combine
import Foundation
import SwiftData

/// Walk-throughキャリブレーションUsecase
///
/// # 概要
/// ユーザーがiPadを持って空間内を歩くだけで、アンテナの位置と角度を自動推定します。
/// CoreMotionのIMUデータからPDR（Pedestrian Dead Reckoning）で歩行軌跡を推定し、
/// UWB観測データと時刻同期してアフィン変換を計算します。
///
/// # キャリブレーションフロー
/// 1. Walk-through開始: IMU記録とUWB観測を同時に開始
/// 2. ユーザーが空間内を歩行（30秒〜1分推奨）
/// 3. Walk-through終了: データ収集停止
/// 4. PDRで歩行軌跡を推定
/// 5. IMU軌跡とUWB観測を時刻同期でマッチング
/// 6. マッチングされた対応点からアフィン変換を推定
/// 7. 結果をSwiftDataに保存
actor WalkThroughCalibrationUsecase {

    // MARK: - Dependencies

    private let swiftDataRepository: SwiftDataRepository
    private let pdrAlgorithm: PedestrianDeadReckoning
    private let affineCalibration: AntennaAffineCalibration
    private let dataProcessor: SensorDataProcessor

    // MARK: - State

    /// キャリブレーション中かどうか
    private var isCalibrating: Bool = false

    /// Walk-through開始時刻
    private var walkStartTime: Date?

    /// 収集されたUWB観測データ
    private var uwbObservations: [TimestampedUWBObservation] = []

    /// IMU記録結果
    private var imuRecordingResult: IMURecordingResult?

    /// PDR軌跡
    private var pdrTrajectory: PedestrianDeadReckoning.PDRResult?

    // MARK: - Types

    /// タイムスタンプ付きUWB観測データ
    struct TimestampedUWBObservation: Sendable {
        let timestamp: Date
        let antennaId: String
        let position: Point3D
        let quality: SignalQuality

        init(
            timestamp: Date,
            antennaId: String,
            position: Point3D,
            quality: SignalQuality
        ) {
            self.timestamp = timestamp
            self.antennaId = antennaId
            self.position = position
            self.quality = quality
        }
    }

    /// Walk-throughキャリブレーション結果
    struct WalkThroughCalibrationResult: Sendable {
        let antennaConfigs: [String: AntennaAffineCalibration.AntennaConfig]
        let trajectoryLength: Double
        let stepCount: Int
        let matchedPointCount: Int
        let duration: TimeInterval
        let rmse: Double
        let warnings: [String]
        let success: Bool

        init(
            antennaConfigs: [String: AntennaAffineCalibration.AntennaConfig],
            trajectoryLength: Double,
            stepCount: Int,
            matchedPointCount: Int,
            duration: TimeInterval,
            rmse: Double,
            warnings: [String],
            success: Bool
        ) {
            self.antennaConfigs = antennaConfigs
            self.trajectoryLength = trajectoryLength
            self.stepCount = stepCount
            self.matchedPointCount = matchedPointCount
            self.duration = duration
            self.rmse = rmse
            self.warnings = warnings
            self.success = success
        }
    }

    // MARK: - Configuration

    /// Walk-throughキャリブレーション設定
    struct Config: Sendable {
        /// 時刻同期の最大許容差（秒）
        let maxTimeDelta: TimeInterval

        /// 最小マッチング点数
        let minMatchedPoints: Int

        /// PDR設定
        let pdrConfig: PedestrianDeadReckoning.Config

        /// データ前処理設定
        let processingConfig: SensorDataProcessingConfig

        init(
            maxTimeDelta: TimeInterval = 1.0,  // 0.1から1.0秒に増加（デバッグ用）
            minMatchedPoints: Int = 10,
            pdrConfig: PedestrianDeadReckoning.Config = .walkThrough,
            processingConfig: SensorDataProcessingConfig = .default
        ) {
            self.maxTimeDelta = maxTimeDelta
            self.minMatchedPoints = minMatchedPoints
            self.pdrConfig = pdrConfig
            self.processingConfig = processingConfig
        }

        static let `default` = Config()
    }

    private let config: Config

    // MARK: - Initialization

    init(
        swiftDataRepository: SwiftDataRepository,
        config: Config = .default
    ) {
        self.swiftDataRepository = swiftDataRepository
        self.config = config
        self.pdrAlgorithm = PedestrianDeadReckoning(config: config.pdrConfig)
        self.affineCalibration = AntennaAffineCalibration()
        self.dataProcessor = SensorDataProcessor(config: config.processingConfig)
    }

    // MARK: - Public Methods

    /// Walk-throughキャリブレーションを開始
    ///
    /// - Note: この後、`addUWBObservation()`でUWBデータを追加し続ける必要があります
    func startWalkThrough() {
        guard !self.isCalibrating else {
            print("⚠️ 既にキャリブレーション中です")
            return
        }

        self.isCalibrating = true
        self.walkStartTime = Date()
        self.uwbObservations.removeAll()
        self.imuRecordingResult = nil
        self.pdrTrajectory = nil

        print("🚶 Walk-throughキャリブレーション開始")
    }

    /// UWB観測データを追加（リアルタイムで呼ばれる）
    ///
    /// - Parameters:
    ///   - antennaId: アンテナID
    ///   - position: 観測座標
    ///   - quality: 信号品質
    ///   - timestamp: タイムスタンプ
    func addUWBObservation(
        antennaId: String,
        position: Point3D,
        quality: SignalQuality,
        timestamp: Date = Date()
    ) {
        guard self.isCalibrating else { return }

        let observation = TimestampedUWBObservation(
            timestamp: timestamp,
            antennaId: antennaId,
            position: position,
            quality: quality
        )
        self.uwbObservations.append(observation)
    }

    /// Walk-throughキャリブレーションを終了し、結果を計算
    ///
    /// - Parameter imuResult: CoreMotionManagerから取得したIMU記録結果
    /// - Returns: キャリブレーション結果
    func stopWalkThrough(imuResult: IMURecordingResult) async throws -> WalkThroughCalibrationResult {
        guard self.isCalibrating else {
            throw WalkThroughError.notCalibrating
        }

        self.isCalibrating = false
        self.imuRecordingResult = imuResult

        let duration = self.walkStartTime.map { Date().timeIntervalSince($0) } ?? 0

        print("""
        🛑 Walk-through終了
           経過時間: \(String(format: "%.1f", duration))秒
           IMUサンプル数: \(imuResult.sampleCount)
           UWB観測数: \(self.uwbObservations.count)
        """)

        // 1. PDRで軌跡を推定
        let pdrResult = self.pdrAlgorithm.estimateTrajectory(from: imuResult.dataPoints)
        self.pdrTrajectory = pdrResult

        print("""
        📍 PDR軌跡推定完了
           歩数: \(pdrResult.stepCount)
           移動距離: \(String(format: "%.2f", pdrResult.totalDistance))m
           軌跡点数: \(pdrResult.trajectoryPoints.count)
        """)

        // 1.5. 軌跡を0.1秒間隔でリサンプリング（UWB観測とのマッチング精度向上）
        let resampledTrajectory = self.pdrAlgorithm.resampleTrajectory(
            pdrResult.trajectoryPoints,
            interval: 0.1  // 100ms間隔
        )

        print("📊 リサンプリング後の軌跡点数: \(resampledTrajectory.count)")

        // デバッグ: タイムスタンプ範囲を出力
        if let firstTrajectory = resampledTrajectory.first,
           let lastTrajectory = resampledTrajectory.last
        {
            print("""
            📊 軌跡タイムスタンプ範囲:
               開始: \(firstTrajectory.timestamp)
               終了: \(lastTrajectory.timestamp)
            """)
        }
        if let firstUWB = self.uwbObservations.first, let lastUWB = self.uwbObservations.last {
            print("""
            📊 UWBタイムスタンプ範囲:
               開始: \(firstUWB.timestamp)
               終了: \(lastUWB.timestamp)
            """)
        }

        // 2. 時刻同期マッチング（リサンプリングした軌跡を使用）
        let matchedPoints = self.matchTrajectoryWithUWB(
            trajectory: resampledTrajectory,
            uwbData: self.uwbObservations
        )

        print("🔗 時刻同期マッチング: \(matchedPoints.count)点（許容誤差: \(self.config.maxTimeDelta)秒）")

        // 3. キャリブレーション実行
        return try self.performCalibration(
            matchedPoints: matchedPoints,
            pdrResult: pdrResult,
            duration: duration
        )
    }

    /// 現在のUWB観測数を取得
    func getCurrentUWBObservationCount() -> Int {
        self.uwbObservations.count
    }

    /// データをクリア
    func clearData() {
        self.uwbObservations.removeAll()
        self.imuRecordingResult = nil
        self.pdrTrajectory = nil
        self.isCalibrating = false
        self.walkStartTime = nil
        print("🧹 Walk-throughデータをクリアしました")
    }

    /// キャリブレーション結果をSwiftDataに保存
    ///
    /// - Parameters:
    ///   - floorMapId: フロアマップID
    ///   - results: キャリブレーション結果
    func saveCalibrationResults(
        floorMapId: String,
        results: [String: AntennaAffineCalibration.AntennaConfig]
    ) async throws {
        for (antennaId, config) in results {
            let existingPositions = try await self.swiftDataRepository.loadAntennaPositions(
                for: floorMapId
            )

            if let existing = existingPositions.first(where: { $0.antennaId == antennaId }) {
                // 更新
                let updatedPosition = AntennaPositionData(
                    id: existing.id,
                    antennaId: antennaId,
                    antennaName: existing.antennaName,
                    position: config.position,
                    rotation: config.angleDegrees,
                    floorMapId: floorMapId
                )
                try await self.swiftDataRepository.updateAntennaPosition(updatedPosition)
                print("♻️  \(antennaId) の位置を更新しました")
            } else {
                // 新規作成
                let antennaPosition = AntennaPositionData(
                    id: UUID().uuidString,
                    antennaId: antennaId,
                    antennaName: antennaId,
                    position: config.position,
                    rotation: config.angleDegrees,
                    floorMapId: floorMapId
                )
                try await self.swiftDataRepository.saveAntennaPosition(antennaPosition)
                print("➕ \(antennaId) の位置を新規作成しました")
            }
        }

        print("💾 Walk-throughキャリブレーション結果を保存しました")
    }

    // MARK: - Private Methods

    /// IMU軌跡とUWB観測の時刻同期マッチング
    private func matchTrajectoryWithUWB(
        trajectory: [PedestrianDeadReckoning.TrajectoryPoint],
        uwbData: [TimestampedUWBObservation]
    ) -> [(trajectoryPoint: Point3D, uwbPoint: Point3D, antennaId: String)] {
        var matchedPoints: [(trajectoryPoint: Point3D, uwbPoint: Point3D, antennaId: String)] = []

        print("🔍 時刻同期マッチング開始: 軌跡点\(trajectory.count)個, UWB観測\(uwbData.count)個")

        // 各UWB観測に対して、最も近い時刻の軌跡点を見つける
        for (index, uwbObs) in uwbData.enumerated() {
            var bestMatch: PedestrianDeadReckoning.TrajectoryPoint?
            var bestTimeDelta: TimeInterval = .infinity

            for trajectoryPoint in trajectory {
                let timeDelta = abs(trajectoryPoint.timestamp.timeIntervalSince(uwbObs.timestamp))

                if timeDelta < bestTimeDelta {
                    bestTimeDelta = timeDelta
                    if timeDelta <= self.config.maxTimeDelta {
                        bestMatch = trajectoryPoint
                    }
                }
            }

            // デバッグ出力: 各UWB観測の最小時刻差を出力
            print(
                "   UWB[\(index)]: 最小時刻差=\(String(format: "%.3f", bestTimeDelta))秒, マッチ=\(bestMatch != nil ? "○" : "×")"
            )

            if let match = bestMatch {
                matchedPoints.append((
                    trajectoryPoint: match.toPoint3D,
                    uwbPoint: uwbObs.position,
                    antennaId: uwbObs.antennaId
                ))
            }
        }

        return matchedPoints
    }

    /// キャリブレーション実行
    private func performCalibration(
        matchedPoints: [(trajectoryPoint: Point3D, uwbPoint: Point3D, antennaId: String)],
        pdrResult: PedestrianDeadReckoning.PDRResult,
        duration: TimeInterval
    ) throws -> WalkThroughCalibrationResult {
        var warnings: [String] = []

        // マッチング点数チェック
        if matchedPoints.count < self.config.minMatchedPoints {
            warnings.append(
                "マッチング点数が少ないです（\(matchedPoints.count)点）。精度が低下する可能性があります。"
            )
        }

        // アンテナごとにグループ化
        let pointsByAntenna = Dictionary(grouping: matchedPoints) { $0.antennaId }

        guard !pointsByAntenna.isEmpty else {
            throw WalkThroughError.noMatchedPoints
        }

        var antennaConfigs: [String: AntennaAffineCalibration.AntennaConfig] = [:]
        var totalRMSE = 0.0
        var rmseCount = 0

        for (antennaId, points) in pointsByAntenna {
            // 軌跡点とUWB観測点をマッピング
            // PDR軌跡を「真の位置」、UWB観測を「測定位置」として扱う
            var measuredPointsByTag: [String: [Point3D]] = [:]
            var truePositions: [String: Point3D] = [:]

            // 軌跡点を一定間隔でサンプリングしてタグとして使用
            let stepPoints = points.filter { _ in true }  // 全点使用

            for (index, point) in stepPoints.enumerated() {
                let tagId = "walk_\(index)"
                measuredPointsByTag[tagId] = [point.uwbPoint]
                truePositions[tagId] = point.trajectoryPoint
            }

            // 最低3点必要
            guard truePositions.count >= 3 else {
                warnings.append("\(antennaId): データ点数が不足しています（\(truePositions.count)点）")
                continue
            }

            do {
                let config = try self.affineCalibration.estimateAntennaConfig(
                    measuredPointsByTag: measuredPointsByTag,
                    truePositions: truePositions
                )
                antennaConfigs[antennaId] = config
                totalRMSE += config.rmse
                rmseCount += 1

                print("""
                📡 \(antennaId) のキャリブレーション成功
                   位置: (\(String(format: "%.2f", config.x)), \(String(format: "%.2f", config.y)))
                   角度: \(String(format: "%.1f", config.angleDegrees))°
                   RMSE: \(String(format: "%.4f", config.rmse))m
                """)
            } catch {
                warnings.append("\(antennaId): キャリブレーション失敗 - \(error.localizedDescription)")
            }
        }

        let averageRMSE = rmseCount > 0 ? totalRMSE / Double(rmseCount) : 0
        let success = !antennaConfigs.isEmpty

        return WalkThroughCalibrationResult(
            antennaConfigs: antennaConfigs,
            trajectoryLength: pdrResult.totalDistance,
            stepCount: pdrResult.stepCount,
            matchedPointCount: matchedPoints.count,
            duration: duration,
            rmse: averageRMSE,
            warnings: warnings,
            success: success
        )
    }

    // MARK: - Errors

    enum WalkThroughError: LocalizedError {
        case notCalibrating
        case noMatchedPoints
        case insufficientData(required: Int, found: Int)

        var errorDescription: String? {
            switch self {
            case .notCalibrating:
                return "Walk-throughキャリブレーションが開始されていません。"
            case .noMatchedPoints:
                return "IMU軌跡とUWB観測のマッチングができませんでした。"
            case .insufficientData(let required, let found):
                return "データ点数が不足しています。最低\(required)点必要ですが、\(found)点しかありません。"
            }
        }
    }
}

// MARK: - Debug Extension

extension WalkThroughCalibrationUsecase {

    /// デバッグ用: 現在の状態をログ出力
    func printDebugInfo() {
        print("""

        === WalkThroughCalibration Debug Info ===
        キャリブレーション中: \(self.isCalibrating)
        Walk-through開始時刻: \(self.walkStartTime?.description ?? "なし")
        UWB観測数: \(self.uwbObservations.count)
        IMU記録: \(self.imuRecordingResult?.sampleCount ?? 0)サンプル
        PDR軌跡: \(self.pdrTrajectory?.trajectoryPoints.count ?? 0)点
        =========================================

        """)
    }
}
