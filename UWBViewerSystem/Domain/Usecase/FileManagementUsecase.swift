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
        setupFileStoragePath()

        Task {
            await loadReceivedFiles()
        }
    }

    // MARK: - File Storage Management

    private func setupFileStoragePath() {
        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let uwbFilesDirectory = documentsDirectory.appendingPathComponent("UWBFiles")
            fileStoragePath = uwbFilesDirectory.path

            // フォルダーが存在しない場合は作成
            createDirectoryIfNeeded(at: uwbFilesDirectory)
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
        guard !fileStoragePath.isEmpty else { return }

        let url = URL(fileURLWithPath: fileStoragePath)

        // フォルダーが存在しない場合は作成
        createDirectoryIfNeeded(at: url)

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

        receivedFiles.append(receivedFile)

        // 進捗を削除
        fileTransferProgress.removeValue(forKey: endpointId)

        // SwiftDataに保存
        Task {
            do {
                try await swiftDataRepository.saveReceivedFile(receivedFile)

                // システム活動ログも記録
                let activity = SystemActivity(
                    activityType: "file_transfer",
                    activityDescription: "ファイル受信完了: \(fileName) (\(receivedFile.formattedSize)) from \(deviceName)"
                )
                try await swiftDataRepository.saveSystemActivity(activity)

                print("ファイル受信完了・保存済み: \(fileName) (\(receivedFile.formattedSize)) from \(deviceName)")
            } catch {
                print("受信ファイル保存エラー: \(error)")
            }
        }
    }

    public func onFileTransferProgress(endpointId: String, progress: Int) {
        fileTransferProgress[endpointId] = progress
        print("ファイル転送進捗: \(endpointId) - \(progress)%")
    }

    public func processFileTransferStart(_ json: [String: Any], fromEndpointId: String) {
        let fileName = json["fileName"] as? String ?? "Unknown"
        let fileSize = json["fileSize"] as? Int64 ?? 0

        print("File transfer starting: \(fileName), size: \(fileSize)")

        // 進捗を初期化
        fileTransferProgress[fromEndpointId] = 0
    }

    // MARK: - File Management

    private func loadReceivedFiles() async {
        do {
            receivedFiles = try await swiftDataRepository.loadReceivedFiles()
        } catch {
            print("受信ファイル読み込みエラー: \(error)")
        }
    }

    public func clearReceivedFiles() {
        receivedFiles.removeAll()
        fileTransferProgress.removeAll()

        Task {
            do {
                try await swiftDataRepository.deleteAllReceivedFiles()
                print("全受信ファイルを削除しました")
            } catch {
                print("受信ファイル全削除エラー: \(error)")
            }
        }
    }

    public func removeReceivedFile(_ file: ReceivedFile) {
        receivedFiles.removeAll { $0.id == file.id }

        Task {
            do {
                try await swiftDataRepository.deleteReceivedFile(by: file.id)
                print("受信ファイルを削除しました: \(file.fileName)")
            } catch {
                print("受信ファイル削除エラー: \(error)")
            }
        }

        // 実際のファイルも削除するかはオプション（ここでは削除しない）
        // try? FileManager.default.removeItem(at: file.fileURL)
    }

    public func getFileTransferProgress(for endpointId: String) -> Int? {
        fileTransferProgress[endpointId]
    }

    public var hasReceivedFiles: Bool {
        !receivedFiles.isEmpty
    }

    public var isTransferringFiles: Bool {
        !fileTransferProgress.isEmpty
    }
}
