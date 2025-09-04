import SwiftUI

/// 情報セクションを表示するコンポーネント
struct InformationSection: View {
    let title: String
    let systemImage: String
    let imageColor: Color
    let items: [String]

    init(
        title: String,
        systemImage: String = "info.circle",
        imageColor: Color = .blue,
        items: [String]
    ) {
        self.title = title
        self.systemImage = systemImage
        self.imageColor = imageColor
        self.items = items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // タイトル
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundColor(imageColor)

                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            // 項目リスト
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.body)
                            .foregroundColor(imageColor)

                        Text(item)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(imageColor.opacity(0.1))
        .cornerRadius(8)
    }
}

/// ステップ形式の説明セクション
struct StepInstructionView: View {
    struct Step {
        let number: Int
        let text: String
        let icon: String?
        let iconColor: Color

        init(number: Int, text: String, icon: String? = nil, iconColor: Color = .blue) {
            self.number = number
            self.text = text
            self.icon = icon
            self.iconColor = iconColor
        }
    }

    let title: String?
    let steps: [Step]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(steps, id: \.number) { step in
                    HStack(alignment: .top, spacing: 12) {
                        // ステップ番号
                        ZStack {
                            Circle()
                                .fill(step.iconColor)
                                .frame(width: 24, height: 24)

                            Text("\(step.number)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }

                        // アイコンとテキスト
                        HStack(alignment: .top, spacing: 8) {
                            if let icon = step.icon {
                                Image(systemName: icon)
                                    .font(.subheadline)
                                    .foregroundColor(step.iconColor)
                            }

                            Text(step.text)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }
                }
            }
        }
    }
}

#Preview("Information Components") {
    VStack(spacing: 16) {
        InformationSection(
            title: "注意事項",
            systemImage: "exclamationmark.triangle",
            imageColor: .orange,
            items: [
                "アンテナは最低3台必要です",
                "三角形以上の形状に配置してください",
                "壁際への設置は避けてください"
            ]
        )

        StepInstructionView(
            title: "アンテナ配置手順",
            steps: [
                .init(number: 1, text: "フロアマップ上でアンテナをドラッグして配置"),
                .init(number: 2, text: "ダブルタップして向きを調整", icon: "arrow.up"),
                .init(number: 3, text: "最低3台以上のアンテナを配置", icon: "antenna.radiowaves.left.and.right"),
                .init(number: 4, text: "三角形以上の形状になるように配置")
            ]
        )
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}