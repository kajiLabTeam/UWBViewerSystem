//
//  SensorDataProcessor.swift
//  UWBViewerSystem
//
//  センサーデータの前処理を行うユーティリティ
//  Pythonのキャリブレーションコードの前処理機能に対応
//

import Foundation

/// センサーデータ前処理の設定
public struct SensorDataProcessingConfig {
    /// 先頭からトリミングする数
    public let firstTrim: Int

    /// 末尾からトリミングする数
    public let endTrim: Int

    /// 移動平均のウィンドウサイズ
    public let movingAverageWindowSize: Int

    /// nLoSフィルタを適用するか
    public let filterNLOS: Bool

    /// デフォルト設定
    public static let `default` = SensorDataProcessingConfig(
        firstTrim: 20,
        endTrim: 20,
        movingAverageWindowSize: 10,
        filterNLOS: false
    )

    public init(
        firstTrim: Int = 20,
        endTrim: Int = 20,
        movingAverageWindowSize: Int = 10,
        filterNLOS: Bool = false
    ) {
        self.firstTrim = firstTrim
        self.endTrim = endTrim
        self.movingAverageWindowSize = movingAverageWindowSize
        self.filterNLOS = filterNLOS
    }
}

/// センサーデータの前処理を行う構造体
public struct SensorDataProcessor {
    /// 処理設定
    private let config: SensorDataProcessingConfig

    public init(config: SensorDataProcessingConfig = .default) {
        self.config = config
    }

    // MARK: - Public Methods

    /// 観測データポイントのリストを前処理する
    /// - Parameter observations: 観測データポイントのリスト
    /// - Returns: 前処理後の観測データポイントのリスト
    public func processObservations(_ observations: [ObservationPoint]) -> [ObservationPoint] {
        // 1. データのトリミング
        let trimmed = self.trimData(observations)

        // 2. nLoSフィルタリング（設定で有効な場合）
        let filtered = self.config.filterNLOS ? self.filterNLOS(trimmed) : trimmed

        // 3. 移動平均フィルタを適用
        let smoothed = self.applyMovingAverage(filtered)

        return smoothed
    }

    /// 位置データのリストに移動平均を適用する
    /// - Parameter points: 位置データのリスト
    /// - Returns: 移動平均適用後の位置データのリスト
    public func applyMovingAverageToPoints(_ points: [Point3D]) -> [Point3D] {
        guard points.count >= self.config.movingAverageWindowSize else {
            return points
        }

        var result: [Point3D] = []

        for i in 0..<points.count {
            let start = max(0, i - self.config.movingAverageWindowSize + 1)
            let end = min(points.count, i + 1)
            let window = points[start..<end]

            let avgX = window.map { $0.x }.reduce(0, +) / Double(window.count)
            let avgY = window.map { $0.y }.reduce(0, +) / Double(window.count)
            let avgZ = window.map { $0.z }.reduce(0, +) / Double(window.count)

            result.append(Point3D(x: avgX, y: avgY, z: avgZ))
        }

        return result
    }

    // MARK: - Private Methods

    /// データのトリミングを行う
    /// - Parameter observations: 観測データポイントのリスト
    /// - Returns: トリミング後の観測データポイントのリスト
    private func trimData(_ observations: [ObservationPoint]) -> [ObservationPoint] {
        let totalCount = observations.count

        // データが十分にない場合はそのまま返す
        guard totalCount > self.config.firstTrim + self.config.endTrim else {
            return observations
        }

        let startIndex = self.config.firstTrim
        let endIndex = totalCount - self.config.endTrim

        return Array(observations[startIndex..<endIndex])
    }

    /// nLoS（見通し線なし）データを除外する
    /// - Parameter observations: 観測データポイントのリスト
    /// - Returns: nLoSでない観測データポイントのリスト
    private func filterNLOS(_ observations: [ObservationPoint]) -> [ObservationPoint] {
        observations.filter { $0.quality.isLineOfSight }
    }

    /// 移動平均フィルタを適用する
    /// - Parameter observations: 観測データポイントのリスト
    /// - Returns: 移動平均適用後の観測データポイントのリスト
    private func applyMovingAverage(_ observations: [ObservationPoint]) -> [ObservationPoint] {
        guard observations.count >= self.config.movingAverageWindowSize else {
            return observations
        }

        var result: [ObservationPoint] = []

        for i in 0..<observations.count {
            let start = max(0, i - self.config.movingAverageWindowSize + 1)
            let end = min(observations.count, i + 1)
            let window = observations[start..<end]

            // 位置の平均
            let avgX = window.map { $0.position.x }.reduce(0, +) / Double(window.count)
            let avgY = window.map { $0.position.y }.reduce(0, +) / Double(window.count)
            let avgZ = window.map { $0.position.z }.reduce(0, +) / Double(window.count)

            // 距離の平均
            let avgDistance = window.map { $0.distance }.reduce(0, +) / Double(window.count)

            // RSSIの平均
            let avgRSSI = window.map { $0.rssi }.reduce(0, +) / Double(window.count)

            // 信号品質の平均
            let avgStrength = window.map { $0.quality.strength }.reduce(0, +) / Double(window.count)
            let avgConfidence = window.map { $0.quality.confidenceLevel }.reduce(0, +) / Double(window
                .count)
            let avgError = window.map { $0.quality.errorEstimate }.reduce(0, +) / Double(window.count)

            // isLineOfSightは多数決で決定
            let losCount = window.filter { $0.quality.isLineOfSight }.count
            let isLOS = losCount > window.count / 2

            // 平均化されたObservationPointを作成
            let smoothedObservation = ObservationPoint(
                id: observations[i].id,  // 元のIDを維持
                antennaId: observations[i].antennaId,
                position: Point3D(x: avgX, y: avgY, z: avgZ),
                timestamp: observations[i].timestamp,  // 元のタイムスタンプを維持
                quality: SignalQuality(
                    strength: avgStrength,
                    isLineOfSight: isLOS,
                    confidenceLevel: avgConfidence,
                    errorEstimate: avgError
                ),
                distance: avgDistance,
                rssi: avgRSSI,
                sessionId: observations[i].sessionId
            )

            result.append(smoothedObservation)
        }

        return result
    }
}

// MARK: - Extension for Statistics

extension SensorDataProcessor {
    /// データ処理の統計情報を計算する
    /// - Parameters:
    ///   - original: 元のデータ
    ///   - processed: 処理後のデータ
    /// - Returns: 統計情報
    public func calculateStatistics(
        original: [ObservationPoint],
        processed: [ObservationPoint]
    ) -> ProcessingStatistics {
        let originalCount = original.count
        let processedCount = processed.count
        let trimmedCount = originalCount - processedCount

        // 位置の標準偏差を計算
        let originalStdDev = self.calculatePositionStdDev(original)
        let processedStdDev = self.calculatePositionStdDev(processed)

        return ProcessingStatistics(
            originalCount: originalCount,
            processedCount: processedCount,
            trimmedCount: trimmedCount,
            originalStdDev: originalStdDev,
            processedStdDev: processedStdDev
        )
    }

    /// 位置の標準偏差を計算する
    private func calculatePositionStdDev(_ observations: [ObservationPoint]) -> Double {
        guard observations.count > 1 else { return 0.0 }

        // 平均位置を計算
        let meanX = observations.map { $0.position.x }.reduce(0, +) / Double(observations.count)
        let meanY = observations.map { $0.position.y }.reduce(0, +) / Double(observations.count)

        // 分散を計算
        let variance = observations.map { obs in
            let dx = obs.position.x - meanX
            let dy = obs.position.y - meanY
            return dx * dx + dy * dy
        }.reduce(0, +) / Double(observations.count - 1)

        return sqrt(variance)
    }
}

/// データ処理の統計情報
public struct ProcessingStatistics {
    /// 元のデータ数
    public let originalCount: Int

    /// 処理後のデータ数
    public let processedCount: Int

    /// トリミングされたデータ数
    public let trimmedCount: Int

    /// 元のデータの位置標準偏差
    public let originalStdDev: Double

    /// 処理後のデータの位置標準偏差
    public let processedStdDev: Double

    /// トリミング率
    public var trimRate: Double {
        guard self.originalCount > 0 else { return 0.0 }
        return Double(self.trimmedCount) / Double(self.originalCount)
    }

    /// 標準偏差の改善率
    public var stdDevImprovement: Double {
        guard self.originalStdDev > 0 else { return 0.0 }
        return (self.originalStdDev - self.processedStdDev) / self.originalStdDev
    }
}
