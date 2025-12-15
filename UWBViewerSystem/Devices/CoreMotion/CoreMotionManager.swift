//
//  CoreMotionManager.swift
//  UWBViewerSystem
//
//  CoreMotionを使用したIMUデータの取得・管理
//

import Combine
import CoreMotion
import Foundation

/// CoreMotionデータ管理クラス
@MainActor
public class CoreMotionManager: ObservableObject {
    // MARK: - Published Properties

    /// CoreMotionが利用可能かどうか
    @Published public private(set) var isAvailable: Bool = false

    /// 現在記録中かどうか
    @Published public private(set) var isRecording: Bool = false

    /// 現在の歩数（記録開始からの累計）
    @Published public private(set) var stepCount: Int = 0

    /// 現在の方位（ラジアン）
    @Published public private(set) var currentHeading: Double = 0.0

    /// 現在の加速度の大きさ（G単位）
    @Published public private(set) var currentAccelerationG: Double = 0.0

    /// エラーメッセージ
    @Published public private(set) var errorMessage: String?

    // MARK: - Private Properties

    private let motionManager = CMMotionManager()
    private let pedometer = CMPedometer()
    private var imuDataBuffer: [IMUDataPoint] = []
    private var recordingStartTime: Date?

    /// 更新頻度（100Hz）
    private let updateInterval: TimeInterval = 1.0 / 100.0

    /// 歩数検出用の状態
    private var lastStepDetectionTime: Date?
    private var peakDetectionState: PeakDetectionState = .lookingForPeak

    /// 歩数検出の設定
    private let stepDetectionThreshold: Double = 1.2  // G
    private let minStepInterval: TimeInterval = 0.3  // 秒

    private enum PeakDetectionState {
        case lookingForPeak
        case lookingForValley
    }

    // MARK: - Initialization

    public init() {
        self.checkAvailability()
    }

    // MARK: - Public Methods

    /// IMUデータの記録を開始
    public func startRecording() {
        guard self.isAvailable, !self.isRecording else { return }

        self.imuDataBuffer.removeAll()
        self.stepCount = 0
        self.recordingStartTime = Date()
        self.lastStepDetectionTime = nil
        self.peakDetectionState = .lookingForPeak
        self.errorMessage = nil

        self.motionManager.deviceMotionUpdateInterval = self.updateInterval
        self.motionManager.startDeviceMotionUpdates(
            using: .xArbitraryCorrectedZVertical,
            to: OperationQueue()
        ) { [weak self] motion, error in
            if let error {
                Task { @MainActor in
                    self?.errorMessage = error.localizedDescription
                }
                return
            }

            guard let motion else { return }

            Task { @MainActor in
                self?.processMotionData(motion)
            }
        }

        self.isRecording = true
    }

    /// IMUデータの記録を停止し、結果を返す
    public func stopRecording() -> IMURecordingResult {
        self.motionManager.stopDeviceMotionUpdates()
        self.isRecording = false

        let endTime = Date()
        let duration = self.recordingStartTime.map { endTime.timeIntervalSince($0) } ?? 0
        let sampleCount = self.imuDataBuffer.count
        let averageSampleRate = duration > 0 ? Double(sampleCount) / duration : 0

        let result = IMURecordingResult(
            dataPoints: self.imuDataBuffer,
            duration: duration,
            sampleCount: sampleCount,
            averageSampleRate: averageSampleRate
        )

        return result
    }

    /// 現在バッファされているIMUデータを取得（記録を継続）
    public func getCurrentBuffer() -> [IMUDataPoint] {
        self.imuDataBuffer
    }

    /// バッファをクリア
    public func clearBuffer() {
        self.imuDataBuffer.removeAll()
    }

    // MARK: - Private Methods

    private func checkAvailability() {
        self.isAvailable = self.motionManager.isDeviceMotionAvailable
    }

    private func processMotionData(_ motion: CMDeviceMotion) {
        let timestamp = Date()
        let dataPoint = IMUDataPoint(from: motion, timestamp: timestamp)

        self.imuDataBuffer.append(dataPoint)

        // UI更新用のプロパティを更新
        self.currentAccelerationG = dataPoint.accelerationMagnitudeInG
        self.currentHeading = motion.attitude.yaw

        // 歩数検出
        self.detectStep(accelerationG: dataPoint.accelerationMagnitudeInG, timestamp: timestamp)
    }

    /// 加速度ピーク検出による歩数カウント
    private func detectStep(accelerationG: Double, timestamp: Date) {
        // 最小間隔チェック
        if let lastTime = self.lastStepDetectionTime {
            if timestamp.timeIntervalSince(lastTime) < self.minStepInterval {
                return
            }
        }

        switch self.peakDetectionState {
        case .lookingForPeak:
            if accelerationG > self.stepDetectionThreshold {
                self.peakDetectionState = .lookingForValley
            }

        case .lookingForValley:
            if accelerationG < self.stepDetectionThreshold * 0.8 {
                // 歩数検出
                self.stepCount += 1
                self.lastStepDetectionTime = timestamp
                self.peakDetectionState = .lookingForPeak
            }
        }
    }
}

// MARK: - Extension for Testing

extension CoreMotionManager {
    /// テスト用: 手動でIMUデータを追加
    public func addTestDataPoint(_ dataPoint: IMUDataPoint) {
        self.imuDataBuffer.append(dataPoint)
    }
}
