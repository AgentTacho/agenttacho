import Foundation
import Testing
@testable import UsageCore

@Suite struct IconCatalogTests {
    let catalog = IconCatalog.shared

    @Test func loadsTheBundledCatalog() {
        #expect(catalog.entries.count > 1900)
        #expect(catalog.version == "7.3.1")
        // Sorted by name, then style.
        let keys = catalog.entries.map { ($0.name, $0.style) }
        #expect(zip(keys, keys.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func resolvesKnownIcons() throws {
        let claude = try #require(catalog.icon(for: "brands:claude"))
        #expect(claude.label == "Claude")
        #expect(claude.character == Character(Unicode.Scalar(0xE861)!))
        #expect(catalog.contains("solid:robot"))
        #expect(catalog.contains("regular:cloud"))
        #expect(catalog.contains("solid:cloud"))
        #expect(!catalog.contains("brands:robot"))       // wrong style
        #expect(!catalog.contains("solid:no-such-icon"))
    }

    @Test func iconRefRoundTripAndInvalidInput() {
        #expect(IconRef("brands:claude") == IconRef(style: .brands, name: "claude"))
        #expect(IconRef("brands:claude")?.description == "brands:claude")
        for invalid in ["claude", "brands:", ":claude", "duotone:claude", "", "solid"] {
            #expect(IconRef(invalid) == nil, "\(invalid)")
        }
    }

    @Test func searchRanksNameMatchesFirst() {
        let names = catalog.search("clou").map(\.name)
        let cloud = names.firstIndex(of: "cloud")
        let cloudflare = names.firstIndex(of: "cloudflare")
        #expect(cloud != nil && cloudflare != nil)
        #expect(cloud! < cloudflare!)
        // Prefix matches come before substring matches.
        let soundcloud = names.firstIndex(of: "soundcloud")
        #expect(soundcloud != nil && cloudflare! < soundcloud!)
    }

    @Test func searchCoversLabelsAndTermsAndIgnoresCase() {
        #expect(catalog.search("CLAUDE").first?.ref == IconRef("brands:claude"))
        // "backup" is only a search term of cloud, not part of its name.
        #expect(catalog.search("backup").contains { $0.name == "cloud" })
        #expect(catalog.search("").count == catalog.entries.count)
        #expect(catalog.search("zzzz-nothing").isEmpty)
    }

    @Test func everyStyleHasItsFontInTheBundle() {
        let urls = catalog.fontURLs
        for style in IconStyle.allCases {
            let url = urls[style]
            #expect(url != nil, "\(style)")
            if let url { #expect(FileManager.default.fileExists(atPath: url.path)) }
        }
    }
}
