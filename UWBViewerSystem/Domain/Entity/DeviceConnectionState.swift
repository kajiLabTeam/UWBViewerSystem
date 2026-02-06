import Foundation

/// ニアバイコネクションの接続状態
public enum DeviceConnectionState: Equatable {
    /// 未接続
    case disconnected
    /// 接続中
    case connecting
    /// 接続済み
    case connected(deviceName: String, endpointId: String)
    /// 接続エラー
    case error(message: String)
    /// 再接続中
    case reconnecting(attempt: Int, maxAttempts: Int)
    /// 接続断（復旧可能）
    case disconnectedRecoverable(deviceName: String, reason: String)

    /// 接続が確立されているかどうか
    public var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }

    /// エラー状態かどうか
    public var isError: Bool {
        if case .error = self {
            return true
        }
        return false
    }

    /// 再接続中かどうか
    public var isReconnecting: Bool {
        if case .reconnecting = self {
            return true
        }
        return false
    }

    /// 復旧可能な切断状態かどうか
    public var isRecoverable: Bool {
        if case .disconnectedRecoverable = self {
            return true
        }
        return false
    }

    /// 状態の説明文
    public var description: String {
        switch self {
        case .disconnected:
            return "未接続"
        case .connecting:
            return "接続中..."
        case .connected(let deviceName, _):
            return "接続済み: \(deviceName)"
        case .error(let message):
            return "エラー: \(message)"
        case .reconnecting(let attempt, let maxAttempts):
            return "再接続中 (\(attempt)/\(maxAttempts))..."
        case .disconnectedRecoverable(let deviceName, let reason):
            return "接続断: \(deviceName) - \(reason)"
        }
    }
}

/// 接続断の理由
public enum DisconnectionReason: String {
    /// ネットワークエラー
    case networkError = "ネットワークエラー"
    /// タイムアウト
    case timeout = "タイムアウト"
    /// デバイスが範囲外
    case outOfRange = "デバイスが範囲外"
    /// ユーザーによる切断
    case userInitiated = "ユーザーによる切断"
    /// 不明なエラー
    case unknown = "不明なエラー"
}
