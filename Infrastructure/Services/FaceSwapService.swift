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
    
    // MARK: - Environment & Packages Check
    
    public func checkPythonEnvironment() -> (path: String?, version: String?, hasRequiredPackages: Bool, message: String) {
        guard let pythonPath = resolvePythonExecutable() else {
            return (nil, nil, false, "系統中未偵測到 Python 3")
        }
        
        // Check Python version
        var versionString: String? = nil
        let verProc = Process()
        verProc.executableURL = URL(fileURLWithPath: pythonPath)
        verProc.arguments = ["--version"]
        let verPipe = Pipe()
        verProc.standardOutput = verPipe
        verProc.standardError = verPipe
        try? verProc.run()
        verProc.waitUntilExit()
        if verProc.terminationStatus == 0 {
            let data = verPipe.fileHandleForReading.readDataToEndOfFile()
            versionString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Check packages
        let pkgProc = Process()
        pkgProc.executableURL = URL(fileURLWithPath: pythonPath)
        pkgProc.arguments = ["-c", "import gradio_client, PIL, pillow_heif, requests; print('OK')"]
        let pkgPipe = Pipe()
        pkgProc.standardOutput = pkgPipe
        pkgProc.standardError = pkgPipe
        try? pkgProc.run()
        pkgProc.waitUntilExit()
        
        if pkgProc.terminationStatus == 0 {
            let ver = versionString ?? "Python 3"
            return (pythonPath, ver, true, "\(ver) 套件健全 (gradio_client, Pillow, pillow-heif, requests)")
        } else {
            let data = pkgPipe.fileHandleForReading.readDataToEndOfFile()
            let err = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (pythonPath, versionString, false, "缺少必要 Python 依賴: \(err)")
        }
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
    
    // MARK: - Settings Persistence
    
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
    
    public func saveApiServerUrl(_ newUrl: String) throws {
        guard let swapDir = resolveSwapDirectory() else {
            throw FaceSwapError.scriptNotFound("無法定位 swap 目錄")
        }
        let settingsFile = swapDir.appendingPathComponent("appsettings.json")
        guard let data = try? Data(contentsOf: settingsFile),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FaceSwapError.executionFailed("無法讀取或解析 appsettings.json")
        }
        
        let trimmed = newUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        json["api_url"] = trimmed
        
        let updatedData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try updatedData.write(to: settingsFile, options: .atomic)
        
        // Sync to app bundle resource if available
        let bundleSettings = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/appsettings.json")
        if FileManager.default.fileExists(atPath: bundleSettings.path) {
            try? updatedData.write(to: bundleSettings, options: .atomic)
        }
    }
    
    // MARK: - API Connection Testing
    
    public func testApiConnection(urlString: String) async -> (success: Bool, message: String, latencyMs: Int) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (false, "請輸入有效的 API 網址", 0)
        }
        
        // Extract base Gradio server URL
        var baseStr = trimmed
        for suffix in ["/api/predict/", "/api/predict", "/api/", "/api"] {
            if baseStr.hasSuffix(suffix) {
                baseStr = String(baseStr.dropLast(suffix.count))
                break
            }
        }
        
        guard let candidateURL = URL(string: baseStr) else {
            return (false, "網址格式不正確: \(trimmed)", 0)
        }
        
        // Target /config endpoint or root /
        let testEndpoint = candidateURL.appendingPathComponent("config")
        var request = URLRequest(url: testEndpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 4.0
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let elapsed = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            
            if let httpRes = response as? HTTPURLResponse {
                if (200...299).contains(httpRes.statusCode) {
                    return (true, "連線成功！FaceFusion 伺服器運作中 (HTTP \(httpRes.statusCode))", elapsed)
                } else {
                    // Try root endpoint if /config wasn't 200
                    var rootReq = URLRequest(url: candidateURL)
                    rootReq.httpMethod = "GET"
                    rootReq.timeoutInterval = 3.0
                    if let (_, rootRes) = try? await URLSession.shared.data(for: rootReq),
                       let rootHttp = rootRes as? HTTPURLResponse, (200...399).contains(rootHttp.statusCode) {
                        return (true, "伺服器已回應 (HTTP \(rootHttp.statusCode))", elapsed)
                    }
                    return (true, "伺服器已回應 (HTTP \(httpRes.statusCode))", elapsed)
                }
            } else {
                return (true, "連線成功", elapsed)
            }
        } catch {
            // Also try fallback HEAD to root
            do {
                var rootReq = URLRequest(url: candidateURL)
                rootReq.httpMethod = "HEAD"
                rootReq.timeoutInterval = 3.0
                let (_, rootRes) = try await URLSession.shared.data(for: rootReq)
                let elapsed = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
                if let http = rootRes as? HTTPURLResponse {
                    return (true, "連線成功 (HTTP \(http.statusCode))", elapsed)
                }
            } catch {
                // Return original failure
            }
            
            let elapsed = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            return (false, "連線失敗: \(error.localizedDescription)", elapsed)
        }
    }
    
    // MARK: - Process Execution Management
    
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
    
    // MARK: - Single FaceSwap Execution
    
    public func runFaceSwap(
        targetURL: URL,
        sourceFaceURL: URL?,
        blend: Double = 60.0,
        apiUrl: String? = nil,
        stagingDirectoryURL: URL? = nil,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> FaceSwapResult {
        let results = try await runBatchFaceSwap(
            targetURLs: [targetURL],
            sourceFaceURL: sourceFaceURL,
            blend: blend,
            apiUrl: apiUrl,
            stagingDirectoryURL: stagingDirectoryURL,
            onProgress: { _, _, log in
                onProgress(log)
            },
            onItemCompleted: { _ in },
            onItemFailed: { _, _ in }
        )
        
        if let first = results.first, let res = first.result {
            return res
        } else if let err = results.first?.errorMessage {
            throw FaceSwapError.executionFailed(err)
        } else {
            throw FaceSwapError.executionFailed("未產生換臉結果影像")
        }
    }
    
    // MARK: - Batch FaceSwap Execution
    
    public func runBatchFaceSwap(
        targetURLs: [URL],
        sourceFaceURL: URL?,
        blend: Double = 60.0,
        apiUrl: String? = nil,
        stagingDirectoryURL: URL? = nil,
        onProgress: @escaping @Sendable (Int, Int, String) -> Void,
        onItemCompleted: @escaping @Sendable (FaceSwapResult) -> Void,
        onItemFailed: @escaping @Sendable (URL, String) -> Void
    ) async throws -> [FaceSwapBatchItem] {
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
        
        // Prepare preview temporary output directory (faceswap_temp)
        let outputDir: URL
        if let customStaging = stagingDirectoryURL {
            outputDir = customStaging
        } else if let firstTarget = targetURLs.first {
            outputDir = firstTarget.deletingLastPathComponent().appendingPathComponent("faceswap_temp", isDirectory: true)
        } else {
            outputDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ProjectLumina/faceswap_temp", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true, attributes: nil)
        
        var arguments = [
            scriptPath,
            "-c", configPath,
            "-o", outputDir.path,
            "--face-enhancer-blend", String(format: "%.1f", blend),
            "-w", "Y"
        ]
        
        if let api = apiUrl, !api.isEmpty {
            arguments.append(contentsOf: ["--api-url", api])
        }
        
        if let source = sourceFaceURL {
            arguments.append(contentsOf: ["-s", source.path])
        }
        
        // Add targets
        arguments.append("-t")
        for target in targetURLs {
            arguments.append(target.path)
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
                let accumulator = BatchProcessOutputAccumulator(
                    targetURLs: targetURLs,
                    sourceFaceURL: sourceFaceURL,
                    onProgress: onProgress,
                    onItemCompleted: onItemCompleted,
                    onItemFailed: onItemFailed
                )
                
                let outHandle = stdoutPipe.fileHandleForReading
                let errHandle = stderrPipe.fileHandleForReading
                
                outHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                    let lines = text.components(separatedBy: .newlines)
                    for rawLine in lines {
                        let line = rawLine.trimmingCharacters(in: .whitespaces)
                        guard !line.isEmpty else { continue }
                        accumulator.consumeStdoutLine(line)
                    }
                }
                
                errHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                    let lines = text.components(separatedBy: .newlines)
                    for rawLine in lines {
                        let line = rawLine.trimmingCharacters(in: .whitespaces)
                        guard !line.isEmpty else { continue }
                        accumulator.consumeStderrLine(line)
                    }
                }
                
                process.terminationHandler = { [weak self] proc in
                    outHandle.readabilityHandler = nil
                    errHandle.readabilityHandler = nil
                    self?.setActiveProcess(nil)
                    
                    let finalBatchItems = accumulator.finalizeItems()
                    
                    if proc.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: FaceSwapError.cancelled)
                        return
                    }
                    
                    // If at least one succeeded or was processed, return items
                    let successCount = finalBatchItems.filter { $0.result != nil }.count
                    if successCount > 0 || proc.terminationStatus == 0 {
                        continuation.resume(returning: finalBatchItems)
                    } else {
                        let summary = accumulator.errorSummary
                        continuation.resume(throwing: FaceSwapError.executionFailed(summary.isEmpty ? "執行失敗 (代碼 \(proc.terminationStatus))" : summary))
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

// MARK: - Batch Output Accumulator

final class BatchProcessOutputAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private let targetURLs: [URL]
    private let sourceFaceURL: URL?
    private let onProgress: @Sendable (Int, Int, String) -> Void
    private let onItemCompleted: @Sendable (FaceSwapResult) -> Void
    private let onItemFailed: @Sendable (URL, String) -> Void
    
    private var completedResults: [String: FaceSwapResult] = [:]
    private var failedErrors: [String: String] = [:]
    private var logLines: [String] = []
    private var currentProgressIndex: Int = 1
    private let totalTargets: Int
    
    init(
        targetURLs: [URL],
        sourceFaceURL: URL?,
        onProgress: @escaping @Sendable (Int, Int, String) -> Void,
        onItemCompleted: @escaping @Sendable (FaceSwapResult) -> Void,
        onItemFailed: @escaping @Sendable (URL, String) -> Void
    ) {
        self.targetURLs = targetURLs
        self.sourceFaceURL = sourceFaceURL
        self.totalTargets = max(1, targetURLs.count)
        self.onProgress = onProgress
        self.onItemCompleted = onItemCompleted
        self.onItemFailed = onItemFailed
    }
    
    func consumeStdoutLine(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        
        logLines.append(line)
        
        // Detect progress format: [1/12] Processing target image: /path/to/img...
        if let match = line.range(of: #"\[(\d+)/(\d+)\]"#, options: .regularExpression) {
            let bracketed = String(line[match])
            let digits = bracketed.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).components(separatedBy: "/")
            if digits.count == 2, let cur = Int(digits[0]) {
                currentProgressIndex = cur
            }
        }
        
        // Check for success JSON
        if let range = line.range(of: "__FACESWAP_RESULT_JSON__:") {
            let jsonString = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if let data = jsonString.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let outputPath = dict["output_path"] as? String,
               let targetPath = dict["target_path"] as? String {
                let outURL = URL(fileURLWithPath: outputPath)
                let tgtURL = URL(fileURLWithPath: targetPath)
                let fn = dict["filename"] as? String ?? outURL.lastPathComponent
                
                let res = FaceSwapResult(targetURL: tgtURL, sourceFaceURL: sourceFaceURL, previewOutputURL: outURL, filename: fn)
                completedResults[tgtURL.standardizedFileURL.path] = res
                onItemCompleted(res)
            }
        }
        
        // Check for error JSON
        if let range = line.range(of: "__FACESWAP_ERROR_JSON__:") {
            let jsonString = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if let data = jsonString.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = dict["message"] as? String {
                let tgtPath = dict["target_path"] as? String ?? ""
                if !tgtPath.isEmpty {
                    let tgtURL = URL(fileURLWithPath: tgtPath)
                    failedErrors[tgtURL.standardizedFileURL.path] = msg
                    onItemFailed(tgtURL, msg)
                }
            }
        }
        
        onProgress(currentProgressIndex, totalTargets, line)
    }
    
    func consumeStderrLine(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        logLines.append(line)
    }
    
    var errorSummary: String {
        lock.lock()
        defer { lock.unlock() }
        return logLines.suffix(8).joined(separator: "\n")
    }
    
    func finalizeItems() -> [FaceSwapBatchItem] {
        lock.lock()
        defer { lock.unlock() }
        
        return targetURLs.map { targetURL in
            let path = targetURL.standardizedFileURL.path
            let res = completedResults[path]
            let err = failedErrors[path]
            return FaceSwapBatchItem(
                targetURL: targetURL,
                result: res,
                errorMessage: err,
                decision: .pending
            )
        }
    }
}
