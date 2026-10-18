#if AGENTTACHO_DEMO
import AppKit
import DemoMode
import UsageCore

/// One run of the demo build (spec 024, research R8): the scenario chosen at
/// launch, its frame refreshes, and the launch log lines the capture script
/// waits for (contracts/capture-cli.md). Thin glue; the logic lives in
/// `DemoMode`.
@MainActor
final class DemoRun {
    private let launch: Date
    /// Nil when the scenario could not be loaded.
    let player: ScenarioPlayer?
    /// The scenario problem, shown in the dropdown (FR-013).
    let error: String?
    private let log: DiagnosticLog
    /// `-demoRenderBar <dir>`: where the bar images go (FR-019).
    private let renderBarDirectory: URL?
    private var lastFrameLogged = false

    private init(launch: Date, player: ScenarioPlayer?, error: String?, log: DiagnosticLog, renderBarDirectory: URL?) {
        self.launch = launch
        self.player = player
        self.error = error
        self.log = log
        self.renderBarDirectory = renderBarDirectory
    }

    /// Loads the scenario named by `-demoScenario` (default `default`) from
    /// the app bundle and writes it into the demo folders, or leaves the
    /// demo empty and logs the problem (FR-009, FR-013).
    static func start(paths: Paths, log: DiagnosticLog) -> DemoRun {
        let launch = Date()
        let defaults = UserDefaults.standard
        let name = defaults.string(forKey: "demoScenario") ?? "default"
        let renderBar = defaults.string(forKey: "demoRenderBar").map { URL(fileURLWithPath: $0, isDirectory: true) }
        do {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "demo") else {
                throw ScenarioError(path: "", message: "no scenario named \"\(name)\" in the app bundle")
            }
            let scenario = try Scenario.load(from: url)
            try DemoSetup.prepare(scenario: scenario, paths: paths, launch: launch)
            log.append(source: "app", message: "demo build, scenario \(name)")
            return DemoRun(launch: launch, player: ScenarioPlayer(scenario: scenario, launch: launch), error: nil, log: log,
                           renderBarDirectory: renderBar)
        } catch {
            let text = String(describing: error)
            log.append(source: "app", message: "demo build, scenario \(name) not played: \(text)")
            do {
                try DemoSetup.clear(paths: paths)
            } catch {
                log.append(source: "app", message: "demo folders could not be cleared: \(error.localizedDescription)")
            }
            return DemoRun(launch: launch, player: nil, error: "scenario \(name): \(text)", log: log, renderBarDirectory: nil)
        }
    }

    /// One refresh at each frame's refresh time, at once for a time that
    /// has already passed (FR-012).
    func scheduleFrames(coordinator: RefreshCoordinator) {
        guard let player else { return }
        for due in DemoSetup.frameRefreshDates(player.scenario, launch: launch) {
            Task {
                let wait = due.timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                await coordinator.requestRefresh(trigger: .scheduled)
            }
        }
    }

    /// Called with every applied snapshot. The first snapshot from after the
    /// last frame logs `demo: last frame applied` and, with
    /// `-demoRenderBar`, writes the bar images (FR-012, FR-019).
    func snapshotApplied(_ snapshot: UsageSnapshot, items: [BarItem], display: LevelDisplaySettings) {
        guard let player, !lastFrameLogged, !snapshot.isPreliminary else { return }
        guard snapshot.generatedAt >= DemoSetup.lastFrameDate(player.scenario, launch: launch) else { return }
        lastFrameLogged = true
        log.append(source: "app", message: "demo: last frame applied")
        guard let directory = renderBarDirectory else { return }
        do {
            try Self.renderBar(items: items, display: display, into: directory)
            log.append(source: "app", message: "demo: bar rendered")
        } catch {
            log.append(source: "app", message: "demo: bar not rendered: \(error.localizedDescription)")
        }
    }

    /// The menu bar item for the `menubar` shot (FR-019, research R10):
    /// the same bar image the menu bar shows, at 2x on a transparent
    /// background, once in light and once in dark appearance. Drawn, not
    /// captured, so no wallpaper or other menu bar item shows.
    static func renderBar(items: [BarItem], display: LevelDisplaySettings, into directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let entries = BarPresentation.entries(items, settings: display)
        for (name, appearanceName, neutral) in [("light", NSAppearance.Name.aqua, NSColor.black),
                                                ("dark", NSAppearance.Name.darkAqua, NSColor.white)] {
            guard let appearance = NSAppearance(named: appearanceName) else { continue }
            let image = BarLabelBuilder.image(entries, appearance: appearance, neutralOverride: neutral)
            let data = try pngData(image, appearance: appearance, tint: image.isTemplate ? neutral : nil)
            try data.write(to: directory.appendingPathComponent("menubar-\(name).png"), options: .atomic)
        }
    }

    private struct RenderError: LocalizedError {
        let errorDescription: String?
    }

    /// `image` drawn at scale 2 into a transparent bitmap; a template image
    /// is tinted like the menu bar tints it.
    private static func pngData(_ image: NSImage, appearance: NSAppearance, tint: NSColor?) throws -> Data {
        let scale: CGFloat = 2
        let size = image.size
        guard size.width > 0, size.height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw RenderError(errorDescription: "the bar image is empty")
        }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        appearance.performAsCurrentDrawingAppearance {
            let rect = NSRect(origin: .zero, size: size)
            image.draw(in: rect)
            if let tint {
                tint.set()
                rect.fill(using: .sourceAtop)
            }
        }
        NSGraphicsContext.current?.flushGraphics()
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw RenderError(errorDescription: "the bar image could not be encoded as PNG")
        }
        return data
    }
}
#endif
