//
//  PedestrianDeadReckoningTests.swift
//  UWBViewerSystemTests
//
//  PedestrianDeadReckoning（歩行者デッドレコニング）のテスト
//

import Foundation
import Testing

@testable import UWBViewerSystem

@Suite("PedestrianDeadReckoning Tests")
struct PedestrianDeadReckoningTests {

    // MARK: - Test Data Creation

    /// テスト用IMUデータを生成（直進歩行シミュレーション）
    func createStraightWalkIMUData(
        stepCount: Int,
        stepsPerSecond: Double = 2.0,
        heading: Double = 0.0
    ) -> [IMUDataPoint] {
        var dataPoints: [IMUDataPoint] = []
        let baseTime = Date()
        let sampleRate: Double = 100.0  // 100Hz
        let stepDuration = 1.0 / stepsPerSecond
        let samplesPerStep = Int(sampleRate * stepDuration)

        for step in 0..<stepCount {
            for sample in 0..<samplesPerStep {
                let totalSample = step * samplesPerStep + sample
                let timestamp = baseTime.addingTimeInterval(Double(totalSample) / sampleRate)

                // 歩行パターンをシミュレート（正弦波で加速度を生成）
                let phase = Double(sample) / Double(samplesPerStep) * 2 * .pi
                let peakAccel = 1.3  // G（歩数検出閾値1.2Gを超える）

                // 歩行中盤でピークを作る
                let accelMagnitude: Double
                if sample == samplesPerStep / 2 {
                    accelMagnitude = peakAccel
                } else if sample == samplesPerStep / 4 || sample == samplesPerStep * 3 / 4 {
                    accelMagnitude = 0.8  // バレー
                } else {
                    accelMagnitude = 1.0
                }

                let dataPoint = IMUDataPoint(
                    id: UUID(),
                    timestamp: timestamp,
                    accelerationX: 0,
                    accelerationY: 0,
                    accelerationZ: accelMagnitude * 9.81,  // m/s² に変換
                    rotationRateX: 0,
                    rotationRateY: 0,
                    rotationRateZ: 0,
                    pitch: 0,
                    roll: 0,
                    yaw: heading
                )
                dataPoints.append(dataPoint)
            }
        }

        return dataPoints
    }

    /// テスト用IMUデータを生成（静止状態）
    func createStationaryIMUData(duration: TimeInterval) -> [IMUDataPoint] {
        var dataPoints: [IMUDataPoint] = []
        let baseTime = Date()
        let sampleRate: Double = 100.0
        let sampleCount = Int(duration * sampleRate)

        for i in 0..<sampleCount {
            let timestamp = baseTime.addingTimeInterval(Double(i) / sampleRate)
            let dataPoint = IMUDataPoint(
                id: UUID(),
                timestamp: timestamp,
                accelerationX: 0,
                accelerationY: 0,
                accelerationZ: 9.81,  // 1G（重力のみ）
                rotationRateX: 0,
                rotationRateY: 0,
                rotationRateZ: 0,
                pitch: 0,
                roll: 0,
                yaw: 0
            )
            dataPoints.append(dataPoint)
        }

        return dataPoints
    }

    // MARK: - Basic Tests

    @Test("空のIMUデータの場合、空の結果を返す")
    func emptyIMUData() {
        let pdr = PedestrianDeadReckoning()
        let result = pdr.estimateTrajectory(from: [])

        #expect(result.trajectoryPoints.isEmpty)
        #expect(result.stepCount == 0)
        #expect(result.totalDistance == 0)
        #expect(result.duration == 0)
    }

    @Test("静止状態では歩数がカウントされない")
    func stationaryData() {
        let pdr = PedestrianDeadReckoning()
        let imuData = self.createStationaryIMUData(duration: 5.0)
        let result = pdr.estimateTrajectory(from: imuData)

        #expect(result.stepCount == 0)
        #expect(result.totalDistance == 0)
        #expect(result.trajectoryPoints.count >= 1)
    }

    // MARK: - Step Detection Tests

    @Test("歩行パターンで歩数が正しく検出される")
    func stepDetection() {
        let config = PedestrianDeadReckoning.Config(
            defaultStrideLength: 0.7,
            stepDetectionThreshold: 1.2,
            minStepInterval: 0.3
        )
        let pdr = PedestrianDeadReckoning(config: config)

        // 10歩のシミュレーション
        let imuData = self.createStraightWalkIMUData(stepCount: 10)
        let result = pdr.estimateTrajectory(from: imuData)

        // 歩数検出（実際の値は検出アルゴリズムによって若干異なる可能性あり）
        #expect(result.stepCount >= 8)  // 最低8歩は検出されるはず
        #expect(result.stepCount <= 12)  // 最大12歩程度
    }

    @Test("歩幅設定が正しく反映される")
    func strideLength() {
        let strideLength = 0.8
        let config = PedestrianDeadReckoning.Config(
            defaultStrideLength: strideLength,
            stepDetectionThreshold: 1.2,
            minStepInterval: 0.3
        )
        let pdr = PedestrianDeadReckoning(config: config)

        let imuData = self.createStraightWalkIMUData(stepCount: 5)
        let result = pdr.estimateTrajectory(from: imuData)

        if result.stepCount > 0 {
            // 移動距離 = 歩数 × 歩幅
            let expectedDistance = Double(result.stepCount) * strideLength
            #expect(abs(result.totalDistance - expectedDistance) < 0.01)
        }
    }

    // MARK: - Trajectory Tests

    @Test("直進歩行で軌跡が正しく生成される")
    func straightTrajectory() {
        let config = PedestrianDeadReckoning.Config(
            defaultStrideLength: 0.7,
            stepDetectionThreshold: 1.2,
            minStepInterval: 0.3
        )
        let pdr = PedestrianDeadReckoning(config: config)

        // 方位0（北向き）で直進
        let imuData = self.createStraightWalkIMUData(stepCount: 10, heading: 0)
        let result = pdr.estimateTrajectory(from: imuData, startPosition: .zero, startHeading: 0)

        // 軌跡点が生成されている
        #expect(!result.trajectoryPoints.isEmpty)

        // 歩数検出点が含まれている
        let stepPoints = result.trajectoryPoints.filter { $0.isStepPoint }
        #expect(stepPoints.count >= 1)

        // 最終位置は開始位置より北（y軸正方向）に移動しているはず
        if let lastPoint = result.trajectoryPoints.last {
            #expect(lastPoint.y >= 0)  // 北向き歩行なのでy >= 0
        }
    }

    @Test("開始位置が正しく反映される")
    func startPosition() {
        let pdr = PedestrianDeadReckoning()
        let startPos = Point3D(x: 5.0, y: 10.0, z: 0)

        let imuData = self.createStationaryIMUData(duration: 1.0)
        let result = pdr.estimateTrajectory(from: imuData, startPosition: startPos)

        // 最初の点が開始位置に一致
        if let firstPoint = result.trajectoryPoints.first {
            #expect(abs(firstPoint.x - startPos.x) < 0.01)
            #expect(abs(firstPoint.y - startPos.y) < 0.01)
        }
    }

    // MARK: - Angle Normalization Tests

    @Test("方位が正しく正規化される")
    func headingNormalization() {
        let pdr = PedestrianDeadReckoning()

        // 大きな角度でも正規化されるはず（内部テスト）
        let imuData = self.createStraightWalkIMUData(stepCount: 3, heading: 3 * .pi)
        let result = pdr.estimateTrajectory(from: imuData)

        // 軌跡の方位が-π〜πの範囲に収まっている
        for point in result.trajectoryPoints {
            #expect(point.heading >= -.pi)
            #expect(point.heading <= .pi)
        }
    }

    // MARK: - Resampling Tests

    @Test("軌跡のリサンプリングが正しく動作する")
    func trajectoryResampling() {
        let pdr = PedestrianDeadReckoning()

        let imuData = self.createStraightWalkIMUData(stepCount: 10)
        let result = pdr.estimateTrajectory(from: imuData)

        // リサンプリング（0.5秒間隔）
        let resampled = pdr.resampleTrajectory(result.trajectoryPoints, interval: 0.5)

        if result.trajectoryPoints.count >= 2 && result.duration > 0.5 {
            // リサンプリングされた点数は元のデータと異なる
            #expect(!resampled.isEmpty)
        }
    }

    @Test("軌跡が短すぎる場合、リサンプリングはそのまま返す")
    func resamplingShortTrajectory() {
        let pdr = PedestrianDeadReckoning()

        // 1点のみの軌跡
        let singlePoint = [
            PedestrianDeadReckoning.TrajectoryPoint(
                timestamp: Date(),
                x: 0,
                y: 0,
                heading: 0,
                confidence: 1.0,
                isStepPoint: false
            )
        ]

        let resampled = pdr.resampleTrajectory(singlePoint, interval: 0.5)

        // そのまま返る
        #expect(resampled.count == singlePoint.count)
    }

    // MARK: - PDR Result Tests

    @Test("PDR結果の構造が正しい")
    func pdrResultStructure() {
        let pdr = PedestrianDeadReckoning()
        let imuData = self.createStraightWalkIMUData(stepCount: 5)
        let result = pdr.estimateTrajectory(from: imuData)

        // 結果構造の検証
        #expect(result.duration >= 0)
        #expect(result.totalDistance >= 0)
        #expect(result.stepCount >= 0)

        // stepPointsヘルパーが正しく動作
        let stepPoints = result.stepPoints
        #expect(stepPoints.count == result.trajectoryPoints.filter { $0.isStepPoint }.count)
    }

    // MARK: - TrajectoryPoint Tests

    @Test("TrajectoryPointをPoint3Dに変換できる")
    func trajectoryPointToPoint3D() {
        let point = PedestrianDeadReckoning.TrajectoryPoint(
            timestamp: Date(),
            x: 1.5,
            y: 2.5,
            heading: 0.5,
            confidence: 0.9,
            isStepPoint: true
        )

        let point3D = point.toPoint3D

        #expect(point3D.x == 1.5)
        #expect(point3D.y == 2.5)
        #expect(point3D.z == 0)
    }

    // MARK: - Config Tests

    @Test("デフォルト設定が正しく適用される")
    func defaultConfig() {
        let config = PedestrianDeadReckoning.Config.default

        #expect(config.defaultStrideLength == 0.7)
        #expect(config.stepDetectionThreshold == 1.2)
        #expect(config.minStepInterval == 0.3)
        #expect(config.complementaryFilterAlpha == 0.98)
        #expect(config.headingLowPassAlpha == 0.1)
    }

    @Test("カスタム設定が正しく適用される")
    func customConfig() {
        let config = PedestrianDeadReckoning.Config(
            defaultStrideLength: 0.8,
            stepDetectionThreshold: 1.5,
            minStepInterval: 0.4,
            complementaryFilterAlpha: 0.95,
            headingLowPassAlpha: 0.2
        )

        #expect(config.defaultStrideLength == 0.8)
        #expect(config.stepDetectionThreshold == 1.5)
        #expect(config.minStepInterval == 0.4)
        #expect(config.complementaryFilterAlpha == 0.95)
        #expect(config.headingLowPassAlpha == 0.2)
    }

    // MARK: - Point3D Extension Tests

    @Test("Point3Dの2D距離計算が正しい")
    func point3DDistance2D() {
        let p1 = Point3D(x: 0, y: 0, z: 0)
        let p2 = Point3D(x: 3, y: 4, z: 100)  // z座標は無視される

        let distance = p1.distance2D(to: p2)

        #expect(abs(distance - 5.0) < 0.001)  // 3-4-5の三角形
    }
}
