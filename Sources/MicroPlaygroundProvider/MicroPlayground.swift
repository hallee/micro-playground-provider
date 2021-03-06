import Basic
import SPMUtility
import Foundation

public class MicroPlayground {

    static public var moduleName = "MicroPlayground"
    static public let swiftVersionNumber = "5.1"
    static let swiftVersion = swiftVersionNumber + "-RELEASE"
    private let projectPath: String
    lazy private var toolchainPath: String = {
        return projectPath + "/Toolchains/swift-\(MicroPlayground.swiftVersion).xctoolchain/usr/bin"
    }()
    lazy private var sdkPath: AbsolutePath? = {
        var path: AbsolutePath?
        #if os(macOS)
            let foundPath = try? Process.checkNonZeroExit(
                args: "xcrun", "--sdk", "macosx", "--show-sdk-path"
            )
            guard let sdkRoot = foundPath?.spm_chomp(), !sdkRoot.isEmpty else {
                return nil
            }
            path = AbsolutePath(sdkRoot)
        #endif

        return path
    }()

    private let processSet = ProcessSet()
    private var watchdogQueue = DispatchQueue(label: ProcessInfo.processInfo.globallyUniqueString + "Watchdog",
                                              qos: .userInitiated)
    static var processTimeLimit: Double = 5

    private var errorParser = PlaygroundErrorParser(executableName: MicroPlayground.moduleName)
    enum Error: Swift.Error {
        case failed(String)
    }

    init(_ projectDirectoryPath: String) {
        projectPath = projectDirectoryPath
    }

    public func run(code: String, completion: @escaping (PlaygroundResult) -> Void) {
        buildAndRun(code: code) { result in
            var outputString = ""
            if let errors = result.errors {
                for error in errors {
                    outputString += error.description + "\n"
                }
                completion(PlaygroundResult(text: "", error: outputString))
            } else {
                outputString += result.text + "\n"
                completion(PlaygroundResult(text: outputString, error: ""))
            }
        }
    }

    private func buildAndRun(code: String, timeLimit: Double = processTimeLimit,
                             completion: @escaping (RunResult) -> Void) {
        let queue = DispatchQueue(label: ProcessInfo.processInfo.globallyUniqueString, qos: .background)
        var process: Basic.Process?
        var returned = false

        queue.async {
            defer {
                returned = true
            }
            let code = """
            import Foundation
            var rnofilelimit = rlimit(rlim_cur: 1, rlim_max: 1)
            #if os(macOS)
                setrlimit(RLIMIT_NOFILE, &rnofilelimit)
            #else
                setrlimit(__rlimit_resource_t(7), &rnofilelimit)
            #endif

            """ + code
            var playgroundOutput: RunResult
            do {
                let buildResult = try self.build(code: code)
                let runResult = try self.run(binaryPath: buildResult.dematerialize()) { processCreated in
                    process = processCreated
                }
                playgroundOutput = RunResult(text: try runResult.dematerialize(), errors: nil)
            } catch MicroPlayground.Error.failed(let output) {
                if let items = try? self.errorParser.parse(input: output), items.count > 0 {
                    playgroundOutput = RunResult(text: output, errors: items)
                } else {
                    playgroundOutput = RunResult(text: "",
                                                 errors: [PlaygroundError(location: CodeLocation(row: 0, column: 0),
                                                                          description: output)])
                }
            } catch {
                playgroundOutput = RunResult(text: "",
                                             errors: [PlaygroundError(location: CodeLocation(row: 0, column: 0),
                                                                      description: error.localizedDescription)])
            }

            guard !returned else { return }
            completion(playgroundOutput)
        }

        watchdogQueue.asyncAfter(deadline: .now() + timeLimit) {
            guard !returned else { return }
            process?.signal(15)
            completion(RunResult(text: "",
                                 errors: [PlaygroundError(location: CodeLocation(row: 0, column: 0),
                                                          description: "Exceeded time limit.")]))
            returned = true
        }
    }

    private func build(code: String) throws -> Result<AbsolutePath, Error> {
        let fileSystem = Basic.localFileSystem

        let temporaryBuildDirectory = try TemporaryDirectory(prefix: ProcessInfo.processInfo.globallyUniqueString)
        let mainFilePath = temporaryBuildDirectory.path.appending(RelativePath("main.swift"))
        let binaryFilePath = temporaryBuildDirectory.path.appending(component: "main")

        try fileSystem.writeFileContents(mainFilePath, bytes: ByteString(encodingAsUTF8: "" + code))

        var cmd = [String]()
        cmd += ["\(toolchainPath)/swift"]
        cmd += ["--driver-mode=swiftc"]
        #if DEBUG
            cmd += ["-v"]
        #endif
        cmd += ["-gnone"]
        cmd += ["-suppress-warnings"]
        cmd += ["-module-name", MicroPlayground.moduleName]
        #if os(Linux)
            cmd += ["-module-link-name", "Glibc"]
        #endif

        cmd += ["-O"]

        if let sdkPath = sdkPath {
            cmd += ["-sdk", sdkPath.pathString]
        }
        cmd += ["-o", binaryFilePath.pathString]
        cmd += [mainFilePath.pathString]

        let process = Basic.Process(arguments: cmd, outputRedirection: .collect, verbose: false)
        try processSet.add(process)
        try process.launch()
        let result = try process.waitUntilExit()

        switch result.exitStatus {
        case .terminated(let exitCode) where exitCode == 0:
            return Result.success(binaryFilePath)
        case .signalled(let signal):
            return Result.failure(Error.failed("Terminated by signal \(signal)"))
        default:
            return Result.failure(Error.failed(try defaultError(result)))
        }
    }

    private func run(binaryPath: AbsolutePath,
                     processCreated: (Basic.Process) -> Void) throws -> Result<String, Error> {
        var cmd = [String]()
        #if os(macOS)
            // Use sandbox-exec on macOS. This provides some safety against arbitrary code execution.
            cmd += ["sandbox-exec", "-p", sandboxProfile()]
        #endif
        cmd += [binaryPath.pathString]

        let process = Basic.Process(arguments: cmd, environment: [:], outputRedirection: .collect, verbose: false)
        processCreated(process)
        try processSet.add(process)
        try process.launch()
        let result = try process.waitUntilExit()

        // Remove container directory. Cleanup after run.
        try FileManager.default.removeItem(atPath: binaryPath.parentDirectory.pathString)

        switch result.exitStatus {
        case .terminated(let exitCode) where exitCode == 0:
            return Result.success(try result.utf8Output().spm_chuzzle() ?? "")
        case .signalled(let signal):
            return Result.failure(Error.failed("Terminated by signal \(signal)"))
        default:
            return Result.failure(Error.failed(try defaultError(result)))
        }
    }

    private func defaultError(_ result: ProcessResult) throws -> String {
        return try (result.utf8Output() + result.utf8stderrOutput()).spm_chuzzle() ?? "Terminated."
    }

    private func sandboxProfile() -> String {
        let output = """
        (version 1)
        (deny default)
        (import \"system.sb\")
        (allow file-read*)
        (allow process*)
        """
        return output
    }

    private struct RunResult {
        let text: String
        let errors: [PlaygroundError]?
    }

    public struct PlaygroundResult: Codable {
        public let text: String
        public let error: String
    }

}
