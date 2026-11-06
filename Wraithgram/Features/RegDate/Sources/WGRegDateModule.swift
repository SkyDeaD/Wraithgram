import Foundation

/// Entry point of WGRegDate, «Дата регистрации» (owner's decision 2026-11-01): when an account was
/// created, in the profile of every user and bot. Swiftgram's layers in Wraithgram's architecture:
///
/// | Swiftgram | here |
/// |---|---|
/// | `SGRegDateScheme` | `Model/WGRegDateModel.swift` (contract), `Store/WGRegDateStore.swift` |
/// | `SGAPI` regdate | `Remote/WGRegDateAPI.swift` (no address: off), `Remote/WGRegDateRemoteResponse.swift` |
/// | `SGAPIToken`, `SGDeviceToken` | none: no web-app token, no DeviceCheck / App Attest |
/// | `SGRegDate` (cache + request) | `Provider/WGRegDate.swift`, `Evidence/WGRegDateEvidenceCollector.swift` |
/// | the estimate (server side in Swiftgram) | `Estimate/WGRegDateResolver.swift` (by ID, on the device) |
/// | `SGPeerInfoRows` | `Profile/WGRegDateProfileRow.swift` |
public enum WGRegDateModule {
    /// Declares the settings, the menu row, the profile row and the migration. Called once on the main
    /// thread from `WGFeatures.registerAll()`, before `WGHookRegistry.freeze()`.
    public static func register() {
        WGRegDateSettings.declare()
        WGRegDateMenu.register()
        WGRegDateProfileRow.register()
        WGRegDateMigration.register()
    }
}
