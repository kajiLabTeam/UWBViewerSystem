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
            SensingFlowProgressView(navigator: flowNavigator)

            ScrollView {
                VStack(spacing: 24) {
                    // ヘッダー
                    headerSection

                    // ステップ内容
                    currentStepContent

                    // ナビゲーションボタン
                    navigationButtons

                    Spacer(minLength: 80)
                }
                .padding()
            }
        }
        .onAppear {
            // SwiftDataのModelContextを設定
            viewModel.setModelContext(modelContext)

            viewModel.loadInitialData()
            viewModel.reloadData()  // 常に最新のフロアマップデータを取得
            flowNavigator.currentStep = .systemCalibration
            flowNavigator.setRouter(router)

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
            let nearbyRepository = NearbyRepository()
            let connectionUsecase = ConnectionManagementUsecase(nearbyRepository: nearbyRepository)
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
            viewModel.setupStepByStepCalibration(
                calibrationDataFlow: calibrationDataFlow,
                observationUsecase: observationUsecase
            )
        }
        .alert("エラー", isPresented: $viewModel.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert("キャリブレーション完了", isPresented: $viewModel.showSuccessAlert) {
            Button("新しいキャリブレーション", role: .none) {
                viewModel.resetCalibration()
            }
            Button("完了", role: .cancel) {
                flowNavigator.proceedToNextStep()
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

                    Text("ステップ \(viewModel.currentStep + 1) / 3: \(viewModel.currentStepTitle)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // プログレスバー
            ProgressView(value: Double(viewModel.currentStep), total: 2.0)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Step Content

    @ViewBuilder
    private var currentStepContent: some View {
        switch viewModel.currentStep {
        case 0:
            antennaSelectionContent
        case 1:
            coordinateSelectionContent
        case 2:
            calibrationExecutionContent
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

            if viewModel.availableAntennas.isEmpty {
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
                    ForEach(viewModel.availableAntennas, id: \.id) { antenna in
                        let isPositioned = viewModel.antennaPositions.contains { $0.antennaId == antenna.id }
                        let antennaPosition = viewModel.antennaPositions.first { $0.antennaId == antenna.id }

                        Button(action: {
                            viewModel.selectAntenna(antenna.id)
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
                                    if antenna.id == viewModel.selectedAntennaId {
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
                                antenna.id == viewModel.selectedAntennaId
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
            coordinateSelectionHeader
            floorMapDisplayView
            referencePointsList
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
                Text("フロアマップ上で3つの基準座標を設定してください (\(viewModel.referencePoints.count)/3)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if !viewModel.antennaPositions.isEmpty {
                    antennaInfoHint
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
            floorMapImage: viewModel.floorMapImage,
            floorMapInfo: viewModel.currentFloorMapInfo,
            onMapTap: handleMapTap
        ) { geometry in
            // アンテナ表示
            ForEach(viewModel.antennaPositions) { antenna in
                let antennaDisplayData = AntennaDisplayData(
                    id: antenna.antennaId,
                    name: antenna.antennaName,
                    rotation: antenna.rotation,
                    color: antenna.antennaId == viewModel.selectedAntennaId ? .blue : .gray
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
                    isSelected: antenna.antennaId == viewModel.selectedAntennaId,
                    isDraggable: false,
                    showRotationControls: false
                )
            }

            // 基準点表示
            ForEach(Array(viewModel.referencePoints.enumerated()), id: \.offset) { index, point in
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
        }
    }

    private func handleMapTap(at location: CGPoint) {
        if viewModel.referencePoints.count < 3 {
            let point = Point3D(
                x: Double(location.x),
                y: Double(location.y),
                z: 0.0
            )
            viewModel.addReferencePoint(point)
        }
    }

    private var referencePointsList: some View {
        let referencePointsData = viewModel.referencePoints.enumerated().map { index, point in
            ReferencePointDisplayData(
                id: "\(index)",
                label: "\(index + 1)",
                color: .red,
                coordinates: point
            )
        }

        return ReferencePointList(
            points: referencePointsData,
            onClear: { viewModel.clearReferencePoints() },
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
                        Text(viewModel.selectedAntennaId)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                    }

                    HStack {
                        Text("基準座標数:")
                            .font(.subheadline)
                        Text("\(viewModel.referencePoints.count)個")
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
                if viewModel.isCalibrating {
                    VStack(spacing: 16) {
                        ProgressView(value: viewModel.calibrationProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .blue))

                        Text("キャリブレーション実行中... \(viewModel.progressPercentage)")
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
                                .foregroundColor(viewModel.calibrationResultColor)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("キャリブレーション\(viewModel.calibrationResultText)")
                                    .font(.headline)
                                    .foregroundColor(viewModel.calibrationResultColor)

                                Text("精度: \(viewModel.calibrationAccuracyText)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                    }
                    .padding()
                    .background(viewModel.calibrationResultColor.opacity(0.1))
                    .cornerRadius(12)
                } else {
                    VStack(spacing: 12) {
                        // 通常のキャリブレーション実行ボタン
                        Button(action: viewModel.startCalibration) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("キャリブレーション開始")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(.white)
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                        .disabled(!viewModel.canStartCalibration)

                        // 段階的キャリブレーション実行ボタン
                        Button(action: viewModel.startStepByStepCalibration) {
                            HStack {
                                Image(systemName: "figure.walk")
                                Text("段階的キャリブレーション開始")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(.white)
                            .background(Color.green)
                            .cornerRadius(12)
                        }
                        .disabled(!viewModel.canStartCalibration)
                    }
                }
            }

            // 段階的キャリブレーション進行状況表示
            if viewModel.isStepByStepCalibrationActive {
                stepByStepCalibrationProgressView
            }

            // アンテナ位置結果表示
            if viewModel.showAntennaPositionsResult {
                antennaPositionsResultView
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - 段階的キャリブレーション関連ビュー

    private var stepByStepCalibrationProgressView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("段階的キャリブレーション実行中")
                .font(.headline)
                .foregroundColor(.green)

            // 現在のステップ情報
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("ステップ \(viewModel.currentStepNumber) / \(viewModel.totalSteps)")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    Text(String(format: "%.0f%%", viewModel.stepProgress * 100))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                ProgressView(value: viewModel.stepProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .green))
            }

            // 現在のステップ指示
            if !viewModel.currentStepInstructions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("指示:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(viewModel.currentStepInstructions)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }

            // データ収集進行状況
            if viewModel.dataCollectionProgress > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("データ収集中:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        if viewModel.timeRemaining > 0 {
                            Text("残り \(Int(viewModel.timeRemaining))秒")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    ProgressView(value: viewModel.dataCollectionProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .orange))
                }
            }

            // データ収集開始ボタン
            Button(action: viewModel.startDataCollectionForCurrentPoint) {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("データ収集開始")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(.white)
                .background(Color.orange)
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }

    private var antennaPositionsResultView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("キャリブレーション結果")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: viewModel.dismissAntennaPositionsResult) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
            }

            Text("計算されたアンテナ位置:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                ForEach(Array(viewModel.finalAntennaPositions.keys.sorted()), id: \.self) { antennaId in
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
            if viewModel.canGoBack {
                Button("戻る") {
                    viewModel.goBack()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(.blue)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }

            if viewModel.canProceedToNext {
                Button("次へ") {
                    viewModel.proceedToNext()
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
