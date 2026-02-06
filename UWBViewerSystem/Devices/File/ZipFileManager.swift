//
//  ZipFileManager.swift
//  UWBViewerSystem
//
//  Created by Claude Code on 2025/11/25.
//

import Foundation

/// ZIP圧縮処理を担当するファイルマネージャー
/// Devices層のFile管理機能として、ディレクトリのZIP圧縮を提供
class ZipFileManager {
    static let shared = ZipFileManager()

    private init() {}

    /// ディレクトリをZIP圧縮する
    /// - Parameters:
    ///   - sourceURL: 圧縮するディレクトリのURL
    ///   - zipFileName: 作成するZIPファイルの名前
    ///   - destinationDirectory: ZIPファイルを配置するディレクトリ（デフォルトは一時ディレクトリ）
    /// - Returns: 作成されたZIPファイルのURL
    /// - Throws: ファイル操作に関連するエラー
    func zipDirectory(
        at sourceURL: URL,
        to zipFileName: String,
        in destinationDirectory: URL? = nil
    ) throws -> URL {
        let destDir = destinationDirectory ?? FileManager.default.temporaryDirectory
        let zipURL = destDir.appendingPathComponent(zipFileName)

        // 既存のZIPファイルを削除
        try? FileManager.default.removeItem(at: zipURL)

        // ZIP圧縮を実行
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?

        coordinator.coordinate(
            readingItemAt: sourceURL,
            options: .forUploading,
            error: &coordinationError
        ) { zipFileURL in
            do {
                try FileManager.default.copyItem(at: zipFileURL, to: zipURL)
                print("📦 ZIP圧縮成功: \(zipURL.path)")
            } catch {
                print("❌ ZIP作成エラー: \(error)")
            }
        }

        if let error = coordinationError {
            throw error
        }

        return zipURL
    }

    /// 一時ディレクトリにファイルをコピーし、ZIP圧縮する
    /// - Parameters:
    ///   - files: コピーするファイルのURL配列
    ///   - zipFileName: 作成するZIPファイルの名前
    ///   - tempDirectoryName: 一時ディレクトリの名前（デフォルトはランダムUUID）
    /// - Returns: 作成されたZIPファイルのURL
    /// - Throws: ファイル操作に関連するエラー
    func zipFiles(
        _ files: [URL],
        to zipFileName: String,
        tempDirectoryName: String? = nil
    ) throws -> URL {
        // 一時ディレクトリを作成
        let tempDirName = tempDirectoryName ?? UUID().uuidString
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(tempDirName, isDirectory: true)

        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )

        // ファイルをコピー
        for fileURL in files {
            let fileName = fileURL.lastPathComponent
            let destinationURL = tempDir.appendingPathComponent(fileName)
            try FileManager.default.copyItem(at: fileURL, to: destinationURL)
            print("📄 ファイルコピー: \(fileName)")
        }

        // ZIP圧縮
        let zipURL = try zipDirectory(at: tempDir, to: zipFileName)

        // 一時ディレクトリを削除
        try? FileManager.default.removeItem(at: tempDir)

        return zipURL
    }

    /// ディレクトリ内の全ファイルをZIP圧縮する
    /// - Parameters:
    ///   - directoryURL: 圧縮するディレクトリのURL
    ///   - zipFileName: 作成するZIPファイルの名前
    ///   - includeMetadata: メタデータJSONを含めるかどうか
    ///   - metadata: 含めるメタデータ（includeMetadataがtrueの場合）
    /// - Returns: 作成されたZIPファイルのURL、ディレクトリが存在しない場合はnil
    /// - Throws: ファイル操作に関連するエラー
    func zipDirectoryContents(
        at directoryURL: URL,
        to zipFileName: String,
        includeMetadata: Bool = false,
        metadata: [String: Any]? = nil
    ) throws -> URL? {
        // ディレクトリの存在確認
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            print("⚠️ 指定されたディレクトリが存在しません: \(directoryURL.path)")
            return nil
        }

        // 一時ディレクトリを作成
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )

        // ディレクトリ内の全ファイルをコピー
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )

        var copiedFileCount = 0
        for fileURL in files {
            let fileName = fileURL.lastPathComponent
            let destinationURL = tempDir.appendingPathComponent(fileName)
            try fileManager.copyItem(at: fileURL, to: destinationURL)
            print("📄 ファイルコピー: \(fileName)")
            copiedFileCount += 1
        }

        print("✅ \(copiedFileCount)個のファイルをコピーしました")

        // メタデータJSONを追加
        if includeMetadata, let metadata {
            let jsonData = try JSONSerialization.data(
                withJSONObject: metadata,
                options: .prettyPrinted
            )
            let metadataURL = tempDir.appendingPathComponent("metadata.json")
            try jsonData.write(to: metadataURL)
            print("📄 メタデータJSON作成完了: \(metadataURL.path)")
        }

        // ZIP圧縮
        print("🗜️ ZIP圧縮開始")
        let zipURL = try zipDirectory(at: tempDir, to: zipFileName)
        print("🗜️ ZIP圧縮完了: \(zipURL.path)")

        // ZIPファイルの存在確認
        if FileManager.default.fileExists(atPath: zipURL.path) {
            let attributes = try? FileManager.default.attributesOfItem(atPath: zipURL.path)
            let fileSize = attributes?[.size] as? Int64 ?? 0
            print("✅ ZIPファイル確認OK: サイズ=\(fileSize)バイト")
        }

        // 一時ディレクトリを削除
        try? FileManager.default.removeItem(at: tempDir)
        print("🗑️ 一時ディレクトリ削除完了")

        return zipURL
    }
}
