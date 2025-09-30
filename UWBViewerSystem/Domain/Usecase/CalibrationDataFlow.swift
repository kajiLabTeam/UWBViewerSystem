import Foundation
import os.log
import SwiftUI

/// キャリブレーションデータフローを管理するクラス
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

    // MARK: - Private Properties

    private let dataRepository: DataRepositoryProtocol
    private let calibrationUsecase: CalibrationUsecase
    private let observationUsecase: ObservationDataUsecase
    private let swiftDataRepository: SwiftDataRepositoryProtocol?
    private let sensingControlUsecase: SensingControlUsecase?
    private let preferenceRepository: PreferenceRepositoryProtocol
    private let logger = Logger(subsystem: "com.uwbviewer.system", category: "calibration-dataflow")

    // MARK: - Initialization

    public init(
        dataRepository: DataRepositoryProtocol,
        calibrationUsecase: CalibrationUsecase,
        observationUsecase: ObservationDataUsecase,
        swiftDataRepository: SwiftDataRepositoryProtocol? = nil,
        sensingControlUsecase: SensingControlUsecase? = nil,
        preferenceRepository: PreferenceRepositoryProtocol = PreferenceRepository()
    ) {
        self.dataRepository = dataRepository
        self.calibrationUsecase = calibrationUsecase
        self.observationUsecase = observationUsecase
        self.swiftDataRepository = swiftDataRepository
        self.sensingControlUsecase = sensingControlUsecase
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

        self.currentReferencePointIndex = 0
        self.totalReferencePoints = self.referencePoints.count
        self.currentWorkflow = .collectingObservation
        self.isCollectingForCurrentPoint = false

        self.logger.info("段階的キャリブレーション開始 - 基準点数: \(self.totalReferencePoints)")

        await self.processNextReferencePoint()

        // 最初の基準点でのデータ収集を自動的に開始
        await self.startDataCollectionForCurrentPoint()
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

        self.logger.info("基準点 \(self.currentReferencePointIndex + 1) でのデータ収集開始: アンテナID \(currentPoint.antennaId)")

        // リモートセンシングを開始（sensingControlUsecaseが存在する場合）
        if let sensingControl = sensingControlUsecase {
            let fileName = "calib_point\(currentReferencePointIndex + 1)_\(Date().timeIntervalSince1970)"
            sensingControl.startRemoteSensing(fileName: fileName)
            self.logger.info("リモートセンシング開始: \(fileName)")
        }

        // 観測データ収集を開始
        do {
            _ = try await self.observationUsecase.startCalibrationDataCollectionWithProgress(
                for: currentPoint.antennaId,
                referencePoint: "Point\(self.currentReferencePointIndex + 1)"
            )

            // 15秒間のデータ収集を監視
            await self.monitorDataCollection()
        } catch {
            self.logger.error("データ収集の開始に失敗しました: \(error)")
            self.errorMessage = "データ収集の開始に失敗しました: \(error.localizedDescription)"
            self.isCollectingForCurrentPoint = false
            self.currentWorkflow = .failed
        }
    }

    /// データ収集を監視（10秒間）
    private func monitorDataCollection() async {
        let totalSeconds = 10
        let updateInterval: UInt64 = 1_000_000_000  // 1秒

        for second in 1...totalSeconds {
            try? await Task.sleep(nanoseconds: updateInterval)

            // 残り時間を更新
            let remainingSeconds = totalSeconds - second
            let pointNumber = self.currentReferencePointIndex + 1
            self.currentStepInstructions = """
            基準点 \(pointNumber)/\(self.totalReferencePoints) でデータを収集中...
            残り時間: \(remainingSeconds)秒
            """

            self.logger.info("基準点\(pointNumber)データ収集中: 残り\(remainingSeconds)秒")
        }

        await self.completeCurrentPointCollection()
    }

    /// 現在の基準点のデータ収集を完了
    private func completeCurrentPointCollection() async {
        self.isCollectingForCurrentPoint = false

        let completedPointNumber = self.currentReferencePointIndex + 1
        self.logger.info("基準点 \(completedPointNumber) のデータ収集完了")

        // リモートセンシングを停止
        self.sensingControlUsecase?.stopRemoteSensing()

        // 次の基準点に進む
        self.currentReferencePointIndex += 1

        if self.currentReferencePointIndex < self.referencePoints.count {
            let nextPointNumber = self.currentReferencePointIndex + 1
            let nextPoint = self.referencePoints[self.currentReferencePointIndex]

            // 次の基準点への移動指示を表示
            self.currentStepInstructions = """
            基準点 \(completedPointNumber) のデータ収集完了！

            次は基準点 \(nextPointNumber)/\(self.totalReferencePoints) に移動してください
            座標: (\(String(format: "%.2f", nextPoint.realWorldCoordinate.x)), \(String(format: "%.2f", nextPoint.realWorldCoordinate.y)), \(String(format: "%.2f", nextPoint.realWorldCoordinate.z)))

            移動したら「データ収集開始」を押してください
            """

            self.logger.info("次の基準点 \(nextPointNumber) への移動を指示")

            await self.processNextReferencePoint()

            // 5秒待機してから自動的に次のデータ収集を開始
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await self.startDataCollectionForCurrentPoint()
        } else {
            self.logger.info("全ての基準点のデータ収集完了 - キャリブレーション計算開始")

            self.currentStepInstructions = """
            全ての基準点のデータ収集が完了しました！

            キャリブレーション計算を開始します...
            """

            // 全ての基準点の収集が完了したら、マッピングとキャリブレーションを実行
            _ = self.mapObservationsToReferences()
            let result = await self.executeCalibration()

            // 最終結果を表示
            if result.success {
                self.currentStepInstructions = """
                キャリブレーション完了！

                全 \(self.totalReferencePoints) 点のキャリブレーションが成功しました
                アンテナ位置が確定しました
                """
                self.logger.info("段階的キャリブレーション成功")
            } else {
                self.currentStepInstructions = """
                キャリブレーションエラー

                \(result.errorMessage ?? "計算中にエラーが発生しました")
                """
                self.logger.error("段階的キャリブレーション失敗: \(result.errorMessage ?? "不明なエラー")")
            }
        }
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
