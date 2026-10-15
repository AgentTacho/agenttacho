import Foundation
import Testing
@testable import UsageCore

/// AgentMeter runs only once: a second copy finds the first one and offers a
/// kill command for it.
@Suite struct RunningInstanceTests {
    let paths = Paths(home: URL(fileURLWithPath: "/Users/someone"))

    func record(_ pid: Int32, bundle: String? = "dev.rhuss.agentmeter", path: String = "/Applications/AgentMeter.app",
                terminated: Bool = false, version: String? = "0.3.0 (build 72)") -> RunningInstance.Process {
        RunningInstance.Process(pid: pid, bundleIdentifier: bundle, bundlePath: path, isTerminated: terminated, versionText: version)
    }

    @Test func othersExcludeOwnTerminatedAndForeignProcesses() {
        let processes = [
            record(100),
            record(200, path: "/Users/someone/agentmeter/build/AgentMeter.app"),
            record(300, terminated: true),
            record(400, bundle: "com.example.other"),
            record(500, bundle: nil),
        ]
        let others = RunningInstance.others(from: processes, ownPID: 200, bundleIdentifier: "dev.rhuss.agentmeter")
        #expect(others.map(\.pid) == [100])
    }

    @Test func killCommandUsesThePID() {
        let instance = RunningInstance(pid: 2512, bundlePath: "/Applications/AgentMeter.app", versionText: "0.3.0 (build 72)")
        #expect(instance.killCommand == "kill 2512")
    }

    @Test func summaryNamesVersionLocationAndProcess() {
        let instance = RunningInstance(pid: 2512, bundlePath: "/Applications/AgentMeter.app", versionText: "0.3.0 (build 72)")
        #expect(instance.summary(paths: paths)
            == "AgentMeter 0.3.0 (build 72) is already running from /Applications/AgentMeter.app (process 2512).")
    }

    @Test func summaryAbbreviatesTheHomeDirectory() {
        let instance = RunningInstance(pid: 7, bundlePath: "/Users/someone/agentmeter/build/AgentMeter.app", versionText: nil)
        #expect(instance.summary(paths: paths)
            == "AgentMeter is already running from ~/agentmeter/build/AgentMeter.app (process 7).")
    }

    @Test func summaryWithoutAKnownLocation() {
        let instance = RunningInstance(pid: 9, bundlePath: nil, versionText: "0.3.0")
        #expect(instance.summary(paths: paths) == "AgentMeter 0.3.0 is already running (process 9).")
    }

    @Test func instanceFromAProcessRecord() {
        let instance = RunningInstance(record(42))
        #expect(instance.pid == 42)
        #expect(instance.bundlePath == "/Applications/AgentMeter.app")
        #expect(instance.versionText == "0.3.0 (build 72)")
    }
}
