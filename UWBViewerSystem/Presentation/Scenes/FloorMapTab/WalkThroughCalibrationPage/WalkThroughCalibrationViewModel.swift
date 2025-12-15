//
//  WalkThroughCalibrationViewModel.swift
//  UWBViewerSystem
//
//  Walk-throughキャリブレーション画面のViewModel
//

import Combine
import Foundation
import SwiftData
import SwiftUI

/// Walk-through キャリブレーション画面のViewModel
@MainActor
class WalkThroughCalibrationViewModel: ObservableObject {

    // MARK: - Published Properties

    /// 現在のフェーズ
    @Published var currentPhase: WalkThroughPhase = .ready

    /// 歩行軌跡（リアルタイム表示用）
    @Published var trajectoryPoints: [CGPoint] = []

    /// UWB観測点（リアルタイム表示用）
    @Published var uwbPoints: [UWBDisplayPoint] = []

    /// 歩数
    @Published var stepCount: Int = 0

    /// 歩行距離（メートル）
    @Published var walkDistance: Double = 0.0

    /// 経過時間
    @Published var elapsedTime: TimeInterval = 0.0

    /// 現在の方位（度）
    @Published var currentHeadingDegrees: Double = 0.0

    /// 現在の加速度（G）
    @Published var currentAccelerationG: Double = 0.0

    /// UWB観測数
    @Published var uwbObservationCount: Int = 0

    /// キャリブレーション結果
    @Published var calibrationResult: WalkThroughCalibrationUsecase.WalkThroughCalibrationResult?

    /// エラーメッセージ
    @Published var errorMessage: String = ""
    @Published var showErrorAlert: Bool = false

    /// 警告メッセージ
    @Published var warningMessages: [String] = []

    /// フロアマップ情報
    @Published var currentFloorMapInfo: FloorMapInfo?
    @Published var floorMapImage: UIImage?

    /// CoreMotionが利用可能か
    @Published var isMotionAvailable: Bool = false

    // MARK: - Types

    /// Walk-throughのフェーズ
    enum WalkThroughPhase: String {
        case ready = "準備完了"
        case walking = "歩行中"
        case processing = "処理中"
        case completed = "完了"
        case failed = "失敗"

        var description: String {
            switch self {
            case .ready:
                return "「開始」ボタンを押してから歩き始めてください"
            case .walking:
                return "部屋の中を歩いてください（30秒〜1分推奨）"
            case .processing:
                return "データを処理中です..."
            case .completed:
                return "キャリブレーションが完了しました"
            case .failed:
                return "キャリブレーションに失敗しました"
            }
        }

        var iconName: String {
            switch self {
            case .ready:
                return "figure.walk"
            case .walking:
                return "figure.walk.motion"
            case .processing:
                return "gear"
            case .completed:
                return "checkmark.circle.fill"
            case .failed:
                return "xmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .ready:
                return .blue
            case .walking:
                return .green
            case .processing:
                return .orange
            case .completed:
                return .green
            case .failed:
                return .red
            }
        }
    }

    /// UWB観測点の表示用データ
    struct UWBDisplayPoint: Identifiable {
        let id = UUID()
        let point: CGPoint
        let antennaId: String
        let isLineOfSight: Bool
    }

    // MARK: - Dependencies

    private var walkThroughUsecase: WalkThroughCalibrationUsecase?
    private var coreMotionManager: CoreMotionManager?
    private var realtimeDataUsecase: RealtimeDataUsecase?
    private var swiftDataRepository: SwiftDataRepository?
    private var sensingControlUsecase: SensingControlUsecase?
    private var cancellables = Set<AnyCancellable>()
    private var updateTimer: Timer?
    private var walkStartTime: Date?

    /// フロアマップID
    private var floorMapId: String = ""

    /// 前回のUWBデータ数（重複防止用）
    private var lastProcessedDataCounts: [String: Int] = [:]

    // MARK: - Initialization

    init() {}

    // MARK: - Public Methods

    /// セットアップ
    func setup(modelContext: ModelContext, floorMapId: String) {
        self.floorMapId = floorMapId

        // リポジトリとUsecaseの初期化
        self.swiftDataRepository = SwiftDataRepository(modelContext: modelContext)

        if let repository = self.swiftDataRepository {
            self.walkThroughUsecase = WalkThroughCalibrationUsecase(
                swiftDataRepository: repository
            )

            // SensingControlUsecaseの初期化
            self.sensingControlUsecase = SensingControlUsecase(
                connectionUsecase: ConnectionManagementUsecase.shared,
                swiftDataRepository: repository
            )

            // RealtimeDataUsecaseを初期化してConnectionManagementUsecaseに設定
            let realtimeUsecase = RealtimeDataUsecase(
                swiftDataRepository: repository,
                sensingControlUsecase: self.sensingControlUsecase
            )
            self.realtimeDataUsecase = realtimeUsecase

            // ConnectionManagementUsecaseにRealtimeDataUsecaseを設定
            // これによりUWBデータがRealtimeDataUsecaseに転送される
            ConnectionManagementUsecase.shared.setRealtimeDataUsecase(realtimeUsecase)
        }

        // CoreMotionManagerの初期化
        self.coreMotionManager = CoreMotionManager()
        self.isMotionAvailable = self.coreMotionManager?.isAvailable ?? false

        // フロアマップ情報の読み込み
        Task {
            await self.loadFloorMapInfo()
        }

        // CoreMotionの監視設定
        self.setupCoreMotionObservers()

        // UWBデータの監視設定
        self.setupUWBDataObservers()

        print("✅ WalkThroughCalibrationViewModel セットアップ完了")
    }

    /// Walk-through開始
    func startWalkThrough() {
        guard self.currentPhase == .ready || self.currentPhase == .failed else {
            print("⚠️ Walk-throughを開始できません: 現在のフェーズ = \(self.currentPhase.rawValue)")
            return
        }

        guard self.isMotionAvailable else {
            self.errorMessage = "モーションセンサーが利用できません"
            self.showErrorAlert = true
            return
        }

        // 状態をリセット
        self.trajectoryPoints.removeAll()
        self.uwbPoints.removeAll()
        self.stepCount = 0
        self.walkDistance = 0.0
        self.elapsedTime = 0.0
        self.uwbObservationCount = 0
        self.warningMessages.removeAll()
        self.calibrationResult = nil
        self.lastProcessedDataCounts.removeAll()

        // Walk-through開始
        self.currentPhase = .walking
        self.walkStartTime = Date()

        // CoreMotion記録開始
        self.coreMotionManager?.startRecording()

        // UWBリモートセンシング開始（Android端末にセンシング開始コマンドを送信）
        let sensingFileName = "walkthrough_calibration_\(Date().timeIntervalSince1970)"
        self.sensingControlUsecase?.startRemoteSensing(fileName: sensingFileName)

        // Usecase開始
        Task {
            await self.walkThroughUsecase?.startWalkThrough()
        }

        // 更新タイマー開始
        self.startUpdateTimer()

        print("🚶 Walk-through開始（UWBセンシング開始）")
    }

    /// Walk-through停止
    func stopWalkThrough() {
        guard self.currentPhase == .walking else {
            print("⚠️ Walk-throughを停止できません: 現在のフェーズ = \(self.currentPhase.rawValue)")
            return
        }

        self.currentPhase = .processing
        self.stopUpdateTimer()

        // UWBリモートセンシング停止
        self.sensingControlUsecase?.stopRemoteSensing()

        // CoreMotion記録停止
        guard let imuResult = self.coreMotionManager?.stopRecording() else {
            self.currentPhase = .failed
            self.errorMessage = "IMUデータの取得に失敗しました"
            self.showErrorAlert = true
            return
        }

        print("🛑 Walk-through停止: IMUサンプル数 = \(imuResult.sampleCount)")

        // キャリブレーション実行
        Task {
            await self.executeCalibration(imuResult: imuResult)
        }
    }

    /// キャリブレーションをリセット
    func resetCalibration() {
        self.stopUpdateTimer()
        _ = self.coreMotionManager?.stopRecording()

        // UWBリモートセンシング停止（もし実行中の場合）
        self.sensingControlUsecase?.stopRemoteSensing()

        self.currentPhase = .ready
        self.trajectoryPoints.removeAll()
        self.uwbPoints.removeAll()
        self.stepCount = 0
        self.walkDistance = 0.0
        self.elapsedTime = 0.0
        self.warningMessages.removeAll()
        self.calibrationResult = nil

        Task {
            await self.walkThroughUsecase?.clearData()
        }

        print("🔄 キャリブレーションをリセット")
    }

    /// キャリブレーション結果を保存
    func saveCalibrationResults() async {
        guard let result = self.calibrationResult, result.success else {
            self.errorMessage = "保存するキャリブレーション結果がありません"
            self.showErrorAlert = true
            return
        }

        do {
            try await self.walkThroughUsecase?.saveCalibrationResults(
                floorMapId: self.floorMapId,
                results: result.antennaConfigs
            )
            print("💾 キャリブレーション結果を保存しました")
        } catch {
            self.errorMessage = "保存に失敗しました: \(error.localizedDescription)"
            self.showErrorAlert = true
        }
    }

    /// UWB観測データを追加（外部から呼ばれる）
    func addUWBObservation(
        antennaId: String,
        position: Point3D,
        quality: SignalQuality
    ) {
        guard self.currentPhase == .walking else { return }

        Task {
            await self.walkThroughUsecase?.addUWBObservation(
                antennaId: antennaId,
                position: position,
                quality: quality
            )
        }

        // 表示用に追加
        let displayPoint = UWBDisplayPoint(
            point: CGPoint(x: position.x, y: position.y),
            antennaId: antennaId,
            isLineOfSight: quality.isLineOfSight
        )
        self.uwbPoints.append(displayPoint)

        // 最新100点のみ保持
        if self.uwbPoints.count > 100 {
            self.uwbPoints.removeFirst()
        }

        self.uwbObservationCount += 1
    }

    // MARK: - Private Methods

    private func loadFloorMapInfo() async {
        do {
            if let floorMapInfo = try await self.swiftDataRepository?.loadFloorMap(
                by: self.floorMapId
            ) {
                self.currentFloorMapInfo = floorMapInfo
                self.floorMapImage = floorMapInfo.image
                print("📍 フロアマップ情報を読み込みました: \(floorMapInfo.name)")
            }
        } catch {
            print("❌ フロアマップ情報の読み込みに失敗: \(error)")
        }
    }

    private func setupCoreMotionObservers() {
        guard let motionManager = self.coreMotionManager else { return }

        motionManager.$stepCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.stepCount = count
            }
            .store(in: &self.cancellables)

        motionManager.$currentHeading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] heading in
                self?.currentHeadingDegrees = heading * 180 / .pi
            }
            .store(in: &self.cancellables)

        motionManager.$currentAccelerationG
            .receive(on: DispatchQueue.main)
            .sink { [weak self] accel in
                self?.currentAccelerationG = accel
            }
            .store(in: &self.cancellables)
    }

    /// UWBデータの監視設定
    private func setupUWBDataObservers() {
        guard let realtimeUsecase = self.realtimeDataUsecase else {
            print("⚠️ RealtimeDataUsecaseが初期化されていません")
            return
        }

        // アンテナ別データマップを監視
        realtimeUsecase.$antennaDataMap
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dataMap in
                self?.processUWBDataUpdate(dataMap)
            }
            .store(in: &self.cancellables)

        // グローバル座標を監視（統合位置）
        realtimeUsecase.$globalCoordinates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] coordinates in
                self?.processGlobalCoordinatesUpdate(coordinates)
            }
            .store(in: &self.cancellables)

        print("📡 UWBデータ監視を設定しました")
    }

    /// UWBデータ更新の処理
    private func processUWBDataUpdate(_ dataMap: [String: [DeviceRealtimeData]]) {
        guard self.currentPhase == .walking else { return }

        for (antennaId, deviceDataList) in dataMap {
            for deviceData in deviceDataList {
                guard let latestData = deviceData.latestData else { continue }

                // 新しいデータのみ処理（重複防止）
                let currentCount = deviceData.dataHistory.count
                let lastCount = self.lastProcessedDataCounts[antennaId] ?? 0

                if currentCount > lastCount {
                    self.lastProcessedDataCounts[antennaId] = currentCount

                    // 距離と方位から位置を計算（簡易的な座標変換）
                    let distance = latestData.distance
                    let azimuth = latestData.azimuth * .pi / 180.0  // 度からラジアンに変換
                    let elevation = latestData.elevation * .pi / 180.0

                    // 球面座標から直交座標への変換
                    let x = distance * cos(elevation) * sin(azimuth)
                    let y = distance * cos(elevation) * cos(azimuth)
                    let z = distance * sin(elevation)

                    let position = Point3D(x: x, y: y, z: z)

                    // 信号品質の作成
                    let isLoS = latestData.nlos == 0
                    let rssiNormalized = min(max((latestData.rssi + 100) / 60.0, 0.0), 1.0)  // -100〜-40dBmを0〜1に正規化
                    let quality = SignalQuality(
                        strength: rssiNormalized,
                        isLineOfSight: isLoS,
                        confidenceLevel: isLoS ? 0.9 : 0.5,
                        errorEstimate: isLoS ? 0.1 : 0.3
                    )

                    // UWB観測を追加
                    self.addUWBObservation(
                        antennaId: antennaId,
                        position: position,
                        quality: quality
                    )
                }
            }
        }
    }

    /// グローバル座標更新の処理
    private func processGlobalCoordinatesUpdate(_ coordinates: [String: Point3D]) {
        guard self.currentPhase == .walking else { return }

        // グローバル座標を使用してUWB観測を追加
        // この座標はアンテナ位置を基準とした座標系に変換済み
        for (deviceName, position) in coordinates {
            // デバイス名からアンテナIDを取得（ConnectionManagementUsecaseから）
            if let antennaId = self.getAntennaIdForDevice(deviceName) {
                // 簡易的な信号品質（グローバル座標の場合はLoSと仮定）
                let quality = SignalQuality(
                    strength: 0.8,
                    isLineOfSight: true,
                    confidenceLevel: 0.85,
                    errorEstimate: 0.15
                )

                self.addUWBObservation(
                    antennaId: antennaId,
                    position: position,
                    quality: quality
                )
            }
        }
    }

    /// デバイス名からアンテナIDを取得
    /// antennaPairingsは[アンテナID: デバイス名]の辞書なので逆引きする
    private func getAntennaIdForDevice(_ deviceName: String) -> String? {
        let pairings = ConnectionManagementUsecase.shared.antennaPairings
        // 値（デバイス名）が一致するキー（アンテナID）を返す
        return pairings.first(where: { $0.value == deviceName })?.key
    }

    private func startUpdateTimer() {
        self.updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.updateElapsedTime()
            }
        }
    }

    private func stopUpdateTimer() {
        self.updateTimer?.invalidate()
        self.updateTimer = nil
    }

    private func updateElapsedTime() {
        guard let startTime = self.walkStartTime else { return }
        self.elapsedTime = Date().timeIntervalSince(startTime)

        // 推定歩行距離を更新（歩数 × 0.7m）
        self.walkDistance = Double(self.stepCount) * 0.7
    }

    private func executeCalibration(imuResult: IMURecordingResult) async {
        do {
            guard let result = try await self.walkThroughUsecase?.stopWalkThrough(imuResult: imuResult)
            else {
                throw WalkThroughCalibrationUsecase.WalkThroughError.notCalibrating
            }

            self.calibrationResult = result
            self.warningMessages = result.warnings

            if result.success {
                self.currentPhase = .completed
                print("✅ キャリブレーション成功: \(result.antennaConfigs.count)アンテナ")
            } else {
                self.currentPhase = .failed
                self.errorMessage = result.warnings.first ?? "キャリブレーションに失敗しました"
                self.showErrorAlert = true
            }
        } catch {
            self.currentPhase = .failed
            self.errorMessage = error.localizedDescription
            self.showErrorAlert = true
            print("❌ キャリブレーション失敗: \(error)")
        }
    }
}
