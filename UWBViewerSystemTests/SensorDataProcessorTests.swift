//
//  SensorDataProcessorTests.swift
//  UWBViewerSystemTests
//
//  SensorDataProcessorのテスト
//

import Foundation
import Testing

@testable import UWBViewerSystem

@Suite("SensorDataProcessor Tests")
struct SensorDataProcessorTests {

    // MARK: - Test Data Creation

    /// テスト用の観測データを生成
    func createTestObservations(count: Int) -> [ObservationPoint] {
        var observations: [ObservationPoint] = []
        let baseTime = Date()

        for i in 0..<count {
            let observation = ObservationPoint(
                id: "obs_\(i)",
                antennaId: "antenna1",
                position: Point3D(
                    x: Double(i) + Double.random(in: -0.5...0.5),
                    y: Double(i) + Double.random(in: -0.5...0.5),
                    z: 0
                ),
                timestamp: baseTime.addingTimeInterval(Double(i) * 0.1),
                quality: SignalQuality(
                    strength: 0.8,
                    isLineOfSight: i % 5 != 0,  // 5個に1個はnLoS
                    confidenceLevel: 0.9,
                    errorEstimate: 0.1
                ),
                distance: Double(i) * 0.1,
                rssi: -50.0,
                sessionId: "session1"
            )
            observations.append(observation)
        }

        return observations
    }

    // MARK: - Trimming Tests

    @Test("トリミングが正しく動作する")
    func trimming() {
        let config = SensorDataProcessingConfig(
            firstTrim: 5,
            endTrim: 5,
            movingAverageWindowSize: 1,  // 移動平均無効化
            filterNLOS: false
        )
        let processor = SensorDataProcessor(config: config)

        let observations = self.createTestObservations(count: 20)
        let processed = processor.processObservations(observations)

        // 先頭5個と末尾5個が削除されるはず
        #expect(processed.count == 10)
        #expect(processed.first?.id == "obs_5")
        #expect(processed.last?.id == "obs_14")
    }

    @Test("データ数が不足している場合、トリミングされない")
    func trimmingInsufficientData() {
        let config = SensorDataProcessingConfig(
            firstTrim: 10,
            endTrim: 10,
            movingAverageWindowSize: 1,
            filterNLOS: false
        )
        let processor = SensorDataProcessor(config: config)

        let observations = self.createTestObservations(count: 15)  // 15 < 10 + 10
        let processed = processor.processObservations(observations)

        // トリミングされずそのまま返る
        #expect(processed.count == observations.count)
    }

    // MARK: - Moving Average Tests

    @Test("移動平均が正しく計算される")
    func movingAverage() {
        let config = SensorDataProcessingConfig(
            firstTrim: 0,
            endTrim: 0,
            movingAverageWindowSize: 3,
            filterNLOS: false
        )
        let processor = SensorDataProcessor(config: config)

        // 簡単なテストデータ（位置が0, 1, 2, 3, ...）
        var observations: [ObservationPoint] = []
        for i in 0..<5 {
            observations.append(ObservationPoint(
                id: "obs_\(i)",
                antennaId: "antenna1",
                position: Point3D(x: Double(i), y: Double(i), z: 0),
                timestamp: Date(),
                quality: SignalQuality(
                    strength: 0.8,
                    isLineOfSight: true,
                    confidenceLevel: 0.9,
                    errorEstimate: 0.1
                ),
                distance: Double(i),
                rssi: -50.0,
                sessionId: "session1"
            ))
        }

        let processed = processor.processObservations(observations)

        #expect(processed.count == 5)

        // インデックス2の位置は (0+1+2)/3 = 1.0のはず
        #expect(processed[2].position.x == 1.0)
        #expect(processed[2].position.y == 1.0)

        // インデックス4の位置は (2+3+4)/3 = 3.0のはず
        #expect(processed[4].position.x == 3.0)
        #expect(processed[4].position.y == 3.0)
    }

    @Test("移動平均ウィンドウサイズが大きすぎる場合、そのまま返る")
    func movingAverageLargeWindow() {
        let config = SensorDataProcessingConfig(
            firstTrim: 0,
            endTrim: 0,
            movingAverageWindowSize: 100,
            filterNLOS: false
        )
        let processor = SensorDataProcessor(config: config)

        let observations = self.createTestObservations(count: 10)
        let processed = processor.processObservations(observations)

        // ウィンドウサイズが大きすぎる場合、そのまま返る
        #expect(processed.count == observations.count)
    }

    // MARK: - nLoS Filter Tests

    @Test("nLoSフィルタが正しく動作する")
    func nLOSFilter() {
        let config = SensorDataProcessingConfig(
            firstTrim: 0,
            endTrim: 0,
            movingAverageWindowSize: 1,
            filterNLOS: true
        )
        let processor = SensorDataProcessor(config: config)

        let observations = self.createTestObservations(count: 20)
        let processed = processor.processObservations(observations)

        // nLoSが除外されている（5個に1個がnLoSなので、約16個残るはず）
        #expect(!processed.isEmpty)
        #expect(processed.count < observations.count)

        // 全てLoSのはず
        for obs in processed {
            #expect(obs.quality.isLineOfSight)
        }
    }

    @Test("nLoSフィルタが無効の場合、全データが残る")
    func nLOSFilterDisabled() {
        let config = SensorDataProcessingConfig(
            firstTrim: 0,
            endTrim: 0,
            movingAverageWindowSize: 1,
            filterNLOS: false
        )
        let processor = SensorDataProcessor(config: config)

        let observations = self.createTestObservations(count: 20)
        let processed = processor.processObservations(observations)

        // フィルタが無効なので全データが残る
        #expect(processed.count == observations.count)
    }

    // MARK: - Statistics Tests

    @Test("統計情報が正しく計算される")
    func statistics() {
        let config = SensorDataProcessingConfig(
            firstTrim: 5,
            endTrim: 5,
            movingAverageWindowSize: 3,
            filterNLOS: false
        )
        let processor = SensorDataProcessor(config: config)

        let original = self.createTestObservations(count: 30)
        let processed = processor.processObservations(original)

        let stats = processor.calculateStatistics(original: original, processed: processed)

        #expect(stats.originalCount == 30)
        #expect(stats.processedCount == processed.count)
        #expect(stats.trimmedCount == 30 - processed.count)
        #expect(stats.trimRate > 0)
        #expect(stats.trimRate <= 1.0)
    }

    @Test("標準偏差の改善が計算される")
    func standardDeviationImprovement() {
        let config = SensorDataProcessingConfig(
            firstTrim: 0,
            endTrim: 0,
            movingAverageWindowSize: 5,
            filterNLOS: false
        )
        let processor = SensorDataProcessor(config: config)

        let original = self.createTestObservations(count: 50)
        let processed = processor.processObservations(original)

        let stats = processor.calculateStatistics(original: original, processed: processed)

        // 移動平均により標準偏差が減少するはず
        #expect(stats.processedStdDev <= stats.originalStdDev)
        #expect(stats.stdDevImprovement >= 0)
    }

    // MARK: - applyMovingAverageToPoints Tests

    @Test("Point3Dリストへの移動平均が正しく動作する")
    func testApplyMovingAverageToPoints() {
        let config = SensorDataProcessingConfig(
            firstTrim: 0,
            endTrim: 0,
            movingAverageWindowSize: 3,
            filterNLOS: false
        )
        let processor = SensorDataProcessor(config: config)

        let points = [
            Point3D(x: 0, y: 0, z: 0),
            Point3D(x: 1, y: 1, z: 0),
            Point3D(x: 2, y: 2, z: 0),
            Point3D(x: 3, y: 3, z: 0),
            Point3D(x: 4, y: 4, z: 0),
        ]

        let smoothed = processor.applyMovingAverageToPoints(points)

        #expect(smoothed.count == 5)

        // インデックス2の位置は (0+1+2)/3 = 1.0のはず
        #expect(smoothed[2].x == 1.0)
        #expect(smoothed[2].y == 1.0)

        // インデックス4の位置は (2+3+4)/3 = 3.0のはず
        #expect(smoothed[4].x == 3.0)
        #expect(smoothed[4].y == 3.0)
    }

    // MARK: - Integration Tests

    @Test("完全な処理パイプラインが正しく動作する")
    func fullProcessingPipeline() {
        let config = SensorDataProcessingConfig(
            firstTrim: 10,
            endTrim: 10,
            movingAverageWindowSize: 5,
            filterNLOS: true
        )
        let processor = SensorDataProcessor(config: config)

        let original = self.createTestObservations(count: 100)
        let processed = processor.processObservations(original)

        // データが処理されている
        #expect(!processed.isEmpty)
        #expect(processed.count < original.count)

        // 全てLoSのはず
        for obs in processed {
            #expect(obs.quality.isLineOfSight)
        }

        // 統計情報を確認
        let stats = processor.calculateStatistics(original: original, processed: processed)
        #expect(stats.originalCount == 100)
        #expect(stats.processedCount == processed.count)
        #expect(stats.trimRate > 0)
    }
}
