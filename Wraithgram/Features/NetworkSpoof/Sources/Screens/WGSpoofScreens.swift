import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import AlertUI
import PresentationDataUtils
import LocalizedPeerData
import WGCore

// Screens of «Подмены»: phone number, profile substitution. A typed number stays in the screen until
// «Готово»: nothing is written per keystroke.

func wgSpoofMakePhoneController(context: AccountContext) -> ViewController {
    let account = context.account.id.wg
    weak var weakController: ViewController?
    let draft = ValuePromise<String?>(nil, ignoreRepeated: true)
    let draftValue = Atomic<String?>(value: nil)

    let model = combineLatest(queue: .mainQueue(), WGNetworkSpoofSettings.fakePhoneEnabled.signal(for: account), WGNetworkSpoofSettings.fakePhone.signal(for: account), draft.get(), WGLocalization.shared.languageCodeSignal)
    |> map { enabled, number, draftText, _ -> WGSpoofScreenModel in
        var model = WGSpoofScreenModel(title: WGStrings.NetworkSpoof.Phone.title)
        model.sections.append([
            WGSpoofRow(id: "enabled", kind: .toggle(title: WGStrings.NetworkSpoof.Phone.enable, value: enabled, enabled: !number.isEmpty || enabled)),
            WGSpoofRow(id: "number.header", kind: .header(WGStrings.NetworkSpoof.Phone.numberHeader)),
            WGSpoofRow(id: "number", kind: .numberInput(title: "+", text: draftText ?? number, placeholder: "79991234567")),
            WGSpoofRow(id: "footer", kind: .footer(WGStrings.NetworkSpoof.Phone.footer))
        ])
        model.toggle["enabled"] = { value in
            WGNetworkSpoofSettings.fakePhoneEnabled.set(value, for: account)
        }
        model.text["number"] = { value in
            let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(15))
            let _ = draftValue.swap(digits)
            draft.set(digits)
        }
        if draftText != nil {
            model.rightButton = (WGStrings.NetworkSpoof.done, {
                if let digits = draftValue.swap(nil) {
                    WGNetworkSpoofSettings.fakePhone.set(digits, for: account)
                    if digits.isEmpty {
                        WGNetworkSpoofSettings.fakePhoneEnabled.set(false, for: account)
                    }
                }
                draft.set(nil)
                weakController?.view.endEditing(true)
            })
        }
        return model
    }
    let controller = wgSpoofMakeListController(context: context, model: model)
    weakController = controller
    return controller
}

func wgSpoofMakeProfilesController(context: AccountContext) -> ViewController {
    let account = context.account.id.wg
    weak var weakController: ViewController?
    let push: (ViewController) -> Void = { controller in
        (weakController?.navigationController as? NavigationController)?.pushViewController(controller)
    }

    let redirects = WGNetworkSpoofSettings.profileRedirects.signal(for: account)
    let peers = redirects
    |> mapToSignal { redirects -> Signal<[EnginePeer.Id: EnginePeer], NoError> in
        var ids: [EnginePeer.Id] = []
        for (source, target) in redirects {
            if let key = WGPeerKey(string: source) {
                ids.append(PeerId(wgKey: key))
            }
            ids.append(PeerId(wgKey: target))
        }
        return context.engine.data.get(EngineDataMap(ids.map(TelegramEngine.EngineData.Item.Peer.Peer.init)))
        |> map { result -> [EnginePeer.Id: EnginePeer] in
            var peers: [EnginePeer.Id: EnginePeer] = [:]
            for (id, peer) in result {
                if let peer {
                    peers[id] = peer
                }
            }
            return peers
        }
    }

    let model = combineLatest(queue: .mainQueue(), WGNetworkSpoofSettings.profileRedirectEnabled.signal(for: account), redirects, peers, WGLocalization.shared.languageCodeSignal)
    |> map { enabled, redirects, peers, _ -> WGSpoofScreenModel in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let name: (EnginePeer.Id) -> String = { id in
            return peers[id]?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) ?? WGStrings.NetworkSpoof.Profiles.unknownPeer
        }
        var model = WGSpoofScreenModel(title: WGStrings.NetworkSpoof.Profiles.title)
        model.sections.append([
            WGSpoofRow(id: "enabled", kind: .toggle(title: WGStrings.NetworkSpoof.Profiles.enable, value: enabled, enabled: true)),
            WGSpoofRow(id: "enabled.footer", kind: .footer(WGStrings.NetworkSpoof.Profiles.footer))
        ])
        model.toggle["enabled"] = { value in
            WGNetworkSpoofSettings.profileRedirectEnabled.set(value, for: account)
        }

        var rows: [WGSpoofRow] = [WGSpoofRow(id: "pairs.header", kind: .header(WGStrings.NetworkSpoof.Profiles.pairsHeader))]
        for source in redirects.keys.sorted() {
            guard let sourceKey = WGPeerKey(string: source), let target = redirects[source] else {
                continue
            }
            let rowId = "pair.\(source)"
            rows.append(WGSpoofRow(id: rowId, kind: .disclosure(title: WGStrings.NetworkSpoof.Profiles.pair(source: name(PeerId(wgKey: sourceKey)), target: name(PeerId(wgKey: target))), label: "")))
            model.tap[rowId] = {
                let alert = textAlertController(context: context, title: nil, text: WGStrings.NetworkSpoof.Profiles.removeConfirm, actions: [
                    TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                    TextAlertAction(type: .destructiveAction, title: WGStrings.NetworkSpoof.Profiles.remove, action: {
                        var current = WGNetworkSpoofSettings.profileRedirects.value(for: account)
                        current.removeValue(forKey: source)
                        WGNetworkSpoofSettings.profileRedirects.set(current, for: account)
                    })
                ])
                weakController?.present(alert, in: .window(.root))
            }
        }
        rows.append(WGSpoofRow(id: "pairs.add", kind: .action(title: WGStrings.NetworkSpoof.Profiles.add, destructive: false, enabled: true)))
        model.tap["pairs.add"] = {
            let sourcePicker = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.excludeSavedMessages, .excludeSecretChats, .doNotSearchMessages], hasContactSelector: false, title: WGStrings.NetworkSpoof.Profiles.pickSource))
            sourcePicker.peerSelected = { [weak sourcePicker] sourcePeer, _ in
                let targetPicker = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.excludeSavedMessages, .excludeSecretChats, .doNotSearchMessages], hasContactSelector: false, title: WGStrings.NetworkSpoof.Profiles.pickTarget))
                targetPicker.peerSelected = { [weak targetPicker] targetPeer, _ in
                    if targetPeer.id != sourcePeer.id {
                        var current = WGNetworkSpoofSettings.profileRedirects.value(for: account)
                        current[sourcePeer.id.wgKey.stringValue] = targetPeer.id.wgKey
                        WGNetworkSpoofSettings.profileRedirects.set(current, for: account)
                        if !WGNetworkSpoofSettings.profileRedirectEnabled.value(for: account) {
                            WGNetworkSpoofSettings.profileRedirectEnabled.set(true, for: account)
                        }
                    }
                    targetPicker?.dismiss()
                }
                sourcePicker?.dismiss()
                push(targetPicker)
            }
            push(sourcePicker)
        }
        model.sections.append(rows)
        return model
    }
    let controller = wgSpoofMakeListController(context: context, model: model)
    weakController = controller
    return controller
}
