import Foundation
import WGCore
import WGSettingsUI

/// The switch in «Оформление › Профиль и Настройки › Профиль», next to the ID and the dates.
enum WGRegDateMenu {
    /// The section WGAppearance declares («Профиль»); rows of other features join it by id.
    static let profileSection = WGMenuSectionID("appearance.profileSettings.profile")

    static func register() {
        // After «Показывать даты» (order 300).
        WGMenuRegistry.register(WGMenuRow(id: "regDate.show", section: WGRegDateMenu.profileSection, order: 350, title: { WGStrings.RegDate.Menu.title }, subtitle: { WGStrings.RegDate.Menu.subtitle }, kind: .toggle(.global(WGRegDateSettings.show)), searchKeywords: { [WGStrings.RegDate.Menu.keywords] }))
    }
}
