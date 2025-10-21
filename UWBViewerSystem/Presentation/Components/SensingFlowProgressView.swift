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

                    Text("\(Int(self.navigator.flowProgress * 100))%")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                ProgressView(value: self.navigator.flowProgress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .tint(.blue)
            }

            // ステップ一覧
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(SensingFlowStep.allCases, id: \.self) { step in
                        StepIndicatorView(
                            step: step,
                            isCurrent: step == self.navigator.currentStep,
                            isCompleted: self.isStepCompleted(step)
                        )
                        .onTapGesture {
                            if self.canNavigateToStep(step) {
                                self.navigator.jumpToStep(step)
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
                    Image(systemName: self.navigator.currentStep.iconName)
                        .foregroundColor(.blue)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(self.navigator.currentStep.rawValue)
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text(self.navigator.currentStep.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Image(systemName: "clock")
                            .foregroundColor(.orange)
                            .font(.caption)

                        Text("約\(self.navigator.currentStep.estimatedDuration)分")
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
                    .fill(self.backgroundColor)
                    .frame(width: 32, height: 32)

                if self.isCompleted {
                    Image(systemName: "checkmark")
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .bold))
                } else {
                    Image(systemName: self.step.iconName)
                        .foregroundColor(self.iconColor)
                        .font(.system(size: 14))
                }
            }

            Text(self.step.rawValue)
                .font(.caption2)
                .foregroundColor(self.textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 60)
    }

    private var backgroundColor: Color {
        if self.isCompleted {
            return .green
        } else if self.isCurrent {
            return .blue
        } else {
            return Color.gray.opacity(0.3)
        }
    }

    private var iconColor: Color {
        if self.isCurrent {
            return .white
        } else {
            return .secondary
        }
    }

    private var textColor: Color {
        if self.isCurrent {
            return .blue
        } else if self.isCompleted {
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
