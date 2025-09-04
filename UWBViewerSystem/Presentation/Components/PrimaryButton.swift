import SwiftUI

/// プライマリボタンコンポーネント
/// 主要なアクションに使用するボタン
struct PrimaryButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void
    let isDisabled: Bool
    let isFullWidth: Bool

    init(
        title: String,
        systemImage: String? = nil,
        isDisabled: Bool = false,
        isFullWidth: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isDisabled = isDisabled
        self.isFullWidth = isFullWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.body)
                }
                Text(title)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .foregroundColor(.white)
            .background(isDisabled ? Color.gray : Color.blue)
            .cornerRadius(8)
        }
        .disabled(isDisabled)
    }
}

/// セカンダリボタンコンポーネント
/// 補助的なアクションに使用するボタン
struct SecondaryButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void
    let isFullWidth: Bool

    init(
        title: String,
        systemImage: String? = nil,
        isFullWidth: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isFullWidth = isFullWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.body)
                }
                Text(title)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .foregroundColor(.blue)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

/// 破壊的アクション用ボタン
/// 削除などの破壊的なアクションに使用
struct DestructiveButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void
    let isFullWidth: Bool

    init(
        title: String,
        systemImage: String? = nil,
        isFullWidth: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isFullWidth = isFullWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.body)
                }
                Text(title)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .foregroundColor(.white)
            .background(Color.red)
            .cornerRadius(8)
        }
    }
}

#Preview("Buttons") {
    VStack(spacing: 16) {
        PrimaryButton(title: "次へ", systemImage: "arrow.right") {
            print("Primary tapped")
        }

        PrimaryButton(title: "保存", isDisabled: true) {
            print("Save tapped")
        }

        SecondaryButton(title: "キャンセル") {
            print("Cancel tapped")
        }

        DestructiveButton(title: "削除", systemImage: "trash") {
            print("Delete tapped")
        }
    }
    .padding()
}