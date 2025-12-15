//
//  PedestrianDeadReckoning.swift
//  UWBViewerSystem
//
//  歩行者デッドレコニング（PDR）アルゴリズム
//  IMUデータから歩行軌跡を推定
//

import Foundation

/// PDR（歩行者デッドレコニング）アルゴリズム
public struct PedestrianDeadReckoning {
    // MARK: - Configuration

    /// PDR設定
    public struct Config: Sendable {
        /// デフォルト歩幅（メートル）
        public let defaultStrideLength: Double

        /// 歩数検出の加速度閾値（G）
        public let stepDetectionThreshold: Double

        /// 最小歩行間隔（秒）
        public let minStepInterval: TimeInterval

        /// 相補フィルターの重み（0.0-1.0、高いほどジャイロ重視）
        public let complementaryFilterAlpha: Double

        /// 方位のローパスフィルター係数
        public let headingLowPassAlpha: Double

        public init(
            defaultStrideLength: Double = 0.7,
            stepDetectionThreshold: Double = 1.2,
            minStepInterval: TimeInterval = 0.3,
            complementaryFilterAlpha: Double = 0.98,
            headingLowPassAlpha: Double = 0.1
        ) {
            self.defaultStrideLength = defaultStrideLength
            self.stepDetectionThreshold = stepDetectionThreshold
            self.minStepInterval = minStepInterval
            self.complementaryFilterAlpha = complementaryFilterAlpha
            self.headingLowPassAlpha = headingLowPassAlpha
        }

        public static let `default` = Config()

        /// Walk-through用の低感度設定（iPadを持って歩く場合向け）
        public static let walkThrough = Config(
            defaultStrideLength: 0.6,  // iPadを持っているため少し短め
            stepDetectionThreshold: 1.05,  // 閾値を下げて検出しやすくする
            minStepInterval: 0.25,  // 間隔を短くして素早い歩行にも対応
            complementaryFilterAlpha: 0.95,  // 姿勢センサーをやや重視
            headingLowPassAlpha: 0.15  // ローパスを少し強くして安定化
        )
    }

    // MARK: - Types

    /// 軌跡上の1点
    public struct TrajectoryPoint: Identifiable, Sendable {
        public let id: UUID
        public let timestamp: Date
        public let x: Double  // メートル
        public let y: Double  // メートル
        public let heading: Double  // ラジアン
        public let confidence: Double  // 0.0-1.0
        public let isStepPoint: Bool  // 歩数検出時の点か

        public init(
            id: UUID = UUID(),
            timestamp: Date,
            x: Double,
            y: Double,
            heading: Double,
            confidence: Double,
            isStepPoint: Bool
        ) {
            self.id = id
            self.timestamp = timestamp
            self.x = x
            self.y = y
            self.heading = heading
            self.confidence = confidence
            self.isStepPoint = isStepPoint
        }

        /// Point3Dに変換
        public var toPoint3D: Point3D {
            Point3D(x: self.x, y: self.y, z: 0)
        }
    }

    /// PDR結果
    public struct PDRResult: Sendable {
        public let trajectoryPoints: [TrajectoryPoint]
        public let totalDistance: Double  // メートル
        public let stepCount: Int
        public let duration: TimeInterval
        public let averageHeading: Double  // ラジアン

        /// 歩数検出時のポイントのみ取得
        public var stepPoints: [TrajectoryPoint] {
            self.trajectoryPoints.filter { $0.isStepPoint }
        }
    }

    // MARK: - Properties

    private let config: Config

    // MARK: - Initialization

    public init(config: Config = .default) {
        self.config = config
    }

    // MARK: - Public Methods

    /// IMUデータから歩行軌跡を推定
    /// - Parameters:
    ///   - imuData: IMUデータ配列
    ///   - startPosition: 開始位置（デフォルト: 原点）
    ///   - startHeading: 開始方位（ラジアン、デフォルト: 0）
    /// - Returns: PDR結果
    public func estimateTrajectory(
        from imuData: [IMUDataPoint],
        startPosition: Point3D = .zero,
        startHeading: Double = 0.0
    ) -> PDRResult {
        guard !imuData.isEmpty else {
            return PDRResult(
                trajectoryPoints: [],
                totalDistance: 0,
                stepCount: 0,
                duration: 0,
                averageHeading: startHeading
            )
        }

        var trajectoryPoints: [TrajectoryPoint] = []
        var currentX = startPosition.x
        var currentY = startPosition.y
        var currentHeading = startHeading
        var filteredHeading = startHeading
        var stepCount = 0
        var totalDistance = 0.0
        var lastStepTime: Date?

        // 歩数検出用の状態
        var peakDetectionState: PeakDetectionState = .lookingForPeak
        var headingSum = 0.0
        var headingCount = 0

        // 最初の点を追加
        let firstPoint = imuData[0]
        trajectoryPoints.append(
            TrajectoryPoint(
                timestamp: firstPoint.timestamp,
                x: currentX,
                y: currentY,
                heading: currentHeading,
                confidence: 1.0,
                isStepPoint: false
            )
        )

        for i in 1..<imuData.count {
            let dataPoint = imuData[i]
            let previousPoint = imuData[i - 1]

            // 時間差を計算
            let dt = dataPoint.timestamp.timeIntervalSince(previousPoint.timestamp)

            // 方位更新（ジャイロ積分 + ローパスフィルター）
            // yawを使用（z軸周りの回転）
            let gyroHeadingDelta = dataPoint.rotationRateZ * dt
            currentHeading += gyroHeadingDelta

            // 姿勢センサーからの方位との相補フィルター
            let attitudeHeading = dataPoint.yaw
            currentHeading = self.config.complementaryFilterAlpha * currentHeading
                + (1 - self.config.complementaryFilterAlpha) * attitudeHeading

            // 方位のローパスフィルター
            filteredHeading = self.config.headingLowPassAlpha * currentHeading
                + (1 - self.config.headingLowPassAlpha) * filteredHeading

            // 方位を-π〜πに正規化
            currentHeading = self.normalizeAngle(currentHeading)
            filteredHeading = self.normalizeAngle(filteredHeading)

            headingSum += filteredHeading
            headingCount += 1

            // 歩数検出
            let accelerationG = dataPoint.accelerationMagnitudeInG
            let stepDetected = self.detectStep(
                accelerationG: accelerationG,
                timestamp: dataPoint.timestamp,
                lastStepTime: &lastStepTime,
                state: &peakDetectionState
            )

            if stepDetected {
                // 歩数検出時に位置を更新
                let stride = self.config.defaultStrideLength
                currentX += stride * cos(filteredHeading)
                currentY += stride * sin(filteredHeading)
                totalDistance += stride
                stepCount += 1

                // 信頼度計算（時間経過で減衰）
                let timeFromStart =
                    dataPoint.timestamp.timeIntervalSince(imuData[0].timestamp)
                let confidence = max(0.5, 1.0 - timeFromStart / 60.0)  // 60秒で0.5まで減衰

                trajectoryPoints.append(
                    TrajectoryPoint(
                        timestamp: dataPoint.timestamp,
                        x: currentX,
                        y: currentY,
                        heading: filteredHeading,
                        confidence: confidence,
                        isStepPoint: true
                    )
                )
            }
        }

        // 最終点を追加（歩数検出点でない場合）
        if let lastData = imuData.last,
           trajectoryPoints.last?.timestamp != lastData.timestamp
        {
            let timeFromStart =
                lastData.timestamp.timeIntervalSince(imuData[0].timestamp)
            let confidence = max(0.5, 1.0 - timeFromStart / 60.0)

            trajectoryPoints.append(
                TrajectoryPoint(
                    timestamp: lastData.timestamp,
                    x: currentX,
                    y: currentY,
                    heading: filteredHeading,
                    confidence: confidence,
                    isStepPoint: false
                )
            )
        }

        let duration =
            imuData.last.map { $0.timestamp.timeIntervalSince(imuData[0].timestamp) } ?? 0
        let averageHeading = headingCount > 0 ? headingSum / Double(headingCount) : startHeading

        return PDRResult(
            trajectoryPoints: trajectoryPoints,
            totalDistance: totalDistance,
            stepCount: stepCount,
            duration: duration,
            averageHeading: averageHeading
        )
    }

    /// 軌跡点をリサンプリング（一定間隔で）
    /// - Parameters:
    ///   - trajectory: 元の軌跡
    ///   - interval: サンプリング間隔（秒）
    /// - Returns: リサンプリングされた軌跡
    public func resampleTrajectory(
        _ trajectory: [TrajectoryPoint],
        interval: TimeInterval
    ) -> [TrajectoryPoint] {
        guard trajectory.count >= 2 else { return trajectory }

        var resampled: [TrajectoryPoint] = []
        let startTime = trajectory[0].timestamp

        var currentIndex = 0
        var currentTime = startTime

        while currentIndex < trajectory.count - 1 {
            let targetTime = startTime.addingTimeInterval(
                Double(resampled.count) * interval
            )

            // targetTimeに最も近い2点を見つけて補間
            while currentIndex < trajectory.count - 1
                && trajectory[currentIndex + 1].timestamp <= targetTime
            {
                currentIndex += 1
            }

            if currentIndex >= trajectory.count - 1 {
                break
            }

            let p0 = trajectory[currentIndex]
            let p1 = trajectory[currentIndex + 1]

            let t0 = p0.timestamp.timeIntervalSince(startTime)
            let t1 = p1.timestamp.timeIntervalSince(startTime)
            let t = targetTime.timeIntervalSince(startTime)

            let ratio = (t - t0) / (t1 - t0)

            let interpolatedPoint = TrajectoryPoint(
                timestamp: targetTime,
                x: p0.x + (p1.x - p0.x) * ratio,
                y: p0.y + (p1.y - p0.y) * ratio,
                heading: self.interpolateAngle(p0.heading, p1.heading, ratio: ratio),
                confidence: p0.confidence + (p1.confidence - p0.confidence) * ratio,
                isStepPoint: false
            )

            resampled.append(interpolatedPoint)
            currentTime = targetTime
        }

        return resampled
    }

    // MARK: - Private Methods

    private enum PeakDetectionState {
        case lookingForPeak
        case lookingForValley
    }

    private func detectStep(
        accelerationG: Double,
        timestamp: Date,
        lastStepTime: inout Date?,
        state: inout PeakDetectionState
    ) -> Bool {
        // 最小間隔チェック
        if let lastTime = lastStepTime {
            if timestamp.timeIntervalSince(lastTime) < self.config.minStepInterval {
                return false
            }
        }

        switch state {
        case .lookingForPeak:
            if accelerationG > self.config.stepDetectionThreshold {
                state = .lookingForValley
            }
            return false

        case .lookingForValley:
            if accelerationG < self.config.stepDetectionThreshold * 0.8 {
                // 歩数検出
                lastStepTime = timestamp
                state = .lookingForPeak
                return true
            }
            return false
        }
    }

    /// 角度を-π〜πに正規化
    private func normalizeAngle(_ angle: Double) -> Double {
        var normalized = angle
        while normalized > .pi {
            normalized -= 2 * .pi
        }
        while normalized < -.pi {
            normalized += 2 * .pi
        }
        return normalized
    }

    /// 角度の補間（最短経路）
    private func interpolateAngle(_ a0: Double, _ a1: Double, ratio: Double) -> Double {
        var diff = a1 - a0
        if diff > .pi {
            diff -= 2 * .pi
        } else if diff < -.pi {
            diff += 2 * .pi
        }
        return self.normalizeAngle(a0 + diff * ratio)
    }
}

// MARK: - Extension for Point3D

extension Point3D {
    /// 2D距離（z座標を無視）
    public func distance2D(to other: Point3D) -> Double {
        let dx = self.x - other.x
        let dy = self.y - other.y
        return sqrt(dx * dx + dy * dy)
    }
}
