import SwiftUI

struct CalibrationView: View {
    @EnvironmentObject var router: NavigationRouterModel
    @StateObject private var viewModel = CalibrationViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            HeaderSection()
            
            HStack(spacing: 20) {
                CalibrationStatusSection(viewModel: viewModel)
                
                CalibrationInstructionsSection(viewModel: viewModel)
            }
            
            CalibrationControlsSection(viewModel: viewModel)
            
            NavigationButtonsSection(viewModel: viewModel)
        }
        .navigationTitle("キャリブレーション")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        #if os(macOS)
        .background(Color(NSColor.controlBackgroundColor))
        #elseif os(iOS)
        .background(Color(UIColor.systemBackground))
        #endif
        .onAppear {
            viewModel.initialize()
        }
    }
    
    // MARK: - Header Section
    @ViewBuilder
    private func HeaderSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("システムキャリブレーション")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("UWBアンテナ間の距離を測定し、システムの精度を向上させるためのキャリブレーションを実行します。")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Navigation Buttons
    @ViewBuilder
    private func NavigationButtonsSection(viewModel: CalibrationViewModel) -> some View {
        HStack(spacing: 20) {
            Button("戻る") {
                router.pop()
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            if !viewModel.isCompleted {
                Button("キャリブレーションをスキップ") {
                    viewModel.skipCalibration()
                    router.push(.sensingManagement)
                }
                .buttonStyle(.bordered)
            }
            
            Button("次へ") {
                router.push(.sensingManagement)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canProceed)
        }
        .padding()
    }
}

// MARK: - Calibration Status Section
struct CalibrationStatusSection: View {
    @ObservedObject var viewModel: CalibrationViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("キャリブレーション状況")
                .font(.headline)
            
            VStack(spacing: 15) {
                // 全体の進捗
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("全体の進捗")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Text("\(viewModel.calibrationProgress)%")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    ProgressView(value: Double(viewModel.calibrationProgress), total: 100)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                }
                
                Divider()
                
                // アンテナペア別の状況
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.calibrationPairs) { pair in
                        CalibrationPairRow(pair: pair)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    #if os(macOS)
                    .fill(Color(NSColor.controlColor))
                    #elseif os(iOS)
                    .fill(Color(UIColor.systemGray6))
                    #endif
            )
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Calibration Instructions Section
struct CalibrationInstructionsSection: View {
    @ObservedObject var viewModel: CalibrationViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("キャリブレーション手順")
                .font(.headline)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if let currentStep = viewModel.currentCalibrationStep {
                        CurrentStepCard(step: currentStep)
                    }
                    
                    InstructionCard(
                        title: "準備",
                        instructions: [
                            "すべてのUWBアンテナの電源が入っていることを確認",
                            "アンテナ間に障害物がないことを確認",
                            "測定対象エリアに人がいないことを確認"
                        ]
                    )
                    
                    InstructionCard(
                        title: "測定",
                        instructions: [
                            "「キャリブレーション開始」ボタンを押下",
                            "各アンテナペア間の距離測定が自動実行されます",
                            "測定中は機器を移動しないでください",
                            "全てのペアの測定が完了するまでお待ちください"
                        ]
                    )
                    
                    InstructionCard(
                        title: "結果確認",
                        instructions: [
                            "測定結果が理論値と大きく異ならないことを確認",
                            "エラーが発生した場合は再測定を実行",
                            "問題なければ「完了」ボタンで次へ進む"
                        ]
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Calibration Controls Section
struct CalibrationControlsSection: View {
    @ObservedObject var viewModel: CalibrationViewModel
    
    var body: some View {
        VStack(spacing: 15) {
            if viewModel.calibrationState == .idle {
                Button("キャリブレーション開始") {
                    viewModel.startCalibration()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else if viewModel.calibrationState == .running {
                VStack(spacing: 10) {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("キャリブレーション実行中...")
                            .font(.subheadline)
                    }
                    
                    Button("キャリブレーション停止") {
                        viewModel.stopCalibration()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
            } else if viewModel.calibrationState == .completed {
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                        Text("キャリブレーション完了")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    Button("再キャリブレーション") {
                        viewModel.restartCalibration()
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            if viewModel.calibrationState == .error {
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.title2)
                        Text("キャリブレーションエラー")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    Text(viewModel.errorMessage ?? "不明なエラーが発生しました")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("再試行") {
                        viewModel.retryCalibration()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemRed).opacity(0.1))
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                #if os(macOS)
                .fill(Color(NSColor.controlBackgroundColor))
                #elseif os(iOS)
                .fill(Color(UIColor.systemBackground))
                #endif
                .shadow(radius: 1)
        )
        .padding(.horizontal)
    }
}

// MARK: - Supporting Views

struct CalibrationPairRow: View {
    let pair: CalibrationPair
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(pair.antenna1Name) ↔ \(pair.antenna2Name)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if let distance = pair.measuredDistance {
                    Text("測定距離: \(String(format: "%.2f", distance))m")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            CalibrationStatusIcon(status: pair.status)
        }
        .padding(.vertical, 4)
    }
}

struct CalibrationStatusIcon: View {
    let status: CalibrationStatus
    
    var body: some View {
        Group {
            switch status {
            case .pending:
                Image(systemName: "clock")
                    .foregroundColor(.orange)
            case .measuring:
                ProgressView()
                    .scaleEffect(0.8)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .font(.title3)
    }
}

struct CurrentStepCard: View {
    let step: CalibrationStep
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("現在の手順")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            
            Text(step.title)
                .font(.headline)
            
            Text(step.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBlue).opacity(0.1))
        )
    }
}

struct InstructionCard: View {
    let title: String
    let instructions: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(instructions.enumerated()), id: \.offset) { index, instruction in
                    HStack(alignment: .top) {
                        Text("\(index + 1).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(instruction)
                            .font(.caption)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                #if os(macOS)
                .fill(Color(NSColor.controlColor))
                #elseif os(iOS)
                .fill(Color(UIColor.systemGray6))
                #endif
        )
    }
}

#Preview {
    NavigationStack {
        CalibrationView()
            .environmentObject(NavigationRouterModel.shared)
    }
}