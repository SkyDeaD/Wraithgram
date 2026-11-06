import Foundation
import UIKit
import Display
import AppBundle
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import LocalizedPeerData
import ContextUI
import ItemListUI
import WGCore
import WGHooks
import WGSettingsUI

// Screens of the export: what to include (the choice is remembered), the progress with "Cancel",
// the result ("Save to Files", "Share ZIP", "Done" — the temporary tree is deleted
// after it was saved), and the list of exports left unfinished. Entry points: «…» of a profile and
// Messages › Chat export.

enum WGChatExportMenu {
    static let infoSection = WGMenuSectionID("messages.export.info")

    static func register() {
        WGMenuRegistry.register(WGMenuRow(
            id: "chatExport.chat",
            section: .main(of: .messagesExport),
            order: 100,
            title: { WGStrings.ChatExport.Menu.chat },
            subtitle: { WGStrings.ChatExport.Menu.chatInfo },
            icon: .bundle("Chat/Context Menu/Message"),
            kind: .action({ context in
                wgChatExportPickChat(context: context.context, push: { controller in
                    context.push(controller)
                })
            }),
            searchKeywords: { [WGStrings.ChatExport.Menu.keywords] }
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "chatExport.account",
            section: .main(of: .messagesExport),
            order: 200,
            title: { WGStrings.ChatExport.Menu.account },
            subtitle: { WGStrings.ChatExport.Menu.accountInfo },
            icon: .bundle("Chat/Context Menu/Archive"),
            kind: .action({ context in
                context.push(wgMakeChatExportSetupScreen(context: context.context, mode: .account, title: WGStrings.ChatExport.Setup.accountTitle))
            }),
            searchKeywords: { [WGStrings.ChatExport.Menu.keywords] }
        ))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(
            id: WGChatExportMenu.infoSection,
            screen: .tab(.messagesExport),
            order: 300,
            footer: { _ in WGStrings.ChatExport.Menu.footer }
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "chatExport.jobs",
            section: WGChatExportMenu.infoSection,
            order: 100,
            title: { WGStrings.ChatExport.Menu.jobs },
            subtitle: { WGStrings.ChatExport.Menu.jobsInfo },
            icon: .bundle("Chat/Context Menu/Download"),
            kind: .action({ context in
                if WGChatExportManager.shared.current != nil {
                    // The screen of the current export offers «Save to Files» and «Share ZIP» once it
                    // is done: the same check as before an export starts.
                    WGChatExportAuth.authenticate(reason: WGStrings.ChatExport.Jobs.authReason, completion: { success in
                        if success {
                            context.push(wgMakeChatExportProgressScreen(context: context.context))
                        }
                    })
                } else {
                    context.push(wgMakeChatExportJobsScreen(context: context.context))
                }
            }),
            searchKeywords: { [WGStrings.ChatExport.Menu.keywords] }
        ))

        WGPeerInfoHooks.menuItems.register({ peerInfo in
            if peerInfo.isSettings {
                return []
            }
            let context = peerInfo.context
            let peer = peerInfo.chatPeer ?? peerInfo.peer
            weak let controller = peerInfo.controller
            return [.action(ContextMenuActionItem(text: WGStrings.ChatExport.Menu.profileItem, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Download"), color: theme.contextMenu.primaryColor)
            }, action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let title = peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                controller?.push(wgMakeChatExportSetupScreen(context: context, mode: .chat(peer.id.wgKey), title: title))
            }))]
        })
    }
}

private func wgChatExportPickChat(context: AccountContext, push: @escaping (ViewController) -> Void) {
    let picker = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.doNotSearchMessages], hasContactSelector: false, title: WGStrings.ChatExport.Menu.chat))
    picker.peerSelected = { [weak picker] peer, _ in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let title = peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
        let setup = wgMakeChatExportSetupScreen(context: context, mode: .chat(peer.id.wgKey), title: title)
        if let navigationController = picker?.navigationController as? NavigationController {
            navigationController.replaceTopController(setup, animated: true)
        } else {
            push(setup)
        }
    }
    push(picker)
}

private func wgChatExportSizeLabel(_ value: String) -> String {
    if value == "0" {
        return WGStrings.ChatExport.Setup.sizeUnlimited
    }
    return WGStrings.ChatExport.Setup.sizeMegabytes(size: value)
}

private func wgChatExportErrorText(_ code: String?) -> String {
    switch code {
    case "noSpace":
        return WGStrings.ChatExport.Progress.errorNoSpace
    case "chatNotFound":
        return WGStrings.ChatExport.Progress.errorChatNotFound
    default:
        return WGStrings.ChatExport.Progress.errorWrite
    }
}

// MARK: - Setup

func wgMakeChatExportSetupScreen(context: AccountContext, mode: WGChatExportMode, title: String) -> ViewController {
    weak var controllerRef: ItemListController?

    let model = combineLatest(queue: .mainQueue(), WGSettingsStore.shared.revision, WGLocalization.shared.languageCodeSignal)
    |> map { _, _ -> WGPEScreenModel in
        var model = WGPEScreenModel(title: WGStrings.ChatExport.Setup.title)
        let options = WGChatExportSettings.currentOptions()

        model.sections.append([
            WGPERow(id: "target", kind: .header(WGStrings.ChatExport.Setup.target)),
            WGPERow(id: "targetName", kind: .info(title))
        ])

        let toggles: [(String, String, WGSetting<Bool>)] = [
            ("photos", WGStrings.ChatExport.Setup.photos, WGChatExportSettings.photos),
            ("videos", WGStrings.ChatExport.Setup.videos, WGChatExportSettings.videos),
            ("voice", WGStrings.ChatExport.Setup.voiceMessages, WGChatExportSettings.voiceMessages),
            ("round", WGStrings.ChatExport.Setup.videoMessages, WGChatExportSettings.videoMessages),
            ("stickers", WGStrings.ChatExport.Setup.stickers, WGChatExportSettings.stickers),
            ("gifs", WGStrings.ChatExport.Setup.gifs, WGChatExportSettings.gifs),
            ("files", WGStrings.ChatExport.Setup.files, WGChatExportSettings.files)
        ]
        var mediaRows: [WGPERow] = [WGPERow(id: "mediaHeader", kind: .header(WGStrings.ChatExport.Setup.mediaHeader))]
        for (id, label, setting) in toggles {
            mediaRows.append(WGPERow(id: id, kind: .check(title: label, subtitle: nil, checked: setting.value)))
            model.tap[id] = {
                setting.set(!setting.value)
            }
        }
        if options.includesMedia {
            mediaRows.append(WGPERow(id: "size", kind: .disclosure(title: WGStrings.ChatExport.Setup.sizeLimit, label: wgChatExportSizeLabel(WGChatExportSettings.sizeLimit.value), icon: nil, enabled: true)))
            model.tap["size"] = {
                wgPEPresentActionSheet(context: context, from: controllerRef, buttons: WGChatExportSettings.sizeLimitValues.map { value in
                    return (title: wgChatExportSizeLabel(value), isDestructive: false, action: {
                        WGChatExportSettings.sizeLimit.set(value)
                    })
                })
            }
        }
        mediaRows.append(WGPERow(id: "mediaFooter", kind: .footer(WGStrings.ChatExport.Setup.mediaFooter)))
        model.sections.append(mediaRows)

        let format = WGChatExportSettings.format.value
        model.sections.append([
            WGPERow(id: "formatHeader", kind: .header(WGStrings.ChatExport.Setup.formatHeader)),
            WGPERow(id: "formatHTML", kind: .check(title: WGStrings.ChatExport.Setup.formatHtml, subtitle: nil, checked: format == "html")),
            WGPERow(id: "formatJSON", kind: .check(title: WGStrings.ChatExport.Setup.formatJson, subtitle: nil, checked: format == "json")),
            WGPERow(id: "formatBoth", kind: .check(title: WGStrings.ChatExport.Setup.formatBoth, subtitle: nil, checked: format != "html" && format != "json"))
        ])
        model.tap["formatHTML"] = {
            WGChatExportSettings.format.set("html")
        }
        model.tap["formatJSON"] = {
            WGChatExportSettings.format.set("json")
        }
        model.tap["formatBoth"] = {
            WGChatExportSettings.format.set("both")
        }

        var startFooter = WGStrings.ChatExport.Setup.startFooter
        if case .account = mode {
            startFooter = WGStrings.ChatExport.Setup.accountFooter
        }
        if let free = WGChatExportJob.freeSpace() {
            startFooter += "\n" + WGStrings.ChatExport.Setup.freeSpace(size: WGChatExportFormat.fileSize(free))
        }
        model.sections.append([
            WGPERow(id: "start", kind: .action(title: WGStrings.ChatExport.Setup.start, destructive: false, enabled: true)),
            WGPERow(id: "startFooter", kind: .footer(startFooter))
        ])
        model.tap["start"] = {
            guard let controller = controllerRef else {
                return
            }
            if WGChatExportManager.shared.isBusy {
                wgPEPresentToast(context: context, from: controller, text: WGStrings.ChatExport.Setup.alreadyRunning)
                return
            }
            if let free = WGChatExportJob.freeSpace(), free < WGChatExportJob.minimumFreeSpace {
                wgPEPresentToast(context: context, from: controller, text: WGStrings.ChatExport.Progress.errorNoSpace)
                return
            }
            WGChatExportAuth.authenticate(reason: WGStrings.ChatExport.Setup.authReason, completion: { success in
                guard success, let controller = controllerRef else {
                    return
                }
                if WGChatExportManager.shared.start(context: context, mode: mode, title: title) {
                    if let navigationController = controller.navigationController as? NavigationController {
                        navigationController.replaceTopController(wgMakeChatExportProgressScreen(context: context), animated: true)
                    }
                } else {
                    wgPEPresentToast(context: context, from: controller, text: WGStrings.ChatExport.Setup.alreadyRunning)
                }
            })
        }
        return model
    }
    let controller = wgPEMakeListController(context: context, model: model)
    controllerRef = controller
    return controller
}

// MARK: - Progress and result

private final class WGChatExportPickerDelegate: NSObject, UIDocumentPickerDelegate {
    let completed: () -> Void

    init(completed: @escaping () -> Void) {
        self.completed = completed
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.completed()
    }
}

/// Keeps the document picker's delegate alive as long as the screen.
private final class WGChatExportDelegateHolder {
    var delegate: WGChatExportPickerDelegate?
}

private func wgPEPresentNative(_ controller: UIViewController, from presenter: ViewController?) {
    guard var top = presenter?.view.window?.rootViewController else {
        return
    }
    while let presented = top.presentedViewController {
        top = presented
    }
    if let popover = controller.popoverPresentationController {
        popover.sourceView = top.view
        popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0.0, height: 0.0)
        popover.permittedArrowDirections = []
    }
    top.present(controller, animated: true)
}

func wgMakeChatExportProgressScreen(context: AccountContext) -> ViewController {
    weak var controllerRef: ItemListController?
    let pickerDelegate = WGChatExportDelegateHolder()
    let archiving = ValuePromise<Float?>(nil, ignoreRepeated: true)
    let archiveDisposable = MetaDisposable()

    let model = combineLatest(queue: .mainQueue(), WGChatExportManager.shared.progress, archiving.get(), WGLocalization.shared.languageCodeSignal)
    |> map { progress, archiveProgress, _ -> WGPEScreenModel in
        var model = WGPEScreenModel(title: WGStrings.ChatExport.Progress.title)
        guard let progress = progress, let job = WGChatExportManager.shared.current else {
            model.sections.append([WGPERow(id: "none", kind: .info(WGStrings.ChatExport.Progress.none))])
            return model
        }
        let jobId = progress.jobId

        var status: String
        switch progress.stage {
        case .planning:
            status = WGStrings.ChatExport.Progress.planning
        case .sections:
            status = WGStrings.ChatExport.Progress.sections
        case .chats:
            status = WGStrings.ChatExport.Progress.chat(index: "\(min(progress.chatIndex + 1, progress.chatCount))", count: progress.chatCount, name: progress.chatName ?? "")
        case .finished:
            status = WGStrings.ChatExport.Progress.finished
        case .failed:
            status = WGStrings.ChatExport.Progress.failed(reason: wgChatExportErrorText(progress.errorCode))
        }
        let stats = WGStrings.ChatExport.Progress.stats(messages: "\(progress.messages)", files: "\(progress.files)", size: WGChatExportFormat.fileSize(progress.bytes))
        model.sections.append([
            WGPERow(id: "header", kind: .header(progress.title)),
            WGPERow(id: "status", kind: .info(status + "\n" + stats))
        ])

        switch progress.stage {
        case .finished:
            var rows: [WGPERow] = [
                WGPERow(id: "saveFiles", kind: .action(title: WGStrings.ChatExport.Progress.saveToFiles, destructive: false, enabled: archiveProgress == nil)),
                WGPERow(id: "shareZip", kind: .action(title: archiveProgress.map { WGStrings.ChatExport.Progress.archiving(percent: "\(Int($0 * 100.0))") } ?? WGStrings.ChatExport.Progress.shareZip, destructive: false, enabled: archiveProgress == nil)),
                WGPERow(id: "done", kind: .action(title: WGStrings.ChatExport.Progress.done, destructive: true, enabled: true))
            ]
            rows.append(WGPERow(id: "doneFooter", kind: .footer(WGStrings.ChatExport.Progress.doneFooter)))
            model.sections.append(rows)
            let finish = {
                archiveDisposable.set(nil)
                WGChatExportManager.shared.discard(jobId: jobId)
                controllerRef?.dismiss()
            }
            model.tap["saveFiles"] = {
                let picker = UIDocumentPickerViewController(forExporting: [job.resultURL], asCopy: true)
                let delegate = WGChatExportPickerDelegate(completed: finish)
                pickerDelegate.delegate = delegate
                picker.delegate = delegate
                wgPEPresentNative(picker, from: controllerRef)
            }
            model.tap["shareZip"] = {
                archiving.set(0.0)
                archiveDisposable.set((WGChatExportManager.shared.archive(folder: job.resultURL)
                |> deliverOnMainQueue).start(next: { value, url in
                    archiving.set(url == nil && value < 1.0 ? value : nil)
                    if let url = url {
                        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                        activity.completionWithItemsHandler = { _, completed, _, _ in
                            if completed {
                                finish()
                            }
                        }
                        wgPEPresentNative(activity, from: controllerRef)
                    } else if value >= 1.0, let controller = controllerRef {
                        wgPEPresentToast(context: context, from: controller, text: WGStrings.ChatExport.Progress.zipFailed)
                    }
                }))
            }
            model.tap["done"] = finish
        case .failed:
            model.sections.append([
                WGPERow(id: "retry", kind: .action(title: WGStrings.ChatExport.Progress.retry, destructive: false, enabled: true)),
                WGPERow(id: "delete", kind: .action(title: WGStrings.ChatExport.Progress.delete, destructive: true, enabled: true))
            ])
            model.tap["retry"] = {
                if let free = WGChatExportJob.freeSpace(), free < WGChatExportJob.minimumFreeSpace, let controller = controllerRef {
                    wgPEPresentToast(context: context, from: controller, text: WGStrings.ChatExport.Progress.errorNoSpace)
                    return
                }
                WGChatExportManager.shared.retry()
            }
            model.tap["delete"] = {
                WGChatExportManager.shared.discard(jobId: jobId)
                controllerRef?.dismiss()
            }
        case .planning, .sections, .chats:
            model.sections.append([
                WGPERow(id: "cancel", kind: .action(title: WGStrings.ChatExport.Progress.cancel, destructive: true, enabled: true)),
                WGPERow(id: "cancelFooter", kind: .footer(WGStrings.ChatExport.Progress.runningFooter))
            ])
            model.tap["cancel"] = {
                wgPEConfirmDestructive(context: context, from: controllerRef, title: WGStrings.ChatExport.Progress.cancelTitle, text: WGStrings.ChatExport.Progress.cancelText, confirm: WGStrings.ChatExport.Progress.cancel, action: {
                    WGChatExportManager.shared.cancel()
                    controllerRef?.dismiss()
                })
            }
        }
        return model
    }
    let controller = wgPEMakeListController(context: context, model: model)
    controllerRef = controller

    // The screen does not lock while it shows a running export.
    let idleDisposable = MetaDisposable()
    controller.didAppear = { _ in
        idleDisposable.set((WGChatExportManager.shared.progress
        |> deliverOnMainQueue).start(next: { progress in
            UIApplication.shared.isIdleTimerDisabled = progress?.isRunning == true
        }))
    }
    controller.didDisappear = { _ in
        idleDisposable.set(nil)
        UIApplication.shared.isIdleTimerDisabled = false
    }
    return controller
}

// MARK: - Unfinished exports

func wgMakeChatExportJobsScreen(context: AccountContext) -> ViewController {
    weak var controllerRef: ItemListController?
    let format = WGChatExportFormat(languageCode: WGLocalization.shared.languageCode)

    let model = combineLatest(queue: .mainQueue(), WGChatExportManager.shared.storedJobs(accountId: context.account.id.int64), WGLocalization.shared.languageCodeSignal)
    |> map { journals, _ -> WGPEScreenModel in
        var model = WGPEScreenModel(title: WGStrings.ChatExport.Jobs.title)
        var rows: [WGPERow] = [WGPERow(id: "header", kind: .header(WGStrings.ChatExport.Jobs.header))]
        if journals.isEmpty {
            rows.append(WGPERow(id: "empty", kind: .info(WGStrings.ChatExport.Jobs.empty)))
        }
        for journal in journals {
            let id = "job" + journal.id
            let state: String
            switch journal.stage {
            case .finished:
                state = WGStrings.ChatExport.Jobs.finished
            case .failed:
                state = wgChatExportErrorText(journal.errorCode)
            case .planning, .sections, .chats:
                state = WGStrings.ChatExport.Jobs.paused(index: "\(journal.chatIndex)", count: journal.chats.count)
            }
            rows.append(WGPERow(id: id, kind: .disclosure(title: journal.title, label: format.full(journal.createdAt) + " · " + state, icon: nil, enabled: true)))
            model.tap[id] = {
                var buttons: [(title: String, isDestructive: Bool, action: () -> Void)] = []
                if journal.stage != .finished {
                    buttons.append((title: WGStrings.ChatExport.Jobs.resume, isDestructive: false, action: {
                        WGChatExportAuth.authenticate(reason: WGStrings.ChatExport.Setup.authReason, completion: { success in
                            guard success, let controller = controllerRef else {
                                return
                            }
                            if WGChatExportManager.shared.resume(context: context, journal: journal) {
                                controller.push(wgMakeChatExportProgressScreen(context: context))
                            } else {
                                wgPEPresentToast(context: context, from: controller, text: WGStrings.ChatExport.Setup.alreadyRunning)
                            }
                        })
                    }))
                } else {
                    buttons.append((title: WGStrings.ChatExport.Jobs.open, isDestructive: false, action: {
                        // A finished export can be saved or shared from its screen: Face ID first, as
                        // before it was made.
                        WGChatExportAuth.authenticate(reason: WGStrings.ChatExport.Jobs.authReason, completion: { success in
                            guard success, let controller = controllerRef else {
                                return
                            }
                            if WGChatExportManager.shared.resume(context: context, journal: journal) {
                                controller.push(wgMakeChatExportProgressScreen(context: context))
                            }
                        })
                    }))
                }
                buttons.append((title: WGStrings.ChatExport.Jobs.delete, isDestructive: true, action: {
                    WGChatExportManager.shared.discard(jobId: journal.id)
                }))
                wgPEPresentActionSheet(context: context, from: controllerRef, title: journal.title, buttons: buttons)
            }
        }
        rows.append(WGPERow(id: "footer", kind: .footer(WGStrings.ChatExport.Jobs.footer)))
        model.sections.append(rows)
        return model
    }
    let controller = wgPEMakeListController(context: context, model: model)
    controllerRef = controller
    return controller
}
