import SwiftData
import SwiftUI

/// システムキャリブレーション画面
/// 新しいセンシングフローの4番目の画面
struct SystemCalibrationView: View {
    @ObservedObject var viewModel: SystemCalibrationViewModel
    @StateObject private var flowNavigator = SensingFlowNavigator()
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var router: NavigationRouterModel

    init(viewModel: SystemCalibrationViewModel? = nil) {
        if let viewModel {
            self.viewModel = viewModel
        } else {
            self.viewModel = SystemCalibrationViewModel()
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // フロープログレス表示
                SensingFlowProgressView(navigator: flowNavigator)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // ヘッダー
                        headerSection

                        // キャリブレーションステータス
                        calibrationStatusSection

                        // キャリブレーション手順
                        calibrationStepsSection

                        // 自動キャリブレーション設定
                        autoCalibrationSection

                        // 新しいキャリブレーション機能
                        leastSquaresCalibrationSection

                        // キャリブレーション実行
                        calibrationControlSection

                        Spacer(minLength: 80)
                    }
                    .padding()
                }

                // ナビゲーションボタン
                navigationButtons
            }
        }
        .onAppear {
            viewModel.initialize()
            flowNavigator.currentStep = .systemCalibration
            flowNavigator.setRouter(router)
        }
        .alert("エラー", isPresented: $viewModel.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert("キャリブレーション完了", isPresented: $viewModel.showSuccessAlert) {
            Button("確認", role: .cancel) {}
        } message: {
            Text("システムキャリブレーションが正常に完了しました")
        }
        .sheet(isPresented: $viewModel.showManualCalibrationSheet) {
            ManualCalibrationSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showMapBasedCalibrationSheet) {
            if let floorMapId = viewModel.getCurrentFloorMapId() {
                MapBasedCalibrationView(antennaId: viewModel.selectedAntennaId, floorMapId: floorMapId)
            }
        }
        .sheet(isPresented: $viewModel.showIntegratedCalibrationSheet) {
            IntegratedCalibrationWorkflowView(viewModel: viewModel)
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
                    Text("システムキャリブレーション")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("UWBセンシングシステムの精度を向上させます")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Calibration Status Section

    private var calibrationStatusSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("キャリブレーション状況")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(spacing: 16) {
                // 全体の進行状況
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("全体の進行状況")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Spacer()

                        Text("\(Int(viewModel.overallProgress * 100))%")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    ProgressView(value: viewModel.overallProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .tint(progressColor)
                }

                // 現在のステップ
                HStack {
                    Image(systemName: viewModel.currentStepIcon)
                        .foregroundColor(statusColor)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.currentStepTitle)
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text(viewModel.currentStepDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(viewModel.calibrationStatus.displayText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    // MARK: - Calibration Steps Section

    private var calibrationStepsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("キャリブレーション手順")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(spacing: 12) {
                ForEach(Array(SystemCalibrationStep.allCases.enumerated()), id: \.element) { index, step in
                    CalibrationStepRow(
                        step: step,
                        stepNumber: index + 1,
                        isCompleted: viewModel.isStepCompleted(step),
                        isCurrent: viewModel.currentCalibrationStep == step,
                        isEnabled: viewModel.isStepEnabled(step)
                    )
                    .onTapGesture {
                        if viewModel.isStepEnabled(step) {
                            viewModel.selectStep(step)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    // MARK: - Auto Calibration Section

    private var autoCalibrationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("自動キャリブレーション設定")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("自動キャリブレーションを有効にする")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("セッション開始時に自動的にキャリブレーションを実行します")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $viewModel.isAutoCalibrationEnabled)
                }

                if viewModel.isAutoCalibrationEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("キャリブレーション間隔")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Picker("間隔", selection: $viewModel.calibrationInterval) {
                            ForEach(CalibrationInterval.allCases, id: \.self) { interval in
                                Text(interval.displayText).tag(interval)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    // MARK: - Calibration Control Section

    private var calibrationControlSection: some View {
        VStack(spacing: 16) {
            if viewModel.calibrationStatus == .idle {
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
            } else if viewModel.calibrationStatus == .running {
                VStack(spacing: 12) {
                    Button(action: viewModel.pauseCalibration) {
                        HStack {
                            Image(systemName: "pause.fill")
                            Text("一時停止")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(.white)
                        .background(Color.orange)
                        .cornerRadius(12)
                    }

                    Button(action: viewModel.cancelCalibration) {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("キャンセル")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(.white)
                        .background(Color.red)
                        .cornerRadius(12)
                    }
                }
            } else if viewModel.calibrationStatus == .paused {
                HStack(spacing: 12) {
                    Button(action: viewModel.resumeCalibration) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("再開")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(.white)
                        .background(Color.blue)
                        .cornerRadius(12)
                    }

                    Button(action: viewModel.cancelCalibration) {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("キャンセル")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(.white)
                        .background(Color.red)
                        .cornerRadius(12)
                    }
                }
            }

            // 手動キャリブレーションボタン
            Button(action: viewModel.openManualCalibration) {
                HStack {
                    Image(systemName: "hand.point.up")
                    Text("手動キャリブレーション")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(.blue)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }
            .disabled(viewModel.calibrationStatus == .running)

            // マップベースキャリブレーションボタン
            Button(action: viewModel.openMapBasedCalibration) {
                HStack {
                    Image(systemName: "map")
                    Text("マップベースキャリブレーション")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(.green)
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            }
            .disabled(viewModel.calibrationStatus == .running)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    // MARK: - 最小二乗法キャリブレーション

    private var leastSquaresCalibrationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("最小二乗法キャリブレーション")
                .font(.headline)
                .foregroundColor(.primary)

            // アンテナ選択
            VStack(alignment: .leading, spacing: 8) {
                Text("対象アンテナ")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Picker("アンテナ選択", selection: $viewModel.selectedAntennaId) {
                    ForEach(viewModel.availableAntennas) { antenna in
                        Text(antenna.name).tag(antenna.id)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .onChange(of: viewModel.selectedAntennaId) {
                    viewModel.loadCalibrationDataForSelectedAntenna()
                }
            }

            // キャリブレーション統計情報
            if let statistics = viewModel.calibrationStatistics {
                VStack(alignment: .leading, spacing: 8) {
                    Text("キャリブレーション状況")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack {
                        VStack(alignment: .leading) {
                            Text("完了率")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(Int(statistics.completionPercentage))%")
                                .font(.title2)
                                .fontWeight(.bold)
                        }

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text("平均精度")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.2f", statistics.averageAccuracy))
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                    }
                }
            }

            // 統合キャリブレーションワークフロー
            VStack(alignment: .leading, spacing: 12) {
                Text("統合キャリブレーションワークフロー")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.purple)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("基準点数: \(viewModel.referencePointsCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("観測セッション: \(viewModel.observationSessionsCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("状態: \(viewModel.workflowStatusText)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if viewModel.workflowProgress > 0 {
                            Text(viewModel.workflowProgressText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if viewModel.isObservationCollecting {
                    HStack {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundColor(.green)
                        Text("観測データ収集中...")
                            .font(.caption)
                            .foregroundColor(.green)
                        Spacer()
                    }
                }

                Button(action: viewModel.startIntegratedCalibration) {
                    HStack {
                        Image(systemName: "waveform.path.ecg")
                        Text("統合ワークフロー開始")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundColor(.white)
                    .background(Color.purple)
                    .cornerRadius(8)
                }
                .disabled(viewModel.selectedAntennaId.isEmpty)
            }

            Divider()

            // 従来のキャリブレーションボタン
            VStack(alignment: .leading, spacing: 12) {
                Text("従来の手動キャリブレーション")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 12) {
                    Button(action: {
                        viewModel.performLeastSquaresCalibration()
                    }) {
                        HStack {
                            Image(systemName: "target")
                            Text("個別実行")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(.white)
                        .background(Color.green)
                        .cornerRadius(8)
                    }
                    .disabled(viewModel.selectedAntennaId.isEmpty)

                    Button(action: viewModel.performAllCalibrations) {
                        HStack {
                            Image(systemName: "target")
                            Text("全実行")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(.white)
                        .background(Color.blue)
                        .cornerRadius(8)
                    }
                    .disabled(viewModel.availableAntennas.isEmpty)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            Button(action: {
                flowNavigator.goToPreviousStep()
            }) {
                HStack {
                    Image(systemName: "chevron.left")
                    Text("戻る")
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.2))
                .foregroundColor(.primary)
                .cornerRadius(12)
            }

            Button(action: {
                flowNavigator.proceedToNextStep()
            }) {
                HStack {
                    Text("次へ")
                    Image(systemName: "chevron.right")
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!viewModel.canProceedToNext)
        }
        .padding()
        .background(Color.clear)
    }

    // MARK: - Computed Properties

    private var progressColor: Color {
        switch viewModel.calibrationStatus {
        case .idle:
            return .gray
        case .running:
            return .blue
        case .paused:
            return .orange
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }

    private var statusColor: Color {
        switch viewModel.calibrationStatus {
        case .idle:
            return .gray
        case .running:
            return .blue
        case .paused:
            return .orange
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
}

// MARK: - Calibration Step Row

struct CalibrationStepRow: View {
    let step: SystemCalibrationStep
    let stepNumber: Int
    let isCompleted: Bool
    let isCurrent: Bool
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            // ステップ番号またはチェックマーク
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 32, height: 32)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .bold))
                } else {
                    Text("\(stepNumber)")
                        .foregroundColor(textColor)
                        .font(.system(size: 14, weight: .medium))
                }
            }

            // ステップ情報
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isEnabled ? .primary : .secondary)

                Text(step.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // ステータスアイコン
            if isCurrent {
                Image(systemName: "arrow.right")
                    .foregroundColor(.blue)
                    .font(.caption)
            }
        }
        .padding(.vertical, 8)
        .opacity(isEnabled ? 1.0 : 0.6)
    }

    private var backgroundColor: Color {
        if isCompleted {
            return .green
        } else if isCurrent {
            return .blue
        } else if isEnabled {
            return Color.gray.opacity(0.3)
        } else {
            return Color.gray.opacity(0.2)
        }
    }

    private var textColor: Color {
        if isCurrent {
            return .white
        } else {
            return .secondary
        }
    }
}

// MARK: - Manual Calibration Sheet

struct ManualCalibrationSheet: View {
    @ObservedObject var viewModel: SystemCalibrationViewModel
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // ヘッダー
                    VStack(alignment: .leading, spacing: 8) {
                        Text("手動キャリブレーション")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("正確な座標で測定することで、システムの精度を向上できます")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // 現在のキャリブレーション点
                    if !viewModel.calibrationPoints.isEmpty {
                        calibrationPointsList
                    }

                    // 新しい測定点の追加
                    newCalibrationPointSection

                    Spacer(minLength: 50)
                }
                .padding()
            }
            .navigationTitle("")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .navigationBarBackButtonHidden(true)
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .fontWeight(.semibold)
                }
#elseif os(macOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .fontWeight(.semibold)
                }
#endif
            }
        }
    }

    private var calibrationPointsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("登録済み測定点")
                .font(.headline)

            LazyVStack(spacing: 8) {
                ForEach(viewModel.calibrationPoints) { point in
                    CalibrationPointRow(
                        point: point,
                        onDelete: { viewModel.removeCalibrationPoint(pointId: point.id) }
                    )
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    private var newCalibrationPointSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新しい測定点を追加")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                Text("正解座標（実際の位置）")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("X (m)")
                            .font(.caption)
                        TextField("0.0", text: $viewModel.referenceX)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
#if os(iOS)
                            .keyboardType(.decimalPad)
#endif
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Y (m)")
                            .font(.caption)
                        TextField("0.0", text: $viewModel.referenceY)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
#if os(iOS)
                            .keyboardType(.decimalPad)
#endif
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Z (m)")
                            .font(.caption)
                        TextField("0.0", text: $viewModel.referenceZ)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
#if os(iOS)
                            .keyboardType(.decimalPad)
#endif
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("測定座標（センサー値）")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("X (m)")
                            .font(.caption)
                        TextField("0.0", text: $viewModel.measuredX)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
#if os(iOS)
                            .keyboardType(.decimalPad)
#endif
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Y (m)")
                            .font(.caption)
                        TextField("0.0", text: $viewModel.measuredY)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
#if os(iOS)
                            .keyboardType(.decimalPad)
#endif
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Z (m)")
                            .font(.caption)
                        TextField("0.0", text: $viewModel.measuredZ)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
#if os(iOS)
                            .keyboardType(.decimalPad)
#endif
                    }
                }
            }

            Button("測定点を追加") {
                viewModel.addCalibrationPoint()
            }
            .frame(maxWidth: .infinity)
            .padding()
            .foregroundColor(.white)
            .background(canAddPoint ? Color.blue : Color.gray)
            .cornerRadius(8)
            .disabled(!canAddPoint)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    private var canAddPoint: Bool {
        !viewModel.referenceX.isEmpty &&
        !viewModel.referenceY.isEmpty &&
        !viewModel.measuredX.isEmpty &&
        !viewModel.measuredY.isEmpty &&
        Double(viewModel.referenceX) != nil &&
        Double(viewModel.referenceY) != nil &&
        Double(viewModel.measuredX) != nil &&
        Double(viewModel.measuredY) != nil
    }
}

// MARK: - Calibration Point Row

struct CalibrationPointRow: View {
    let point: CalibrationPoint
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("正解: (\(String(format: "%.2f", point.referencePosition.x)), \(String(format: "%.2f", point.referencePosition.y)), \(String(format: "%.2f", point.referencePosition.z)))")
                    .font(.caption)
                    .foregroundColor(.primary)

                Text("測定: (\(String(format: "%.2f", point.measuredPosition.x)), \(String(format: "%.2f", point.measuredPosition.y)), \(String(format: "%.2f", point.measuredPosition.z)))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("誤差: \(String(format: "%.3f", point.referencePosition.distance(to: point.measuredPosition)))m")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(8)
        .shadow(radius: 1)
    }
}

// MARK: - Preview

struct SystemCalibrationView_Previews: PreviewProvider {
    static var previews: some View {
        SystemCalibrationView()
    }
}
