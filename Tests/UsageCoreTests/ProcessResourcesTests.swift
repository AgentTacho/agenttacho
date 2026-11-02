import Foundation
import Testing
@testable import UsageCore

/// The process's resource counters for the bench report and the refresh
/// log lines (spec 039 FR-002, FR-007, research R2).
@Suite struct ProcessResourcesTests {
    /// Keeps this thread busy for about `milliseconds`; the result keeps
    /// the optimizer from dropping the loop.
    static func busyLoop(milliseconds: Int) -> UInt64 {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: .milliseconds(milliseconds))
        var x: UInt64 = 0x9E37_79B9_7F4A_7C15
        while clock.now < end {
            for _ in 0..<1_000 { x = x &* 6_364_136_223_846_793_005 &+ 1 }
        }
        return x
    }

    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    @Test func snapshotHasNonNegativeFields() {
        let snapshot = ProcessResources.snapshot()
        #expect(snapshot.userCPU >= .zero)
        #expect(snapshot.systemCPU >= .zero)
        #expect(snapshot.maxRSS > 0)
        #expect(snapshot.maxPhysicalFootprint > 0)
        #expect(snapshot.diskBytesRead >= 0)
    }

    @Test func deltaOverABusyLoopShowsUserCPUAndTheWallTime() {
        let before = ProcessResources.snapshot()
        let sink = Self.busyLoop(milliseconds: 50)
        let delta = ProcessResources.snapshot().delta(since: before)
        #expect(sink != 0)
        #expect(delta.userCPU > .zero)
        #expect(delta.wall >= .milliseconds(50))
        #expect(delta.systemCPU >= .zero)
    }

    @Test func diskBytesAndPeaksNeverDecrease() {
        let first = ProcessResources.snapshot()
        _ = Self.busyLoop(milliseconds: 5)
        let second = ProcessResources.snapshot()
        #expect(second.diskBytesRead >= first.diskBytesRead)
        #expect(second.maxRSS >= first.maxRSS)
        #expect(second.maxPhysicalFootprint >= first.maxPhysicalFootprint)
        let delta = second.delta(since: first)
        #expect(delta.diskBytesRead == second.diskBytesRead - first.diskBytesRead)
        #expect(delta.maxRSS == second.maxRSS)
        #expect(delta.maxPhysicalFootprint == second.maxPhysicalFootprint)
    }

    @Test func averageCPUIsTheCPUTimeOverTheWallTime() {
        let before = ProcessResources.snapshot()
        _ = Self.busyLoop(milliseconds: 20)
        let delta = ProcessResources.snapshot().delta(since: before)
        let cpu = Self.seconds(delta.userCPU + delta.systemCPU)
        let wall = Self.seconds(delta.wall)
        #expect(wall > 0)
        #expect(abs(delta.averageCPU - cpu / wall) < 1e-9)
        #expect(abs(Self.seconds(delta.cpu) - cpu) < 1e-9)
    }

    @Test func cpuSecondsGrowAcrossABusyLoop() {
        let before = ProcessResources.cpuSeconds()
        _ = Self.busyLoop(milliseconds: 30)
        #expect(ProcessResources.cpuSeconds() > before)
    }
}
