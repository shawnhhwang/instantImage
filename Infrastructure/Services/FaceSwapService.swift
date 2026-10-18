import Foundation
import AppKit

public enum FaceSwapError: LocalizedError, Sendable {
    case pythonNotFound
    case scriptNotFound(String)
    case sourceImageNotFound
    case targetImageNotFound
    case executionFailed(String)
    case cancelled
    
    public var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            return "找不到合適的 Python 3 執行環境，請確認本機已安裝 Python 3 且包含 gradio_client 與 pillow 套件。"
        case .scriptNotFound(let path):
            return "找不到換臉腳本: \(path)"
        case .sourceImageNotFound:
            return "未指定或找不到來源人臉圖片 (Source Face)。"
        case .targetImageNotFound:
            return "目標圖片不存在或無法讀取。"
        case .executionFailed(let msg):
            return "FaceSwap API 執行失敗: \(msg)"
        case .cancelled:
            return "換臉運算已被使用者取消。"
        }
    }
}

public final class FaceSwapService: @unchecked Sendable {
    public static let shared = FaceSwapService()
    
    private var activeProcess: Process?
    private let lock = NSLock()
    
    private init() {}
    
    // MARK: - Path Resolvers
    
    public func resolveSwapDirectory() -> URL? {
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("swap"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("swap"),
            URL(fileURLWithPath: "/Users/shawnwang/Documents/agy/image3/swap")
        ]
        
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
    
    public func resolvePythonExecutable() -> String? {
        let candidates = [
            "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
        
        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        
        // Fallback check with which
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["python3"]
        proc.standardOutput = pipe
        try? proc.run()
        proc.waitUntilExit()
        
        if proc.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                return output
            }
        }
        
        return nil
    }
    
    // MARK: - Source Face Discovery
    
    public func loadAvailableSourceFaces() -> [SourceFaceItem] {
        guard let swapDir = resolveSwapDirectory() else { return [] }
        let sourceDir = swapDir.appendingPathComponent("source")
        
        guard let enumerator = FileManager.default.enumerator(
            at: sourceDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        
        let validExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "heif"]
        var items: [SourceFaceItem] = []
        
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            if validExtensions.contains(ext) {
                items.append(SourceFaceItem(url: fileURL))
            }
        }
        
        return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    public func readApiServerUrl() -> String? {
        guard let swapDir = resolveSwapDirectory() else { return nil }
        let settingsFile = swapDir.appendingPathComponent("appsettings.json")
        guard let data = try? Data(contentsOf: settingsFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let url = json["api_url"] as? String else {
            return nil
        }
        return url
    }
    
    // MARK: - Execution
    
    public func cancelRunningSwap() {
        lock.lock()
        defer { lock.unlock() }
        if let proc = activeProcess, proc.isRunning {
            proc.terminate()
        }
        activeProcess = nil
    }
    
    private func setActiveProcess(_ proc: Process?) {
        lock.lock()
        defer { lock.unlock() }
        self.activeProcess = proc
    }
    
    public func runFaceSwap(
        targetURL: URL,
        sourceFaceURL: URL?,
        blend: Double = 60.0,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> FaceSwapResult {
        guard let pythonPath = resolvePythonExecutable() else {
            throw FaceSwapError.pythonNotFound
        }
        
        guard let swapDir = resolveSwapDirectory() else {
            throw FaceSwapError.scriptNotFound("無法定位 swap 目錄")
        }
        
        let scriptPath = swapDir.appendingPathComponent("face_swap_client.py").path
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            throw FaceSwapError.scriptNotFound(scriptPath)
        }
        
        let configPath = swapDir.appendingPathComponent("appsettings.json").path
        
        // Prepare preview temporary output directory
        let tempPreviewDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ProjectLumina/FaceSwapPreview", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempPreviewDir, withIntermediateDirectories: true, attributes: nil)
        
        var arguments = [
            scriptPath,
            "-t", targetURL.path,
            "-c", configPath,
            "-o", tempPreviewDir.path,
            "--face-enhancer-blend", String(format: "%.1f", blend),
            "-w", "Y"
        ]
        
        if let source = sourceFaceURL {
            arguments.append(contentsOf: ["-s", source.path])
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = arguments
        process.currentDirectoryURL = swapDir
        
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        if let currentPath = env["PATH"] {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/Library/Frameworks/Python.framework/Versions/3.14/bin:" + currentPath
        }
        process.environment = env
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        self.setActiveProcess(process)
        
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let accumulator = ProcessOutputAccumulator()
                let outHandle = stdoutPipe.fileHandleForReading
                let errHandle = stderrPipe.fileHandleForReading
                
                // Read stdout asynchronously
                outHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                    
                    let lines = text.components(separatedBy: .newlines)
                    for rawLine in lines {
                        let line = rawLine.trimmingCharacters(in: .whitespaces)
                        guard !line.isEmpty else { continue }
                        accumulator.appendLine(line)
                        onProgress(line)
                    }
                }
                
                errHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                    let lines = text.components(separatedBy: .newlines)
                    for rawLine in lines {
                        let line = rawLine.trimmingCharacters(in: .whitespaces)
                        guard !line.isEmpty else { continue }
                        accumulator.appendLine(line)
                    }
                }
                
                process.terminationHandler = { [weak self] proc in
                    outHandle.readabilityHandler = nil
                    errHandle.readabilityHandler = nil
                    
                    self?.setActiveProcess(nil)
                    
                    let snapshot = accumulator.snapshot
                    
                    if proc.terminationStatus == 0 || snapshot.resultLine != nil {
                        if let resLine = snapshot.resultLine,
                           let range = resLine.range(of: "__FACESWAP_RESULT_JSON__:") {
                            let jsonString = String(resLine[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                            if let jsonData = jsonString.data(using: .utf8),
                               let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                               let outputPath = dict["output_path"] as? String {
                                let outputURL = URL(fileURLWithPath: outputPath)
                                let filename = dict["filename"] as? String ?? outputURL.lastPathComponent
                                
                                let swapResult = FaceSwapResult(
                                    targetURL: targetURL,
                                    sourceFaceURL: sourceFaceURL,
                                    previewOutputURL: outputURL,
                                    filename: filename
                                )
                                continuation.resume(returning: swapResult)
                                return
                            }
                        }
                    }
                    
                    // If we reached here, check for structured error
                    if let errL = snapshot.errorLine,
                       let range = errL.range(of: "__FACESWAP_ERROR_JSON__:") {
                        let jsonString = String(errL[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                        if let jsonData = jsonString.data(using: .utf8),
                           let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                           let msg = dict["message"] as? String {
                            continuation.resume(throwing: FaceSwapError.executionFailed(msg))
                            return
                        }
                    }
                    
                    let summaryError = snapshot.logSummary
                    if proc.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: FaceSwapError.cancelled)
                    } else {
                        continuation.resume(throwing: FaceSwapError.executionFailed(summaryError.isEmpty ? "執行失敗 (代碼 \(proc.terminationStatus))" : summaryError))
                    }
                }
                
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: FaceSwapError.executionFailed("無法啟動 Python 行程: \(error.localizedDescription)"))
                }
            }
        } onCancel: {
            self.cancelRunningSwap()
        }
    }
}

final class ProcessOutputAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var _resultLine: String?
    private var _errorLine: String?
    private var _logLines: [String] = []
    
    func appendLine(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        _logLines.append(line)
        if line.contains("__FACESWAP_RESULT_JSON__:") {
            _resultLine = line
        }
        if line.contains("__FACESWAP_ERROR_JSON__:") {
            _errorLine = line
        }
    }
    
    var snapshot: (resultLine: String?, errorLine: String?, logSummary: String) {
        lock.lock()
        defer { lock.unlock() }
        return (_resultLine, _errorLine, _logLines.suffix(6).joined(separator: "\n"))
    }
}
