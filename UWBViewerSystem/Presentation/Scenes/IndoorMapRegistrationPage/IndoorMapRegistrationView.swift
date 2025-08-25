import SwiftUI

struct IndoorMapRegistrationView: View {
    @EnvironmentObject var router: NavigationRouterModel
    @StateObject private var viewModel = IndoorMapRegistrationViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            HeaderSection()
            
            ScrollView {
                VStack(spacing: 30) {
                    MapUploadSection(viewModel: viewModel)
                    
                    MapPreviewSection(viewModel: viewModel)
                    
                    MapDetailsSection(viewModel: viewModel)
                }
                .padding()
            }
            
            NavigationButtonsSection()
        }
        .navigationTitle("屋内マップ登録")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        #if os(macOS)
        .background(Color(NSColor.controlBackgroundColor))
        #elseif os(iOS)
        .background(Color(UIColor.systemBackground))
        #endif
    }
    
    // MARK: - Header Section
    @ViewBuilder
    private func HeaderSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("屋内マップを登録してください")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("使用する建物のフロアマップをアップロードし、基本情報を設定してください。")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Navigation Buttons
    @ViewBuilder
    private func NavigationButtonsSection() -> some View {
        HStack(spacing: 20) {
            Button("戻る") {
                router.pop()
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            Button("次へ") {
                router.push(.deviceSelection)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canProceed)
        }
        .padding()
    }
}

// MARK: - Map Upload Section
struct MapUploadSection: View {
    @ObservedObject var viewModel: IndoorMapRegistrationViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("マップファイル")
                .font(.headline)
            
            Button(action: {
                viewModel.selectMapFile()
            }) {
                VStack(spacing: 10) {
                    Image(systemName: viewModel.selectedMapFile == nil ? "plus.circle" : "checkmark.circle")
                        .font(.largeTitle)
                        .foregroundColor(viewModel.selectedMapFile == nil ? .blue : .green)
                    
                    Text(viewModel.selectedMapFile?.lastPathComponent ?? "マップファイルを選択")
                        .font(.subheadline)
                    
                    Text("PNG, JPG, PDF対応")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                #if os(macOS)
                .background(Color(NSColor.controlColor))
                #elseif os(iOS)
                .background(Color(UIColor.systemGray6))
                #endif
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 1, dash: [5]))
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Map Preview Section
struct MapPreviewSection: View {
    @ObservedObject var viewModel: IndoorMapRegistrationViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("プレビュー")
                .font(.headline)
            
            if let mapFile = viewModel.selectedMapFile,
               let image = viewModel.mapPreviewImage {
                VStack {
                    #if os(macOS)
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .cornerRadius(8)
                        .shadow(radius: 2)
                    #elseif os(iOS)
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .cornerRadius(8)
                        .shadow(radius: 2)
                    #endif
                    
                    Text(mapFile.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    #if os(macOS)
                    .fill(Color(NSColor.controlColor))
                    #elseif os(iOS)
                    .fill(Color(UIColor.systemGray5))
                    #endif
                    .frame(height: 200)
                    .overlay(
                        VStack {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("マップファイルを選択してください")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    )
            }
        }
    }
}

// MARK: - Map Details Section
struct MapDetailsSection: View {
    @ObservedObject var viewModel: IndoorMapRegistrationViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("マップ情報")
                .font(.headline)
            
            VStack(spacing: 15) {
                HStack {
                    Text("マップ名")
                        .frame(width: 100, alignment: .leading)
                    TextField("マップ名を入力", text: $viewModel.mapName)
                        .textFieldStyle(.roundedBorder)
                }
                
                HStack {
                    Text("建物名")
                        .frame(width: 100, alignment: .leading)
                    TextField("建物名を入力", text: $viewModel.buildingName)
                        .textFieldStyle(.roundedBorder)
                }
                
                HStack {
                    Text("フロア")
                        .frame(width: 100, alignment: .leading)
                    TextField("フロア名を入力", text: $viewModel.floorName)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("実際のサイズ")
                            .frame(width: 100, alignment: .leading)
                        Spacer()
                    }
                    
                    HStack(spacing: 10) {
                        TextField("幅", text: $viewModel.realWidth)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text("×")
                        TextField("高さ", text: $viewModel.realHeight)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text("メートル")
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(alignment: .top) {
                    Text("説明")
                        .frame(width: 100, alignment: .leading)
                    TextField("マップの説明（任意）", text: $viewModel.description, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        IndoorMapRegistrationView()
            .environmentObject(NavigationRouterModel.shared)
    }
}