import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    self.headerSection
                    self.aboutSection
                }
                .padding()
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayModeIfAvailable(.large)
        }
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

            Text("アプリケーション情報")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.purple.opacity(0.1))
        .cornerRadius(12)
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

                    Text(self.viewModel.appVersion)
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
                    self.viewModel.showHelp()
                }

                Divider()
                    .padding(.leading, 44)

                SettingsRow(
                    icon: "doc.text",
                    title: "利用規約",
                    subtitle: nil,
                    showChevron: true
                ) {
                    self.viewModel.showTerms()
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
        Button(action: self.action) {
            HStack {
                Image(systemName: self.icon)
                    .frame(width: 20)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(self.title)
                        .foregroundColor(.primary)

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if self.showChevron {
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

#Preview {
    SettingsView()
}
