//
//  SessionDataExportUsecase.swift
//  UWBViewerSystem
//
//  Created by Claude Code on 2025/11/25.
//

import Foundation

/// セッションデータのエクスポートを担当するUseCase
/// ViewModelからビジネスロジックを分離し、データエクスポート処理を集約
@MainActor
class SessionDataExportUsecase {
    private let zipFileManager: ZipFileManager

    init(zipFileManager: ZipFileManager = .shared) {
        self.zipFileManager = zipFileManager
    }

    /// センシングデータのディレクトリからZIPファイルを作成
    /// - Parameter session: エクスポートするセッション
    /// - Returns: 作成されたZIPファイルのURL、失敗した場合はnil
    func exportSessionToZip(_ session: SensingSession) async -> URL? {
        do {
            print("📦 セッションデータを圧縮中: \(session.name)")

            // 1. センシングデータが保存されているディレクトリを特定
            guard let documentsDirectory = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first else {
                print("❌ Documentsディレクトリが見つかりません")
                return nil
            }

            // 日付フォーマッターの設定
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.timeZone = TimeZone.current
            dateFormatter.dateFormat = "yyyyMMdd"
            let dateString = dateFormatter.string(from: session.startTime)

            dateFormatter.dateFormat = "HHmmss"
            let timeString = dateFormatter.string(from: session.startTime)

            // セッションディレクトリ名を構築（customNameがある場合は「HHmmss-customName」形式、空の場合は「HHmmss」のみ）
            let directoryName = if !session.name.isEmpty {
                "\(timeString)-\(session.name)"
            } else {
                timeString
            }

            // デバッグ情報を出力
            print("🔍 [DEBUG] セッション情報:")
            print("  - セッション名: \(session.name)")
            print("  - セッションID: \(session.id)")
            print("  - 開始時刻: \(session.startTime)")
            print("  - 日付文字列: \(dateString)")
            print("  - 時刻文字列: \(timeString)")
            print("  - ディレクトリ名: \(directoryName)")

            // センシングデータディレクトリのパス
            let sensingDirectory = documentsDirectory
                .appendingPathComponent("sensing")
                .appendingPathComponent(dateString)
                .appendingPathComponent(directoryName)

            print("📁 構築したパス: \(sensingDirectory.path)")

            // sensingディレクトリの内容を確認
            let sensingBaseDir = documentsDirectory.appendingPathComponent("sensing")
            print("🔍 [DEBUG] sensingベースディレクトリ: \(sensingBaseDir.path)")

            if FileManager.default.fileExists(atPath: sensingBaseDir.path) {
                print("✅ sensingディレクトリは存在します")

                // sensingディレクトリ内の日付フォルダを列挙
                if let dateDirs = try? FileManager.default.contentsOfDirectory(atPath: sensingBaseDir.path) {
                    print("📂 sensing内の日付フォルダ: \(dateDirs.count)個")
                    for dateDir in dateDirs {
                        print("  - \(dateDir)")

                        // 各日付フォルダ内のセッションフォルダを列挙
                        let dateDirPath = sensingBaseDir.appendingPathComponent(dateDir)
                        if let sessionDirs = try? FileManager.default.contentsOfDirectory(atPath: dateDirPath.path) {
                            print("    📁 \(dateDir)内のセッションフォルダ: \(sessionDirs.count)個")
                            for sessionDir in sessionDirs {
                                print("      - \(sessionDir)")
                            }
                        }
                    }
                } else {
                    print("⚠️ sensingディレクトリの内容を取得できませんでした")
                }
            } else {
                print("❌ sensingディレクトリが存在しません")
            }

            // 2. ディレクトリが存在するか確認
            guard FileManager.default.fileExists(atPath: sensingDirectory.path) else {
                print("⚠️ 指定されたセンシングデータディレクトリが存在しません: \(sensingDirectory.path)")
                print("❌ センシングデータが見つからないため、ZIPを作成できません")
                return nil
            }

            // 3. メタデータを作成
            let copiedFileCount = (try? FileManager.default
                .contentsOfDirectory(at: sensingDirectory, includingPropertiesForKeys: nil)
                .count) ?? 0

            let metadata: [String: Any] = [
                "sessionName": session.name,
                "sessionId": session.id,
                "startTime": ISO8601DateFormatter().string(from: session.startTime),
                "endTime": session.endTime.map { ISO8601DateFormatter().string(from: $0) } ?? "N/A",
                "dataPoints": session.dataPoints,
                "copiedFiles": copiedFileCount as Int,
            ]

            // 4. ZipFileManagerを使用してZIP圧縮
            let zipFileName = "\(session.name.isEmpty ? session.id : session.name).zip"
            guard let zipURL = try self.zipFileManager.zipDirectoryContents(
                at: sensingDirectory,
                to: zipFileName,
                includeMetadata: true,
                metadata: metadata
            ) else {
                print("❌ ZIP圧縮に失敗しました")
                return nil
            }

            print("✅ ZIP作成完了: \(zipURL.path)")
            return zipURL

        } catch {
            print("❌ セッションデータの圧縮エラー: \(error)")
            print("❌ エラー詳細: \(error.localizedDescription)")
            return nil
        }
    }

    /// セッションデータを削除する（SwiftDataとCSVファイルの両方）
    /// - Parameters:
    ///   - session: 削除するセッション
    ///   - swiftDataRepository: SwiftDataリポジトリ
    /// - Returns: 削除が成功した場合はtrue、失敗した場合はfalse
    func deleteSessionData(
        _ session: SensingSession,
        swiftDataRepository: SwiftDataRepositoryProtocol
    ) async -> Bool {
        do {
            print("🗑️ セッションデータを削除中: \(session.name)")

            // 1. センシングデータディレクトリを特定
            guard let documentsDirectory = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first else {
                print("❌ Documentsディレクトリが見つかりません")
                return false
            }

            // 日付フォーマッターの設定
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.timeZone = TimeZone.current
            dateFormatter.dateFormat = "yyyyMMdd"
            let dateString = dateFormatter.string(from: session.startTime)

            dateFormatter.dateFormat = "HHmmss"
            let timeString = dateFormatter.string(from: session.startTime)

            // セッションディレクトリ名を構築
            let directoryName = if !session.name.isEmpty {
                "\(timeString)-\(session.name)"
            } else {
                timeString
            }

            // センシングデータディレクトリのパス
            let sensingDirectory = documentsDirectory
                .appendingPathComponent("sensing")
                .appendingPathComponent(dateString)
                .appendingPathComponent(directoryName)

            print("📁 削除対象ディレクトリ: \(sensingDirectory.path)")

            // 2. CSVファイルの削除
            var csvDeleted = false
            if FileManager.default.fileExists(atPath: sensingDirectory.path) {
                try FileManager.default.removeItem(at: sensingDirectory)
                print("✅ CSVファイル削除完了")
                csvDeleted = true
            } else {
                print("⚠️ CSVディレクトリが存在しません（既に削除済みの可能性）")
                csvDeleted = true  // 存在しない場合は削除済みとみなす
            }

            // 3. SwiftDataからセッションを削除
            try await swiftDataRepository.deleteSensingSession(by: session.id)
            print("✅ SwiftDataからセッション削除完了")

            print("✅ セッションデータ削除完了: \(session.name)")
            return csvDeleted

        } catch {
            print("❌ セッションデータの削除エラー: \(error)")
            print("❌ エラー詳細: \(error.localizedDescription)")
            return false
        }
    }
}
