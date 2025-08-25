import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject var router: NavigationRouterModel
    
    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    
                    connectionSettingsSection
                    
                    dataManagementSection
                    
                    advancedSettingsSection
                    
                    aboutSection
                }
                .padding()
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 350)
        } detail: {
            if let selectedDetail = viewModel.selectedSettingDetail {
                SettingsDetailView(detailType: selectedDetail)
            } else {
                Text("設定項目を選択してください")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.controlBackgroundColor))
            }
        }
        #else
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    
                    connectionSettingsSection
                    
                    dataManagementSection
                    
                    advancedSettingsSection
                    
                    aboutSection
                }
                .padding()
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.large)
        }
        #endif
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "gearshape")
                    .font(.title2)
                    .foregroundColor(.purple)
                
                Text("システム設定")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            Text("アプリケーションの設定と管理")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.purple.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var connectionSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("接続設定")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 0) {
                SettingsRow(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "アンテナ配置設定",
                    subtitle: "UWBアンテナの位置を設定",
                    showChevron: true
                ) {
                    #if os(macOS)
                    viewModel.selectSettingDetail(.antennaSettings)
                    #else
                    router.push(.fieldSettingPage)
                    #endif
                }
                
                Divider()
                    .padding(.leading, 44)
                
                SettingsRow(
                    icon: "link.circle",
                    title: "端末ペアリング",
                    subtitle: "Android端末との接続設定",
                    showChevron: true
                ) {
                    #if os(macOS)
                    viewModel.selectSettingDetail(.pairingSettings)
                    #else
                    router.push(.pairingSettingPage)
                    #endif
                }
                
                Divider()
                    .padding(.leading, 44)
                
                SettingsRow(
                    icon: "network",
                    title: "接続管理",
                    subtitle: "現在の接続状態を確認",
                    showChevron: true
                ) {
                    #if os(macOS)
                    viewModel.selectSettingDetail(.connectionManagement)
                    #else
                    router.push(.connectionManagementPage)
                    #endif
                }
            }
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
        }
    }
    
    private var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("データ管理")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 0) {
                SettingsRow(
                    icon: "externaldrive",
                    title: "データエクスポート",
                    subtitle: "センシングデータの書き出し",
                    showChevron: true
                ) {
                    #if os(macOS)
                    viewModel.selectSettingDetail(.dataExport)
                    #else
                    viewModel.exportData()
                    #endif
                }
                
                Divider()
                    .padding(.leading, 44)
                
                SettingsRow(
                    icon: "trash",
                    title: "キャッシュクリア",
                    subtitle: "一時データの削除",
                    showChevron: true
                ) {
                    #if os(macOS)
                    viewModel.selectSettingDetail(.cacheManagement)
                    #else
                    viewModel.clearCache()
                    #endif
                }
                
                Divider()
                    .padding(.leading, 44)
                
                HStack {
                    Image(systemName: "icloud")
                        .frame(width: 20)
                        .foregroundColor(.blue)
                    
                    Text("自動バックアップ")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Toggle("", isOn: $viewModel.autoBackupEnabled)
                        .labelsHidden()
                }
                .padding()
            }
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
        }
    }
    
    private var advancedSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("詳細設定")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 0) {
                SettingsRow(
                    icon: "megaphone",
                    title: "広告専用画面",
                    subtitle: "デバイス広告の詳細設定",
                    showChevron: true
                ) {
                    #if os(macOS)
                    viewModel.selectSettingDetail(.advertiserSettings)
                    #else
                    router.push(.advertiserPage)
                    #endif
                }
                
                Divider()
                    .padding(.leading, 44)
                
                HStack {
                    Image(systemName: "waveform.path.ecg")
                        .frame(width: 20)
                        .foregroundColor(.blue)
                    
                    Text("高精度モード")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Toggle("", isOn: $viewModel.highAccuracyMode)
                        .labelsHidden()
                }
                .padding()
                
                Divider()
                    .padding(.leading, 44)
                
                HStack {
                    Image(systemName: "bell")
                        .frame(width: 20)
                        .foregroundColor(.blue)
                    
                    Text("通知設定")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Toggle("", isOn: $viewModel.notificationsEnabled)
                        .labelsHidden()
                }
                .padding()
            }
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
        }
    }
    
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("情報")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "info.circle")
                        .frame(width: 20)
                        .foregroundColor(.blue)
                    
                    Text("バージョン")
                    
                    Spacer()
                    
                    Text(viewModel.appVersion)
                        .foregroundColor(.secondary)
                }
                .padding()
                
                Divider()
                    .padding(.leading, 44)
                
                SettingsRow(
                    icon: "questionmark.circle",
                    title: "ヘルプ",
                    subtitle: "使い方ガイド",
                    showChevron: true
                ) {
                    #if os(macOS)
                    viewModel.selectSettingDetail(.help)
                    #else
                    viewModel.showHelp()
                    #endif
                }
                
                Divider()
                    .padding(.leading, 44)
                
                SettingsRow(
                    icon: "doc.text",
                    title: "利用規約",
                    subtitle: nil,
                    showChevron: true
                ) {
                    #if os(macOS)
                    viewModel.selectSettingDetail(.terms)
                    #else
                    viewModel.showTerms()
                    #endif
                }
            }
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    let showChevron: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundColor(.primary)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .padding()
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SettingsDetailView: View {
    let detailType: SettingsDetailType
    @EnvironmentObject var router: NavigationRouterModel
    
    var body: some View {
        VStack(spacing: 30) {
            // ヘッダー
            VStack(alignment: .leading, spacing: 16) {
                Text(detailType.rawValue)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text(subtitle)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.primary.opacity(0.05))
            .cornerRadius(12)
            
            // メインコンテンツ
            switch detailType {
            case .antennaSettings:
                antennaSettingsContent
            case .pairingSettings:
                pairingSettingsContent
            case .connectionManagement:
                connectionManagementContent
            case .dataExport:
                dataExportContent
            case .cacheManagement:
                cacheManagementContent
            case .advertiserSettings:
                advertiserSettingsContent
            case .help:
                helpContent
            case .terms:
                termsContent
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .background(Color(NSColor.controlBackgroundColor))
        #else
        .background(Color(UIColor.systemBackground))
        #endif
    }
    
    private var subtitle: String {
        switch detailType {
        case .antennaSettings:
            return "UWBアンテナの位置と設定を管理します"
        case .pairingSettings:
            return "Android端末との接続を設定します"
        case .connectionManagement:
            return "現在の接続状態を確認・管理します"
        case .dataExport:
            return "センシングデータを外部ファイルに出力します"
        case .cacheManagement:
            return "アプリの一時データを削除します"
        case .advertiserSettings:
            return "デバイス広告機能の設定を行います"
        case .help:
            return "アプリの使用方法を確認できます"
        case .terms:
            return "利用規約とプライバシーポリシー"
        }
    }
    
    @ViewBuilder
    private var antennaSettingsContent: some View {
        VStack(spacing: 16) {
            Button(action: {
                router.push(.fieldSettingPage)
            }) {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("アンテナ配置設定を開く")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
    }
    
    @ViewBuilder
    private var pairingSettingsContent: some View {
        VStack(spacing: 16) {
            Button(action: {
                router.push(.pairingSettingPage)
            }) {
                HStack {
                    Image(systemName: "link.circle")
                    Text("ペアリング設定を開く")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
    }
    
    @ViewBuilder
    private var connectionManagementContent: some View {
        VStack(spacing: 16) {
            Button(action: {
                router.push(.connectionManagementPage)
            }) {
                HStack {
                    Image(systemName: "network")
                    Text("接続管理を開く")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
    }
    
    @ViewBuilder
    private var dataExportContent: some View {
        VStack(spacing: 16) {
            Text("データエクスポート機能")
                .font(.headline)
            
            Text("センシングデータをCSVまたはJSON形式で出力できます。")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: {
                // データエクスポート処理
            }) {
                HStack {
                    Image(systemName: "externaldrive")
                    Text("データをエクスポート")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.purple)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
    }
    
    @ViewBuilder
    private var cacheManagementContent: some View {
        VStack(spacing: 16) {
            Text("キャッシュ管理")
                .font(.headline)
            
            Text("アプリの動作を軽快に保つため、定期的にキャッシュをクリアすることをお勧めします。")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: {
                // キャッシュクリア処理
            }) {
                HStack {
                    Image(systemName: "trash")
                    Text("キャッシュをクリア")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
    }
    
    @ViewBuilder
    private var advertiserSettingsContent: some View {
        VStack(spacing: 16) {
            Button(action: {
                router.push(.advertiserPage)
            }) {
                HStack {
                    Image(systemName: "megaphone")
                    Text("広告設定を開く")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.indigo)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
    }
    
    @ViewBuilder
    private var helpContent: some View {
        VStack(spacing: 16) {
            Text("ヘルプ・使い方ガイド")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("• フロアマップの登録方法")
                Text("• アンテナの配置設定")
                Text("• 端末のペアリング手順")
                Text("• センシングの開始方法")
                Text("• データの表示・エクスポート")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    @ViewBuilder
    private var termsContent: some View {
        VStack(spacing: 16) {
            Text("利用規約・プライバシーポリシー")
                .font(.headline)
            
            ScrollView {
                Text("このアプリケーションは研究目的で開発されたUWBセンシングシステムです。収集されたデータは研究目的でのみ使用され、第三者に提供されることはありません。")
                    .padding()
            }
            .frame(height: 200)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(NavigationRouterModel())
}