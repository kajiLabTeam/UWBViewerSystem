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
            viewModel.reloadData() // 常に最新のフロアマップデータを取得
            flowNavigator.currentStep = .systemCalibration
            flowNavigator.setRouter(router)
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
                                        Text("位置: (\(String(format: "%.1f", position.position.x)), \(String(format: "%.1f", position.position.y)))")
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
                            .background(antenna.id == viewModel.selectedAntennaId ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.05))
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
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
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