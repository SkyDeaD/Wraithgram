import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import LocalizedPeerData
import ItemListUI
import WGCore
import WGSettingsUI

// More › Fake gifts: the switch, the account's list, "Delete all". One editor for a gift
// (sender — a chat, anonymous or none; caption; date; shown / pinned; delete), reached from the list
// and from the gift's own «…».

enum WGFakeGiftsMenu {
    static func register() {
        WGMenuRegistry.register(WGMenuRow(
            id: "fakeGifts.isEnabled",
            section: .main(of: .moreFakeGifts),
            order: 100,
            title: { WGStrings.FakeGifts.Menu.enable },
            subtitle: { WGStrings.FakeGifts.Menu.enableInfo },
            kind: .toggle(.global(WGFakeGiftsSettings.isEnabled)),
            searchKeywords: { [WGStrings.FakeGifts.Menu.keywords] }
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "fakeGifts.list",
            section: .main(of: .moreFakeGifts),
            order: 200,
            title: { WGStrings.FakeGifts.Menu.list },
            subtitle: { WGStrings.FakeGifts.Menu.listInfo },
            icon: .bundle("Chat/Context Menu/Gift"),
            kind: .action({ context in
                context.push(wgMakeFakeGiftsListScreen(context: context.context))
            }),
            isVisible: { _ in WGFakeGiftsSettings.isEnabled.value },
            searchKeywords: { [WGStrings.FakeGifts.Menu.keywords] },
            label: { context in
                let count = WGFakeGiftsStore.shared.records(accountPeerId: context.context.account.peerId).count
                return count == 0 ? nil : "\(count)"
            }
        ))
    }
}

func wgFakeGiftTitle(_ gift: StarGift, number: Int32?) -> String {
    switch gift {
    case let .unique(uniqueGift):
        return "\(uniqueGift.title) #\(uniqueGift.number)"
    case let .generic(generic):
        let title = generic.title ?? WGStrings.FakeGifts.List.giftTitle
        if let number = number {
            return "\(title) #\(number)"
        }
        return title
    }
}

private let wgFakeGiftDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()

/// Main thread only (the formatter is shared by the screens).
func wgFakeGiftDateString(_ date: Int32) -> String {
    assert(Thread.isMainThread)
    wgFakeGiftDateFormatter.locale = Locale(identifier: WGLocalization.shared.languageCode)
    return wgFakeGiftDateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(date)))
}

func wgMakeFakeGiftsListScreen(context: AccountContext) -> ViewController {
    let accountPeerId = context.account.peerId
    weak var controllerRef: ItemListController?

    let model = combineLatest(queue: .mainQueue(), WGFakeGiftsStore.shared.recordsSignal(accountPeerId: accountPeerId), WGLocalization.shared.languageCodeSignal)
    |> map { records, _ -> WGPEScreenModel in
        var model = WGPEScreenModel(title: WGStrings.FakeGifts.List.title)
        var rows: [WGPERow] = [WGPERow(id: "header", kind: .header(WGStrings.FakeGifts.List.header))]
        if records.isEmpty {
            rows.append(WGPERow(id: "empty", kind: .info(WGStrings.FakeGifts.List.empty)))
        }
        for record in records {
            var label = wgFakeGiftDateString(record.date)
            if record.pinnedToTop {
                label = WGStrings.FakeGifts.List.pinned + " · " + label
            } else if !record.savedToProfile {
                label = WGStrings.FakeGifts.List.hidden + " · " + label
            }
            let id = "gift\(record.localId)"
            rows.append(WGPERow(id: id, kind: .disclosure(title: wgFakeGiftTitle(record.gift, number: record.number), label: label, icon: nil, enabled: true)))
            let localId = record.localId
            model.tap[id] = {
                controllerRef?.push(wgMakeFakeGiftEditor(context: context, localId: localId))
            }
        }
        rows.append(WGPERow(id: "footer", kind: .footer(WGStrings.FakeGifts.List.footer)))
        model.sections.append(rows)
        if !records.isEmpty {
            model.sections.append([WGPERow(id: "deleteAll", kind: .action(title: WGStrings.FakeGifts.List.deleteAll, destructive: true, enabled: true))])
            model.tap["deleteAll"] = {
                wgPEConfirmDestructive(context: context, from: controllerRef, title: WGStrings.FakeGifts.List.deleteAllTitle, text: WGStrings.FakeGifts.List.deleteAllText, confirm: WGStrings.FakeGifts.List.deleteAllConfirm, action: {
                    WGFakeGiftsStore.shared.removeAll(accountPeerId: accountPeerId)
                })
            }
        }
        return model
    }
    let controller = wgPEMakeListController(context: context, model: model)
    controllerRef = controller
    return controller
}

/// The editor works on a draft; "Done" writes it once.
func wgMakeFakeGiftEditor(context: AccountContext, localId: Int64) -> ViewController {
    let accountPeerId = context.account.peerId
    weak var controllerRef: ItemListController?

    guard let initial = WGFakeGiftsStore.shared.records(accountPeerId: accountPeerId).first(where: { $0.localId == localId }) else {
        return wgMakeFakeGiftsListScreen(context: context)
    }
    let draft = ValuePromise<WGFakeGiftRecord>(initial, ignoreRepeated: true)
    let draftValue = Atomic<WGFakeGiftRecord>(value: initial)
    let updateDraft: ((inout WGFakeGiftRecord) -> Void) -> Void = { transform in
        var value = draftValue.with { $0 }
        transform(&value)
        let _ = draftValue.swap(value)
        draft.set(value)
    }

    let sender: Signal<EnginePeer?, NoError> = draft.get()
    |> map { record -> EnginePeer.Id? in
        return record.fromPeer.map(PeerId.init(wgKey:))
    }
    |> distinctUntilChanged
    |> mapToSignal { peerId -> Signal<EnginePeer?, NoError> in
        guard let peerId = peerId else {
            return .single(nil)
        }
        return context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
    }

    let model = combineLatest(queue: .mainQueue(), draft.get(), sender, WGLocalization.shared.languageCodeSignal)
    |> map { record, senderPeer, _ -> WGPEScreenModel in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        var model = WGPEScreenModel(title: wgFakeGiftTitle(record.gift, number: record.number))

        let senderLabel: String
        if record.nameHidden {
            senderLabel = WGStrings.FakeGifts.Editor.anonymous
        } else if let senderPeer = senderPeer {
            senderLabel = senderPeer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
        } else {
            senderLabel = WGStrings.FakeGifts.Editor.noSender
        }
        model.sections.append([
            WGPERow(id: "senderHeader", kind: .header(WGStrings.FakeGifts.Editor.senderHeader)),
            WGPERow(id: "sender", kind: .peer(title: WGStrings.FakeGifts.Editor.sender, label: senderLabel, peer: record.nameHidden ? nil : senderPeer))
        ])
        model.tap["sender"] = {
            wgPEPresentActionSheet(context: context, from: controllerRef, buttons: [
                (title: WGStrings.FakeGifts.Editor.chooseSender, isDestructive: false, action: {
                    let picker = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.excludeSecretChats, .doNotSearchMessages], hasContactSelector: true, title: WGStrings.FakeGifts.Editor.chooseSender))
                    picker.peerSelected = { [weak picker] peer, _ in
                        updateDraft { record in
                            record.fromPeer = peer.id.wgKey
                            record.nameHidden = false
                        }
                        picker?.dismiss()
                    }
                    controllerRef?.push(picker)
                }),
                (title: WGStrings.FakeGifts.Editor.anonymous, isDestructive: false, action: {
                    updateDraft { record in
                        record.nameHidden = true
                    }
                }),
                (title: WGStrings.FakeGifts.Editor.noSender, isDestructive: false, action: {
                    updateDraft { record in
                        record.fromPeer = nil
                        record.nameHidden = false
                    }
                })
            ])
        }

        model.sections.append([
            WGPERow(id: "captionHeader", kind: .header(WGStrings.FakeGifts.Editor.captionHeader)),
            WGPERow(id: "caption", kind: .multilineInput(text: record.text ?? "", placeholder: WGStrings.FakeGifts.Editor.captionPlaceholder))
        ])
        model.text["caption"] = { text in
            updateDraft { record in
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if record.text != text {
                    // A typed caption has no entities of its own.
                    record.entities = nil
                }
                record.text = trimmed.isEmpty ? nil : text
            }
        }

        model.sections.append([
            WGPERow(id: "dateHeader", kind: .header(WGStrings.FakeGifts.Editor.dateHeader)),
            WGPERow(id: "date", kind: .disclosure(title: WGStrings.FakeGifts.Editor.date, label: wgFakeGiftDateString(record.date), icon: nil, enabled: true))
        ])
        model.tap["date"] = {
            let now = Int32(Date().timeIntervalSince1970)
            let day: Int32 = 24 * 60 * 60
            let presets: [(String, Int32)] = [
                (WGStrings.FakeGifts.Editor.dateNow, now),
                (WGStrings.FakeGifts.Editor.dateYesterday, now - day),
                (WGStrings.FakeGifts.Editor.dateWeek, now - 7 * day),
                (WGStrings.FakeGifts.Editor.dateMonth, now - 30 * day),
                (WGStrings.FakeGifts.Editor.dateYear, now - 365 * day)
            ]
            wgPEPresentActionSheet(context: context, from: controllerRef, buttons: presets.map { preset in
                return (title: preset.0, isDestructive: false, action: {
                    updateDraft { record in
                        record.date = preset.1
                    }
                })
            })
        }

        model.sections.append([
            WGPERow(id: "shown", kind: .toggle(title: WGStrings.FakeGifts.Editor.shown, value: record.savedToProfile, enabled: true)),
            WGPERow(id: "pinned", kind: .toggle(title: WGStrings.FakeGifts.Editor.pinned, value: record.pinnedToTop, enabled: true)),
            WGPERow(id: "flagsFooter", kind: .footer(WGStrings.FakeGifts.Editor.flagsFooter))
        ])
        model.toggle["shown"] = { value in
            updateDraft { record in
                record.savedToProfile = value
                if !value {
                    record.pinnedToTop = false
                }
            }
        }
        model.toggle["pinned"] = { value in
            updateDraft { record in
                record.pinnedToTop = value
                if value {
                    record.savedToProfile = true
                }
            }
        }

        model.sections.append([WGPERow(id: "delete", kind: .action(title: WGStrings.FakeGifts.Editor.delete, destructive: true, enabled: true))])
        model.tap["delete"] = {
            wgPEConfirmDestructive(context: context, from: controllerRef, title: WGStrings.FakeGifts.Editor.deleteTitle, text: WGStrings.FakeGifts.Editor.deleteText, confirm: WGStrings.FakeGifts.Editor.delete, action: {
                WGFakeGiftsStore.shared.remove(accountPeerId: accountPeerId, localId: localId)
                controllerRef?.dismiss()
            })
        }

        model.rightButton = (title: presentationData.strings.Common_Done, enabled: true, action: {
            let value = draftValue.with { $0 }
            WGFakeGiftsStore.shared.update(accountPeerId: accountPeerId, localId: localId, { record in
                record = value
            })
            controllerRef?.dismiss()
        })
        return model
    }
    let controller = wgPEMakeListController(context: context, model: model)
    controllerRef = controller
    return controller
}
