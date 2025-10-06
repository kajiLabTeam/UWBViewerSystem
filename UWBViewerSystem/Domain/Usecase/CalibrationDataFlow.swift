import Foundation
import os.log
import SwiftUI

/// キャリブレーションデータフローを管理するクラス
/// 段階的キャリブレーションのステップ
public enum StepByStepCalibrationStep {
    case idle  // 未開始
    case placingTag  // タグを配置する段階
    case readyToStart  // センシング開始可能
    case collecting  // データ収集中
    case showingAntennaPosition  // アンテナ位置を表示中
    case completed  // 全て完了
    case failed  // エラー発生
}

@MainActor
public class CalibrationDataFlow: ObservableObject {

    // MARK: - Published Properties

    @Published public var currentWorkflow: CalibrationWorkflowStatus = .idle
    @Published public var referencePoints: [MapCalibrationPoint] = []
    @Published public var observationSessions: [String: ObservationSession] = [:]  // antennaId -> session
    @Published public var mappings: [ReferenceObservationMapping] = []
    @Published public var workflowProgress: Double = 0.0
    @Published public var errorMessage: String?
    @Published public var lastCalibrationResult: CalibrationWorkflowResult?

    // 段階的キャリブレーション用プロパティ
    @Published public var currentReferencePointIndex: Int = 0
    @Published public var totalReferencePoints: Int = 0
    @Published public var isCollectingForCurrentPoint: Bool = false
    @Published public var currentStepInstructions: String = ""
    @Published public var calibrationStepProgress: Double = 0.0
    @Published public var finalAntennaPositions: [String: Point3D] = [:]
    @Published public var currentStep: StepByStepCalibrationStep = .idle
    @Published public var estimatedAntennaPosition: Point3D? = nil  // 推定アンテナ位置

    // MARK: - Private Properties

    private let dataRepository: DataRepositoryProtocol
    private let calibrationUsecase: CalibrationUsecase
    private let observationUsecase: ObservationDataUsecase
    public let realtimeDataUsecase: RealtimeDataUsecase
    private let swiftDataRepository: SwiftDataRepositoryProtocol?
    private let sensingControlUsecase: SensingControlUsecase?
    private let connectionManagement: ConnectionManagementUsecase?
    private let preferenceRepository: PreferenceRepositoryProtocol
    private let logger = Logger(subsystem: "com.uwbviewer.system", category: "calibration-dataflow")

    // MARK: - Initialization

    public init(
        dataRepository: DataRepositoryProtocol,
        calibrationUsecase: CalibrationUsecase,
        observationUsecase: ObservationDataUsecase,
        realtimeDataUsecase: RealtimeDataUsecase? = nil,
        swiftDataRepository: SwiftDataRepositoryProtocol? = nil,
        sensingControlUsecase: SensingControlUsecase? = nil,
        connectionManagement: ConnectionManagementUsecase? = nil,
        preferenceRepository: PreferenceRepositoryProtocol = PreferenceRepository()
    ) {
        self.dataRepository = dataRepository
        self.calibrationUsecase = calibrationUsecase
        self.observationUsecase = observationUsecase
        self.realtimeDataUsecase = realtimeDataUsecase ?? RealtimeDataUsecase()
        self.swiftDataRepository = swiftDataRepository
        self.sensingControlUsecase = sensingControlUsecase
        self.connectionManagement = connectionManagement
        self.preferenceRepository = preferenceRepository
    }

    // MARK: - 1. 基準データ取得

    /// マップから基準座標を取得
    /// - Parameter points: マップ上で指定された基準座標
    public func collectReferencePoints(from points: [MapCalibrationPoint]) {
        self.referencePoints = points
        self.currentWorkflow = .collectingReference
        self.updateProgress()

        self.logger.info("基準座標を収集: \(points.count)個の点")
        for point in points {
            self.logger.debug(
                "座標: (\(point.realWorldCoordinate.x), \(point.realWorldCoordinate.y), \(point.realWorldCoordinate.z))")
        }
    }

    /// 手動で基準座標を追加
    /// - Parameters:
    ///   - position: 基準座標
    ///   - name: 座標の名前
    public func addReferencePoint(position: Point3D, name: String) {
        let point = MapCalibrationPoint(
            mapCoordinate: Point3D(x: 0, y: 0, z: 0),  // マップベースでない場合は(0,0,0)
            realWorldCoordinate: position,
            antennaId: "",  // 手動追加の場合は空文字
            pointIndex: referencePoints.count + 1
        )
        self.referencePoints.append(point)
        self.updateProgress()
    }

    // MARK: - 2. 観測データ取得

    /// 指定されたアンテナから観測データを収集開始
    /// - Parameter antennaId: 観測対象のアンテナID
    public func startObservationData(for antennaId: String) async {
        self.currentWorkflow = .collectingObservation

        do {
            let session = try await observationUsecase.startObservationSession(
                for: antennaId,
                name: "キャリブレーション観測_\(Date().timeIntervalSince1970)"
            )
            self.observationSessions[antennaId] = session
            self.updateProgress()

            self.logger.info("観測データ収集開始: アンテナ \(antennaId)")
        } catch {
            self.errorMessage = "観測データ収集の開始に失敗しました: \(error.localizedDescription)"
            self.currentWorkflow = .failed
        }
    }

    /// 観測データ収集を停止
    /// - Parameter antennaId: 観測対象のアンテナID
    public func stopObservationData(for antennaId: String) async {
        guard let session = observationSessions[antennaId] else { return }

        do {
            let completedSession = try await observationUsecase.stopObservationSession(session.id)
            self.observationSessions[antennaId] = completedSession
            self.updateProgress()

            self.logger.info("観測データ収集停止: アンテナ \(antennaId), データ点数: \(completedSession.observations.count)")
        } catch {
            self.errorMessage = "観測データ収集の停止に失敗しました: \(error.localizedDescription)"
        }
    }

    // MARK: - 3. 誤差算出とマッピング

    /// 基準座標と観測データをマッピング
    public func mapObservationsToReferences() -> [(reference: Point3D, observation: Point3D)] {
        self.currentWorkflow = .calculating
        self.mappings.removeAll()

        var mappedPairs: [(reference: Point3D, observation: Point3D)] = []

        // 各基準点に対して最も近い観測データを見つける
        for referencePoint in self.referencePoints {
            var bestMappings: [ObservationPoint] = []
            var minDistance = Double.infinity

            // 全てのアンテナの観測データから最適な点を探す
            for session in self.observationSessions.values {
                let validObservations = session.observations.filter { observation in
                    observation.quality.strength > 0.5  // 品質閾値
                        && observation.quality.isLineOfSight  // 見通し線が取れている
                }

                for observation in validObservations {
                    let distance = referencePoint.realWorldCoordinate.distance(to: observation.position)
                    if distance < minDistance && distance < 5.0 {  // 5m以内の観測点のみ考慮
                        minDistance = distance
                        bestMappings = [observation]
                    } else if abs(distance - minDistance) < 0.1 {  // 同程度の距離の場合は追加
                        bestMappings.append(observation)
                    }
                }
            }

            if !bestMappings.isEmpty {
                let mapping = ReferenceObservationMapping(
                    referencePosition: referencePoint.realWorldCoordinate,
                    observations: bestMappings
                )
                self.mappings.append(mapping)

                // マッピングペアを作成（重心を使用）
                mappedPairs.append(
                    (
                        reference: referencePoint.realWorldCoordinate,
                        observation: mapping.centroidPosition
                    ))

                self.logger.info(
                    "マッピング作成: 基準(\(referencePoint.realWorldCoordinate.x), \(referencePoint.realWorldCoordinate.y)) -> 観測(\(mapping.centroidPosition.x), \(mapping.centroidPosition.y)), 誤差: \(mapping.positionError)m"
                )
            }
        }

        self.updateProgress()
        return mappedPairs
    }

    // MARK: - 段階的キャリブレーション

    /// 段階的キャリブレーションを開始
    public func startStepByStepCalibration() async {
        guard !self.referencePoints.isEmpty else {
            self.logger.error("基準点が設定されていません")
            self.errorMessage = "基準点が設定されていません"
            self.currentWorkflow = .failed
            return
        }

        // 前回のリアルタイムデータとペアリング情報をクリア
        self.realtimeDataUsecase.clearAllRealtimeData()
        self.logger.info("🗑️ リアルタイムデータをクリアしました")

        // 接続済み端末をすべて切断して新しい接続に備える
        if let connectionMgmt = self.connectionManagement {
            connectionMgmt.resetAll()
            self.logger.info("🔌 接続済み端末をリセットしました")

            // iOS側で広告を開始し、Android側から発見・接続できるようにする
            connectionMgmt.startAdvertising()
            self.logger.info("📡 広告を開始しました（Android端末が接続できる状態）")
        }

        self.currentReferencePointIndex = 0
        self.totalReferencePoints = self.referencePoints.count
        self.currentWorkflow = .collectingObservation
        self.isCollectingForCurrentPoint = false

        // 初期ステートをタグ配置に設定
        self.currentStep = .placingTag

        let currentPoint = self.referencePoints[0]
        self.currentStepInstructions = """
        タグ1の場所にタグを置いてください
        座標: (\(String(format: "%.2f", currentPoint.realWorldCoordinate.x)), \(String(format: "%.2f", currentPoint.realWorldCoordinate.y)), \(String(format: "%.2f", currentPoint.realWorldCoordinate.z)))

        タグを置いたら「センシング開始」ボタンを押してください
        """

        self.logger.info("段階的キャリブレーション開始 - 基準点数: \(self.totalReferencePoints)")

        // 自動開始は行わない - ユーザーのボタン押下を待つ
    }

    /// 次の基準点を処理
    public func processNextReferencePoint() async {
        guard self.currentReferencePointIndex < self.referencePoints.count else {
            self.logger.info("全ての基準点の処理が完了しました")
            // データのマッピングとキャリブレーション実行
            _ = self.mapObservationsToReferences()
            _ = await self.executeCalibration()
            return
        }

        let currentPoint = self.referencePoints[self.currentReferencePointIndex]
        let pointNumber = self.currentReferencePointIndex + 1

        self.currentStepInstructions = "基準点 \(pointNumber)/\(self.totalReferencePoints) でデータを収集してください\n座標: (\(String(format: "%.2f", currentPoint.realWorldCoordinate.x)), \(String(format: "%.2f", currentPoint.realWorldCoordinate.y)), \(String(format: "%.2f", currentPoint.realWorldCoordinate.z)))"
        self.calibrationStepProgress = Double(self.currentReferencePointIndex) / Double(self.totalReferencePoints)

        self.logger.info("基準点 \(pointNumber)/\(self.totalReferencePoints) の処理準備完了")
    }

    /// 現在の基準点でデータ収集を開始
    public func startDataCollectionForCurrentPoint() async {
        guard self.currentReferencePointIndex < self.referencePoints.count else {
            self.logger.error("有効な基準点がありません")
            return
        }

        let currentPoint = self.referencePoints[self.currentReferencePointIndex]
        self.isCollectingForCurrentPoint = true
        self.currentStep = .collecting

        self.logger.info("基準点 \(self.currentReferencePointIndex + 1) でのデータ収集開始: アンテナID \(currentPoint.antennaId)")

        // リモートセンシングを開始（sensingControlUsecaseが存在する場合）
        if let sensingControl = sensingControlUsecase {
            let fileName = "calib_point\(currentReferencePointIndex + 1)_\(Date().timeIntervalSince1970)"
            sensingControl.startRemoteSensing(fileName: fileName)
            self.logger.info("リモートセンシング開始: \(fileName)")
        } else {
            self.logger.error("SensingControlUsecaseが初期化されていません")
            self.errorMessage = "センシング制御が初期化されていません"
            self.isCollectingForCurrentPoint = false
            self.currentWorkflow = .failed
            self.currentStep = .failed
            return
        }

        // 10秒間のデータ収集を監視（ローカルのUWB接続チェックはスキップ）
        await self.monitorDataCollection()
    }

    /// データ収集を監視（10秒間）
    private func monitorDataCollection() async {
        let totalSeconds = 10
        let updateInterval: UInt64 = 1_000_000_000  // 1秒
        let pointNumber = self.currentReferencePointIndex + 1
        let pointId = "point_\(self.currentReferencePointIndex)"

        // セッションを初期化（まだ存在しない場合）
        if self.observationSessions[pointId] == nil {
            let currentPoint = self.referencePoints[self.currentReferencePointIndex]
            self.observationSessions[pointId] = ObservationSession(
                id: pointId,
                name: "CalibPoint_\(pointNumber)",
                startTime: Date(),
                antennaId: currentPoint.antennaId,
                floorMapId: nil
            )
            self.logger.info("観測セッション初期化: \(pointId)")
        }

        for second in 1...totalSeconds {
            try? await Task.sleep(nanoseconds: updateInterval)

            // リアルタイムデータを収集して observationSessions に追加
            let realtimeDataList = self.realtimeDataUsecase.deviceRealtimeDataList
            self.logger.info("📊 データ収集ループ \(second)/\(totalSeconds): デバイス数=\(realtimeDataList.count)")

            for deviceData in realtimeDataList {
                self.logger.debug("🔍 デバイス: \(deviceData.deviceName), latestData=\(deviceData.latestData != nil ? "あり" : "なし")")

                if let latestData = deviceData.latestData {
                    self.logger.debug("📡 受信データ: distance=\(latestData.distance), elevation=\(latestData.elevation), azimuth=\(latestData.azimuth)")

                    // 無効なデータをフィルタリング（distance=0のデータを除外）
                    guard latestData.distance > 0 else {
                        self.logger.debug("❌ 無効なデータをスキップ: distance=\(latestData.distance)")
                        continue
                    }

                    // 球面座標から直交座標への変換
                    let azimuthRad = latestData.azimuth * .pi / 180
                    let elevationRad = latestData.elevation * .pi / 180
                    let position = Point3D(
                        x: latestData.distance * cos(azimuthRad) * cos(elevationRad),
                        y: latestData.distance * sin(azimuthRad) * cos(elevationRad),
                        z: latestData.distance * sin(elevationRad)
                    )

                    // 信号品質を計算
                    let quality = SignalQuality(
                        strength: latestData.rssi > -70 ? 0.8 : (latestData.rssi > -90 ? 0.5 : 0.2),
                        isLineOfSight: latestData.nlos == 0,
                        confidenceLevel: latestData.nlos == 0 ? 0.9 : 0.5,
                        errorEstimate: latestData.nlos == 0 ? 0.5 : 2.0
                    )

                    // TimeIntervalをDateに変換
                    let timestamp = Date(timeIntervalSince1970: latestData.timestamp / 1000)

                    let observation = ObservationPoint(
                        antennaId: deviceData.deviceName,
                        position: position,
                        timestamp: timestamp,
                        quality: quality,
                        distance: latestData.distance,
                        rssi: latestData.rssi,
                        sessionId: pointId
                    )

                    // CalibrationDataFlowのobservationSessionsに追加
                    self.observationSessions[pointId]?.observations.append(observation)

                    // ObservationDataUsecaseのcurrentSessionsにも追加
                    if var usecaseSession = self.observationUsecase.currentSessions[pointId] {
                        usecaseSession.observations.append(observation)
                        self.observationUsecase.currentSessions[pointId] = usecaseSession
                        self.logger.debug("💾 ObservationDataUsecaseにデータ追加: \(pointId)")
                    } else {
                        // セッションが存在しない場合は作成
                        let currentPoint = self.referencePoints[self.currentReferencePointIndex]
                        var newSession = ObservationSession(
                            id: pointId,
                            name: "CalibPoint_\(pointNumber)",
                            startTime: Date(),
                            antennaId: currentPoint.antennaId,
                            floorMapId: nil
                        )
                        newSession.observations.append(observation)
                        self.observationUsecase.currentSessions[pointId] = newSession
                        self.logger.info("📝 ObservationDataUsecaseに新セッション作成: \(pointId)")
                    }

                    self.logger.info("✅ 有効なデータを追加: distance=\(latestData.distance), position=(\(String(format: "%.2f", position.x)), \(String(format: "%.2f", position.y)), \(String(format: "%.2f", position.z)))")
                } else {
                    self.logger.debug("⚠️ デバイス \(deviceData.deviceName) の latestData が nil")
                }
            }

            // 現在の observationSessions の状態をログ出力
            let currentObservationCount = self.observationSessions[pointId]?.observations.count ?? 0
            let usecaseObservationCount = self.observationUsecase.currentSessions[pointId]?.observations.count ?? 0
            self.logger.info("📈 CalibrationDataFlow観測データ数: \(currentObservationCount)")
            self.logger.info("📈 ObservationDataUsecase観測データ数: \(usecaseObservationCount)")

            // 残り時間を更新
            let remainingSeconds = totalSeconds - second
            self.currentStepInstructions = """
            基準点 \(pointNumber)/\(self.totalReferencePoints) でデータを収集中...
            残り時間: \(remainingSeconds)秒
            """

            self.logger.info("基準点\(pointNumber)データ収集中: 残り\(remainingSeconds)秒")
        }

        // 収集したデータ数をログに出力
        let collectedCount = self.observationSessions[pointId]?.observations.count ?? 0
        let usecaseCollectedCount = self.observationUsecase.currentSessions[pointId]?.observations.count ?? 0
        self.logger.info("基準点\(pointNumber)でのデータ収集完了: CalibrationDataFlow=\(collectedCount)件, ObservationDataUsecase=\(usecaseCollectedCount)件")

        await self.completeCurrentPointCollection()
    }

    /// 現在の基準点のデータ収集を完了
    private func completeCurrentPointCollection() async {
        self.isCollectingForCurrentPoint = false

        let pointNumber = self.currentReferencePointIndex + 1
        self.logger.info("基準点\(pointNumber)のデータ収集が完了しました")

        // データ収集完了のメッセージ
        self.currentStepInstructions = """
        基準点 \(pointNumber)/\(self.totalReferencePoints) のデータ収集が完了しました
        データを処理しています...
        """

        // アンテナ位置を推定して表示
        await self.calculateAndShowAntennaPosition()

        // 次の基準点に進むかどうかチェック
        self.currentReferencePointIndex += 1

        if self.currentReferencePointIndex < self.referencePoints.count {
            // まだ基準点が残っている場合
            let nextPointNumber = self.currentReferencePointIndex + 1
            let nextPoint = self.referencePoints[self.currentReferencePointIndex]

            self.currentStep = .placingTag
            self.currentStepInstructions = """
            タグ\(nextPointNumber)の場所にタグを置いてください
            座標: (\(String(format: "%.2f", nextPoint.realWorldCoordinate.x)), \(String(format: "%.2f", nextPoint.realWorldCoordinate.y)), \(String(format: "%.2f", nextPoint.realWorldCoordinate.z)))

            タグを置いたら「センシング開始」ボタンを押してください
            """

            self.logger.info("次の基準点\(nextPointNumber)の準備完了")
        } else {
            // 全ての基準点の収集が完了
            self.logger.info("全ての基準点のデータ収集が完了しました")

            self.currentStepInstructions = """
            全ての基準点のデータ収集が完了しました
            キャリブレーションを実行しています...
            """

            // キャリブレーション実行
            _ = await self.executeCalibration()

            if self.currentWorkflow == .completed {
                self.currentStep = .completed

                self.currentStepInstructions = """
                キャリブレーション完了

                最終的なアンテナ位置:
                \(self.formatAntennaPositions())
                """
            } else {
                self.currentStep = .failed
                self.currentStepInstructions = """
                キャリブレーションに失敗しました
                \(self.errorMessage ?? "不明なエラー")
                """
            }
        }
    }

    /// ユーザーが「センシング開始」ボタンを押したときに呼ばれる
    public func startSensingForCurrentPoint() async {
        guard self.currentStep == .placingTag else {
            self.logger.warning("現在のステップではセンシング開始できません")
            return
        }

        self.currentStep = .readyToStart
        self.logger.info("センシング開始準備完了 - データ収集を開始します")

        // データ収集を開始
        await self.startDataCollectionForCurrentPoint()
    }

    /// アンテナ位置を推定して表示
    private func calculateAndShowAntennaPosition() async {
        self.currentStep = .showingAntennaPosition

        // 現在収集したデータからアンテナ位置を推定
        let currentPointIndex = self.currentReferencePointIndex

        // observationSessionsは[String: ObservationSession]なので、indexではなくpointIdで検索
        let pointId = "point_\(currentPointIndex)"

        if let session = self.observationSessions[pointId] {
            // 最も多くデータを取得したアンテナのIDを取得
            let antennaCounts = session.observations.reduce(into: [String: Int]()) { counts, obs in
                counts[obs.antennaId, default: 0] += 1
            }

            if let mostFrequentAntenna = antennaCounts.max(by: { $0.value < $1.value })?.key {
                // そのアンテナの最新の観測データを取得
                let antennaObservations = session.observations.filter { $0.antennaId == mostFrequentAntenna }
                if let latestObs = antennaObservations.last {
                    // 観測座標をアンテナ位置の推定値として使用
                    self.estimatedAntennaPosition = latestObs.position

                    self.logger.info(
                        "推定アンテナ位置: (\(String(format: "%.2f", latestObs.position.x)), \(String(format: "%.2f", latestObs.position.y)), \(String(format: "%.2f", latestObs.position.z)))"
                    )

                    let pointNumber = currentPointIndex + 1
                    self.currentStepInstructions = """
                    基準点 \(pointNumber)/\(self.totalReferencePoints) のデータ収集完了

                    このあたりにアンテナがあると思います:
                    座標: (\(String(format: "%.2f", latestObs.position.x)), \(String(format: "%.2f", latestObs.position.y)), \(String(format: "%.2f", latestObs.position.z)))

                    フロアマップで位置を確認してください
                    """

                    // 3秒間表示してから次のステップへ
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    return
                }
            }
        }

        // データが取得できなかった場合
        self.estimatedAntennaPosition = nil
        self.logger.warning("アンテナ位置を推定できませんでした - データが不足しています")

        let pointNumber = currentPointIndex + 1
        self.currentStepInstructions = """
        基準点 \(pointNumber)/\(self.totalReferencePoints) のデータ収集完了

        ⚠️ アンテナ位置を推定できませんでした
        データが不足している可能性があります
        """

        // 3秒間表示してから次のステップへ
        try? await Task.sleep(nanoseconds: 3_000_000_000)
    }

    /// 最終的なアンテナ位置をフォーマット
    private func formatAntennaPositions() -> String {
        guard !self.finalAntennaPositions.isEmpty else {
            return "アンテナ位置情報がありません"
        }

        return self.finalAntennaPositions.map { antennaId, position in
            "\(antennaId): (\(String(format: "%.2f", position.x)), \(String(format: "%.2f", position.y)), \(String(format: "%.2f", position.z)))"
        }.joined(separator: "\n")
    }

    /// ワークフローをキャンセル
    public func cancelWorkflow() async {
        self.logger.info("ワークフローキャンセル開始")

        // 進行中のセッションを停止
        for sessionId in self.observationSessions.keys {
            do {
                _ = try await self.observationUsecase.stopObservationSession(sessionId)
            } catch {
                self.logger.error("セッション停止エラー: \(error)")
            }
        }

        // リモートセンシングを停止
        self.sensingControlUsecase?.stopRemoteSensing()

        // 状態をリセット
        self.isCollectingForCurrentPoint = false
        self.currentReferencePointIndex = 0
        self.totalReferencePoints = 0
        self.currentStepInstructions = ""
        self.calibrationStepProgress = 0.0
        self.currentWorkflow = .idle

        self.logger.info("ワークフローキャンセル完了")
    }

    /// アンテナ位置をデータベースに保存
    private func saveAntennaPositionToDatabase(antennaId: String, position: Point3D, floorMapId: String) async {
        guard let repository = swiftDataRepository else {
            self.logger.warning("SwiftDataRepositoryが利用できないため、アンテナ位置を保存できません")
            return
        }

        do {
            let antennaPosition = AntennaPositionData(
                id: UUID().uuidString,
                antennaId: antennaId,
                antennaName: "Antenna_\(antennaId)",
                position: position,
                rotation: 0.0,
                calibratedAt: Date(),
                floorMapId: floorMapId
            )

            try await repository.saveAntennaPosition(antennaPosition)
            self.logger.info("アンテナ位置を保存しました: アンテナID \(antennaId), 位置 (\(position.x), \(position.y), \(position.z))")
        } catch {
            self.logger.error("アンテナ位置の保存に失敗しました: \(error)")
            self.errorMessage = "アンテナ位置の保存に失敗しました: \(error.localizedDescription)"
        }
    }

    // MARK: - 4. 変換行列算出とキャリブレーション実行

    /// 完全なキャリブレーションワークフローを実行
    public func executeCalibration() async -> CalibrationWorkflowResult {
        self.currentWorkflow = .calculating

        do {
            // 1. マッピングの検証
            guard !self.mappings.isEmpty else {
                throw CalibrationWorkflowError.insufficientMappings
            }

            guard self.mappings.count >= 3 else {
                throw CalibrationWorkflowError.insufficientPoints(required: 3, provided: self.mappings.count)
            }

            // 2. 各アンテナごとにキャリブレーション実行
            var results: [String: CalibrationResult] = [:]
            var allSuccessful = true

            for (antennaId, _) in self.observationSessions {
                // そのアンテナの観測データを使ってキャリブレーション点を作成
                let calibrationPoints = self.createCalibrationPoints(for: antennaId, from: self.mappings)

                if calibrationPoints.count >= 3 {
                    // キャリブレーション点を既存のUseCaseに追加
                    for point in calibrationPoints {
                        self.calibrationUsecase.addCalibrationPoint(
                            for: antennaId,
                            referencePosition: point.referencePosition,
                            measuredPosition: point.measuredPosition
                        )
                    }

                    // キャリブレーション実行
                    await self.calibrationUsecase.performCalibration(for: antennaId)

                    if let result = calibrationUsecase.lastCalibrationResult {
                        results[antennaId] = result
                        if !result.success {
                            allSuccessful = false
                        }
                        self.logger.info("アンテナ \(antennaId) キャリブレーション完了: \(result.success ? "成功" : "失敗")")
                    }
                } else {
                    allSuccessful = false
                    self.logger.warning("アンテナ \(antennaId): キャリブレーション点が不足 (\(calibrationPoints.count)/3)")
                }
            }

            // 3. 結果をまとめる
            let workflowResult = CalibrationWorkflowResult(
                success: allSuccessful,
                processedAntennas: Array(observationSessions.keys),
                calibrationResults: results,
                qualityStatistics: self.calculateOverallQualityStatistics(),
                timestamp: Date()
            )

            self.lastCalibrationResult = workflowResult
            self.currentWorkflow = allSuccessful ? .completed : .failed

            if !allSuccessful {
                self.errorMessage = "一部のアンテナでキャリブレーションに失敗しました"
            }

            // 4. 成功時にアンテナ位置を設定・保存
            if allSuccessful {
                for (antennaId, result) in results where result.success {
                    if let transform = result.transform {
                        // translationをアンテナ位置として使用
                        let antennaPosition = transform.translation
                        finalAntennaPositions[antennaId] = antennaPosition
                        logger.info("アンテナ位置を設定しました: \(antennaId) -> (\(antennaPosition.x), \(antennaPosition.y), \(antennaPosition.z))")

                        // データベースに保存（フロアマップIDが必要）
                        if let floorMapId = preferenceRepository.loadCurrentFloorMapInfo()?.id {
                            await saveAntennaPositionToDatabase(antennaId: antennaId, position: antennaPosition, floorMapId: floorMapId)
                        } else {
                            logger.warning("フロアマップIDが取得できないため、アンテナ位置をデータベースに保存できません")
                        }
                    }
                }
            }

            self.updateProgress()
            return workflowResult

        } catch {
            let workflowResult = CalibrationWorkflowResult(
                success: false,
                processedAntennas: Array(observationSessions.keys),
                calibrationResults: [:],
                qualityStatistics: self.calculateOverallQualityStatistics(),
                timestamp: Date(),
                errorMessage: error.localizedDescription
            )

            self.lastCalibrationResult = workflowResult
            self.currentWorkflow = .failed
            self.errorMessage = error.localizedDescription

            return workflowResult
        }
    }

    // MARK: - 5. ワークフロー管理

    /// ワークフローをリセット
    public func resetWorkflow() {
        self.currentWorkflow = .idle
        self.referencePoints.removeAll()
        self.observationSessions.removeAll()
        self.mappings.removeAll()
        self.workflowProgress = 0.0
        self.errorMessage = nil
        self.lastCalibrationResult = nil

        // リアルタイムデータとペアリング情報もクリア
        self.realtimeDataUsecase.clearAllRealtimeData()
        self.logger.info("🗑️ ワークフローリセット時にリアルタイムデータをクリアしました")

        // 接続済み端末もリセット
        if let connectionMgmt = self.connectionManagement {
            connectionMgmt.resetAll()
            self.logger.info("🔌 ワークフローリセット時に接続済み端末をリセットしました")
        }
    }

    /// 現在のワークフロー状態の検証
    public func validateCurrentState() -> CalibrationWorkflowValidation {
        var issues: [String] = []
        var canProceed = true

        // 基準点の検証
        if self.referencePoints.count < 3 {
            issues.append("基準点が不足しています (必要: 3点以上, 現在: \(self.referencePoints.count)点)")
            canProceed = false
        }

        // 観測データの検証
        if self.observationSessions.isEmpty {
            issues.append("観測データがありません")
            canProceed = false
        } else {
            for (antennaId, session) in self.observationSessions {
                if session.observations.isEmpty {
                    issues.append("アンテナ \(antennaId) の観測データがありません")
                    canProceed = false
                }

                let validObservations = session.observations.filter { $0.quality.strength > 0.5 }
                if validObservations.count < 10 {
                    issues.append("アンテナ \(antennaId) の有効な観測データが不足しています (推奨: 10点以上, 現在: \(validObservations.count)点)")
                }
            }
        }

        // マッピングの検証
        if !self.mappings.isEmpty {
            let averageQuality = self.mappings.map { $0.mappingQuality }.reduce(0, +) / Double(self.mappings.count)
            if averageQuality < 0.6 {
                issues.append("マッピング品質が低いです (平均品質: \(String(format: "%.1f", averageQuality * 100))%)")
            }
        }

        return CalibrationWorkflowValidation(
            canProceed: canProceed,
            issues: issues,
            recommendations: self.generateRecommendations()
        )
    }

    // MARK: - Private Methods

    private func updateProgress() {
        let totalSteps = 5.0
        var completedSteps = 0.0

        if !self.referencePoints.isEmpty { completedSteps += 1.0 }
        if !self.observationSessions.isEmpty { completedSteps += 1.0 }
        if !self.mappings.isEmpty { completedSteps += 1.0 }
        if self.currentWorkflow == .calculating || self.currentWorkflow == .completed { completedSteps += 1.0 }
        if self.currentWorkflow == .completed { completedSteps += 1.0 }

        self.workflowProgress = completedSteps / totalSteps
    }

    private func createCalibrationPoints(for antennaId: String, from mappings: [ReferenceObservationMapping])
        -> [CalibrationPoint]
    {
        mappings.compactMap { mapping in
            // そのアンテナの観測データのみを抽出
            let antennaObservations = mapping.observations.filter { $0.antennaId == antennaId }
            guard !antennaObservations.isEmpty else { return nil }

            // 複数の観測点がある場合は重心を計算
            let totalX = antennaObservations.map { $0.position.x }.reduce(0, +)
            let totalY = antennaObservations.map { $0.position.y }.reduce(0, +)
            let totalZ = antennaObservations.map { $0.position.z }.reduce(0, +)
            let count = Double(antennaObservations.count)

            let averagePosition = Point3D(
                x: totalX / count,
                y: totalY / count,
                z: totalZ / count
            )

            return CalibrationPoint(
                referencePosition: mapping.referencePosition,
                measuredPosition: averagePosition,
                antennaId: antennaId
            )
        }
    }

    private func calculateOverallQualityStatistics() -> CalibrationWorkflowQualityStatistics {
        var totalObservations = 0
        var validObservations = 0
        var totalQuality = 0.0
        var losCount = 0

        for session in self.observationSessions.values {
            totalObservations += session.observations.count
            for observation in session.observations {
                if observation.quality.strength > 0.3 {
                    validObservations += 1
                    totalQuality += observation.quality.strength
                }
                if observation.quality.isLineOfSight {
                    losCount += 1
                }
            }
        }

        let averageQuality = validObservations > 0 ? totalQuality / Double(validObservations) : 0.0
        let losPercentage = totalObservations > 0 ? Double(losCount) / Double(totalObservations) * 100.0 : 0.0
        let mappingAccuracy =
            self.mappings.isEmpty ? 0.0 : self.mappings.map { $0.mappingQuality }.reduce(0, +) / Double(self.mappings.count)

        return CalibrationWorkflowQualityStatistics(
            totalObservations: totalObservations,
            validObservations: validObservations,
            averageSignalQuality: averageQuality,
            lineOfSightPercentage: losPercentage,
            mappingAccuracy: mappingAccuracy,
            processedAntennas: self.observationSessions.count
        )
    }

    private func generateRecommendations() -> [String] {
        var recommendations: [String] = []

        if self.referencePoints.count < 5 {
            recommendations.append("より多くの基準点を設定することで精度が向上します")
        }

        for (antennaId, session) in self.observationSessions {
            let avgQuality = session.qualityStatistics.averageQuality
            if avgQuality < 0.7 {
                recommendations.append("アンテナ \(antennaId) の観測環境を改善してください（障害物の除去、位置調整など）")
            }
        }

        if !self.mappings.isEmpty {
            let avgMappingQuality = self.mappings.map { $0.mappingQuality }.reduce(0, +) / Double(self.mappings.count)
            if avgMappingQuality < 0.7 {
                recommendations.append("基準点と観測点の対応付けを見直してください")
            }
        }

        return recommendations
    }
}

// MARK: - Supporting Types

/// キャリブレーションワークフローの状態
public enum CalibrationWorkflowStatus {
    case idle
    case collectingReference
    case collectingObservation
    case calculating
    case completed
    case failed

    public var displayText: String {
        switch self {
        case .idle:
            return "待機中"
        case .collectingReference:
            return "基準データ収集中"
        case .collectingObservation:
            return "観測データ収集中"
        case .calculating:
            return "キャリブレーション計算中"
        case .completed:
            return "完了"
        case .failed:
            return "失敗"
        }
    }
}

/// ワークフロー全体の結果
public struct CalibrationWorkflowResult: Codable {
    public let success: Bool
    public let processedAntennas: [String]
    public let calibrationResults: [String: CalibrationResult]
    public let qualityStatistics: CalibrationWorkflowQualityStatistics
    public let timestamp: Date
    public let errorMessage: String?

    public init(
        success: Bool,
        processedAntennas: [String],
        calibrationResults: [String: CalibrationResult],
        qualityStatistics: CalibrationWorkflowQualityStatistics,
        timestamp: Date,
        errorMessage: String? = nil
    ) {
        self.success = success
        self.processedAntennas = processedAntennas
        self.calibrationResults = calibrationResults
        self.qualityStatistics = qualityStatistics
        self.timestamp = timestamp
        self.errorMessage = errorMessage
    }
}

/// ワークフロー品質統計
public struct CalibrationWorkflowQualityStatistics: Codable {
    public let totalObservations: Int
    public let validObservations: Int
    public let averageSignalQuality: Double
    public let lineOfSightPercentage: Double
    public let mappingAccuracy: Double
    public let processedAntennas: Int

    public init(
        totalObservations: Int,
        validObservations: Int,
        averageSignalQuality: Double,
        lineOfSightPercentage: Double,
        mappingAccuracy: Double,
        processedAntennas: Int
    ) {
        self.totalObservations = totalObservations
        self.validObservations = validObservations
        self.averageSignalQuality = averageSignalQuality
        self.lineOfSightPercentage = lineOfSightPercentage
        self.mappingAccuracy = mappingAccuracy
        self.processedAntennas = processedAntennas
    }
}

/// ワークフロー状態の検証結果
public struct CalibrationWorkflowValidation {
    public let canProceed: Bool
    public let issues: [String]
    public let recommendations: [String]

    public init(canProceed: Bool, issues: [String], recommendations: [String]) {
        self.canProceed = canProceed
        self.issues = issues
        self.recommendations = recommendations
    }
}

/// ワークフローエラー
public enum CalibrationWorkflowError: Error, LocalizedError {
    case insufficientMappings
    case insufficientPoints(required: Int, provided: Int)
    case observationDataMissing(antennaId: String)
    case lowQualityData(quality: Double)

    public var errorDescription: String? {
        switch self {
        case .insufficientMappings:
            return "基準点と観測データのマッピングが不十分です"
        case .insufficientPoints(let required, let provided):
            return "キャリブレーション点が不足しています（必要: \(required)点、提供: \(provided)点）"
        case .observationDataMissing(let antennaId):
            return "アンテナ \(antennaId) の観測データが見つかりません"
        case .lowQualityData(let quality):
            return "データ品質が低すぎます（品質: \(String(format: "%.1f", quality * 100))%）"
        }
    }
}
