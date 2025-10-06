import SwiftData
import SwiftUI

/// シンプルな3ステップキャリブレーション画面
struct SimpleCalibrationView: View {
    @StateObject private var viewModel = SimpleCalibrationViewModel()
    @StateObject private var flowNavigator = SensingFlowNavigator()
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var router: NavigationRouterModel

    var body: some View {
        VStack(spacing: 0) {
            // フロープログレス表示
            SensingFlowProgressView(navigator: self.flowNavigator)

            ScrollView {
                VStack(spacing: 24) {
                    // ヘッダー
                    self.headerSection

                    // ステップ内容
                    self.currentStepContent

                    // ナビゲーションボタン
                    self.navigationButtons

                    Spacer(minLength: 80)
                }
                .padding()
            }
        }
        .onAppear {
            // SwiftDataのModelContextを設定
            self.viewModel.setModelContext(self.modelContext)

            self.viewModel.loadInitialData()
            self.viewModel.reloadData()  // 常に最新のフロアマップデータを取得
            self.flowNavigator.currentStep = .systemCalibration
            self.flowNavigator.setRouter(self.router)

            // CalibrationDataFlowとObservationDataUsecaseを初期化
            let dataRepository = DataRepository()
            let calibrationUsecase = CalibrationUsecase(dataRepository: dataRepository)
            let uwbManager = UWBDataManager()
            let preferenceRepository = PreferenceRepository()
            let observationUsecase = ObservationDataUsecase(
                dataRepository: dataRepository,
                uwbManager: uwbManager,
                preferenceRepository: preferenceRepository
            )

            // SensingControlUsecaseを初期化（Androidデバイスへのセンシングコマンド送信用）
            // シングルトンインスタンスを使用して、アプリ全体で接続状態を共有
            let connectionUsecase = ConnectionManagementUsecase.shared
            let swiftDataRepository = SwiftDataRepository(modelContext: modelContext)
            let sensingControlUsecase = SensingControlUsecase(
                connectionUsecase: connectionUsecase,
                swiftDataRepository: swiftDataRepository
            )

            let calibrationDataFlow = CalibrationDataFlow(
                dataRepository: dataRepository,
                calibrationUsecase: calibrationUsecase,
                observationUsecase: observationUsecase,
                swiftDataRepository: swiftDataRepository,
                sensingControlUsecase: sensingControlUsecase
            )
            self.viewModel.setupStepByStepCalibration(
                calibrationDataFlow: calibrationDataFlow,
                observationUsecase: observationUsecase
            )
        }
        .alert("エラー", isPresented: self.$viewModel.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(self.viewModel.errorMessage)
        }
        .alert("キャリブレーション完了", isPresented: self.$viewModel.showSuccessAlert) {
            Button("新しいキャリブレーション", role: .none) {
                self.viewModel.resetCalibration()
            }
            Button("完了", role: .cancel) {
                self.flowNavigator.proceedToNextStep()
            }
        } message: {
            Text("キャリブレーションが正常に完了しました")
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "gear")
                    .foregroundColor(.orange)
                    .font(.title)

                VStack(alignment: .leading, spacing: 4) {
                    Text("シンプルキャリブレーション")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("ステップ \(self.viewModel.currentStep + 1) / 3: \(self.viewModel.currentStepTitle)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // プログレスバー
            ProgressView(value: Double(self.viewModel.currentStep), total: 2.0)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Step Content

    @ViewBuilder
    private var currentStepContent: some View {
        switch self.viewModel.currentStep {
        case 0:
            self.antennaSelectionContent
        case 1:
            self.coordinateSelectionContent
        case 2:
            self.calibrationExecutionContent
        default:
            EmptyView()
        }
    }

    private var antennaSelectionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("アンテナ選択")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 4) {
                Text("キャリブレーションを行うアンテナを選択してください")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("緑色のアイコンは配置済みアンテナ、灰色は未配置アンテナです。向きがある場合は矢印で表示されます。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if self.viewModel.availableAntennas.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)

                    Text("利用可能なアンテナがありません")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                VStack(spacing: 12) {
                    ForEach(self.viewModel.availableAntennas, id: \.id) { antenna in
                        let isPositioned = self.viewModel.antennaPositions.contains { $0.antennaId == antenna.id }
                        let antennaPosition = self.viewModel.antennaPositions.first { $0.antennaId == antenna.id }

                        Button(action: {
                            self.viewModel.selectAntenna(antenna.id)
                        }) {
                            HStack {
                                // アンテナアイコンと状態表示
                                VStack(spacing: 4) {
                                    ZStack {
                                        Circle()
                                            .fill(isPositioned ? Color.green : Color.gray)
                                            .frame(width: 32, height: 32)

                                        Image(systemName: "antenna.radiowaves.left.and.right")
                                            .font(.system(size: 16))
                                            .foregroundColor(.white)
                                            .rotationEffect(.degrees(antennaPosition?.rotation ?? 0))
                                    }

                                    if isPositioned {
                                        Text("配置済み")
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                            .fontWeight(.medium)
                                    } else {
                                        Text("未配置")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(antenna.id)
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    Text(antenna.name)
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    if let position = antennaPosition {
                                        Text(
                                            "位置: (\(String(format: "%.1f", position.position.x)), \(String(format: "%.1f", position.position.y)))"
                                        )
                                        .font(.caption2)
                                        .foregroundColor(.secondary)

                                        if position.rotation != 0 {
                                            Text("向き: \(String(format: "%.0f", position.rotation))°")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }

                                Spacer()

                                VStack {
                                    if antenna.id == self.viewModel.selectedAntennaId {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                            .font(.title2)
                                    }

                                    if !isPositioned {
                                        Text("※位置設定が必要")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                            .fontWeight(.medium)
                                    }
                                }
                            }
                            .padding()
                            .background(
                                antenna.id == self.viewModel.selectedAntennaId
                                    ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.05)
                            )
                            .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }

    private var coordinateSelectionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            self.coordinateSelectionHeader
            self.floorMapDisplayView
            self.referencePointsList
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }

    private var coordinateSelectionHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("基準座標設定")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 4) {
                Text("フロアマップ上で3つの基準座標を設定してください (\(self.viewModel.referencePoints.count)/3)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if !self.viewModel.antennaPositions.isEmpty {
                    self.antennaInfoHint
                }
            }
        }
    }

    private var antennaInfoHint: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundColor(.blue)
                .font(.caption)

            Text("青色のアンテナが選択中、灰色のアンテナが他の配置済みアンテナです")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var floorMapDisplayView: some View {
        FloorMapCanvas(
            floorMapImage: self.viewModel.floorMapImage,
            floorMapInfo: self.viewModel.currentFloorMapInfo,
            onMapTap: self.handleMapTap
        ) { geometry in
            // アンテナ表示
            ForEach(self.viewModel.antennaPositions) { antenna in
                let antennaDisplayData = AntennaDisplayData(
                    id: antenna.antennaId,
                    name: antenna.antennaName,
                    rotation: antenna.rotation,
                    color: antenna.antennaId == self.viewModel.selectedAntennaId ? .blue : .gray
                )

                let normalizedPosition = geometry.realWorldToNormalized(
                    CGPoint(x: antenna.position.x, y: antenna.position.y)
                )
                let displayPosition = geometry.normalizedToImageCoordinate(normalizedPosition)

                AntennaMarker(
                    antenna: antennaDisplayData,
                    position: displayPosition,
                    size: geometry.antennaSizeInPixels(),
                    sensorRange: geometry.sensorRangeInPixels(),
                    isSelected: antenna.antennaId == self.viewModel.selectedAntennaId,
                    isDraggable: false,
                    showRotationControls: false
                )
            }

            // 基準点表示
            ForEach(Array(self.viewModel.referencePoints.enumerated()), id: \.offset) { index, point in
                let referencePointData = ReferencePointDisplayData(
                    id: "\(index)",
                    label: "\(index + 1)",
                    color: .red,
                    coordinates: point
                )

                let normalizedPoint = geometry.realWorldToNormalized(
                    CGPoint(x: point.x, y: point.y)
                )
                let displayPosition = geometry.normalizedToImageCoordinate(normalizedPoint)

                ReferencePointMarker(
                    point: referencePointData,
                    position: displayPosition
                )
            }

            // 現在位置表示（データ収集中のみ）
            if self.viewModel.calibrationStep == .collecting,
               let currentPos = self.viewModel.currentPosition
            {
                let normalizedPos = geometry.realWorldToNormalized(
                    CGPoint(x: currentPos.x, y: currentPos.y)
                )
                let displayPos = geometry.normalizedToImageCoordinate(normalizedPos)

                ZStack {
                    // 外側の円（パルスアニメーション）
                    Circle()
                        .stroke(Color.green.opacity(0.3), lineWidth: 2)
                        .frame(width: 40, height: 40)

                    // 内側の円
                    Circle()
                        .fill(Color.green)
                        .frame(width: 16, height: 16)

                    // 中心点
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                }
                .position(displayPos)
            }
        }
    }

    private func handleMapTap(at location: CGPoint) {
        if self.viewModel.referencePoints.count < 3 {
            let point = Point3D(
                x: Double(location.x),
                y: Double(location.y),
                z: 0.0
            )
            self.viewModel.addReferencePoint(point)
        }
    }

    private var referencePointsList: some View {
        let referencePointsData = self.viewModel.referencePoints.enumerated().map { index, point in
            ReferencePointDisplayData(
                id: "\(index)",
                label: "\(index + 1)",
                color: .red,
                coordinates: point
            )
        }

        return ReferencePointList(
            points: referencePointsData,
            onClear: { self.viewModel.clearReferencePoints() },
            onPointTap: nil
        )
    }

    private var calibrationExecutionContent: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                Text("キャリブレーション実行")
                    .font(.headline)
                    .foregroundColor(.primary)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("選択アンテナ:")
                            .font(.subheadline)
                        Text(self.viewModel.selectedAntennaId)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                    }

                    HStack {
                        Text("基準座標数:")
                            .font(.subheadline)
                        Text("\(self.viewModel.referencePoints.count)個")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }

            // キャリブレーション実行セクション
            VStack(spacing: 16) {
                if self.viewModel.isCalibrating {
                    VStack(spacing: 16) {
                        ProgressView(value: self.viewModel.calibrationProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .blue))

                        Text("キャリブレーション実行中... \(self.viewModel.progressPercentage)")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                } else if let result = viewModel.calibrationResult {
                    VStack(spacing: 16) {
                        HStack {
                            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.largeTitle)
                                .foregroundColor(self.viewModel.calibrationResultColor)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("キャリブレーション\(self.viewModel.calibrationResultText)")
                                    .font(.headline)
                                    .foregroundColor(self.viewModel.calibrationResultColor)

                                Text("精度: \(self.viewModel.calibrationAccuracyText)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                    }
                    .padding()
                    .background(self.viewModel.calibrationResultColor.opacity(0.1))
                    .cornerRadius(12)
                } else {
                    // 段階的キャリブレーション実行ボタン
                    Button(action: self.viewModel.startStepByStepCalibration) {
                        HStack {
                            Image(systemName: "figure.walk")
                            Text("キャリブレーション開始")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(.white)
                        .background(Color.green)
                        .cornerRadius(12)
                    }
                    .disabled(!self.viewModel.canStartCalibration)
                }
            }

            // 段階的キャリブレーション進行状況表示（常に表示）
            self.stepByStepCalibrationProgressView

            // アンテナ位置結果表示
            if self.viewModel.showAntennaPositionsResult {
                self.antennaPositionsResultView
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - 段階的キャリブレーション関連ビュー

    private var stepByStepCalibrationProgressView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ヘッダー - 現在のステータス
            HStack {
                Image(systemName: self.statusIcon)
                    .foregroundColor(self.statusColor)
                    .font(.headline)

                Text(self.statusTitle)
                    .font(.headline)
                    .foregroundColor(self.statusColor)

                Spacer()
            }

            // 進行状況（開始後のみ表示）
            if self.viewModel.totalSteps > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("進行状況: \(self.viewModel.currentStepNumber + 1) / \(self.viewModel.totalSteps)")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Spacer()

                        Text(String(format: "%.0f%%", self.viewModel.stepProgress * 100))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    ProgressView(value: self.viewModel.stepProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .green))
                }
            }

            // 現在のステップ指示
            if !self.viewModel.currentStepInstructions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("指示:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(self.viewModel.currentStepInstructions)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            } else if self.viewModel.calibrationStep == .idle {
                // 未開始時の説明
                VStack(alignment: .leading, spacing: 8) {
                    Text("キャリブレーションの流れ:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 8) {
                            Text("1.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("指定された場所にタグを置く")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        HStack(alignment: .top, spacing: 8) {
                            Text("2.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("「センシング開始」ボタンを押す")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        HStack(alignment: .top, spacing: 8) {
                            Text("3.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("10秒間データを収集")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        HStack(alignment: .top, spacing: 8) {
                            Text("4.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("推定アンテナ位置を確認")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        HStack(alignment: .top, spacing: 8) {
                            Text("5.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("全ての基準点で1-4を繰り返す")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }

            // リアルタイムデータ表示（データ収集中のみ）
            if self.viewModel.calibrationStep == .collecting {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundColor(.green)
                        Text("リアルタイムデータ")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("収集: \(self.viewModel.collectedDataCount)件")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }

                    // 現在位置表示
                    if let currentPos = self.viewModel.currentPosition {
                        HStack {
                            Image(systemName: "location.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("現在位置: X:\(String(format: "%.2f", currentPos.x))m Y:\(String(format: "%.2f", currentPos.y))m")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                        }
                        .padding(.vertical, 4)
                    }

                    if self.viewModel.realtimeDataList.isEmpty {
                        Text("データ受信待機中...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(self.viewModel.realtimeDataList, id: \.deviceName) { deviceData in
                                if let latestData = deviceData.latestData {
                                    HStack(spacing: 8) {
                                        // デバイス名
                                        Text(deviceData.deviceName)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.blue)
                                            .frame(width: 60, alignment: .leading)

                                        // 距離
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("距離")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Text(String(format: "%.2fm", latestData.distance))
                                                .font(.caption)
                                                .fontWeight(.medium)
                                        }
                                        .frame(width: 55, alignment: .leading)

                                        // RSSI
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("RSSI")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Text("\(latestData.rssi)dBm")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                        }
                                        .frame(width: 60, alignment: .leading)

                                        // NLOS
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("LOS")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            HStack(spacing: 2) {
                                                Circle()
                                                    .fill(latestData.nlos == 0 ? Color.green : Color.orange)
                                                    .frame(width: 6, height: 6)
                                                Text(latestData.nlos == 0 ? "○" : "×")
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                            }
                                        }
                                        .frame(width: 40, alignment: .leading)

                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(Color.secondary.opacity(0.05))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }

            // センシング開始ボタン（タグ配置段階でのみ表示）
            if self.viewModel.canStartSensing {
                Button(action: self.viewModel.startDataCollectionForCurrentPoint) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("センシング開始")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundColor(.white)
                    .background(Color.orange)
                    .cornerRadius(12)
                }
            }

            // アンテナ位置表示（推定位置表示段階）
            if self.viewModel.isShowingAntennaPosition,
               let estimatedPosition = self.viewModel.estimatedAntennaPosition
            {
                VStack(alignment: .leading, spacing: 8) {
                    Text("推定アンテナ位置:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("X: \(String(format: "%.2f", estimatedPosition.x)) m")
                                .font(.subheadline)
                            Text("Y: \(String(format: "%.2f", estimatedPosition.y)) m")
                                .font(.subheadline)
                            Text("Z: \(String(format: "%.2f", estimatedPosition.z)) m")
                                .font(.subheadline)
                        }

                        Spacer()
                    }
                }
                .padding()
                .background(Color.green.opacity(0.2))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(self.statusBackgroundColor)
        .cornerRadius(12)
    }

    // ステータス表示用のヘルパー
    private var statusIcon: String {
        switch self.viewModel.calibrationStep {
        case .idle:
            return "circle.dashed"
        case .placingTag:
            return "hand.point.up.left.fill"
        case .readyToStart, .collecting:
            return "antenna.radiowaves.left.and.right"
        case .showingAntennaPosition:
            return "location.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch self.viewModel.calibrationStep {
        case .idle:
            return .secondary
        case .placingTag:
            return .orange
        case .readyToStart, .collecting:
            return .blue
        case .showingAntennaPosition:
            return .green
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }

    private var statusTitle: String {
        switch self.viewModel.calibrationStep {
        case .idle:
            return "キャリブレーション待機中"
        case .placingTag:
            return "タグ配置中"
        case .readyToStart:
            return "センシング準備完了"
        case .collecting:
            return "データ収集中"
        case .showingAntennaPosition:
            return "アンテナ位置推定完了"
        case .completed:
            return "キャリブレーション完了"
        case .failed:
            return "エラー発生"
        }
    }

    private var statusBackgroundColor: Color {
        switch self.viewModel.calibrationStep {
        case .idle:
            return Color.secondary.opacity(0.05)
        case .placingTag:
            return Color.orange.opacity(0.1)
        case .readyToStart, .collecting:
            return Color.blue.opacity(0.1)
        case .showingAntennaPosition:
            return Color.green.opacity(0.1)
        case .completed:
            return Color.green.opacity(0.1)
        case .failed:
            return Color.red.opacity(0.1)
        }
    }

    private var antennaPositionsResultView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("キャリブレーション結果")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: self.viewModel.dismissAntennaPositionsResult) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
            }

            Text("計算されたアンテナ位置:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                ForEach(Array(self.viewModel.finalAntennaPositions.keys.sorted()), id: \.self) { antennaId in
                    if let position = viewModel.finalAntennaPositions[antennaId] {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundColor(.blue)

                            Text(antennaId)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("X: \(String(format: "%.2f", position.x)) m")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Y: \(String(format: "%.2f", position.y)) m")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Z: \(String(format: "%.2f", position.z)) m")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if self.viewModel.canGoBack {
                Button("戻る") {
                    self.viewModel.goBack()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(.blue)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }

            if self.viewModel.canProceedToNext {
                Button("次へ") {
                    self.viewModel.proceedToNext()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(.white)
                .background(Color.blue)
                .cornerRadius(12)
            }
        }
    }
}

// MARK: - Preview

struct SimpleCalibrationView_Previews: PreviewProvider {
    static var previews: some View {
        SimpleCalibrationView()
            .environmentObject(NavigationRouterModel())
    }
}
