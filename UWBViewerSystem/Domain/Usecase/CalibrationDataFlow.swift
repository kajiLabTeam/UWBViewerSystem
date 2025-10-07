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

        // ConnectionManagementUsecaseにRealtimeDataUsecaseを設定
        connectionManagement?.setRealtimeDataUsecase(self.realtimeDataUsecase)
        self.logger.info("🔗 ConnectionManagementUsecaseにRealtimeDataUsecaseを設定しました")
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

        self.logger.info("🔍 マッピング開始: 基準点数=\(self.referencePoints.count), セッション数=\(self.observationSessions.count)")

        // セッション内の観測データ数をログ出力
        for (sessionId, session) in self.observationSessions {
            self.logger.info("  セッション[\(sessionId)]: 観測データ数=\(session.observations.count), アンテナID=\(session.antennaId)")
        }

        var mappedPairs: [(reference: Point3D, observation: Point3D)] = []

        // 各基準点をセッションIDでマッピング
        for (index, referencePoint) in self.referencePoints.enumerated() {
            let sessionId = "point_\(index)"

            self.logger.info("  🔍 基準点[\(index)]: sessionId=\(sessionId)")

            guard let session = self.observationSessions[sessionId] else {
                self.logger.warning("  ⚠️ セッション[\(sessionId)]が見つかりません")
                continue
            }

            self.logger.info("  ✅ セッション[\(sessionId)]を発見: 観測データ数=\(session.observations.count)")

            // 品質フィルタリング
            let validObservations = session.observations.filter { observation in
                observation.quality.strength > 0.3
            }

            self.logger.info("  ✅ フィルタ後の有効観測数: \(validObservations.count)/\(session.observations.count)")

            guard !validObservations.isEmpty else {
                self.logger.warning("  ⚠️ 有効な観測データがありません")
                continue
            }

            let mapping = ReferenceObservationMapping(
                referencePosition: referencePoint.realWorldCoordinate,
                observations: validObservations
            )
            self.mappings.append(mapping)

            // マッピングペアを作成（重心を使用）
            mappedPairs.append(
                (
                    reference: referencePoint.realWorldCoordinate,
                    observation: mapping.centroidPosition
                ))

            self.logger.info(
                "✅ マッピング作成: 基準(\(referencePoint.realWorldCoordinate.x), \(referencePoint.realWorldCoordinate.y)) -> 観測(\(mapping.centroidPosition.x), \(mapping.centroidPosition.y)), 誤差: \(mapping.positionError)m"
            )
        }

        self.logger.info("🔍 マッピング完了: 成功したマッピング数=\(mappedPairs.count)/\(self.referencePoints.count)")

        if mappedPairs.isEmpty {
            self.logger.error("❌ マッピングが0件です - データ収集が正しく行われていない可能性があります")
        } else if mappedPairs.count < 3 {
            self.logger.warning("⚠️ マッピングが\(mappedPairs.count)件のみです - キャリブレーションには最低3件必要です")
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

        // 前回のリアルタイムデータをクリア（接続は維持）
        self.realtimeDataUsecase.clearAllRealtimeData()
        self.logger.info("🗑️ リアルタイムデータをクリアしました（既存の接続は維持）")

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

        self.currentStepInstructions =
            "基準点 \(pointNumber)/\(self.totalReferencePoints) でデータを収集してください\n座標: (\(String(format: "%.2f", currentPoint.realWorldCoordinate.x)), \(String(format: "%.2f", currentPoint.realWorldCoordinate.y)), \(String(format: "%.2f", currentPoint.realWorldCoordinate.z)))"
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

            // デバイスリストの詳細をログ出力
            if realtimeDataList.isEmpty {
                self.logger.warning("⚠️ デバイスリストが空です - RealtimeDataUsecaseにデータが届いていません")
                self.logger.info("💡 確認ポイント: ConnectionManagementにRealtimeDataUsecaseが設定されているか確認してください")
            } else {
                for (index, device) in realtimeDataList.enumerated() {
                    self.logger.debug("🔍 デバイス[\(index)]: \(device.deviceName)")
                    self.logger.debug("  - isActive: \(device.isActive)")
                    self.logger.debug("  - latestData: \(device.latestData != nil ? "あり" : "なし")")
                    if let latest = device.latestData {
                        self.logger.debug("  - 距離: \(latest.distance)mm")
                        self.logger.debug("  - 方位角: \(latest.azimuth)°")
                        self.logger.debug("  - 仰角: \(latest.elevation)°")
                    }
                }
            }

            for deviceData in realtimeDataList {
                self.logger.debug(
                    "🔍 デバイス: \(deviceData.deviceName), latestData=\(deviceData.latestData != nil ? "あり" : "なし")")

                if let latestData = deviceData.latestData {
                    self.logger.debug(
                        "📡 受信データ: distance=\(latestData.distance), elevation=\(latestData.elevation), azimuth=\(latestData.azimuth)"
                    )

                    // 無効なデータをフィルタリング（distance=0のデータを除外）
                    guard latestData.distance > 0 else {
                        self.logger.debug("❌ 無効なデータをスキップ: distance=\(latestData.distance)")
                        continue
                    }

                    // 距離の単位変換: cm → m
                    let distanceInMeters = latestData.distance / 100.0

                    // 球面座標から直交座標への変換
                    let azimuthRad = latestData.azimuth * .pi / 180
                    let elevationRad = latestData.elevation * .pi / 180
                    let position = Point3D(
                        x: distanceInMeters * cos(azimuthRad) * cos(elevationRad),
                        y: distanceInMeters * sin(azimuthRad) * cos(elevationRad),
                        z: distanceInMeters * sin(elevationRad)
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

                    // 現在の基準点から antennaId を取得
                    let currentPoint = self.referencePoints[self.currentReferencePointIndex]

                    let observation = ObservationPoint(
                        antennaId: currentPoint.antennaId,
                        position: position,
                        timestamp: timestamp,
                        quality: quality,
                        distance: distanceInMeters,
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

                    self.logger.info(
                        "✅ 有効なデータを追加: distance=\(String(format: "%.2f", distanceInMeters))m (元: \(latestData.distance)cm), position=(\(String(format: "%.2f", position.x)), \(String(format: "%.2f", position.y)), \(String(format: "%.2f", position.z)))"
                    )
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
        self.logger.info(
            "基準点\(pointNumber)でのデータ収集完了: CalibrationDataFlow=\(collectedCount)件, ObservationDataUsecase=\(usecaseCollectedCount)件"
        )

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

            // マッピング処理を実行
            _ = self.mapObservationsToReferences()

            // キャリブレーション実行
            _ = await self.executeCalibration()

            if self.currentWorkflow == .completed {
                self.currentStep = .completed

                self.currentStepInstructions = """
                キャリブレーション完了

                最終的なアンテナ位置:
                \(self.formatAntennaPositions())
                """

                // Android側のセンシングを停止
                self.sensingControlUsecase?.stopRemoteSensing()
                self.logger.info("📡 Android側のセンシングを停止しました")

                // Android側にキャリブレーション完了を通知
                self.sendCalibrationCompletedNotification()
            } else {
                self.currentStep = .failed
                self.currentStepInstructions = """
                キャリブレーションに失敗しました
                \(self.errorMessage ?? "不明なエラー")
                """

                // Android側のセンシングを停止
                self.sensingControlUsecase?.stopRemoteSensing()
                self.logger.info("📡 Android側のセンシングを停止しました（失敗時）")

                // Android側にキャリブレーション失敗を通知
                self.sendCalibrationFailedNotification()
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

    /// Android側にキャリブレーション完了を通知
    private func sendCalibrationCompletedNotification() {
        guard let connectionMgmt = self.connectionManagement else {
            self.logger.warning("ConnectionManagementが利用できません - 通知を送信できません")
            return
        }

        let message = "CALIBRATION_COMPLETED"
        connectionMgmt.sendMessage(message)
        self.logger.info("📤 Android側にキャリブレーション完了を通知: \(message)")
    }

    /// Android側にキャリブレーション失敗を通知
    private func sendCalibrationFailedNotification() {
        guard let connectionMgmt = self.connectionManagement else {
            self.logger.warning("ConnectionManagementが利用できません - 通知を送信できません")
            return
        }

        let errorMsg = self.errorMessage ?? "不明なエラー"
        let message = "CALIBRATION_FAILED:\(errorMsg)"
        connectionMgmt.sendMessage(message)
        self.logger.info("📤 Android側にキャリブレーション失敗を通知: \(message)")
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
        self.logger.info("🚀 executeCalibration() 開始")
        self.currentWorkflow = .calculating

        do {
            self.logger.info("📊 ステップ1: マッピング検証開始")
            // 1. マッピングの検証
            guard !self.mappings.isEmpty else {
                self.logger.error("❌ マッピングが空です")
                throw CalibrationWorkflowError.insufficientMappings
            }

            guard self.mappings.count >= 3 else {
                self.logger.error("❌ マッピング数不足: \(self.mappings.count)/3")
                throw CalibrationWorkflowError.insufficientPoints(required: 3, provided: self.mappings.count)
            }

            self.logger.info("✅ マッピング検証成功: \(self.mappings.count)件")

            // 2. 各アンテナごとにキャリブレーション実行
            self.logger.info("📊 ステップ2: アンテナごとのキャリブレーション実行")

            // 全セッションからユニークなアンテナIDを抽出
            let uniqueAntennaIds = Set(self.observationSessions.values.map { $0.antennaId })
            self.logger.info("  対象アンテナ数: \(uniqueAntennaIds.count)")

            var results: [String: CalibrationResult] = [:]
            var allSuccessful = true

            for antennaId in uniqueAntennaIds {
                self.logger.info("🔧 アンテナ[\(antennaId)]のキャリブレーション開始")

                // そのアンテナの観測データを使ってキャリブレーション点を作成
                let calibrationPoints = self.createCalibrationPoints(for: antennaId, from: self.mappings)
                self.logger.info("  キャリブレーション点数: \(calibrationPoints.count)")

                if calibrationPoints.count >= 3 {
                    do {
                        // 最小二乗法で変換行列を計算
                        self.logger.info("  🔄 最小二乗法で変換行列を計算中...")
                        let transform = try LeastSquaresCalibration.calculateTransform(from: calibrationPoints)
                        self.logger.info("  ✅ 変換行列計算成功")
                        self.logger.info(
                            "    回転: \(String(format: "%.3f", transform.rotation * 180 / .pi))度, スケール: (\(String(format: "%.3f", transform.scale.x)), \(String(format: "%.3f", transform.scale.y)), \(String(format: "%.3f", transform.scale.z)))"
                        )

                        // 各基準点からアンテナ位置を逆算
                        // 関係式: Pr = Pa + R*S*Po
                        // 逆に: Pa = Pr - R*S*Po
                        var antennaPositions: [Point3D] = []
                        for (index, point) in calibrationPoints.enumerated() {
                            // Po = 観測データの重心（アンテナから見たタグの位置、アンテナ座標系）
                            let observedPosition = point.measuredPosition

                            // 1. スケール適用
                            let scaled = Point3D(
                                x: observedPosition.x * transform.scale.x,
                                y: observedPosition.y * transform.scale.y,
                                z: observedPosition.z * transform.scale.z
                            )

                            // 2. 回転適用（Z軸周りの2D回転）
                            let cos_r = cos(transform.rotation)
                            let sin_r = sin(transform.rotation)
                            let rotatedScaled = Point3D(
                                x: scaled.x * cos_r - scaled.y * sin_r,
                                y: scaled.x * sin_r + scaled.y * cos_r,
                                z: scaled.z
                            )

                            // 3. アンテナ位置 = 基準点位置 - 変換された観測位置
                            // Pa = Pr - R*S*Po
                            let antennaPosition = Point3D(
                                x: point.referencePosition.x - rotatedScaled.x,
                                y: point.referencePosition.y - rotatedScaled.y,
                                z: point.referencePosition.z - rotatedScaled.z
                            )

                            antennaPositions.append(antennaPosition)
                            self.logger.info(
                                "    基準点[\(index)]から計算: アンテナ位置=(\(String(format: "%.3f", antennaPosition.x)), \(String(format: "%.3f", antennaPosition.y)), \(String(format: "%.3f", antennaPosition.z)))"
                            )
                        }

                        // 3つのアンテナ位置の重心を計算
                        let finalAntennaPosition = Point3D(
                            x: antennaPositions.map { $0.x }.reduce(0, +) / Double(antennaPositions.count),
                            y: antennaPositions.map { $0.y }.reduce(0, +) / Double(antennaPositions.count),
                            z: antennaPositions.map { $0.z }.reduce(0, +) / Double(antennaPositions.count)
                        )

                        self.logger.info(
                            "  ✅ 最終アンテナ位置（重心）: (\(String(format: "%.3f", finalAntennaPosition.x)), \(String(format: "%.3f", finalAntennaPosition.y)), \(String(format: "%.3f", finalAntennaPosition.z)))"
                        )

                        // CalibrationResultを作成
                        // transformは保存するが、実際のアンテナ位置はfinalAntennaPositionを使用
                        let result = CalibrationResult(
                            success: true,
                            antennaPosition: finalAntennaPosition,
                            transform: transform,
                            processedPoints: calibrationPoints,
                            timestamp: Date()
                        )

                        results[antennaId] = result
                        self.logger.info("  ✅ キャリブレーション成功: \(antennaId)")

                    } catch {
                        allSuccessful = false
                        self.logger.error("  ❌ キャリブレーション失敗: \(antennaId) - \(error)")

                        let result = CalibrationResult(
                            success: false,
                            antennaPosition: nil,
                            transform: nil,
                            errorMessage: error.localizedDescription,
                            timestamp: Date()
                        )
                        results[antennaId] = result
                    }
                } else {
                    allSuccessful = false
                    self.logger.warning("⚠️ アンテナ \(antennaId): キャリブレーション点が不足 (\(calibrationPoints.count)/3)")
                }
            }

            // 3. 結果をまとめる
            self.logger.info("📊 ステップ3: 結果の集計")
            let workflowResult = CalibrationWorkflowResult(
                success: allSuccessful,
                processedAntennas: Array(uniqueAntennaIds),
                calibrationResults: results,
                qualityStatistics: self.calculateOverallQualityStatistics(),
                timestamp: Date()
            )

            self.lastCalibrationResult = workflowResult
            self.currentWorkflow = allSuccessful ? .completed : .failed

            if !allSuccessful {
                self.errorMessage = "一部のアンテナでキャリブレーションに失敗しました"
                self.logger.warning("⚠️ 一部のアンテナでキャリブレーションに失敗")
            } else {
                self.logger.info("✅ 全アンテナのキャリブレーション成功")
            }

            // 4. 成功時にアンテナ位置を設定・保存
            if allSuccessful {
                self.logger.info("📊 ステップ4: アンテナ位置の保存")
                for (antennaId, result) in results where result.success {
                    if let antennaPosition = result.antennaPosition {
                        // 重心計算されたアンテナ位置を使用
                        finalAntennaPositions[antennaId] = antennaPosition
                        logger.info(
                            "  💾 アンテナ位置を設定: \(antennaId) -> (\(String(format: "%.3f", antennaPosition.x)), \(String(format: "%.3f", antennaPosition.y)), \(String(format: "%.3f", antennaPosition.z)))"
                        )

                        // データベースに保存（フロアマップIDが必要）
                        if let floorMapId = preferenceRepository.loadCurrentFloorMapInfo()?.id {
                            self.logger.info("  💾 データベースに保存中: \(antennaId)")
                            await saveAntennaPositionToDatabase(
                                antennaId: antennaId, position: antennaPosition, floorMapId: floorMapId)
                            self.logger.info("  ✅ データベース保存完了: \(antennaId)")
                        } else {
                            logger.warning("  ⚠️ フロアマップIDが取得できないため、アンテナ位置をデータベースに保存できません")
                        }
                    }
                }
            }

            self.logger.info("🎉 executeCalibration() 完了 - 成功: \(allSuccessful)")
            self.updateProgress()
            return workflowResult

        } catch {
            self.logger.error("❌ executeCalibration() エラー発生: \(error)")
            self.logger.error("  エラー詳細: \(error.localizedDescription)")

            // エラー時も uniqueAntennaIds を使用
            let uniqueAntennaIds = Set(self.observationSessions.values.map { $0.antennaId })

            let workflowResult = CalibrationWorkflowResult(
                success: false,
                processedAntennas: Array(uniqueAntennaIds),
                calibrationResults: [:],
                qualityStatistics: self.calculateOverallQualityStatistics(),
                timestamp: Date(),
                errorMessage: error.localizedDescription
            )

            self.lastCalibrationResult = workflowResult
            self.currentWorkflow = .failed
            self.errorMessage = error.localizedDescription

            self.logger.info("❌ executeCalibration() 失敗で終了")
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
        self.logger.info("🔧 createCalibrationPoints開始: antennaId=\(antennaId), mappings数=\(mappings.count)")

        let points = mappings.compactMap { mapping -> CalibrationPoint? in
            // そのアンテナの観測データのみを抽出
            let antennaObservations = mapping.observations.filter { $0.antennaId == antennaId }
            self.logger.debug("  マッピング: アンテナ観測数=\(antennaObservations.count)")

            guard !antennaObservations.isEmpty else {
                self.logger.debug("  ⚠️ このマッピングにはアンテナ[\(antennaId)]の観測データなし")
                return nil
            }

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

            self.logger.debug(
                "  ✅ キャリブレーション点作成: 基準=(\(mapping.referencePosition.x), \(mapping.referencePosition.y)), 測定=(\(averagePosition.x), \(averagePosition.y))"
            )

            return CalibrationPoint(
                referencePosition: mapping.referencePosition,
                measuredPosition: averagePosition,
                antennaId: antennaId
            )
        }

        self.logger.info("🔧 createCalibrationPoints完了: 生成点数=\(points.count)")
        return points
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
            self.mappings.isEmpty
                ? 0.0 : self.mappings.map { $0.mappingQuality }.reduce(0, +) / Double(self.mappings.count)

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

    // MARK: - テスト用ダミーデータ送信

    #if DEBUG
        /// デバッグ用: ダミーのリアルタイムデータを送信してキャリブレーションフローをテスト
        public func sendDummyRealtimeData(deviceName: String = "TestDevice", count: Int = 10) {
            self.logger.info("🧪 ダミーデータ送信開始: デバイス名=\(deviceName), データ数=\(count)")

            // デバイスを追加
            self.realtimeDataUsecase.addConnectedDevice(deviceName)

            // ダミーデータを送信
            for i in 0..<count {
                let json: [String: Any] = [
                    "type": "REALTIME_DATA",
                    "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                    "deviceName": deviceName,
                    "data": [
                        "nlos": 0,
                        "distance": Int.random(in: 10...100),
                        "elevation": Double.random(in: -45.0...45.0),
                        "azimuth": Double.random(in: -180.0...180.0),
                        "elevationFom": 100,
                        "rssi": Double.random(in: -90.0...(-50.0)),
                        "pDoA1": Double.random(in: -90.0...90.0),
                        "pDoA2": Double.random(in: -90.0...90.0),
                        "seqCount": i,
                    ],
                ]

                self.realtimeDataUsecase.processRealtimeDataMessage(json, fromEndpointId: "DUMMY")
                self.logger.debug("📤 ダミーデータ送信 [\(i + 1)/\(count)]")
            }

            self.logger.info("✅ ダミーデータ送信完了: \(count)件")
        }
    #endif
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
