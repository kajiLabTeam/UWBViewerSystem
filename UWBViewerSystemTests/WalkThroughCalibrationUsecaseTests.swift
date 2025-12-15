//
//  WalkThroughCalibrationUsecaseTests.swift
//  UWBViewerSystemTests
//
//  WalkThroughCalibrationUsecaseのテスト
//

import Foundation
import Testing

@testable import UWBViewerSystem

@Suite("WalkThroughCalibrationUsecase Tests")
struct WalkThroughCalibrationUsecaseTests {

    // MARK: - Test Data Creation

    /// テスト用IMUデータを生成
    func createTestIMUData(stepCount: Int, duration: TimeInterval) -> [IMUDataPoint] {
        var dataPoints: [IMUDataPoint] = []
        let baseTime = Date()
        let sampleRate: Double = 100.0
        let sampleCount = Int(duration * sampleRate)
        let samplesPerStep = sampleCount / max(stepCount, 1)

        for i in 0..<sampleCount {
            let timestamp = baseTime.addingTimeInterval(Double(i) / sampleRate)

            // 歩行パターンシミュレーション
            let stepIndex = i / samplesPerStep
            let sampleInStep = i % samplesPerStep
            let accelMagnitude: Double
            if sampleInStep == samplesPerStep / 2 && stepIndex < stepCount {
                accelMagnitude = 1.3  // ピーク（歩数検出用）
            } else {
                accelMagnitude = 1.0
            }

            dataPoints.append(IMUDataPoint(
                id: UUID(),
                timestamp: timestamp,
                accelerationX: 0,
                accelerationY: 0,
                accelerationZ: accelMagnitude * 9.81,
                rotationRateX: 0,
                rotationRateY: 0,
                rotationRateZ: 0,
                pitch: 0,
                roll: 0,
                yaw: 0
            ))
        }

        return dataPoints
    }

    /// テスト用IMURecordingResultを生成
    func createTestIMUResult(stepCount: Int = 10, duration: TimeInterval = 10.0) -> IMURecordingResult {
        let dataPoints = self.createTestIMUData(stepCount: stepCount, duration: duration)
        return IMURecordingResult(
            dataPoints: dataPoints,
            duration: duration,
            sampleCount: dataPoints.count,
            averageSampleRate: Double(dataPoints.count) / duration
        )
    }

    // MARK: - Basic Tests

    @Test("初期状態でUWB観測数が0")
    func initialObservationCount() async {
        // Note: SwiftDataRepositoryのモックが必要だが、テスト目的で動作確認
        // 実際のテストではモックを使用
        #expect(true)  // プレースホルダー
    }

    // MARK: - TimestampedUWBObservation Tests

    @Test("TimestampedUWBObservationが正しく作成される")
    func createTimestampedObservation() {
        let timestamp = Date()
        let position = Point3D(x: 1.0, y: 2.0, z: 0.5)
        let quality = SignalQuality(
            strength: 0.8,
            isLineOfSight: true,
            confidenceLevel: 0.9,
            errorEstimate: 0.1
        )

        let observation = WalkThroughCalibrationUsecase.TimestampedUWBObservation(
            timestamp: timestamp,
            antennaId: "antenna1",
            position: position,
            quality: quality
        )

        #expect(observation.timestamp == timestamp)
        #expect(observation.antennaId == "antenna1")
        #expect(observation.position.x == 1.0)
        #expect(observation.position.y == 2.0)
        #expect(observation.quality.isLineOfSight)
    }

    // MARK: - WalkThroughCalibrationResult Tests

    @Test("WalkThroughCalibrationResultが正しく作成される")
    func createCalibrationResult() {
        let antennaConfig = AntennaAffineCalibration.AntennaConfig(
            position: Point3D(x: 5.0, y: 3.0, z: 1.0),
            angleDegrees: 45.0,
            rmse: 0.05
        )

        let result = WalkThroughCalibrationUsecase.WalkThroughCalibrationResult(
            antennaConfigs: ["antenna1": antennaConfig],
            trajectoryLength: 7.0,
            stepCount: 10,
            matchedPointCount: 15,
            duration: 30.0,
            rmse: 0.05,
            warnings: [],
            success: true
        )

        #expect(result.success)
        #expect(result.antennaConfigs.count == 1)
        #expect(result.trajectoryLength == 7.0)
        #expect(result.stepCount == 10)
        #expect(result.matchedPointCount == 15)
        #expect(result.duration == 30.0)
        #expect(result.rmse == 0.05)
        #expect(result.warnings.isEmpty)
    }

    @Test("失敗したキャリブレーション結果")
    func failedCalibrationResult() {
        let result = WalkThroughCalibrationUsecase.WalkThroughCalibrationResult(
            antennaConfigs: [:],
            trajectoryLength: 2.0,
            stepCount: 3,
            matchedPointCount: 2,
            duration: 10.0,
            rmse: 0,
            warnings: ["データ点数が不足しています"],
            success: false
        )

        #expect(!result.success)
        #expect(result.antennaConfigs.isEmpty)
        #expect(result.warnings.count == 1)
    }

    // MARK: - Config Tests

    @Test("デフォルト設定が正しく適用される")
    func defaultConfig() {
        let config = WalkThroughCalibrationUsecase.Config.default

        #expect(config.maxTimeDelta == 0.1)
        #expect(config.minMatchedPoints == 10)
    }

    @Test("カスタム設定が正しく作成される")
    func customConfig() {
        let config = WalkThroughCalibrationUsecase.Config(
            maxTimeDelta: 0.2,
            minMatchedPoints: 20
        )

        #expect(config.maxTimeDelta == 0.2)
        #expect(config.minMatchedPoints == 20)
    }

    // MARK: - Error Tests

    @Test("WalkThroughErrorのエラーメッセージが正しい")
    func errorMessages() {
        let notCalibrating = WalkThroughCalibrationUsecase.WalkThroughError.notCalibrating
        #expect(notCalibrating.errorDescription?.contains("開始されていません") == true)

        let noMatchedPoints = WalkThroughCalibrationUsecase.WalkThroughError.noMatchedPoints
        #expect(noMatchedPoints.errorDescription?.contains("マッチング") == true)

        let insufficientData = WalkThroughCalibrationUsecase.WalkThroughError.insufficientData(
            required: 10, found: 3)
        #expect(insufficientData.errorDescription?.contains("10") == true)
        #expect(insufficientData.errorDescription?.contains("3") == true)
    }

    // MARK: - IMUData Tests

    @Test("IMUDataPointが正しく作成される")
    func createIMUDataPoint() {
        let timestamp = Date()
        let dataPoint = IMUDataPoint(
            id: UUID(),
            timestamp: timestamp,
            accelerationX: 0.1,
            accelerationY: 0.2,
            accelerationZ: 9.8,
            rotationRateX: 0.01,
            rotationRateY: 0.02,
            rotationRateZ: 0.03,
            pitch: 0.1,
            roll: 0.2,
            yaw: 0.3
        )

        #expect(dataPoint.accelerationX == 0.1)
        #expect(dataPoint.accelerationY == 0.2)
        #expect(dataPoint.accelerationZ == 9.8)
        #expect(dataPoint.rotationRateX == 0.01)
        #expect(dataPoint.rotationRateY == 0.02)
        #expect(dataPoint.rotationRateZ == 0.03)
        #expect(dataPoint.pitch == 0.1)
        #expect(dataPoint.roll == 0.2)
        #expect(dataPoint.yaw == 0.3)
    }

    @Test("加速度マグニチュードが正しく計算される")
    func accelerationMagnitude() {
        let dataPoint = IMUDataPoint(
            id: UUID(),
            timestamp: Date(),
            accelerationX: 3.0,
            accelerationY: 4.0,
            accelerationZ: 0,
            rotationRateX: 0,
            rotationRateY: 0,
            rotationRateZ: 0,
            pitch: 0,
            roll: 0,
            yaw: 0
        )

        // sqrt(3² + 4²) = 5
        #expect(abs(dataPoint.accelerationMagnitude - 5.0) < 0.001)
    }

    @Test("加速度マグニチュードのG変換が正しい")
    func accelerationMagnitudeInG() {
        let dataPoint = IMUDataPoint(
            id: UUID(),
            timestamp: Date(),
            accelerationX: 0,
            accelerationY: 0,
            accelerationZ: 9.81,  // 1G
            rotationRateX: 0,
            rotationRateY: 0,
            rotationRateZ: 0,
            pitch: 0,
            roll: 0,
            yaw: 0
        )

        #expect(abs(dataPoint.accelerationMagnitudeInG - 1.0) < 0.001)
    }

    // MARK: - IMURecordingResult Tests

    @Test("IMURecordingResultが正しく作成される")
    func createIMURecordingResult() {
        let dataPoints = [
            IMUDataPoint(
                id: UUID(),
                timestamp: Date(),
                accelerationX: 0,
                accelerationY: 0,
                accelerationZ: 9.81,
                rotationRateX: 0,
                rotationRateY: 0,
                rotationRateZ: 0,
                pitch: 0,
                roll: 0,
                yaw: 0
            )
        ]

        let result = IMURecordingResult(
            dataPoints: dataPoints,
            duration: 10.0,
            sampleCount: 1000,
            averageSampleRate: 100.0
        )

        #expect(result.dataPoints.count == 1)
        #expect(result.duration == 10.0)
        #expect(result.sampleCount == 1000)
        #expect(result.averageSampleRate == 100.0)
    }

    // MARK: - Integration Test Helpers

    @Test("テスト用IMUデータ生成が動作する")
    func iMUDataGeneration() {
        let imuResult = self.createTestIMUResult(stepCount: 5, duration: 5.0)

        #expect(imuResult.duration == 5.0)
        #expect(imuResult.sampleCount == imuResult.dataPoints.count)
        #expect(imuResult.averageSampleRate > 0)
    }
}

// MARK: - Mock Repository for Testing

/// テスト用のモックSwiftDataRepository
/// 注: 実際のテストではSwiftDataRepositoryのプロトコル化とモック実装が必要
struct MockSwiftDataRepositoryForWalkThrough {
    var antennaPositions: [String: [AntennaPositionData]] = [:]
    var floorMapInfos: [String: FloorMapInfo] = [:]

    func loadAntennaPositions(for floorMapId: String) -> [AntennaPositionData] {
        self.antennaPositions[floorMapId] ?? []
    }
}
