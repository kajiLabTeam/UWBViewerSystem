import Combine
import SwiftUI

/// 統合キャリブレーションワークフロービュー
struct IntegratedCalibrationWorkflowView: View {
    @ObservedObject var viewModel: SystemCalibrationViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep: WorkflowStep = .referenceSetup
    @State private var showValidationResults = false

    var body: some View {
        VStack(spacing: 0) {
            // プログレスインジケーター
            workflowProgressView

            ScrollView {
                VStack(spacing: 24) {
                    // ヘッダー
                    headerView

                    // ステップコンテンツ
                    stepContentView

                    // アクションボタン
                    actionButtonsView

                    // 検証結果
                    if showValidationResults {
                        validationResultsView
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("統合キャリブレーション")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") {
                            viewModel.resetIntegratedCalibration()
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("検証") {
                            showValidationResults.toggle()
                        }
                        .foregroundColor(.blue)
                    }
                }
        }
    }

    // MARK: - Progress View

    private var workflowProgressView: some View {
        VStack(spacing: 12) {
            // プログレスバー
            ProgressView(value: viewModel.workflowProgress)
                .progressViewStyle(LinearProgressViewStyle(tint: .purple))
                .scaleEffect(x: 1, y: 2, anchor: .center)

            // ステップ表示
            HStack {
                ForEach(WorkflowStep.allCases, id: \.self) { step in
                    stepIndicator(for: step)
                    if step != WorkflowStep.allCases.last {
                        Rectangle()
                            .fill(stepColor(for: step))
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            Text(viewModel.workflowStatusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
    }

    private func stepIndicator(for step: WorkflowStep) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(stepColor(for: step))
                    .frame(width: 30, height: 30)

                Image(systemName: step.icon)
                    .foregroundColor(.white)
                    .font(.caption)
            }

            Text(step.title)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .frame(width: 60)
        }
    }

    private func stepColor(for step: WorkflowStep) -> Color {
        let currentIndex = WorkflowStep.allCases.firstIndex(of: currentStep) ?? 0
        let stepIndex = WorkflowStep.allCases.firstIndex(of: step) ?? 0

        if stepIndex < currentIndex {
            return .green
        } else if stepIndex == currentIndex {
            return .purple
        } else {
            return .gray
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(.purple)
                    .font(.title)

                VStack(alignment: .leading, spacing: 4) {
                    Text("統合キャリブレーションワークフロー")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("アンテナ: \(viewModel.selectedAntennaId)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // 全体的な統計
            HStack {
                statCard(title: "基準点", value: "\(viewModel.referencePointsCount)", color: .blue)
                statCard(title: "観測セッション", value: "\(viewModel.observationSessionsCount)", color: .green)
                statCard(title: "進行率", value: viewModel.workflowProgressText, color: .purple)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    private func statCard(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Step Content View

    private var stepContentView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(currentStep.title)
                .font(.headline)
                .foregroundColor(.primary)

            Text(currentStep.description)
                .font(.body)
                .foregroundColor(.secondary)

            switch currentStep {
            case .referenceSetup:
                referenceSetupView
            case .observationCollection:
                observationCollectionView
            case .dataMapping:
                dataMappingView
            case .calibrationExecution:
                calibrationExecutionView
            case .validation:
                validationView
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Step-specific Views

    private var referenceSetupView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("基準座標の設定")
                .font(.subheadline)
                .fontWeight(.medium)

            VStack(spacing: 8) {
                Button("マップから基準点を選択") {
                    // マップベースの基準点設定
                    viewModel.showMapBasedCalibrationSheet = true
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.getCurrentFloorMapId() == nil)

                Text("または手動で基準座標を入力:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    TextField("X", text: $viewModel.referenceX)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    TextField("Y", text: $viewModel.referenceY)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    TextField("Z", text: $viewModel.referenceZ)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Button("追加") {
                        viewModel.addManualReferencePoint()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if viewModel.referencePointsCount > 0 {
                Text("設定済み基準点: \(viewModel.referencePointsCount)個")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.top, 8)
            }
        }
    }

    private var observationCollectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("観測データ収集")
                .font(.subheadline)
                .fontWeight(.medium)

            if viewModel.isObservationCollecting {
                VStack(spacing: 8) {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("観測データ収集中...")
                            .font(.caption)
                            .foregroundColor(.green)
                        Spacer()
                    }

                    Button("収集停止") {
                        viewModel.stopObservationCollection()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
            } else {
                VStack(spacing: 8) {
                    Text("アンテナ '\(viewModel.selectedAntennaId)' からの観測データを収集します")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("観測データ収集開始") {
                        viewModel.startObservationCollection()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if viewModel.observationSessionsCount > 0 {
                Text("収集済みセッション: \(viewModel.observationSessionsCount)個")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.top, 8)
            }
        }
    }

    private var dataMappingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("データマッピング")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("基準座標と観測データの対応付けを行います")
                .font(.caption)
                .foregroundColor(.secondary)

            if viewModel.referencePointsCount >= 3 && viewModel.observationSessionsCount > 0 {
                Button("マッピング実行") {
                    currentStep = .calibrationExecution
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("マッピングには基準点3個以上と観測データが必要です")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.top, 8)
            }
        }
    }

    private var calibrationExecutionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("キャリブレーション実行")
                .font(.subheadline)
                .fontWeight(.medium)

            if viewModel.isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("キャリブレーション計算中...")
                        .font(.caption)
                        .foregroundColor(.purple)
                }
            } else {
                Button("統合キャリブレーション実行") {
                    viewModel.executeIntegratedCalibration()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canExecuteWorkflow)
            }
        }
    }

    private var validationView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("検証と完了")
                .font(.subheadline)
                .fontWeight(.medium)

            if viewModel.workflowStatus == .completed {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("キャリブレーション完了!")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }

                    Button("閉じる") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text("キャリブレーション実行後に結果を確認できます")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtonsView: some View {
        HStack(spacing: 12) {
            Button("前のステップ") {
                goToPreviousStep()
            }
            .buttonStyle(.bordered)
            .disabled(currentStep == .referenceSetup)

            Spacer()

            Button("次のステップ") {
                goToNextStep()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canProceedToNextStep())

            Button("リセット") {
                viewModel.resetIntegratedCalibration()
                currentStep = .referenceSetup
            }
            .buttonStyle(.bordered)
            .foregroundColor(.red)
        }
    }

    // MARK: - Validation Results

    private var validationResultsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ワークフロー検証結果")
                .font(.headline)

            if let validation = viewModel.validateWorkflowState() {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: validation.canProceed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(validation.canProceed ? .green : .orange)
                        Text(validation.canProceed ? "実行可能" : "要改善")
                            .fontWeight(.medium)
                            .foregroundColor(validation.canProceed ? .green : .orange)
                    }

                    if !validation.issues.isEmpty {
                        Text("問題:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        ForEach(validation.issues, id: \.self) { issue in
                            Text("• \(issue)")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    if !validation.recommendations.isEmpty {
                        Text("推奨事項:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        ForEach(validation.recommendations, id: \.self) { recommendation in
                            Text("• \(recommendation)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Navigation Logic

    private func goToPreviousStep() {
        let currentIndex = WorkflowStep.allCases.firstIndex(of: currentStep) ?? 0
        if currentIndex > 0 {
            currentStep = WorkflowStep.allCases[currentIndex - 1]
        }
    }

    private func goToNextStep() {
        let currentIndex = WorkflowStep.allCases.firstIndex(of: currentStep) ?? 0
        if currentIndex < WorkflowStep.allCases.count - 1 {
            currentStep = WorkflowStep.allCases[currentIndex + 1]
        }
    }

    private func canProceedToNextStep() -> Bool {
        switch currentStep {
        case .referenceSetup:
            return viewModel.referencePointsCount >= 3
        case .observationCollection:
            return viewModel.observationSessionsCount > 0
        case .dataMapping:
            return viewModel.referencePointsCount >= 3 && viewModel.observationSessionsCount > 0
        case .calibrationExecution:
            return viewModel.workflowStatus == .completed
        case .validation:
            return false
        }
    }
}

// MARK: - Supporting Types

enum WorkflowStep: CaseIterable {
    case referenceSetup
    case observationCollection
    case dataMapping
    case calibrationExecution
    case validation

    var title: String {
        switch self {
        case .referenceSetup:
            return "基準設定"
        case .observationCollection:
            return "観測収集"
        case .dataMapping:
            return "データマッピング"
        case .calibrationExecution:
            return "キャリブレーション実行"
        case .validation:
            return "検証"
        }
    }

    var description: String {
        switch self {
        case .referenceSetup:
            return "マップ上で基準座標を設定するか、手動で座標を入力してください。最低3つの基準点が必要です。"
        case .observationCollection:
            return "選択されたアンテナから観測データを収集します。十分なデータを収集するまでお待ちください。"
        case .dataMapping:
            return "基準座標と観測データの対応付けを行います。品質の高いマッピングを作成します。"
        case .calibrationExecution:
            return "収集したデータを使用してキャリブレーションを実行します。変換行列が計算されます。"
        case .validation:
            return "キャリブレーション結果を検証し、精度を確認します。"
        }
    }

    var icon: String {
        switch self {
        case .referenceSetup:
            return "mappin"
        case .observationCollection:
            return "dot.radiowaves.left.and.right"
        case .dataMapping:
            return "point.3.connected.trianglepath.dotted"
        case .calibrationExecution:
            return "function"
        case .validation:
            return "checkmark.seal"
        }
    }
}
