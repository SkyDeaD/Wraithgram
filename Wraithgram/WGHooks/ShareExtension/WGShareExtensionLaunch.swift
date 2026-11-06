// Compiled into ShareExtensionContext (filegroup //Wraithgram/WGHooks:ShareExtensionHookSources):
// launch of Wraithgram in the share extension. Accounts opened there go through `Account.init`,
// whose Core point loads their Wraithgram settings (WGAccountHooks).

import Foundation
import WGCore
import WGFeaturesShared

private var wgShareExtensionStarted = false

/// WRAITH hook target: on the main thread, before `initializeAccountManagement()` and before any
/// account is opened. The first call starts Wraithgram in the process; a later one (iOS may keep the
/// process for the next share) reads the settings files again.
func wgShareExtensionDidStart(appGroupPath: String) {
    assert(Thread.isMainThread)
    if wgShareExtensionStarted {
        WGCore.reloadSettings()
        return
    }
    wgShareExtensionStarted = true
    WGCore.bootstrap(WGCoreEnvironment(appGroupPath: appGroupPath, process: .share))
    WGFeaturesShared.registerForExtension()
    wgShareExtensionRegisterPhotoHandlers()
    WGHookRegistry.freeze()
}
