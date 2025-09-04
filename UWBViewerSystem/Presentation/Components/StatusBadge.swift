import SwiftUI

/// ステータスを表示するバッジコンポーネント
struct StatusBadge: View {
    enum Status {
        case success
        case warning
        case error
        case info
        case custom(color: Color)

        var color: Color {
            switch self {
            case .success:
                return .green
            case .warning:
                return .orange
            case .error:
                return .red
            case .info:
                return .blue
            case .custom(let color):
                return color
            }
        }
    }

    let text: String
    let status: Status
    let systemImage: String?

    init(text: String, status: Status, systemImage: String? = nil) {
        self.text = text
        self.status = status
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption)
            }
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundColor(.white)
        .background(status.color)
        .cornerRadius(4)
    }
}

/// 接続ステータス表示用のインジケーター
struct ConnectionStatusIndicator: View {
    let isConnected: Bool
    let label: String?

    init(isConnected: Bool, label: String? = nil) {
        self.isConnected = isConnected
        self.label = label
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isConnected ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            if let label {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview("Status Components") {
    VStack(spacing: 16) {
        HStack(spacing: 8) {
            StatusBadge(text: "接続済み", status: .success)
            StatusBadge(text: "警告", status: .warning, systemImage: "exclamationmark.triangle")
            StatusBadge(text: "エラー", status: .error)
            StatusBadge(text: "情報", status: .info)
        }

        HStack(spacing: 16) {
            ConnectionStatusIndicator(isConnected: true, label: "オンライン")
            ConnectionStatusIndicator(isConnected: false, label: "オフライン")
        }
    }
    .padding()
}