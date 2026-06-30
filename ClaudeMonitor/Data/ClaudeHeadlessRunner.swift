// ClaudeMonitor/Data/ClaudeHeadlessRunner.swift
import Foundation

/// 외부 명령 실행 추상화 — 테스트에서 가짜로 주입하기 위해 분리.
protocol CommandRunning {
    func run(executable: String, args: [String], stdin: String?, timeout: TimeInterval) throws -> (stdout: String, exitCode: Int32)
}

enum HeadlessError: Error, Equatable { case unavailable, failed(String), timedOut }

/// 로그인된 Claude Code를 헤드리스(`claude -p`)로 호출해 텍스트를 받는다.
/// API 키 불필요 — 사용자의 기존 구독을 그대로 사용. 회고 생성 시에만 1콜.
final class ClaudeHeadlessRunner {
    /// GUI 앱은 셸 PATH를 못 받으므로 알려진 경로를 직접 탐색한다.
    static var defaultCandidates: [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.npm-global/bin/claude",
        ]
    }

    private let runner: CommandRunning
    let executable: String?

    init(runner: CommandRunning,
         candidates: [String] = ClaudeHeadlessRunner.defaultCandidates,
         exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) {
        self.runner = runner
        self.executable = Self.resolveExecutable(candidates: candidates, exists: exists)
    }

    var isAvailable: Bool { executable != nil }

    static func resolveExecutable(candidates: [String], exists: (String) -> Bool) -> String? {
        candidates.first(where: exists)
    }

    /// `claude -p <prompt>` 실행 → 모델 텍스트. 실패 시 HeadlessError throw.
    func run(prompt: String, timeout: TimeInterval = 120) throws -> String {
        guard let exe = executable else { throw HeadlessError.unavailable }
        let (out, code) = try runner.run(executable: exe, args: ["-p", prompt], stdin: "", timeout: timeout)
        guard code == 0 else { throw HeadlessError.failed(out.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HeadlessError.failed("empty output") }
        return trimmed
    }
}

/// 실제 `Process` 기반 실행 어댑터. (통합 계층 — 단위테스트는 ClaudeHeadlessRunner 로직만)
struct ProcessCommandRunner: CommandRunning {
    func run(executable: String, args: [String], stdin: String?, timeout: TimeInterval) throws -> (stdout: String, exitCode: Int32) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args

        let outPipe = Pipe(); proc.standardOutput = outPipe; proc.standardError = outPipe
        let inPipe = Pipe(); proc.standardInput = inPipe

        // GUI 앱은 빈약한 PATH 를 가지므로 node 등을 찾도록 보강
        var env = ProcessInfo.processInfo.environment
        let extra = "/usr/local/bin:/opt/homebrew/bin:\(NSHomeDirectory())/.local/bin"
        env["PATH"] = (env["PATH"].map { "\($0):\(extra)" }) ?? extra
        proc.environment = env

        try proc.run()
        if let stdin, let d = stdin.data(using: .utf8) { inPipe.fileHandleForWriting.write(d) }
        try? inPipe.fileHandleForWriting.close()

        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async { proc.waitUntilExit(); sem.signal() }
        if sem.wait(timeout: .now() + timeout) == .timedOut {
            proc.terminate()
            throw HeadlessError.timedOut
        }
        // 회고 출력은 작아(수 KB) 종료 후 일괄 읽기로 충분
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "", proc.terminationStatus)
    }
}
