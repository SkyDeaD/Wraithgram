import Foundation
import Display
import AccountContext
import WGSettingsUI

// WRAITH: Wraithgram's menu in Telegram's own settings search. The places come from WGSettingsUI
// (`wgSettingsSearchItems`), the same index the Wraithgram root screen searches; breadcrumbs start
// at «Wraithgram», and opening a result pushes the screen and highlights the row — through the
// menu's access gates (a locked category asks for the code first, possibly pushing later).
func wgSettingsSearchableItems(context: AccountContext) -> [SettingsSearchableItem] {
    return wgSettingsSearchItems(context: context).map { item in
        let open = item.open
        return SettingsSearchableItem(
            id: item.id,
            title: item.title,
            alternate: item.keywords,
            icon: .wraithgram,
            breadcrumbs: item.breadcrumbs,
            present: { context, _, present in
                open(context, { controller in
                    present(.push, controller)
                })
            }
        )
    }
}
