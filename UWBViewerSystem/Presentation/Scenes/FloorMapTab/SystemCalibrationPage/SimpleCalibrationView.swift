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
            Text("基準座標設定")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 4) {
                Text("フロアマップ上で3つの基準座標を設定してください (\(viewModel.referencePoints.count)/3)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if !viewModel.antennaPositions.isEmpty {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                            .font(.caption)

                        Text("青色のアンテナが選択中、灰色のアンテナが他の配置済みアンテナです")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // フロアマップビュー
            ZStack {
                // 背景
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 300)

                if let floorMapImage = viewModel.floorMapImage {
                    // フロアマップ画像がある場合
                    #if canImport(UIKit)
                    Image(uiImage: floorMapImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 300)
                        .clipped()
                    #elseif canImport(AppKit)
                    Image(nsImage: floorMapImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 300)
                        .clipped()
                    #endif
                } else {
                    // フロアマップ画像がない場合のプレースホルダー
                    VStack(spacing: 8) {
                        Image(systemName: "map")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)

                        if let floorMapInfo = viewModel.currentFloorMapInfo {
                            Text(floorMapInfo.name)
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text("画像ファイルが見つかりません")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Text("フロアマップが設定されていません")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text("フロアマップタブで設定してください")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }

                        Text("タップして座標を設定")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // 配置済みアンテナの表示
                ForEach(viewModel.antennaPositions) { antenna in
                    CalibrationAntennaMarker(
                        antenna: antenna,
                        isSelected: antenna.antennaId == viewModel.selectedAntennaId,
                        mapSize: CGSize(width: 300, height: 300) // マップ表示サイズに調整
                    )
                }

                // 設定済み基準点の表示
                ForEach(0..<viewModel.referencePoints.count, id: \.self) { index in
                    let point = viewModel.referencePoints[index]
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Text("\(index + 1)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        )
                        .position(
                            x: CGFloat(point.x * 10),
                            y: CGFloat(point.y * 10)
                        )
                }
            }
            .cornerRadius(12)
            .onTapGesture { location in
                if viewModel.referencePoints.count < 3 {
                    let point = Point3D(
                        x: Double(location.x / 10),
                        y: Double(location.y / 10),
                        z: 0.0
                    )
                    viewModel.addReferencePoint(point)
                }
            }

            // 設定済み座標の表示
            if !viewModel.referencePoints.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("設定済み座標")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ForEach(0..<viewModel.referencePoints.count, id: \.self) { index in
                        let point = viewModel.referencePoints[index]
                        HStack {
                            Text("座標 \(index + 1)")
                                .font(.caption)

                            Spacer()

                            Text(String(format: "(%.1f, %.1f, %.1f)", point.x, point.y, point.z))
                                .font(.caption)
                                .fontDesign(.monospaced)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                }

                Button("座標をクリア") {
                    viewModel.clearReferencePoints()
                }
                .foregroundColor(.red)
                .font(.caption)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
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

// MARK: - Calibration Antenna Marker

struct CalibrationAntennaMarker: View {
    let antenna: AntennaPositionData
    let isSelected: Bool
    let mapSize: CGSize

    // アンテナの位置をマップ座標に変換（簡単な正規化）
    private var displayPosition: CGPoint {
        // アンテナ位置データから実際の表示位置を計算
        // ここでは簡易的な実装として、フロアマップのサイズに基づいて正規化
        CGPoint(
            x: min(max(antenna.position.x * 30, 0), mapSize.width),
            y: min(max(antenna.position.y * 30, 0), mapSize.height)
        )
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                // アンテナ背景円
                Circle()
                    .fill(isSelected ? Color.blue : Color.gray)
                    .frame(width: 24, height: 24)
                    .shadow(radius: isSelected ? 3 : 1)

                // アンテナアイコン（回転対応）
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(antenna.rotation))

                // 向きを示す矢印（選択時または回転がある場合）
                if isSelected || antenna.rotation != 0 {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 8))
                        .foregroundColor(.yellow)
                        .offset(y: -18)
                        .rotationEffect(.degrees(antenna.rotation))
                }
            }

            // アンテナ名表示
            Text(antenna.antennaName)
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isSelected ? Color.blue.opacity(0.8) : Color.gray.opacity(0.8))
                )
                .foregroundColor(.white)
        }
        .position(displayPosition)
        .scaleEffect(isSelected ? 1.2 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - Preview

struct SimpleCalibrationView_Previews: PreviewProvider {
    static var previews: some View {
        SimpleCalibrationView()
            .environmentObject(NavigationRouterModel())
    }
}
