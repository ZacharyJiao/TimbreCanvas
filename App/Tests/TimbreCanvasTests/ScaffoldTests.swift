import Testing
@testable import TimbreCanvas

@Test func applicationIdentityIsStable() {
    #expect(AppIdentity.displayName == "TimbreCanvas")
    #expect(AppIdentity.bundleIdentifier == "com.zaryolabs.TimbreCanvas")
}
