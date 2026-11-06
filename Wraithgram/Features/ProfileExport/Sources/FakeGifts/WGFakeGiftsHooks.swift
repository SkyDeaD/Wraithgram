import Foundation
import UIKit
import Display
import AppBundle
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import ContextUI
import GiftViewScreen
import WGCore
import WGHooks

// Fake gifts on the profile: the own profile's gift list gets the account's fake gifts (filters,
// pinning and hidden ones respected), hide and pin on a fake are handled locally, and
// the "…" menu of any gift's screen offers "Add to my profile" (or "Edit" / "Delete" on a
// fake). The gate comes first: with the feature off nothing is read.

enum WGFakeGiftsHooks {
    static func register() {
        WGAccountHooks.accountWillStart.register({ start in
            WGFakeGiftsStore.shared.accountWillStart(start)
        })
        WGAccountHooks.accountWillBeRemoved.register({ id in
            WGFakeGiftsStore.shared.accountWillBeRemoved(id)
        })

        WGGiftHooks.profileGifts.register({ state, query in
            guard WGFakeGiftsSettings.isEnabled.value, query.collectionId == nil, query.peerId == query.account.peerId else {
                return
            }
            let fakes = WGFakeGiftsStore.shared.resolvedGifts(accountPeerId: query.peerId)
            if fakes.isEmpty {
                return
            }
            WGFakeGiftsStore.shared.refreshIfNeeded(account: query.account)
            wgInsertFakeGifts(&state, fakes: fakes)
        })

        WGGiftHooks.localGiftAction.register({ reference, action, query in
            guard WGFakeGiftsSettings.isEnabled.value, let localId = WGFakeGiftsStore.localId(of: reference, accountPeerId: query.account.peerId) else {
                return false
            }
            switch action {
            case let .setSavedToProfile(saved):
                WGFakeGiftsStore.shared.updateFlags(accountPeerId: query.account.peerId, localId: localId, savedToProfile: saved, pinnedToTop: saved ? nil : false)
            case let .setPinnedToTop(pinned):
                WGFakeGiftsStore.shared.updateFlags(accountPeerId: query.account.peerId, localId: localId, savedToProfile: pinned ? true : nil, pinnedToTop: pinned)
            }
            return true
        })

        // A fake takes no slot of the server's pin limit and never reaches the server's pinned list.
        WGGiftHooks.isLocalGift.register({ reference, account in
            return WGFakeGiftsSettings.isEnabled.value && WGFakeGiftsStore.localId(of: reference, accountPeerId: account.peerId) != nil
        })

        WGGiftViewHooks.menuItems.register({ menuContext in
            return wgFakeGiftMenuItems(menuContext)
        })
        WGGiftViewHooks.isLocalGift.register({ menuContext in
            return WGFakeGiftsStore.localId(of: menuContext.reference, accountPeerId: menuContext.context.account.peerId) != nil
        })

        WGFakeGiftsPendingPoints.register()
    }
}

// MARK: - The profile's list

/// Whether a fake gift is shown under the list's filter.
func wgFakeGiftMatches(_ gift: ProfileGiftsContext.State.StarGift, filter: ProfileGiftsContext.Filters) -> Bool {
    if gift.savedToProfile {
        if !filter.contains(.displayed) {
            return false
        }
    } else if !filter.contains(.hidden) {
        return false
    }
    switch gift.gift {
    case .unique:
        return filter.contains(.unique)
    case let .generic(generic):
        if generic.availability != nil {
            return filter.contains(.limitedUpgradable) || filter.contains(.limitedNonUpgradable)
        }
        return filter.contains(.unlimited)
    }
}

/// Pinned fakes after the real pinned gifts; the others by date among the real ones when the list
/// is sorted by date, after them otherwise.
func wgMergeFakeGifts(_ real: [ProfileGiftsContext.State.StarGift], fakes: [ProfileGiftsContext.State.StarGift], byDate: Bool) -> [ProfileGiftsContext.State.StarGift] {
    if fakes.isEmpty {
        return real
    }
    var pinnedCount = 0
    while pinnedCount < real.count && real[pinnedCount].pinnedToTop {
        pinnedCount += 1
    }
    var result = Array(real.prefix(pinnedCount))
    result.append(contentsOf: fakes.filter { $0.pinnedToTop })
    var rest = Array(real.dropFirst(pinnedCount))
    let others = fakes.filter { !$0.pinnedToTop }
    if byDate {
        for fake in others {
            if let index = rest.firstIndex(where: { $0.date < fake.date }) {
                rest.insert(fake, at: index)
            } else {
                rest.append(fake)
            }
        }
    } else {
        rest.append(contentsOf: others)
    }
    result.append(contentsOf: rest)
    return result
}

func wgInsertFakeGifts(_ state: inout ProfileGiftsContext.State, fakes: [ProfileGiftsContext.State.StarGift]) {
    let shown = fakes.filter { wgFakeGiftMatches($0, filter: state.filter) }
    state.gifts = wgMergeFakeGifts(state.gifts, fakes: fakes, byDate: true)
    state.filteredGifts = wgMergeFakeGifts(state.filteredGifts, fakes: shown, byDate: state.sorting == .date)
    state.count = (state.count ?? 0) + Int32(shown.count)
}

// MARK: - The gift screen's «…»

private func wgFakeGiftMenuItems(_ menuContext: WGGiftViewMenuContext) -> [ContextMenuItem] {
    guard WGFakeGiftsSettings.isEnabled.value else {
        return []
    }
    let context = menuContext.context
    let accountPeerId = context.account.peerId
    weak let controller = menuContext.controller

    if let localId = WGFakeGiftsStore.localId(of: menuContext.reference, accountPeerId: accountPeerId) {
        return [
            .action(ContextMenuActionItem(text: WGStrings.FakeGifts.Menu.edit, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Edit"), color: theme.contextMenu.primaryColor)
            }, action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                wgOpenFakeGiftEditor(context: context, localId: localId, from: controller)
            })),
            .action(ContextMenuActionItem(text: WGStrings.FakeGifts.Menu.delete, textColor: .destructive, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Delete"), color: theme.contextMenu.destructiveColor)
            }, action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                WGFakeGiftsStore.shared.remove(accountPeerId: accountPeerId, localId: localId)
                controller?.dismiss(animated: true)
            }))
        ]
    }

    let gift = menuContext.gift
    let fromPeerId = menuContext.nameHidden ? nil : menuContext.fromPeerId
    let nameHidden = menuContext.nameHidden
    let text = menuContext.text
    let entities = menuContext.entities
    let number = menuContext.number
    return [
        .action(ContextMenuActionItem(text: WGStrings.FakeGifts.Menu.add, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Gift"), color: theme.contextMenu.primaryColor)
        }, action: { contextController, _ in
            contextController?.dismiss(completion: nil)
            let date = Int32(Date().timeIntervalSince1970)
            WGFakeGiftsStore.shared.add(accountPeerId: accountPeerId, gift: gift, fromPeer: fromPeerId == accountPeerId ? nil : fromPeerId, nameHidden: nameHidden, date: date, text: text, entities: entities, number: number, completion: { localId in
                guard let localId = localId else {
                    return
                }
                wgPEPresentToast(context: context, from: controller, text: WGStrings.FakeGifts.Toast.added, actionTitle: WGStrings.FakeGifts.Toast.edit, action: {
                    wgOpenFakeGiftEditor(context: context, localId: localId, from: controller)
                })
            })
        }))
    ]
}

/// Closes the gift screen (a sheet over the stack) and opens the editor on the account's stack.
private func wgOpenFakeGiftEditor(context: AccountContext, localId: Int64, from controller: ViewController?) {
    let navigationController = (controller?.navigationController as? NavigationController) ?? wgProfileExportTopController(context: context)?.0
    controller?.dismiss(animated: true)
    navigationController?.pushViewController(wgMakeFakeGiftEditor(context: context, localId: localId))
}
