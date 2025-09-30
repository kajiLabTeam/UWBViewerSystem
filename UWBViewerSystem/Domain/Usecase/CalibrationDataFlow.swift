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
        referencePoints = points
        currentWorkflow = .collectingReference
        updateProgress()

        logger.info("基準座標を収集: \(points.count)個の点")
        for point in points {
            logger.debug(
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
        referencePoints.append(point)
        updateProgress()
    }

    // MARK: - 2. 観測データ取得

    /// 指定されたアンテナから観測データを収集開始
    /// - Parameter antennaId: 観測対象のアンテナID
    public func startObservationData(for antennaId: String) async {
        currentWorkflow = .collectingObservation

        do {
            let session = try await observationUsecase.startObservationSession(
                for: antennaId,
                name: "キャリブレーション観測_\(Date().timeIntervalSince1970)"
            )
            observationSessions[antennaId] = session
            updateProgress()

            logger.info("観測データ収集開始: アンテナ \(antennaId)")
        } catch {
            errorMessage = "観測データ収集の開始に失敗しました: \(error.localizedDescription)"
            currentWorkflow = .failed
        }
    }

    /// 観測データ収集を停止
    /// - Parameter antennaId: 観測対象のアンテナID
    public func stopObservationData(for antennaId: String) async {
        guard let session = observationSessions[antennaId] else { return }

        do {
            let completedSession = try await observationUsecase.stopObservationSession(session.id)
            observationSessions[antennaId] = completedSession
            updateProgress()

            logger.info("観測データ収集停止: アンテナ \(antennaId), データ点数: \(completedSession.observations.count)")
        } catch {
            errorMessage = "観測データ収集の停止に失敗しました: \(error.localizedDescription)"
        }
    }

    // MARK: - 3. 誤差算出とマッピング

    /// 基準座標と観測データをマッピング
    public func mapObservationsToReferences() -> [(reference: Point3D, observation: Point3D)] {
        currentWorkflow = .calculating
        mappings.removeAll()

        var mappedPairs: [(reference: Point3D, observation: Point3D)] = []

        // 各基準点に対して最も近い観測データを見つける
        for referencePoint in referencePoints {
            var bestMappings: [ObservationPoint] = []
            var minDistance = Double.infinity

            // 全てのアンテナの観測データから最適な点を探す
            for session in observationSessions.values {
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
                mappings.append(mapping)

                // マッピングペアを作成（重心を使用）
                mappedPairs.append(
                    (
                        reference: referencePoint.realWorldCoordinate,
                        observation: mapping.centroidPosition
                    ))

                logger.info(
                    "マッピング作成: 基準(\(referencePoint.realWorldCoordinate.x), \(referencePoint.realWorldCoordinate.y)) -> 観測(\(mapping.centroidPosition.x), \(mapping.centroidPosition.y)), 誤差: \(mapping.positionError)m"
                )
            }
        }

        updateProgress()
        return mappedPairs
    }

    // MARK: - 段階的キャリブレーション

    /// 段階的キャリブレーションを開始
    public func startStepByStepCalibration() async {
        guard !referencePoints.isEmpty else {
            logger.error("基準点が設定されていません")
            errorMessage = "基準点が設定されていません"
            currentWorkflow = .failed
            return
        }

        currentReferencePointIndex = 0
        totalReferencePoints = referencePoints.count
        currentWorkflow = .collectingObservation
        isCollectingForCurrentPoint = false

        logger.info("段階的キャリブレーション開始 - 基準点数: \(totalReferencePoints)")

        await processNextReferencePoint()
    }

    /// 次の基準点を処理
    public func processNextReferencePoint() async {
        guard currentReferencePointIndex < referencePoints.count else {
            logger.info("全ての基準点の処理が完了しました")
            // データのマッピングとキャリブレーション実行
            _ = mapObservationsToReferences()
            _ = await executeCalibration()
            return
        }

        let currentPoint = referencePoints[currentReferencePointIndex]
        let pointNumber = currentReferencePointIndex + 1

        currentStepInstructions = "基準点 \(pointNumber)/\(totalReferencePoints) でデータを収集してください\n座標: (\(String(format: "%.2f", currentPoint.realWorldCoordinate.x)), \(String(format: "%.2f", currentPoint.realWorldCoordinate.y)), \(String(format: "%.2f", currentPoint.realWorldCoordinate.z)))"
        calibrationStepProgress = Double(currentReferencePointIndex) / Double(totalReferencePoints)

        logger.info("基準点 \(pointNumber)/\(totalReferencePoints) の処理準備完了")
    }

    /// 現在の基準点でデータ収集を開始
    public func startDataCollectionForCurrentPoint() async {
        guard currentReferencePointIndex < referencePoints.count else {
            logger.error("有効な基準点がありません")
            return
        }

        let currentPoint = referencePoints[currentReferencePointIndex]
        isCollectingForCurrentPoint = true

        logger.info("基準点 \(currentReferencePointIndex + 1) でのデータ収集開始: アンテナID \(currentPoint.antennaId)")

        // リモートセンシングを開始（sensingControlUsecaseが存在する場合）
        if let sensingControl = sensingControlUsecase {
            let fileName = "calib_point\(currentReferencePointIndex + 1)_\(Date().timeIntervalSince1970)"
            sensingControl.startRemoteSensing(fileName: fileName)
            logger.info("リモートセンシング開始: \(fileName)")
        }

        // 観測データ収集を開始
        do {
            _ = try await observationUsecase.startCalibrationDataCollectionWithProgress(
                for: currentPoint.antennaId,
                referencePoint: "Point\(currentReferencePointIndex + 1)"
            )

            // 15秒間のデータ収集を監視
            await monitorDataCollection()
        } catch {
            logger.error("データ収集の開始に失敗しました: \(error)")
            errorMessage = "データ収集の開始に失敗しました: \(error.localizedDescription)"
            isCollectingForCurrentPoint = false
            currentWorkflow = .failed
        }
    }

    /// データ収集を監視
    private func monitorDataCollection() async {
        // 15秒待機（実際の収集時間）
        try? await Task.sleep(nanoseconds: 15_000_000_000)

        await completeCurrentPointCollection()
    }

    /// 現在の基準点のデータ収集を完了
    private func completeCurrentPointCollection() async {
        isCollectingForCurrentPoint = false

        logger.info("基準点 \(currentReferencePointIndex + 1) のデータ収集完了")

        // 次の基準点に進む
        currentReferencePointIndex += 1

        if currentReferencePointIndex < referencePoints.count {
            await processNextReferencePoint()
        } else {
            logger.info("全ての基準点のデータ収集完了 - キャリブレーション計算開始")
            // 全ての基準点の収集が完了したら、マッピングとキャリブレーションを実行
            _ = mapObservationsToReferences()
            _ = await executeCalibration()
        }
    }

    /// ワークフローをキャンセル
    public func cancelWorkflow() async {
        logger.info("ワークフローキャンセル開始")

        // 進行中のセッションを停止
        for sessionId in observationSessions.keys {
            do {
                _ = try await observationUsecase.stopObservationSession(sessionId)
            } catch {
                logger.error("セッション停止エラー: \(error)")
            }
        }

        // リモートセンシングを停止
        sensingControlUsecase?.stopRemoteSensing()

        // 状態をリセット
        isCollectingForCurrentPoint = false
        currentReferencePointIndex = 0
        totalReferencePoints = 0
        currentStepInstructions = ""
        calibrationStepProgress = 0.0
        currentWorkflow = .idle

        logger.info("ワークフローキャンセル完了")
    }

    /// アンテナ位置をデータベースに保存
    private func saveAntennaPositionToDatabase(antennaId: String, position: Point3D, floorMapId: String) async {
        guard let repository = swiftDataRepository else {
            logger.warning("SwiftDataRepositoryが利用できないため、アンテナ位置を保存できません")
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
            logger.info("アンテナ位置を保存しました: アンテナID \(antennaId), 位置 (\(position.x), \(position.y), \(position.z))")
        } catch {
            logger.error("アンテナ位置の保存に失敗しました: \(error)")
            errorMessage = "アンテナ位置の保存に失敗しました: \(error.localizedDescription)"
        }
    }

    // MARK: - 4. 変換行列算出とキャリブレーション実行

    /// 完全なキャリブレーションワークフローを実行
    public func executeCalibration() async -> CalibrationWorkflowResult {
        currentWorkflow = .calculating

        do {
            // 1. マッピングの検証
            guard !mappings.isEmpty else {
                throw CalibrationWorkflowError.insufficientMappings
            }

            guard mappings.count >= 3 else {
                throw CalibrationWorkflowError.insufficientPoints(required: 3, provided: mappings.count)
            }

            // 2. 各アンテナごとにキャリブレーション実行
            var results: [String: CalibrationResult] = [:]
            var allSuccessful = true

            for (antennaId, _) in observationSessions {
                // そのアンテナの観測データを使ってキャリブレーション点を作成
                let calibrationPoints = createCalibrationPoints(for: antennaId, from: mappings)

                if calibrationPoints.count >= 3 {
                    // キャリブレーション点を既存のUseCaseに追加
                    for point in calibrationPoints {
                        calibrationUsecase.addCalibrationPoint(
                            for: antennaId,
                            referencePosition: point.referencePosition,
                            measuredPosition: point.measuredPosition
                        )
                    }

                    // キャリブレーション実行
                    await calibrationUsecase.performCalibration(for: antennaId)

                    if let result = calibrationUsecase.lastCalibrationResult {
                        results[antennaId] = result
                        if !result.success {
                            allSuccessful = false
                        }
                        logger.info("アンテナ \(antennaId) キャリブレーション完了: \(result.success ? "成功" : "失敗")")
                    }
                } else {
                    allSuccessful = false
                    logger.warning("アンテナ \(antennaId): キャリブレーション点が不足 (\(calibrationPoints.count)/3)")
                }
            }

            // 3. 結果をまとめる
            let workflowResult = CalibrationWorkflowResult(
                success: allSuccessful,
                processedAntennas: Array(observationSessions.keys),
                calibrationResults: results,
                qualityStatistics: calculateOverallQualityStatistics(),
                timestamp: Date()
            )

            lastCalibrationResult = workflowResult
            currentWorkflow = allSuccessful ? .completed : .failed

            if !allSuccessful {
                errorMessage = "一部のアンテナでキャリブレーションに失敗しました"
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

            updateProgress()
            return workflowResult

        } catch {
            let workflowResult = CalibrationWorkflowResult(
                success: false,
                processedAntennas: Array(observationSessions.keys),
                calibrationResults: [:],
                qualityStatistics: calculateOverallQualityStatistics(),
                timestamp: Date(),
                errorMessage: error.localizedDescription
            )

            lastCalibrationResult = workflowResult
            currentWorkflow = .failed
            errorMessage = error.localizedDescription

            return workflowResult
        }
    }

    // MARK: - 5. ワークフロー管理

    /// ワークフローをリセット
    public func resetWorkflow() {
        currentWorkflow = .idle
        referencePoints.removeAll()
        observationSessions.removeAll()
        mappings.removeAll()
        workflowProgress = 0.0
        errorMessage = nil
        lastCalibrationResult = nil
    }

    /// 現在のワークフロー状態の検証
    public func validateCurrentState() -> CalibrationWorkflowValidation {
        var issues: [String] = []
        var canProceed = true

        // 基準点の検証
        if referencePoints.count < 3 {
            issues.append("基準点が不足しています (必要: 3点以上, 現在: \(referencePoints.count)点)")
            canProceed = false
        }

        // 観測データの検証
        if observationSessions.isEmpty {
            issues.append("観測データがありません")
            canProceed = false
        } else {
            for (antennaId, session) in observationSessions {
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
        if !mappings.isEmpty {
            let averageQuality = mappings.map { $0.mappingQuality }.reduce(0, +) / Double(mappings.count)
            if averageQuality < 0.6 {
                issues.append("マッピング品質が低いです (平均品質: \(String(format: "%.1f", averageQuality * 100))%)")
            }
        }

        return CalibrationWorkflowValidation(
            canProceed: canProceed,
            issues: issues,
            recommendations: generateRecommendations()
        )
    }

    // MARK: - Private Methods

    private func updateProgress() {
        let totalSteps = 5.0
        var completedSteps = 0.0

        if !referencePoints.isEmpty { completedSteps += 1.0 }
        if !observationSessions.isEmpty { completedSteps += 1.0 }
        if !mappings.isEmpty { completedSteps += 1.0 }
        if currentWorkflow == .calculating || currentWorkflow == .completed { completedSteps += 1.0 }
        if currentWorkflow == .completed { completedSteps += 1.0 }

        workflowProgress = completedSteps / totalSteps
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

        for session in observationSessions.values {
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
            mappings.isEmpty ? 0.0 : mappings.map { $0.mappingQuality }.reduce(0, +) / Double(mappings.count)

        return CalibrationWorkflowQualityStatistics(
            totalObservations: totalObservations,
            validObservations: validObservations,
            averageSignalQuality: averageQuality,
            lineOfSightPercentage: losPercentage,
            mappingAccuracy: mappingAccuracy,
            processedAntennas: observationSessions.count
        )
    }

    private func generateRecommendations() -> [String] {
        var recommendations: [String] = []

        if referencePoints.count < 5 {
            recommendations.append("より多くの基準点を設定することで精度が向上します")
        }

        for (antennaId, session) in observationSessions {
            let avgQuality = session.qualityStatistics.averageQuality
            if avgQuality < 0.7 {
                recommendations.append("アンテナ \(antennaId) の観測環境を改善してください（障害物の除去、位置調整など）")
            }
        }

        if !mappings.isEmpty {
            let avgMappingQuality = mappings.map { $0.mappingQuality }.reduce(0, +) / Double(mappings.count)
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
