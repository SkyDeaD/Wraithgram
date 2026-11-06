import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import AlertUI
import PresentationDataUtils
import WGCore
import WGFeaturesShared

// Screens of «VPN по подписке»: servers and subscriptions (status, choice, ping), a new
// subscription, a subscription's settings.

enum WGVlessText {
    static func status(_ status: WGVlessStatus) -> String {
        switch status {
        case .off:
            return WGStrings.Vless.Status.off
        case .notBundled:
            return WGStrings.Vless.Status.notBundled
        case .noServer:
            return WGStrings.Vless.Status.noServer
        case .starting:
            return WGStrings.Vless.Status.starting
        case let .running(serverName):
            return WGStrings.Vless.Status.running(server: serverName)
        case let .unreachable(serverName):
            return WGStrings.Vless.Status.unreachable(server: serverName)
        case let .failed(failure):
            switch failure {
            case .loadFailed:
                return WGStrings.Vless.Status.loadFailed
            case .configInvalid:
                return WGStrings.Vless.Status.configInvalid
            case .startFailed:
                return WGStrings.Vless.Status.startFailed
            }
        }
    }

    static func error(_ error: WGVlessFetchError) -> String {
        return WGVlessText.error(code: WGVlessController.errorCode(error))
    }

    static func error(code: String) -> String {
        if code.hasPrefix("http:") {
            return WGStrings.Vless.Error.http(code: String(code.dropFirst("http:".count)))
        }
        switch code {
        case "invalidURL":
            return WGStrings.Vless.Error.invalidURL
        case "tooLarge":
            return WGStrings.Vless.Error.tooLarge
        case "empty":
            return WGStrings.Vless.Error.empty
        default:
            return WGStrings.Vless.Error.network
        }
    }

    static func bytes(_ value: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func date(_ timestamp: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: WGLocalization.shared.languageCode)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    static func interval(_ interval: WGVlessUpdateInterval) -> String {
        switch interval {
        case .provider:
            return WGStrings.Vless.Subscription.Interval.provider
        case .hours6:
            return WGStrings.Vless.Subscription.Interval.hours6
        case .hours12:
            return WGStrings.Vless.Subscription.Interval.hours12
        case .hours24:
            return WGStrings.Vless.Subscription.Interval.hours24
        case .manual:
            return WGStrings.Vless.Subscription.Interval.manual
        }
    }

    /// Usage, expiry, last refresh or its error — one info block under a subscription's header.
    static func subscriptionInfo(_ subscription: WGVlessSubscription) -> String {
        var lines: [String] = [WGStrings.Vless.Subscription.servers(count: subscription.servers.count)]
        if let usage = subscription.usage {
            let used = usage.upload + usage.download
            if usage.total > 0 {
                lines.append(WGStrings.Vless.Servers.usage(used: WGVlessText.bytes(used), total: WGVlessText.bytes(usage.total)))
            } else {
                lines.append(WGStrings.Vless.Servers.usageUnlimited(used: WGVlessText.bytes(used)))
            }
            if usage.expire > 0 {
                lines.append(WGStrings.Vless.Servers.expires(date: WGVlessText.date(Double(usage.expire))))
            }
        }
        if subscription.url == nil {
            lines.append(WGStrings.Vless.Servers.manual)
        } else if let error = subscription.lastError {
            lines.append(WGStrings.Vless.Error.lastRefresh(reason: WGVlessText.error(code: error)))
        } else if subscription.updatedAt > 0 {
            lines.append(WGStrings.Vless.Servers.updated(date: WGVlessText.date(subscription.updatedAt)))
        }
        return lines.joined(separator: "\n")
    }
}

func wgVlessMakeServersController(context: AccountContext) -> ViewController {
    WGVlessController.shared.attach(context: context)
    weak var weakController: ViewController?
    let push: (ViewController) -> Void = { controller in
        (weakController?.navigationController as? NavigationController)?.pushViewController(controller)
    }

    let model = combineLatest(queue: .mainQueue(),
        WGVlessStore.shared.subscriptionsSignal,
        WGVlessController.shared.status,
        WGVlessController.shared.pingResults,
        WGVlessController.shared.traffic(),
        WGSettingsStore.shared.revision,
        WGLocalization.shared.languageCodeSignal
    )
    |> map { subscriptions, status, pings, traffic, _, _ -> WGVlessScreenModel in
        var model = WGVlessScreenModel(title: WGStrings.Vless.Servers.title)
        let selectedId = WGVlessSettings.selectedServer.value

        var statusRows: [WGVlessRow] = [WGVlessRow(id: "status.header", kind: .header(WGStrings.Vless.Status.title))]
        // The same switch as in the menu: this screen is also reached from Telegram's proxy screen.
        let enabled = WGVlessSettings.enabled.value
        let canSwitch = enabled || (WGXrayCore.isBundled && !selectedId.isEmpty)
        statusRows.append(WGVlessRow(id: "status.enabled", kind: .toggle(title: WGStrings.Vless.Menu.enable, value: enabled, enabled: canSwitch)))
        model.toggle["status.enabled"] = { value in
            WGVlessSettings.enabled.set(value)
        }
        var statusText = WGVlessText.status(status)
        if let traffic {
            statusText += "\n" + WGStrings.Vless.Status.traffic(up: WGVlessText.bytes(traffic.uplink), down: WGVlessText.bytes(traffic.downlink))
        }
        if !selectedId.isEmpty && WGVlessStore.shared.server(id: selectedId) == nil, case let .running(serverName) = status {
            statusText += "\n" + WGStrings.Vless.Servers.removed(server: serverName)
        }
        statusRows.append(WGVlessRow(id: "status.text", kind: .info(statusText)))
        model.sections.append(statusRows)

        var actions: [WGVlessRow] = [WGVlessRow(id: "action.add", kind: .action(title: WGStrings.Vless.Servers.add, destructive: false, enabled: true))]
        model.tap["action.add"] = {
            push(wgVlessMakeAddController(context: context))
        }
        if !subscriptions.isEmpty {
            actions.append(WGVlessRow(id: "action.ping", kind: .action(title: WGStrings.Vless.Servers.ping, destructive: false, enabled: true)))
            model.tap["action.ping"] = {
                WGVlessController.shared.pingAll()
            }
            if subscriptions.contains(where: { $0.url != nil }) {
                actions.append(WGVlessRow(id: "action.refresh", kind: .action(title: WGStrings.Vless.Servers.refreshAll, destructive: false, enabled: true)))
                model.tap["action.refresh"] = {
                    for subscription in WGVlessStore.shared.subscriptions where subscription.url != nil {
                        let _ = WGVlessController.shared.refresh(subscriptionId: subscription.id).start()
                    }
                }
            }
        } else {
            actions.append(WGVlessRow(id: "action.empty", kind: .footer(WGStrings.Vless.Servers.empty)))
        }
        model.sections.append(actions)

        for subscription in subscriptions {
            var rows: [WGVlessRow] = [WGVlessRow(id: "sub.\(subscription.id).header", kind: .header(subscription.name.isEmpty ? WGStrings.Vless.Subscription.title : subscription.name))]
            for server in subscription.servers {
                let rowId = "server.\(subscription.id).\(server.id)"
                var label = ""
                if let ping = pings[server.id] {
                    label = ping >= 0 ? WGStrings.Vless.Servers.pingMs(ms: String(ping)) : WGStrings.Vless.Servers.pingFailed
                }
                rows.append(WGVlessRow(id: rowId, kind: .check(title: server.name, label: label, checked: server.id == selectedId)))
                let serverId = server.id
                model.tap[rowId] = {
                    WGVlessSettings.selectedServer.set(serverId)
                }
            }
            let settingsId = "sub.\(subscription.id).settings"
            rows.append(WGVlessRow(id: settingsId, kind: .disclosure(title: WGStrings.Vless.Servers.settings, label: "")))
            let subscriptionId = subscription.id
            model.tap[settingsId] = {
                push(wgVlessMakeSubscriptionController(context: context, subscriptionId: subscriptionId))
            }
            rows.append(WGVlessRow(id: "sub.\(subscription.id).info", kind: .footer(WGVlessText.subscriptionInfo(subscription))))
            model.sections.append(rows)
        }
        return model
    }
    let controller = wgVlessMakeListController(context: context, model: model)
    weakController = controller
    return controller
}

func wgVlessMakeAddController(context: AccountContext) -> ViewController {
    weak var weakController: ViewController?
    struct State: Equatable {
        var link = ""
        var name = ""
        var loading = false
        var error: String?
    }
    let state = ValuePromise(State(), ignoreRepeated: true)
    let stateValue = Atomic(value: State())
    let update: ((inout State) -> Void) -> Void = { f in
        state.set(stateValue.modify { current in
            var current = current
            f(&current)
            return current
        })
    }
    let addDisposable = MetaDisposable()

    let model = combineLatest(queue: .mainQueue(), state.get(), WGLocalization.shared.languageCodeSignal)
    |> map { state, _ -> WGVlessScreenModel in
        var model = WGVlessScreenModel(title: WGStrings.Vless.Add.title)
        model.sections.append([
            WGVlessRow(id: "link.header", kind: .header(WGStrings.Vless.Add.linkHeader)),
            WGVlessRow(id: "link", kind: .multilineInput(text: state.link, placeholder: WGStrings.Vless.Add.linkPlaceholder)),
            WGVlessRow(id: "link.footer", kind: .footer(WGStrings.Vless.Add.linkFooter))
        ])
        model.sections.append([
            WGVlessRow(id: "name.header", kind: .header(WGStrings.Vless.Add.nameHeader)),
            WGVlessRow(id: "name", kind: .input(text: state.name, placeholder: WGStrings.Vless.Add.namePlaceholder))
        ])
        var actionRows: [WGVlessRow] = [WGVlessRow(id: "add", kind: .action(title: state.loading ? WGStrings.Vless.Add.adding : WGStrings.Vless.Add.add, destructive: false, enabled: !state.loading && !state.link.isEmpty))]
        if let error = state.error {
            actionRows.append(WGVlessRow(id: "error", kind: .footer(WGStrings.Vless.Add.failed(reason: error))))
        }
        model.sections.append(actionRows)
        model.text["link"] = { value in
            update { $0.link = value }
        }
        model.text["name"] = { value in
            update { $0.name = value }
        }
        model.tap["add"] = {
            let current = stateValue.with { $0 }
            if current.loading || current.link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return
            }
            update {
                $0.loading = true
                $0.error = nil
            }
            addDisposable.set((WGVlessController.shared.addSubscription(input: current.link, name: current.name)
            |> deliverOnMainQueue).start(next: { subscription in
                if WGVlessSettings.selectedServer.value.isEmpty, let first = subscription.servers.first {
                    WGVlessSettings.selectedServer.set(first.id)
                }
                weakController?.dismiss()
            }, error: { error in
                update {
                    $0.loading = false
                    $0.error = WGVlessText.error(error)
                }
            }))
        }
        return model
    }
    let controller = wgVlessMakeListController(context: context, model: model)
    controller.navigationPresentation = .modal
    weakController = controller
    return controller
}

func wgVlessMakeSubscriptionController(context: AccountContext, subscriptionId: String) -> ViewController {
    weak var weakController: ViewController?
    // Text edits stay in the screen until «Готово»: no write per keystroke.
    let draftName = Atomic<String?>(value: nil)
    let draftURL = Atomic<String?>(value: nil)
    let refreshDisposable = MetaDisposable()

    let model = combineLatest(queue: .mainQueue(), WGVlessStore.shared.subscriptionsSignal, WGLocalization.shared.languageCodeSignal)
    |> map { subscriptions, _ -> WGVlessScreenModel in
        var model = WGVlessScreenModel(title: WGStrings.Vless.Subscription.title)
        guard let subscription = subscriptions.first(where: { $0.id == subscriptionId }) else {
            return model
        }
        model.sections.append([
            WGVlessRow(id: "name.header", kind: .header(WGStrings.Vless.Subscription.nameHeader)),
            WGVlessRow(id: "name", kind: .input(text: draftName.with { $0 } ?? subscription.name, placeholder: WGStrings.Vless.Add.namePlaceholder))
        ])
        model.text["name"] = { value in
            let _ = draftName.swap(value)
        }
        if let url = subscription.url {
            model.sections.append([
                WGVlessRow(id: "url.header", kind: .header(WGStrings.Vless.Subscription.urlHeader)),
                WGVlessRow(id: "url", kind: .multilineInput(text: draftURL.with { $0 } ?? url, placeholder: WGStrings.Vless.Add.linkPlaceholder))
            ])
            model.text["url"] = { value in
                let _ = draftURL.swap(value)
            }
            var intervalRows: [WGVlessRow] = [WGVlessRow(id: "interval.header", kind: .header(WGStrings.Vless.Subscription.intervalHeader))]
            for interval in WGVlessUpdateInterval.allCases {
                let rowId = "interval.\(interval.rawValue)"
                intervalRows.append(WGVlessRow(id: rowId, kind: .check(title: WGVlessText.interval(interval), label: "", checked: subscription.updateInterval == interval)))
                model.tap[rowId] = {
                    WGVlessController.shared.updateSubscription(id: subscriptionId, { $0.updateInterval = interval })
                }
            }
            intervalRows.append(WGVlessRow(id: "interval.footer", kind: .footer(WGStrings.Vless.Subscription.intervalFooter)))
            model.sections.append(intervalRows)
            model.sections.append([WGVlessRow(id: "refresh", kind: .action(title: WGStrings.Vless.Subscription.refresh, destructive: false, enabled: true))])
            model.tap["refresh"] = {
                refreshDisposable.set(WGVlessController.shared.refresh(subscriptionId: subscriptionId).start())
            }
        }
        model.sections.append([
            WGVlessRow(id: "delete", kind: .action(title: WGStrings.Vless.Subscription.delete, destructive: true, enabled: true)),
            WGVlessRow(id: "info", kind: .footer(WGVlessText.subscriptionInfo(subscription)))
        ])
        let name = subscription.name
        model.tap["delete"] = {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let alert = textAlertController(context: context, title: nil, text: WGStrings.Vless.Subscription.deleteConfirm(name: name), actions: [
                TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                TextAlertAction(type: .destructiveAction, title: WGStrings.Vless.Subscription.delete, action: {
                    WGVlessController.shared.removeSubscription(id: subscriptionId)
                    let _ = weakController?.navigationController?.popViewController(animated: true)
                })
            ])
            weakController?.present(alert, in: .window(.root))
        }
        model.rightButton = (WGStrings.Vless.Subscription.save, {
            let name = draftName.swap(nil)
            let url = draftURL.swap(nil)
            var urlChanged = false
            WGVlessController.shared.updateSubscription(id: subscriptionId, { subscription in
                if let name {
                    subscription.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let url, subscription.url != nil {
                    let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty && trimmed != subscription.url {
                        subscription.url = trimmed
                        subscription.lastError = nil
                        urlChanged = true
                    }
                }
            })
            if urlChanged {
                refreshDisposable.set(WGVlessController.shared.refresh(subscriptionId: subscriptionId).start())
            }
            let _ = weakController?.navigationController?.popViewController(animated: true)
        })
        return model
    }
    let controller = wgVlessMakeListController(context: context, model: model)
    weakController = controller
    return controller
}
