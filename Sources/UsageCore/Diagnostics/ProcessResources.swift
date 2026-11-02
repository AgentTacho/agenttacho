import Darwin
import Foundation

/// The process's resource counters: CPU time, peak memory and the bytes
/// physically read from disk, for the bench report (spec 039 FR-002) and
/// the CPU seconds of the refresh log lines (FR-007), research R2.
///
/// CPU time and the peak resident set come from `getrusage(RUSAGE_SELF)`;
/// the disk bytes and the peak physical footprint, the figure Activity
/// Monitor shows, from `proc_pid_rusage(RUSAGE_INFO_V4)`. That call's CPU
/// times are in Mach time units, so CPU comes from `getrusage` instead.
public enum ProcessResources {
    /// One reading of the counters.
    public struct Snapshot: Sendable {
        public let wall: ContinuousClock.Instant
        public let userCPU: Duration
        public let systemCPU: Duration
        /// Peak resident set size in bytes (`ru_maxrss`, bytes on macOS).
        public let maxRSS: Int
        /// Peak physical footprint in bytes (`ri_lifetime_max_phys_footprint`).
        public let maxPhysicalFootprint: Int
        /// Bytes read from disk since the process started
        /// (`ri_diskio_bytesread`); reads served by the page cache do not
        /// count.
        public let diskBytesRead: Int

        /// The counters from `earlier` to this snapshot. The peaks are this
        /// snapshot's, since a peak has no difference.
        public func delta(since earlier: Snapshot) -> Delta {
            Delta(wall: earlier.wall.duration(to: wall),
                  userCPU: userCPU - earlier.userCPU,
                  systemCPU: systemCPU - earlier.systemCPU,
                  diskBytesRead: diskBytesRead - earlier.diskBytesRead,
                  maxRSS: maxRSS,
                  maxPhysicalFootprint: maxPhysicalFootprint)
        }
    }

    /// The counters between two snapshots.
    public struct Delta: Equatable, Sendable {
        public let wall: Duration
        public let userCPU: Duration
        public let systemCPU: Duration
        public let diskBytesRead: Int
        public let maxRSS: Int
        public let maxPhysicalFootprint: Int

        public init(wall: Duration, userCPU: Duration, systemCPU: Duration, diskBytesRead: Int, maxRSS: Int, maxPhysicalFootprint: Int) {
            self.wall = wall
            self.userCPU = userCPU
            self.systemCPU = systemCPU
            self.diskBytesRead = diskBytesRead
            self.maxRSS = maxRSS
            self.maxPhysicalFootprint = maxPhysicalFootprint
        }

        /// User plus system CPU time.
        public var cpu: Duration { userCPU + systemCPU }

        /// CPU time over wall time: 4.0 means 400%, four cores busy on
        /// average (spec 039 SC-002).
        public var averageCPU: Double {
            let wallSeconds = ProcessResources.seconds(wall)
            return wallSeconds > 0 ? ProcessResources.seconds(cpu) / wallSeconds : 0
        }
    }

    public static func snapshot() -> Snapshot {
        let wall = ContinuousClock.now
        let usage = resourceUsage()
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        return Snapshot(wall: wall,
                        userCPU: duration(usage.ru_utime),
                        systemCPU: duration(usage.ru_stime),
                        maxRSS: Int(usage.ru_maxrss),
                        maxPhysicalFootprint: status == 0 ? Int(clamping: info.ri_lifetime_max_phys_footprint) : 0,
                        diskBytesRead: status == 0 ? Int(clamping: info.ri_diskio_bytesread) : 0)
    }

    /// The process's user plus system CPU seconds so far; a source takes it
    /// at the start and the end of a refresh (spec 039 FR-007).
    public static func cpuSeconds() -> Double {
        let usage = resourceUsage()
        return seconds(duration(usage.ru_utime) + duration(usage.ru_stime))
    }

    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private static func resourceUsage() -> rusage {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return usage
    }

    private static func duration(_ value: timeval) -> Duration {
        .seconds(Int64(value.tv_sec)) + .microseconds(Int64(value.tv_usec))
    }
}
