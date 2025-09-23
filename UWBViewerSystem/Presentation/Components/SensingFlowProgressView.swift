import SwiftUI

/// センシングフローの進行状況を表示するコンポーネント
struct SensingFlowProgressView: View {
    @ObservedObject var navigator: SensingFlowNavigator

    var body: some View {
        VStack(spacing: 16) {
            // プログレスバー
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("進行状況")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    Text("\(Int(navigator.flowProgress * 100))%")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                ProgressView(value: navigator.flowProgress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .tint(.blue)
            }

            // ステップ一覧
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(SensingFlowStep.allCases, id: \.self) { step in
                        StepIndicatorView(
                            step: step,
                            isCurrent: step == navigator.currentStep,
                            isCompleted: isStepCompleted(step)
                        )
                        .onTapGesture {
                            if canNavigateToStep(step) {
                                navigator.jumpToStep(step)
                            }
                        }

                        if step != SensingFlowStep.allCases.last {
                            Image(systemName: "arrow.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            // 現在のステップ情報
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: navigator.currentStep.iconName)
                        .foregroundColor(.blue)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(navigator.currentStep.rawValue)
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text(navigator.currentStep.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Image(systemName: "clock")
                            .foregroundColor(.orange)
                            .font(.caption)

                        Text("約\(navigator.currentStep.estimatedDuration)分")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .padding()
    }

    /// 指定されたステップが完了済みかどうかを判定
    private func isStepCompleted(_ step: SensingFlowStep) -> Bool {
        guard let currentIndex = SensingFlowStep.allCases.firstIndex(of: navigator.currentStep),
              let stepIndex = SensingFlowStep.allCases.firstIndex(of: step)
        else {
            return false
        }

        return stepIndex < currentIndex
    }

    /// 指定されたステップにナビゲート可能かどうかを判定
    private func canNavigateToStep(_ step: SensingFlowStep) -> Bool {
        // 通常は前のステップが完了していれば次のステップに進める
        // ここでは簡単な実装として、現在のステップより前のステップには戻れるようにする
        guard let currentIndex = SensingFlowStep.allCases.firstIndex(of: navigator.currentStep),
              let stepIndex = SensingFlowStep.allCases.firstIndex(of: step)
        else {
            return false
        }

        return stepIndex <= currentIndex
    }
}

/// 個別ステップの表示コンポーネント
struct StepIndicatorView: View {
    let step: SensingFlowStep
    let isCurrent: Bool
    let isCompleted: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 32, height: 32)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .bold))
                } else {
                    Image(systemName: step.iconName)
                        .foregroundColor(iconColor)
                        .font(.system(size: 14))
                }
            }

            Text(step.rawValue)
                .font(.caption2)
                .foregroundColor(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 60)
    }

    private var backgroundColor: Color {
        if isCompleted {
            return .green
        } else if isCurrent {
            return .blue
        } else {
            return Color.gray.opacity(0.3)
        }
    }

    private var iconColor: Color {
        if isCurrent {
            return .white
        } else {
            return .secondary
        }
    }

    private var textColor: Color {
        if isCurrent {
            return .blue
        } else if isCompleted {
            return .green
        } else {
            return .secondary
        }
    }
}

/// プレビュー用
struct SensingFlowProgressView_Previews: PreviewProvider {
    static var previews: some View {
        let navigator = SensingFlowNavigator()
        navigator.currentStep = .antennaConfiguration

        return SensingFlowProgressView(navigator: navigator)
            .previewLayout(.sizeThatFits)
            .padding()
    }
}
