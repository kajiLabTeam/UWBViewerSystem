import Combine
import Foundation

#if os(macOS)
    import AppKit
#endif

// MARK: - ファイル管理 Usecase

@MainActor
public class FileManagementUsecase: ObservableObject {
    @Published var receivedFiles: [ReceivedFile] = []
    @Published var fileTransferProgress: [String: Int] = [:]  // endpointId: progress
    @Published var fileStoragePath: String = ""

    private let swiftDataRepository: SwiftDataRepositoryProtocol

    public init(swiftDataRepository: SwiftDataRepositoryProtocol = DummySwiftDataRepository()) {
        self.swiftDataRepository = swiftDataRepository
        self.setupFileStoragePath()

        Task {
            await self.loadReceivedFiles()
        }
    }

    // MARK: - File Storage Management

    private func setupFileStoragePath() {
        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let uwbFilesDirectory = documentsDirectory.appendingPathComponent("UWBFiles")
            self.fileStoragePath = uwbFilesDirectory.path

            // フォルダーが存在しない場合は作成
            self.createDirectoryIfNeeded(at: uwbFilesDirectory)
        }
    }

    private func createDirectoryIfNeeded(at url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                print("ファイル保存フォルダーを作成しました: \(url.path)")
            } catch {
                print("フォルダー作成エラー: \(error.localizedDescription)")
            }
        }
    }

    public func openFileStorageFolder() {
        guard !self.fileStoragePath.isEmpty else { return }

        let url = URL(fileURLWithPath: fileStoragePath)

        // フォルダーが存在しない場合は作成
        self.createDirectoryIfNeeded(at: url)

        #if os(macOS)
            NSWorkspace.shared.open(url)
        #endif
    }

    // MARK: - File Reception

    public func onFileReceived(endpointId: String, fileURL: URL, fileName: String, deviceNames: Set<String>) {
        // ファイルサイズを取得
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0

        // デバイス名を取得（endpointIdから推定）
        let deviceName = deviceNames.first { $0.contains(endpointId) } ?? endpointId

        let receivedFile = ReceivedFile(
            fileName: fileName,
            fileURL: fileURL,
            deviceName: deviceName,
            receivedAt: Date(),
            fileSize: fileSize
        )

        self.receivedFiles.append(receivedFile)

        // 進捗を削除
        self.fileTransferProgress.removeValue(forKey: endpointId)

        // SwiftDataに保存
        Task {
            do {
                try await self.swiftDataRepository.saveReceivedFile(receivedFile)

                // システム活動ログも記録
                let activity = SystemActivity(
                    activityType: "file_transfer",
                    activityDescription: "ファイル受信完了: \(fileName) (\(receivedFile.formattedSize)) from \(deviceName)"
                )
                try await self.swiftDataRepository.saveSystemActivity(activity)

                print("ファイル受信完了・保存済み: \(fileName) (\(receivedFile.formattedSize)) from \(deviceName)")
            } catch {
                print("受信ファイル保存エラー: \(error)")
            }
        }
    }

    public func onFileTransferProgress(endpointId: String, progress: Int) {
        self.fileTransferProgress[endpointId] = progress
        print("ファイル転送進捗: \(endpointId) - \(progress)%")
    }

    public func processFileTransferStart(_ json: [String: Any], fromEndpointId: String) {
        let fileName = json["fileName"] as? String ?? "Unknown"
        let fileSize = json["fileSize"] as? Int64 ?? 0

        print("File transfer starting: \(fileName), size: \(fileSize)")

        // 進捗を初期化
        self.fileTransferProgress[fromEndpointId] = 0
    }

    // MARK: - File Management

    private func loadReceivedFiles() async {
        do {
            self.receivedFiles = try await self.swiftDataRepository.loadReceivedFiles()
        } catch {
            print("受信ファイル読み込みエラー: \(error)")
        }
    }

    public func clearReceivedFiles() {
        Task {
            do {
                try await self.swiftDataRepository.deleteAllReceivedFiles()
                await MainActor.run {
                    self.receivedFiles.removeAll()
                    self.fileTransferProgress.removeAll()
                }
                print("全受信ファイルを削除しました")
            } catch {
                print("受信ファイル全削除エラー: \(error)")
                // エラー時はUIを更新しない（既存の状態を維持）
            }
        }
    }

    public func removeReceivedFile(_ file: ReceivedFile) {
        Task {
            do {
                // まずデータベースから削除
                try await self.swiftDataRepository.deleteReceivedFile(by: file.id)
                print("受信ファイルを削除しました: \(file.fileName)")

                // 削除成功後にUIを更新
                await MainActor.run {
                    self.receivedFiles.removeAll { $0.id == file.id }
                }
            } catch {
                print("受信ファイル削除エラー: \(error)")
                // エラー時はUIを更新しない（既存の状態を維持）
            }
        }

        // 実際のファイルも削除するかはオプション（ここでは削除しない）
        // try? FileManager.default.removeItem(at: file.fileURL)
    }

    public func getFileTransferProgress(for endpointId: String) -> Int? {
        self.fileTransferProgress[endpointId]
    }

    public var hasReceivedFiles: Bool {
        !self.receivedFiles.isEmpty
    }

    public var isTransferringFiles: Bool {
        !self.fileTransferProgress.isEmpty
    }
}
