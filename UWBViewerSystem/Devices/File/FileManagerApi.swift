//
//  FileManagerApi.swift
//  UWBViewerSystem
//
//  Created by 牧野遥斗 on R 7/04/09.
//

import Foundation

class FileManagerApi {
    static let shared = FileManagerApi()

    private let documentsPath: String

    private init() {
        self.documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    }

    func getExportFileUrl(to directory: URL, fileName: String) -> URL? {
        let fileURL = directory.appendingPathComponent(fileName + ".usdz")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            print("Exported to: \(fileURL)")
            return fileURL
        } catch {
            print("Error exporting scan: \(error)")
            return nil
        }
    }

    func createStringToFile(
        to directory: URL,
        fileName: String,
        text: String,
        ext: String
    ) -> URL? {
        let fileUrl = directory.appendingPathComponent("\(fileName).\(ext)")
        // 新規ファイルを作成する
        if FileManager.default.createFile(
            atPath: fileUrl.path,
            contents: text.data(using: .utf8),
            attributes: nil
        ) {
            return fileUrl
        } else {
            return nil
        }
    }

    func createDataToFile(
        to directory: URL,
        fileName: String,
        data: Data,
        ext: String
    ) -> URL? {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileUrl = directory.appendingPathComponent("\(fileName).\(ext)")
            try data.write(to: fileUrl)
            return fileUrl
        } catch {
            print("Error saving file: \(error)")
            return nil
        }
    }

    func createExportDirectory(date: Date = Date()) -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let today = dateFormatter.string(from: date)

        dateFormatter.dateFormat = "HHmmss"
        let time = dateFormatter.string(from: date)

        let directory = URL(fileURLWithPath: documentsPath)
            .appendingPathComponent(today)
            .appendingPathComponent(time)

        return directory
    }

    // 絶対パスを相対パスに変換する
    func getRelativePath(from url: URL) -> String {
        let documentsURL = URL(fileURLWithPath: documentsPath)
        let relativePath = url.path.replacingOccurrences(of: documentsURL.path, with: "")
        return relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
    }

    // 相対パスから絶対パスを取得する
    func getAbsolutePath(from relativePath: String) -> URL {
        URL(fileURLWithPath: self.documentsPath).appendingPathComponent(relativePath)
    }

    /// 指定されたファイルの内容を全て削除します
    /// - Parameter fileURL: 内容を削除するファイルのURL
    /// - Returns: 成功した場合はtrue、失敗した場合はfalse
    func clearFileContents(at fileURL: URL) -> Bool {
        do {
            try "".write(to: fileURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            print("ファイルの内容を削除中にエラーが発生しました: \(error)")
            return false
        }
    }

    /// 指定されたファイルの内容を全て削除します
    /// 指定されたファイルまたはディレクトリを完全に削除します
    /// - Parameter fileURL: 削除するファイルまたはディレクトリのURL
    /// - Returns: 成功した場合はtrue、失敗した場合はfalse
    func deleteFile(at fileURL: URL) -> Bool {
        do {
            let fileManager = FileManager.default
            var isDirectory: ObjCBool = false

            // パスが存在するか確認
            guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
                print("指定されたパスが存在しません: \(fileURL.path)")
                return false
            }

            // ディレクトリの場合は中身も含めて削除
            if isDirectory.boolValue {
                try fileManager.removeItem(at: fileURL)
            } else {
                try fileManager.removeItem(at: fileURL)
            }
            return true
        } catch {
            print("ファイルまたはディレクトリの削除中にエラーが発生しました: \(error)")
            return false
        }
    }

    /// 指定されたディレクトリ内の全てのファイルとサブディレクトリを削除します
    /// - Parameter directoryURL: 内容を削除するディレクトリのURL
    /// - Returns: 成功した場合はtrue、失敗した場合はfalse
    func clearDirectoryContents(at directoryURL: URL) -> Bool {
        do {
            let fileManager = FileManager.default
            let contents = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)

            for fileURL in contents {
                try fileManager.removeItem(at: fileURL)
            }
            return true
        } catch {
            print("ディレクトリの内容を削除中にエラーが発生しました: \(error)")
            return false
        }
    }
}
