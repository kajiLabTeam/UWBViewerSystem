import SwiftUI
import Foundation
import Combine

@MainActor
class CalibrationViewModel: ObservableObject {
    @Published var calibrationState: CalibrationState = .idle
    @Published var calibrationProgress: Int = 0
    @Published var calibrationPairs: [CalibrationPair] = []
    @Published var currentCalibrationStep: CalibrationStep?
    @Published var errorMessage: String?
    @Published var isCompleted: Bool = false
    
    private var antennaPositions: [AntennaPositionData] = []
    private var calibrationTimer: Timer?
    private var currentPairIndex: Int = 0
    
    var canProceed: Bool {
        isCompleted || calibrationState == .completed
    }
    
    func initialize() {
        loadAntennaPositions()
        generateCalibrationPairs()
        setupInitialStep()
    }
    
    private func loadAntennaPositions() {
        if let data = UserDefaults.standard.data(forKey: "AntennaPositions"),
           let decoded = try? JSONDecoder().decode([AntennaPositionData].self, from: data) {
            antennaPositions = decoded
        }
    }
    
    private func generateCalibrationPairs() {
        calibrationPairs = []
        
        for i in 0..<antennaPositions.count {
            for j in (i+1)..<antennaPositions.count {
                let antenna1 = antennaPositions[i]
                let antenna2 = antennaPositions[j]
                
                let pair = CalibrationPair(
                    id: "\(antenna1.deviceId)-\(antenna2.deviceId)",
                    antenna1Id: antenna1.deviceId,
                    antenna1Name: antenna1.deviceName,
                    antenna2Id: antenna2.deviceId,
                    antenna2Name: antenna2.deviceName,
                    theoreticalDistance: calculateDistance(
                        from: antenna1.realWorldPosition,
                        to: antenna2.realWorldPosition
                    ),
                    status: .pending
                )
                
                calibrationPairs.append(pair)
            }
        }
    }
    
    private func setupInitialStep() {
        currentCalibrationStep = CalibrationStep(
            title: "キャリブレーションの準備",
            description: "すべてのUWBアンテナが正常に接続されていることを確認し、測定エリアに障害物がないことを確認してください。"
        )
    }
    
    private func calculateDistance(from pos1: RealWorldPosition, to pos2: RealWorldPosition) -> Double {
        let dx = pos1.x - pos2.x
        let dy = pos1.y - pos2.y
        let dz = pos1.z - pos2.z
        return sqrt(dx*dx + dy*dy + dz*dz)
    }
    
    func startCalibration() {
        calibrationState = .running
        currentPairIndex = 0
        calibrationProgress = 0
        errorMessage = nil
        
        // 全てのペアを pending 状態に戻す
        for index in calibrationPairs.indices {
            calibrationPairs[index].status = .pending
            calibrationPairs[index].measuredDistance = nil
        }
        
        currentCalibrationStep = CalibrationStep(
            title: "キャリブレーション実行中",
            description: "アンテナペア間の距離測定を実行しています。測定が完了するまでお待ちください。"
        )
        
        startNextMeasurement()
    }
    
    private func startNextMeasurement() {
        guard currentPairIndex < calibrationPairs.count else {
            completeCalibration()
            return
        }
        
        // 現在のペアを測定中状態に変更
        calibrationPairs[currentPairIndex].status = .measuring
        
        // シミュレートされた測定（実際の実装では実際のUWB測定を行う）
        calibrationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.completeMeasurement()
        }
    }
    
    private func completeMeasurement() {
        guard currentPairIndex < calibrationPairs.count else { return }
        
        let pair = calibrationPairs[currentPairIndex]
        
        // シミュレートされた測定結果（実際の実装では実際の測定値を使用）
        let theoreticalDistance = pair.theoreticalDistance
        let measurementError = Double.random(in: -0.1...0.1) // ±10cm の誤差
        let measuredDistance = theoreticalDistance + measurementError
        
        // 測定結果が理論値から大きく異なる場合はエラーとする
        if abs(measuredDistance - theoreticalDistance) > 0.5 { // 50cm以上の誤差
            calibrationPairs[currentPairIndex].status = .failed
            calibrationState = .error
            errorMessage = "測定値が理論値から大きく異なります。アンテナの配置や環境を確認してください。"
            return
        }
        
        // 正常な測定結果を記録
        calibrationPairs[currentPairIndex].measuredDistance = measuredDistance
        calibrationPairs[currentPairIndex].status = .completed
        
        // 進捗を更新
        currentPairIndex += 1
        calibrationProgress = Int((Double(currentPairIndex) / Double(calibrationPairs.count)) * 100)
        
        // 次の測定に進む
        startNextMeasurement()
    }
    
    private func completeCalibration() {
        calibrationState = .completed
        isCompleted = true
        calibrationProgress = 100
        calibrationTimer?.invalidate()
        
        currentCalibrationStep = CalibrationStep(
            title: "キャリブレーション完了",
            description: "すべてのアンテナペアの距離測定が完了しました。次の画面でセンシングを開始できます。"
        )
        
        saveCalibrationResults()
    }
    
    func stopCalibration() {
        calibrationState = .idle
        calibrationTimer?.invalidate()
        
        // 測定中だったペアを pending に戻す
        if currentPairIndex < calibrationPairs.count {
            calibrationPairs[currentPairIndex].status = .pending
        }
        
        setupInitialStep()
    }
    
    func retryCalibration() {
        calibrationState = .idle
        calibrationTimer?.invalidate()
        errorMessage = nil
        setupInitialStep()
    }
    
    func restartCalibration() {
        calibrationState = .idle
        isCompleted = false
        calibrationTimer?.invalidate()
        setupInitialStep()
    }
    
    func skipCalibration() {
        calibrationState = .completed
        isCompleted = true
        calibrationProgress = 100
        
        // スキップした場合の理論値をそのまま使用
        for index in calibrationPairs.indices {
            calibrationPairs[index].measuredDistance = calibrationPairs[index].theoreticalDistance
            calibrationPairs[index].status = .completed
        }
        
        saveCalibrationResults()
    }
    
    private func saveCalibrationResults() {
        let results = calibrationPairs.map { pair in
            CalibrationResult(
                antenna1Id: pair.antenna1Id,
                antenna2Id: pair.antenna2Id,
                theoreticalDistance: pair.theoreticalDistance,
                measuredDistance: pair.measuredDistance ?? pair.theoreticalDistance,
                accuracy: calculateAccuracy(
                    theoretical: pair.theoreticalDistance,
                    measured: pair.measuredDistance ?? pair.theoreticalDistance
                ),
                calibrationDate: Date()
            )
        }
        
        if let encoded = try? JSONEncoder().encode(results) {
            UserDefaults.standard.set(encoded, forKey: "CalibrationResults")
        }
    }
    
    private func calculateAccuracy(theoretical: Double, measured: Double) -> Double {
        let error = abs(theoretical - measured)
        let accuracy = max(0, (1.0 - (error / theoretical)) * 100)
        return accuracy
    }
}

// MARK: - Data Models
enum CalibrationState {
    case idle
    case running
    case completed
    case error
}

enum CalibrationStatus {
    case pending
    case measuring
    case completed
    case failed
}

struct CalibrationPair: Identifiable {
    let id: String
    let antenna1Id: String
    let antenna1Name: String
    let antenna2Id: String
    let antenna2Name: String
    let theoreticalDistance: Double
    var measuredDistance: Double?
    var status: CalibrationStatus
}

struct CalibrationStep {
    let title: String
    let description: String
}

struct CalibrationResult: Codable {
    let antenna1Id: String
    let antenna2Id: String
    let theoreticalDistance: Double
    let measuredDistance: Double
    let accuracy: Double
    let calibrationDate: Date
}