import SwiftData
import SwiftUI

/// 自動アンテナキャリブレーション画面
///
/// 各アンテナの位置と角度を自動推定するためのキャリブレーション画面。
/// 複数のタグ位置（既知）でセンシングを行い、各アンテナが観測した座標から
/// アフィン変換を推定してアンテナのANTENNA_CONFIGを自動生成します。
struct AutoAntennaCalibrationView: View {
    @StateObject private var viewModel = AutoAntennaCalibrationViewModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            self.headerSection

            ScrollView {
                VStack(spacing: 24) {
                    // ステップコンテンツ
                    self.currentStepContent

                    // ナビゲーションボタン
                    self.navigationButtons

                    Spacer(minLength: 80)
                }
                .padding()
            }
        }
        .onAppear {
            self.viewModel.setup(modelContext: self.modelContext)
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
            Button("完了", role: .cancel) {}
        } message: {
            Text("全てのアンテナのキャリブレーションが正常に完了しました")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(.blue)
                    .font(.title)

                VStack(alignment: .leading, spacing: 4) {
                    Text("自動アンテナキャリブレーション")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("ステップ \(self.viewModel.currentStep + 1) / 3: \(self.viewModel.currentStepTitle)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            ProgressView(value: Double(self.viewModel.currentStep), total: 2.0)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
    }

    // MARK: - Step Content

    @ViewBuilder
    private var currentStepContent: some View {
        switch self.viewModel.currentStep {
        case 0:
            self.tagPositionSetupStep
        case 1:
            self.dataCollectionStep
        case 2:
            self.calibrationExecutionStep
        default:
            EmptyView()
        }
    }

    // MARK: - Step 1: タグ位置設定

    private var tagPositionSetupStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ステップ1: タグ位置設定")
                .font(.headline)

            Text("フロアマップ上で既知のタグ位置を3つ以上設定してください")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // フロアマップ
            if let floorMapImage = viewModel.floorMapImage,
               let floorMapInfo = viewModel.currentFloorMapInfo
            {
                FloorMapCanvas(
                    floorMapImage: floorMapImage,
                    floorMapInfo: floorMapInfo,
                    calibrationPoints: nil,
                    onMapTap: self.handleMapTap
                ) { geometry in
                    // タグマーカーを表示
                    ForEach(Array(self.viewModel.trueTagPositions.enumerated()), id: \.offset) {
                        index, tagPos in
                        let normalizedPoint = geometry.realWorldToNormalized(
                            CGPoint(x: tagPos.position.x, y: tagPos.position.y)
                        )
                        let displayPosition = geometry.normalizedToImageCoordinate(normalizedPoint)

                        ZStack {
                            Circle()
                                .fill(tagPos.isCollected ? Color.green : Color.blue)
                                .frame(width: 32, height: 32)

                            Text("\(index + 1)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)

                            if tagPos.isCollected {
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                                    .offset(x: 12, y: -12)
                            }
                        }
                        .position(displayPosition)
                    }
                }
            } else {
                Text("フロアマップを読み込んでいます...")
                    .frame(maxWidth: .infinity, minHeight: 300)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
            }

            // タグリスト
            self.tagPositionList

            // アンテナ選択
            self.antennaSelectionSection
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }

    private var tagPositionList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("設定済みタグ位置 (\(self.viewModel.trueTagPositions.count)個)")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if !self.viewModel.trueTagPositions.isEmpty {
                    Button("全てクリア") {
                        self.viewModel.clearTagPositions()
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }

            if self.viewModel.trueTagPositions.isEmpty {
                Text("マップをタップしてタグ位置を設定してください")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(self.viewModel.trueTagPositions.enumerated()), id: \.offset) {
                        index, tagPos in
                        HStack {
                            Circle()
                                .fill(tagPos.isCollected ? Color.green : Color.blue)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Text("\(index + 1)")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(tagPos.tagId)
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Text(
                                    "X: \(String(format: "%.2f", tagPos.position.x))m, Y: \(String(format: "%.2f", tagPos.position.y))m"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }

                            Spacer()

                            if tagPos.isCollected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }

                            Button(action: {
                                self.viewModel.removeTagPosition(at: index)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    private var antennaSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("キャリブレーション対象アンテナ")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                HStack(spacing: 12) {
                    Button("全選択") {
                        self.viewModel.selectAllAntennas()
                    }
                    .font(.caption)

                    Button("全解除") {
                        self.viewModel.deselectAllAntennas()
                    }
                    .font(.caption)
                }
            }

            if self.viewModel.availableAntennas.isEmpty {
                Text("利用可能なアンテナがありません")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(self.viewModel.availableAntennas) { antenna in
                        Button(action: {
                            self.viewModel.toggleAntennaSelection(antenna.id)
                        }) {
                            HStack {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .foregroundColor(antenna.isSelected ? .blue : .gray)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(antenna.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)

                                    Text(antenna.id)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if antenna.isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding()
                            .background(
                                antenna.isSelected
                                    ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.05)
                            )
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: - Step 2: データ収集

    private var dataCollectionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ステップ2: データ収集")
                .font(.headline)

            Text("各タグ位置でセンシングを実行し、データを収集します")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // 進行状況
            if self.viewModel.isCollecting {
                VStack(spacing: 12) {
                    ProgressView(value: self.viewModel.collectionProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .green))

                    Text("データ収集中... \(Int(self.viewModel.collectionProgress * 100))%")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }

            // データ収集開始ボタン
            if !self.viewModel.isCollecting && self.viewModel.collectionProgress < 1.0 {
                Button(action: {
                    self.viewModel.startDataCollection()
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("データ収集開始")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundColor(.white)
                    .background(self.viewModel.canStartCollection ? Color.green : Color.gray)
                    .cornerRadius(12)
                }
                .disabled(!self.viewModel.canStartCollection)
            }

            // データ統計
            if !self.viewModel.dataStatistics.isEmpty {
                self.dataStatisticsView
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }

    private var dataStatisticsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("収集データ統計")
                .font(.subheadline)
                .fontWeight(.medium)

            ForEach(Array(self.viewModel.dataStatistics.keys.sorted()), id: \.self) { antennaId in
                if let tagData = viewModel.dataStatistics[antennaId] {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundColor(.blue)

                            Text(antennaId)
                                .font(.caption)
                                .fontWeight(.medium)

                            Spacer()

                            Text("計\(tagData.values.reduce(0, +))件")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }

                        ForEach(Array(tagData.keys.sorted()), id: \.self) { tagId in
                            HStack {
                                Text(tagId)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                Spacer()

                                Text("\(tagData[tagId] ?? 0)件")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .padding(.leading)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Step 3: キャリブレーション実行

    private var calibrationExecutionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ステップ3: キャリブレーション実行")
                .font(.headline)

            Text("収集したデータから各アンテナの位置と角度を自動推定します")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // キャリブレーション実行ボタン
            if !self.viewModel.isCalibrating && self.viewModel.calibrationResults.isEmpty {
                Button(action: {
                    self.viewModel.startCalibration()
                }) {
                    HStack {
                        Image(systemName: "waveform.path.ecg")
                        Text("キャリブレーション実行")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundColor(.white)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
            }

            // 実行中
            if self.viewModel.isCalibrating {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)

                    Text("キャリブレーション実行中...")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }

            // 結果表示
            if !self.viewModel.calibrationResults.isEmpty {
                self.calibrationResultsView
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }

    private var calibrationResultsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)

                Text("キャリブレーション結果")
                    .font(.headline)
                    .foregroundColor(.green)
            }

            ForEach(Array(self.viewModel.calibrationResults.keys.sorted()), id: \.self) { antennaId in
                if let result = viewModel.calibrationResults[antennaId] {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundColor(.blue)

                            Text(antennaId)
                                .font(.subheadline)
                                .fontWeight(.bold)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("位置:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text(
                                    "X: \(String(format: "%.3f", result.position.x))m, Y: \(String(format: "%.3f", result.position.y))m"
                                )
                                .font(.caption)
                                .fontWeight(.medium)
                            }

                            HStack {
                                Text("角度:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text("\(String(format: "%.2f", result.angleDegrees))°")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }

                            HStack {
                                Text("RMSE:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text("\(String(format: "%.4f", result.rmse))m")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(
                                        result.rmse < 0.1 ? .green : (result.rmse < 0.3 ? .orange : .red)
                                    )
                            }

                            HStack {
                                Text("スケール:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text(
                                    "sx: \(String(format: "%.3f", result.scaleFactors.sx)), sy: \(String(format: "%.3f", result.scaleFactors.sy))"
                                )
                                .font(.caption)
                                .fontWeight(.medium)
                            }
                        }
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Navigation

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

    // MARK: - Handlers

    private func handleMapTap(at location: CGPoint) {
        guard self.viewModel.currentStep == 0 else { return }

        let point = Point3D(
            x: Double(location.x),
            y: Double(location.y),
            z: 0.0
        )
        self.viewModel.addTagPosition(at: point)
    }
}

// MARK: - Preview

struct AutoAntennaCalibrationView_Previews: PreviewProvider {
    static var previews: some View {
        AutoAntennaCalibrationView()
    }
}
