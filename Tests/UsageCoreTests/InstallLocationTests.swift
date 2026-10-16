import Foundation
import Testing
@testable import UsageCore

/// spec 013 FR-012, FR-018, FR-023: where the running app is, and which
/// staging folder launch cleanup may delete.
@Suite struct InstallLocationTests {
    @Test func translocatedPaths() {
        #expect(InstallLocation.isTranslocated(path: "/private/var/folders/ab/T/AppTranslocation/1234-ABCD/d/AgentMeter.app"))
        #expect(!InstallLocation.isTranslocated(path: "/Applications/AgentMeter.app"))
    }

    @Test func diskImageLocations() {
        #expect(InstallLocation.isOnDiskImage(path: "/Volumes/AgentMeter/AgentMeter.app", volumeIsReadOnly: true, volumeIsRootFileSystem: false))
        #expect(InstallLocation.isOnDiskImage(path: "/Volumes/AgentMeter/AgentMeter.app", volumeIsReadOnly: nil, volumeIsRootFileSystem: nil))
        #expect(InstallLocation.isOnDiskImage(path: "/Applications/AgentMeter.app", volumeIsReadOnly: true, volumeIsRootFileSystem: true))
        #expect(!InstallLocation.isOnDiskImage(path: "/Applications/AgentMeter.app", volumeIsReadOnly: false, volumeIsRootFileSystem: true))
        #expect(!InstallLocation.isOnDiskImage(path: "/Users/me/Applications/AgentMeter.app", volumeIsReadOnly: false, volumeIsRootFileSystem: nil))
    }

    @Test func stagingFoldersCreatedForTheSwapAreRemovable() {
        #expect(InstallLocation.isRemovableStagingPath("/private/var/folders/ab/cd/T/TemporaryItems/NSIRD_AgentMeter_x1y2"))
        #expect(InstallLocation.isRemovableStagingPath("/Volumes/Ext/.TemporaryItems/folders.501/TemporaryItems/NSIRD_AgentMeter_1"))
    }

    @Test(arguments: [
        "",
        "relative/TemporaryItems/NSIRD_x",
        "/var/folders/T/TemporaryItems",
        "/var/folders/T/TemporaryItems/",
        "/var/folders/T/TemporaryItems/NSIRD_",
        "/var/folders/T/TemporaryItems/other",
        "/var/folders/T/TemporaryItems/NSIRD_x/..",
        "/var/folders/T/TemporaryItems/../../NSIRD_x",
        "/var/folders/T/TemporaryItems/./NSIRD_x",
        "/Users/me/TemporaryItems-not/NSIRD_x",
        "/Applications",
    ])
    func otherPathsAreNeverRemoved(_ path: String) {
        #expect(!InstallLocation.isRemovableStagingPath(path))
    }
}
