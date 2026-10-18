import Foundation
import Testing
@testable import DemoMode
import UsageCore

/// The scenario file (spec 024 FR-010, FR-011, FR-013,
/// contracts/scenario-format.md).
@Suite struct ScenarioTests {
    /// The configuration every fixture shares: one account of each kind and
    /// a monthly group.
    static let configuration = """
    {
      "version": 1,
      "accounts": [
        { "id": "acc-max", "type": "subscription", "icon": "brands:claude", "displayName": "Claude Max",
          "thresholds": [80, 100] },
        { "id": "acc-codex", "type": "codexSubscription", "icon": "brands:openai", "displayName": "Codex",
          "harness": "codex", "codexHome": "~/Library/Application Support/agenttacho-demo/codex", "thresholds": [80, 100] },
        { "id": "acc-vertex", "type": "tokenBased", "provider": "vertex", "groupId": "grp-company",
          "displayName": "Vertex", "harness": "openCode" }
      ],
      "groups": [
        { "id": "grp-company", "name": "Company budget", "icon": "solid:building", "period": "monthly",
          "budgetUSD": 500, "thresholds": [80, 100] }
      ]
    }
    """

    /// The example of contracts/scenario-format.md, adapted to the fixture
    /// configuration. Placeholders are replaced by the tests.
    static func json(name: String = "test", claude: String? = nil, codex: String? = nil, usage: String? = nil,
                     frames: String? = nil) -> String {
        """
        {
          "name": "\(name)",
          "configuration": \(configuration),
          "importedPrices": { "version": 1, "batches": [] },
          "claude": \(claude ?? """
            { "acc-max": { "plan": "max",
                           "fiveHour": { "used": 58, "resetsIn": "2h" },
                           "sevenDay": { "used": 70, "resetsIn": "3d12h" } } }
            """),
          "codex": \(codex ?? """
            { "acc-codex": { "plan": "plus",
                             "windows": [ { "lengthMinutes": 300, "used": 40, "resetsIn": "1h30m" },
                                          { "lengthMinutes": 10080, "used": 60, "resetsIn": "3d12h" } ] } }
            """),
          "usage": \(usage ?? """
            [ { "at": "-2d3h", "account": "acc-vertex", "harness": "openCode",
                "model": "claude-sonnet-5-5", "project": "~/src/checkout-service",
                "input": 182000, "output": 21000, "cacheRead": 940000, "cacheWrite": 64000 } ]
            """),
          "frames": \(frames ?? """
            [ { "at": "12s",
                "claude": { "acc-max": { "sevenDay": { "used": 72 } } },
                "usage": [ { "at": "-1m", "account": "acc-vertex", "harness": "openCode",
                             "model": "claude-sonnet-5-5", "project": "~/src/billing",
                             "input": 900000, "output": 120000, "cacheRead": 0, "cacheWrite": 0 } ] } ]
            """)
        }
        """
    }

    static func decode(_ text: String) throws -> Scenario {
        try Scenario.decode(Data(text.utf8))
    }

    /// The error a scenario text produces, or nil when it is valid.
    static func error(_ text: String) -> ScenarioError? {
        do {
            _ = try decode(text)
            return nil
        } catch let error as ScenarioError {
            return error
        } catch {
            Issue.record("unexpected error type: \(error)")
            return nil
        }
    }

    @Test func decodesTheContractExample() throws {
        let scenario = try Self.decode(Self.json())
        #expect(scenario.name == "test")
        #expect(scenario.configuration.accounts.map(\.id) == ["acc-max", "acc-codex", "acc-vertex"])
        #expect(scenario.configuration.groups.first?.period == .monthly)
        #expect(scenario.importedPrices == ImportedPrices.empty)
        let max = try #require(scenario.claude["acc-max"])
        #expect(max.plan == "max")
        #expect(max.fiveHour == WindowValue(used: 58, resetsIn: try ScenarioDuration(parsing: "2h")))
        #expect(max.sevenDay.resetsIn.seconds == 3.5 * 86_400)
        let codex = try #require(scenario.codex["acc-codex"])
        #expect(codex.plan == "plus")
        #expect(codex.windows.map(\.lengthMinutes) == [300, 10080])
        #expect(scenario.usage.count == 1)
        #expect(scenario.usage[0].at.seconds == -(2 * 86_400 + 3 * 3600))
        #expect(scenario.usage[0].harness == .openCode)
        #expect(scenario.usage[0].cacheWrite == 64000)
        #expect(scenario.frames.count == 1)
        #expect(scenario.frames[0].at.seconds == 12)
        #expect(scenario.frames[0].claude?["acc-max"]?.sevenDay?.used == 72)
        #expect(scenario.frames[0].claude?["acc-max"]?.sevenDay?.resetsIn == nil)
        #expect(scenario.frames[0].usage?.count == 1)
    }

    /// The configuration goes through UsageCore's own decoder, defaults
    /// included (contracts/scenario-format.md).
    @Test func configurationUsesTheAppDecoder() throws {
        let scenario = try Self.decode(Self.json())
        #expect(scenario.configuration.refreshIntervalSeconds == Configuration.defaultRefreshIntervalSeconds)
        #expect(scenario.configuration.account(id: "acc-codex")?.kind.codexSubscription?.liveLimits == true)
        #expect(scenario.configuration.account(id: "acc-vertex")?.kind.tokenBased?.groupId == "grp-company")
    }

    @Test func usedPercentAbove100IsRejectedWithItsPath() {
        let text = Self.json(claude: """
            { "acc-max": { "plan": "max", "fiveHour": { "used": 58, "resetsIn": "2h" },
                           "sevenDay": { "used": 101, "resetsIn": "3d" } } }
            """)
        #expect(Self.error(text) == ScenarioError(path: "claude.acc-max.sevenDay.used", message: "expected a number from 0 to 100"))
    }

    @Test func usedPercentInAFrameIsCheckedToo() {
        let text = Self.json(frames: """
            [ { "at": "12s", "claude": { "acc-max": { "sevenDay": { "used": -1 } } } } ]
            """)
        #expect(Self.error(text)?.path == "frames[0].claude.acc-max.sevenDay.used")
    }

    @Test func unknownAccountInClaudeIsRejected() {
        let text = Self.json(claude: """
            { "acc-nope": { "plan": "max", "fiveHour": { "used": 1, "resetsIn": "2h" },
                            "sevenDay": { "used": 1, "resetsIn": "3d" } } }
            """)
        #expect(Self.error(text) == ScenarioError(path: "claude.acc-nope", message: "unknown account id"))
    }

    @Test func claudeIdMustBeASubscriptionAccount() {
        let text = Self.json(claude: """
            { "acc-codex": { "plan": "max", "fiveHour": { "used": 1, "resetsIn": "2h" },
                             "sevenDay": { "used": 1, "resetsIn": "3d" } } }
            """)
        #expect(Self.error(text) == ScenarioError(path: "claude.acc-codex", message: "not a subscription account"))
    }

    @Test func unknownAccountInCodexIsRejected() {
        let text = Self.json(codex: """
            { "acc-nope": { "plan": "plus", "windows": [ { "lengthMinutes": 300, "used": 1, "resetsIn": "1h" } ] } }
            """)
        #expect(Self.error(text) == ScenarioError(path: "codex.acc-nope", message: "unknown account id"))
    }

    @Test func codexIdMustBeACodexSubscriptionAccount() {
        let text = Self.json(codex: """
            { "acc-max": { "plan": "plus", "windows": [ { "lengthMinutes": 300, "used": 1, "resetsIn": "1h" } ] } }
            """)
        #expect(Self.error(text) == ScenarioError(path: "codex.acc-max", message: "not a Codex subscription account"))
    }

    @Test func unknownAccountInUsageIsRejected() {
        let text = Self.json(usage: """
            [ { "at": "-1h", "account": "acc-nope", "harness": "codex", "model": "gpt-5", "project": "~/src/x",
                "input": 1, "output": 1, "cacheRead": 0, "cacheWrite": 0 } ]
            """)
        #expect(Self.error(text) == ScenarioError(path: "usage[0].account", message: "unknown account id"))
    }

    @Test func positiveUsageTimeIsRejected() {
        let text = Self.json(usage: """
            [ { "at": "1h", "account": "acc-vertex", "harness": "openCode", "model": "claude-sonnet-5-5",
                "project": "~/src/x", "input": 1, "output": 1, "cacheRead": 0, "cacheWrite": 0 } ]
            """)
        #expect(Self.error(text) == ScenarioError(path: "usage[0].at", message: "expected a time before launch, for example -2h"))
    }

    @Test func framesOutOfOrderAreRejected() {
        let text = Self.json(frames: """
            [ { "at": "12s" }, { "at": "10s" } ]
            """)
        #expect(Self.error(text) == ScenarioError(path: "frames[1].at", message: "frames must be in increasing order of time"))
    }

    @Test(arguments: ["0s", "-5s"])
    func frameAtOrBeforeLaunchIsRejected(at: String) {
        #expect(Self.error(Self.json(frames: #"[ { "at": "\#(at)" } ]"#))
                == ScenarioError(path: "frames[0].at", message: "expected a time after launch, for example 12s"))
    }

    @Test func resetBeforeLaunchIsRejected() {
        let text = Self.json(claude: """
            { "acc-max": { "plan": "max", "fiveHour": { "used": 58, "resetsIn": "-1h" },
                           "sevenDay": { "used": 70, "resetsIn": "3d" } } }
            """)
        #expect(Self.error(text) == ScenarioError(path: "claude.acc-max.fiveHour.resetsIn", message: "expected a time after launch, for example 2h"))
        let frame = Self.json(frames: #"[ { "at": "12s", "codex": { "acc-codex": { "windows": [ { "lengthMinutes": 300, "resetsIn": "0s" } ] } } } ]"#)
        #expect(Self.error(frame)?.path == "frames[0].codex.acc-codex.windows[0].resetsIn")
    }

    @Test func codexWindowLengthMustBePositive() {
        let text = Self.json(codex: """
            { "acc-codex": { "plan": "plus", "windows": [ { "lengthMinutes": 0, "used": 1, "resetsIn": "1h" } ] } }
            """)
        #expect(Self.error(text) == ScenarioError(path: "codex.acc-codex.windows[0].lengthMinutes",
                                                  message: "expected a length in minutes greater than 0"))
    }

    @Test func negativeTokenCountIsRejected() {
        let text = Self.json(usage: """
            [ { "at": "-1h", "account": "acc-vertex", "harness": "openCode", "model": "claude-sonnet-5-5",
                "project": "~/src/x", "input": 1, "output": -2, "cacheRead": 0, "cacheWrite": 0 } ]
            """)
        #expect(Self.error(text) == ScenarioError(path: "usage[0].output", message: "expected a token count of 0 or more"))
    }

    @Test func frameForAnAccountWithoutWindowsIsRejected() {
        let text = Self.json(claude: "{}", frames: #"[ { "at": "12s", "claude": { "acc-max": { "sevenDay": { "used": 1 } } } } ]"#)
        #expect(Self.error(text) == ScenarioError(path: "frames[0].claude.acc-max", message: "no plan windows to change in claude"))
    }

    @Test func frameForAnUnknownModelLimitIsRejected() {
        let text = Self.json(frames: #"[ { "at": "12s", "claude": { "acc-max": { "models": { "Fable": { "used": 1 } } } } } ]"#)
        #expect(Self.error(text) == ScenarioError(path: "frames[0].claude.acc-max.models.Fable", message: "no such model limit in claude"))
    }

    @Test func frameForAnUnknownCodexWindowIsRejected() {
        let text = Self.json(frames: #"[ { "at": "12s", "codex": { "acc-codex": { "windows": [ { "lengthMinutes": 60, "used": 1 } ] } } } ]"#)
        #expect(Self.error(text) == ScenarioError(path: "frames[0].codex.acc-codex.windows[0].lengthMinutes",
                                                  message: "no window of this length in codex"))
        let wrongKind = Self.json(frames: #"[ { "at": "12s", "codex": { "acc-max": { "windows": [] } } } ]"#)
        #expect(Self.error(wrongKind) == ScenarioError(path: "frames[0].codex.acc-max", message: "not a Codex subscription account"))
    }

    @Test func frameUsageIsCheckedLikeBaseUsage() {
        let text = Self.json(frames: """
            [ { "at": "12s", "usage": [ { "at": "-1m", "account": "acc-nope", "harness": "codex", "model": "gpt-5.6",
                                          "project": "~/src/x", "input": 1, "output": 1, "cacheRead": 0, "cacheWrite": 0 } ] } ]
            """)
        #expect(Self.error(text) == ScenarioError(path: "frames[0].usage[0].account", message: "unknown account id"))
    }

    @Test func invalidImportedPricesAreRejected() {
        let text = Self.json().replacingOccurrences(of: #""importedPrices": { "version": 1, "batches": [] }"#,
                                                    with: #""importedPrices": { "version": 9, "batches": [] }"#)
        #expect(Self.error(text)?.path == "importedPrices")
    }

    @Test func badDurationCarriesItsPath() {
        let text = Self.json(frames: #"[ { "at": "12x" } ]"#)
        #expect(Self.error(text)?.path == "frames[0].at")
    }

    @Test func typeMismatchCarriesItsPath() {
        let text = Self.json(codex: """
            { "acc-codex": { "plan": "plus", "windows": [ { "lengthMinutes": "long", "used": 1, "resetsIn": "1h" } ] } }
            """)
        #expect(Self.error(text)?.path == "codex.acc-codex.windows[0].lengthMinutes")
    }

    @Test func invalidConfigurationIsRejected() {
        let text = Self.json().replacingOccurrences(of: "\"budgetUSD\": 500", with: "\"budgetUSD\": 0")
        #expect(Self.error(text)?.path == "configuration")
    }

    @Test func errorDescriptionJoinsPathAndMessage() {
        let error = ScenarioError(path: "frames[0].claude.acc-max.sevenDay.used", message: "expected a number from 0 to 100")
        #expect(error.description == "frames[0].claude.acc-max.sevenDay.used: expected a number from 0 to 100")
    }

    @Test func loadChecksTheFileName() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let good = dir.appendingPathComponent("test.json")
        try Data(Self.json().utf8).write(to: good)
        #expect(try Scenario.load(from: good).name == "test")
        let other = dir.appendingPathComponent("other.json")
        try Data(Self.json().utf8).write(to: other)
        #expect(throws: ScenarioError(path: "name", message: "\"test\" does not match the file name \"other\"")) {
            try Scenario.load(from: other)
        }
    }

    @Test func missingFileIsAScenarioError() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        #expect(throws: ScenarioError.self) { try Scenario.load(from: url) }
    }
}
