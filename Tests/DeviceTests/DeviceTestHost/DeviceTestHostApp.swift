import SwiftUI

/// Hosts OMSWalletDeviceTests: tests that need a physical iOS device, which cannot run in the
/// package's tool-hosted test target.
@main
struct DeviceTestHostApp: App {
    var body: some Scene {
        WindowGroup {
            Text("OMS Wallet device tests")
        }
    }
}
