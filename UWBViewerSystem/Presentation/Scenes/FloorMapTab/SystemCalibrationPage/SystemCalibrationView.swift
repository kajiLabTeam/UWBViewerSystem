import SwiftData
import SwiftUI

/// システムキャリブレーション画面
/// 新しいセンシングフローの4番目のステップ
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

                ScrollView {
                    VStack(spacing: 24) {
                        // ヘッダー
                        headerSection

                        // キャリブレーションステータス
                        calibrationStatusSection

                        // キャリブレーション手順
                        calibrationStepsSection

                        // 自動キャリブレーション設定
                        autoCalibrationSection

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
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        VStack(spacing: 12) {
            Divider()

            HStack(spacing: 16) {
                Button("戻る") {
                    flowNavigator.goToPreviousStep()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(.secondary)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)

                Button("次へ") {
                    flowNavigator.proceedToNextStep()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(.white)
                .background(viewModel.canProceedToNext ? Color.blue : Color.gray)
                .cornerRadius(8)
                .disabled(!viewModel.canProceedToNext)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
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
            return .secondary
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

// MARK: - Preview

struct SystemCalibrationView_Previews: PreviewProvider {
    static var previews: some View {
        SystemCalibrationView()
    }
}
