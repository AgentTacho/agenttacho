import Testing
@testable import UsageCore

@Suite struct AppVersionInfoTests {
    @Test func displayVersionAndBuildFormTheLabel() {
        let info = AppVersionInfo(infoDictionary: [
            "AgentMeterVersionDisplay": "0.2.0-dev",
            "CFBundleShortVersionString": "0.2.0",
            "CFBundleVersion": "120",
        ])
        #expect(info.label == "AgentMeter 0.2.0-dev (build 120)")
    }

    @Test func missingDisplayKeyFallsBackToShortVersion() {
        let info = AppVersionInfo(infoDictionary: [
            "CFBundleShortVersionString": "0.3.1",
            "CFBundleVersion": "7",
        ])
        #expect(info.label == "AgentMeter 0.3.1 (build 7)")
    }

    @Test func emptyDictionaryIsUnknown() {
        let info = AppVersionInfo(infoDictionary: [:])
        #expect(info.label == "AgentMeter unknown")
    }

    @Test func missingBuildOmitsBuildPart() {
        let info = AppVersionInfo(infoDictionary: ["AgentMeterVersionDisplay": "0.2.0"])
        #expect(info.label == "AgentMeter 0.2.0")
    }

    @Test func emptyStringsCountAsMissing() {
        let info = AppVersionInfo(infoDictionary: [
            "AgentMeterVersionDisplay": "",
            "CFBundleShortVersionString": "0.4.0",
            "CFBundleVersion": "",
        ])
        #expect(info.label == "AgentMeter 0.4.0")
    }
}
