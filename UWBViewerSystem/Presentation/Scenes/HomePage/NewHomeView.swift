import SwiftUI

/// 新しいHomeView - ダッシュボード機能に特化
/// 各専用画面への案内とシステム全体の概要表示
struct NewHomeView: View {
    @StateObject private var dashboardViewModel = DashboardViewModel()
    @EnvironmentObject var router: NavigationRouterModel
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                headerSection
                
                quickActionsSection
                
                systemStatusSection
                
                recentActivitySection
                
                navigationSection
                
                Spacer(minLength: 20)
            }
            .padding()
        }
        .navigationTitle("UWB制御センター")
        .onAppear {
            dashboardViewModel.refreshStatus()
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "sensor")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("UWBViewerSystem")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Ultra-Wideband センサー制御システム")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
        }
    }
    
    // MARK: - Quick Actions Section
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("クイックアクション")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack(spacing: 16) {
                QuickActionCard(
                    icon: "play.circle.fill",
                    title: "データ収集",
                    subtitle: "センシング開始",
                    color: .green,
                    isEnabled: !dashboardViewModel.isSensingActive
                ) {
                    router.push(.dataCollectionPage)
                }
                
                QuickActionCard(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "データ表示",
                    subtitle: "リアルタイム表示",
                    color: .blue,
                    isEnabled: true
                ) {
                    router.push(.dataDisplayPage)
                }
                
                QuickActionCard(
                    icon: "network",
                    title: "接続管理",
                    subtitle: "デバイス管理",
                    color: .orange,
                    isEnabled: true
                ) {
                    router.push(.connectionManagementPage)
                }
            }
        }
    }
    
    // MARK: - System Status Section
    private var systemStatusSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("システム状態")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                StatusRow(
                    icon: "antenna.radiowaves.left.and.right",
                    label: "アンテナ設定",
                    value: "\(dashboardViewModel.antennaCount) 台設定済み",
                    status: dashboardViewModel.antennaCount > 0 ? .success : .warning
                )
                
                StatusRow(
                    icon: "link.circle",
                    label: "端末ペアリング",
                    value: "\(dashboardViewModel.pairedDeviceCount) 台ペアリング済み",
                    status: dashboardViewModel.pairedDeviceCount > 0 ? .success : .warning
                )
                
                StatusRow(
                    icon: "iphone.and.arrow.forward",
                    label: "接続状態",
                    value: "\(dashboardViewModel.connectedDeviceCount) / \(dashboardViewModel.pairedDeviceCount) 台接続中",
                    status: dashboardViewModel.connectionStatus
                )
                
                StatusRow(
                    icon: "waveform.path.ecg",
                    label: "センシング状態",
                    value: dashboardViewModel.sensingStatus,
                    status: dashboardViewModel.isSensingActive ? .active : .inactive
                )
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Recent Activity Section
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("最近のアクティビティ")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: dashboardViewModel.clearActivity) {
                    Text("クリア")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            if dashboardViewModel.recentActivities.isEmpty {
                Text("アクティビティはありません")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
            } else {
                VStack(spacing: 8) {
                    ForEach(dashboardViewModel.recentActivities.prefix(5), id: \.id) { activity in
                        ActivityRow(activity: activity)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Navigation Section
    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("設定・管理")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                NavigationRow(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "アンテナ配置設定",
                    subtitle: "UWBアンテナの位置を設定"
                ) {
                    router.push(.fieldSettingPage)
                }
                
                NavigationRow(
                    icon: "link.circle",
                    title: "端末紐付け設定",
                    subtitle: "アンテナとAndroid端末を紐付け"
                ) {
                    router.push(.pairingSettingPage)
                }
                
                NavigationRow(
                    icon: "megaphone",
                    title: "広告専用画面",
                    subtitle: "詳細な端末管理機能"
                ) {
                    router.push(.advertiserPage)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
        }
    }
}

// MARK: - Supporting Views

struct QuickActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundColor(isEnabled ? color : .gray)
                
                VStack(spacing: 4) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(isEnabled ? .primary : .gray)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isEnabled ? color.opacity(0.1) : Color.gray.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isEnabled ? color.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

struct StatusRow: View {
    let icon: String
    let label: String
    let value: String
    let status: SystemStatus
    
    enum SystemStatus {
        case success, warning, error, active, inactive
        
        var color: Color {
            switch self {
            case .success, .active: return .green
            case .warning: return .orange
            case .error: return .red
            case .inactive: return .gray
            }
        }
        
        var statusIcon: String {
            switch self {
            case .success, .active: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            case .inactive: return "circle"
            }
        }
    }
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(label)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 6) {
                Text(value)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Image(systemName: status.statusIcon)
                    .foregroundColor(status.color)
                    .font(.caption)
            }
        }
    }
}

struct ActivityRow: View {
    let activity: DashboardActivity
    
    var body: some View {
        HStack {
            Image(systemName: activity.icon)
                .foregroundColor(activity.type.color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.description)
                    .font(.body)
                
                Text(activity.formattedTimestamp)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

struct NavigationRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        NewHomeView()
            .environmentObject(NavigationRouterModel())
    }
}