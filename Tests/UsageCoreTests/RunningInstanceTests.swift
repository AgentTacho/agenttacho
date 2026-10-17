import Foundation
import Testing
@testable import UsageCore

/// AgentTacho runs only once: a second copy finds the first one, or a running
/// AgentMeter (spec 023 FR-012), and offers a kill command for it.
@Suite struct RunningInstanceTests {
    let paths = Paths(home: URL(fileURLWithPath: "/Users/someone"))

    func record(_ pid: Int32, bundle: String? = "dev.rhuss.agenttacho", path: String = "/Applications/AgentTacho.app",
                terminated: Bool = false, version: String? = "0.3.0 (build 72)") -> RunningInstance.Process {
        RunningInstance.Process(pid: pid, bundleIdentifier: bundle, bundlePath: path, isTerminated: terminated, versionText: version)
    }

    @Test func othersExcludeOwnTerminatedAndForeignProcesses() {
        let processes = [
            record(100),
            record(200, path: "/Users/someone/agenttacho/build/AgentTacho.app"),
            record(300, terminated: true),
            record(400, bundle: "com.example.other"),
            record(500, bundle: nil),
        ]
        let others = RunningInstance.others(from: processes, ownPID: 200,
                                            bundleIdentifiers: [RunningInstance.ownBundleIdentifier])
        #expect(others.map(\.pid) == [100])
    }

    @Test func bundleIdentifiers() {
        #expect(RunningInstance.ownBundleIdentifier == "dev.rhuss.agenttacho")
        #expect(RunningInstance.legacyBundleIdentifier == "dev.rhuss.agentmeter")
    }

    @Test func aRunningAgentMeterCountsAsAnotherCopy() {
        let processes = [
            record(100, bundle: "dev.rhuss.agentmeter", path: "/Applications/AgentMeter.app"),
            record(200),
            record(300, bundle: "dev.rhuss.agentmeter", terminated: true),
        ]
        let others = RunningInstance.others(from: processes, ownPID: 200,
                                            bundleIdentifiers: [RunningInstance.ownBundleIdentifier,
                                                                RunningInstance.legacyBundleIdentifier])
        #expect(others.map(\.pid) == [100])
        #expect(others.first?.appName == "AgentMeter")
    }

    @Test func watchedIdentifiersAreTheOwnAndTheLegacyOne() {
        let both: Set<String> = ["dev.rhuss.agenttacho", "dev.rhuss.agentmeter"]
        #expect(RunningInstance.watchedBundleIdentifiers(own: nil) == both)
        #expect(RunningInstance.watchedBundleIdentifiers(own: "dev.rhuss.agenttacho") == both)
        // A build with another identifier still watches the legacy one.
        #expect(RunningInstance.watchedBundleIdentifiers(own: "dev.example.build")
            == ["dev.example.build", "dev.rhuss.agentmeter"])
    }

    @Test func aRunningAgentMeterIsFoundThroughTheWatchedIdentifiers() {
        let processes = [record(100, bundle: "dev.rhuss.agentmeter", path: "/Applications/AgentMeter.app"), record(200)]
        let others = RunningInstance.others(from: processes, ownPID: 200,
                                            bundleIdentifiers: RunningInstance.watchedBundleIdentifiers(own: nil))
        #expect(others.map(\.appName) == ["AgentMeter"])
    }

    @Test func appNameConstants() {
        #expect(RunningInstance.ownAppName == "AgentTacho")
        #expect(RunningInstance.legacyAppName == "AgentMeter")
        #expect(RunningInstance(pid: 1, bundlePath: nil, versionText: nil).appName == RunningInstance.ownAppName)
    }

    @Test func anotherBundleIdentifierIsIgnored() {
        let processes = [record(100, bundle: "dev.rhuss.agentmeter-fork"), record(101, bundle: "com.example.other")]
        let others = RunningInstance.others(from: processes, ownPID: 200,
                                            bundleIdentifiers: [RunningInstance.ownBundleIdentifier,
                                                                RunningInstance.legacyBundleIdentifier])
        #expect(others.isEmpty)
    }

    @Test func appNameFollowsTheBundleIdentifier() {
        #expect(RunningInstance.appName(forBundleIdentifier: "dev.rhuss.agentmeter") == "AgentMeter")
        #expect(RunningInstance.appName(forBundleIdentifier: "dev.rhuss.agenttacho") == "AgentTacho")
        #expect(RunningInstance.appName(forBundleIdentifier: nil) == "AgentTacho")
        #expect(RunningInstance(record(1)).appName == "AgentTacho")
        #expect(RunningInstance(record(2, bundle: "dev.rhuss.agentmeter")).appName == "AgentMeter")
    }

    @Test func summaryNamesARunningAgentMeter() {
        let instance = RunningInstance(record(2512, bundle: "dev.rhuss.agentmeter", path: "/Applications/AgentMeter.app",
                                              version: "0.4.1 (build 9)"))
        #expect(instance.summary(paths: paths)
            == "AgentMeter 0.4.1 (build 9) is already running from /Applications/AgentMeter.app (process 2512).")
    }

    @Test func killCommandUsesThePID() {
        let instance = RunningInstance(pid: 2512, bundlePath: "/Applications/AgentTacho.app", versionText: "0.3.0 (build 72)")
        #expect(instance.killCommand == "kill 2512")
    }

    @Test func summaryNamesVersionLocationAndProcess() {
        let instance = RunningInstance(pid: 2512, bundlePath: "/Applications/AgentTacho.app", versionText: "0.3.0 (build 72)")
        #expect(instance.summary(paths: paths)
            == "AgentTacho 0.3.0 (build 72) is already running from /Applications/AgentTacho.app (process 2512).")
    }

    @Test func summaryAbbreviatesTheHomeDirectory() {
        let instance = RunningInstance(pid: 7, bundlePath: "/Users/someone/agenttacho/build/AgentTacho.app", versionText: nil)
        #expect(instance.summary(paths: paths)
            == "AgentTacho is already running from ~/agenttacho/build/AgentTacho.app (process 7).")
    }

    @Test func summaryWithoutAKnownLocation() {
        let instance = RunningInstance(pid: 9, bundlePath: nil, versionText: "0.3.0")
        #expect(instance.summary(paths: paths) == "AgentTacho 0.3.0 is already running (process 9).")
    }

    @Test func instanceFromAProcessRecord() {
        let instance = RunningInstance(record(42))
        #expect(instance.pid == 42)
        #expect(instance.bundlePath == "/Applications/AgentTacho.app")
        #expect(instance.versionText == "0.3.0 (build 72)")
    }
}
