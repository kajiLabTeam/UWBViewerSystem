//
//  IMUData.swift
//  UWBViewerSystem
//
//  IMUセンサーデータのモデル
//

import CoreMotion
import Foundation

/// IMUデータポイント（加速度・ジャイロスコープ）
public struct IMUDataPoint: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date

    /// 加速度 (m/s²)
    public let accelerationX: Double
    public let accelerationY: Double
    public let accelerationZ: Double

    /// 角速度 (rad/s)
    public let rotationRateX: Double
    public let rotationRateY: Double
    public let rotationRateZ: Double

    /// 姿勢角 (rad)
    public let pitch: Double
    public let roll: Double
    public let yaw: Double

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        accelerationX: Double,
        accelerationY: Double,
        accelerationZ: Double,
        rotationRateX: Double,
        rotationRateY: Double,
        rotationRateZ: Double,
        pitch: Double = 0,
        roll: Double = 0,
        yaw: Double = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.accelerationX = accelerationX
        self.accelerationY = accelerationY
        self.accelerationZ = accelerationZ
        self.rotationRateX = rotationRateX
        self.rotationRateY = rotationRateY
        self.rotationRateZ = rotationRateZ
        self.pitch = pitch
        self.roll = roll
        self.yaw = yaw
    }

    /// 加速度の大きさ (m/s²)
    public var accelerationMagnitude: Double {
        sqrt(
            self.accelerationX * self.accelerationX + self.accelerationY * self.accelerationY
                + self.accelerationZ * self.accelerationZ)
    }

    /// 加速度の大きさ (G単位)
    public var accelerationMagnitudeInG: Double {
        self.accelerationMagnitude / 9.81
    }

    /// CMDeviceMotionから初期化
    public init(from motion: CMDeviceMotion, timestamp: Date) {
        self.id = UUID()
        self.timestamp = timestamp
        // ユーザー加速度 + 重力を含む全加速度
        self.accelerationX = motion.userAcceleration.x * 9.81
        self.accelerationY = motion.userAcceleration.y * 9.81
        self.accelerationZ = motion.userAcceleration.z * 9.81
        self.rotationRateX = motion.rotationRate.x
        self.rotationRateY = motion.rotationRate.y
        self.rotationRateZ = motion.rotationRate.z
        self.pitch = motion.attitude.pitch
        self.roll = motion.attitude.roll
        self.yaw = motion.attitude.yaw
    }
}

/// IMU記録結果
public struct IMURecordingResult: Sendable {
    public let dataPoints: [IMUDataPoint]
    public let duration: TimeInterval
    public let sampleCount: Int
    public let averageSampleRate: Double

    public init(
        dataPoints: [IMUDataPoint],
        duration: TimeInterval,
        sampleCount: Int,
        averageSampleRate: Double
    ) {
        self.dataPoints = dataPoints
        self.duration = duration
        self.sampleCount = sampleCount
        self.averageSampleRate = averageSampleRate
    }
}
