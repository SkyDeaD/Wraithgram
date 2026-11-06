// Compiled into TelegramUI (filegroup //Wraithgram/WGHooks:TelegramUIHookSources): launch of
// Wraithgram in the app and the call-site helpers of the UI points that need TelegramUI's
// internal types (ChatControllerImpl, ChatControllerNode). No feature logic here.

import Foundation
import UIKit
import ObjectiveC
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import ContextUI
import ChatInterfaceState
import ChatPresentationInterfaceState
import SettingsUI
import UIKitRuntimeUtils
import WGCore
import WGHooks
import WGSettingsUI
import WGFeatures

// MARK: - Launch and lifecycle (FOUNDATION_SPEC §2)

private var wgApplicationLaunched = false

/// WRAITH hook target: AppDelegate, as soon as the App Group path is known and before the
/// AccountManager and the accounts exist.
func wgApplicationDidLaunch(appGroupPath: String) {
    assert(Thread.isMainThread)
    if wgApplicationLaunched {
        return
    }
    wgApplicationLaunched = true
    WGCore.bootstrap(WGCoreEnvironment(appGroupPath: appGroupPath, process: .app))
    // Screens WGSettingsUI can not link itself (it sits below SettingsUI).
    WGSettingsUIEnvironment.shared.makeTelegramLanguageController = { context in
        return LocalizationListController(context: context)
    }
    // `wraithgram://settings` / `wg://settings` open the Wraithgram menu (features may claim other links).
    WGLifecycleHooks.openURL.register({ url, context, navigationController in
        guard let scheme = url.scheme?.lowercased(), scheme == "wraithgram" || scheme == "wg" else {
            return false
        }
        if url.host?.lowercased() == "settings" {
            navigationController.pushViewController(wgMakeSettingsController(context: context))
            return true
        }
        return false
    }, order: 1000)
    // A double tap that edits a message (WGMessageGestureHooks) reaches the chat's input panel.
    WGMessageGestureHooks.editMessage = { chatNode, messageId in
        guard let chatNode = chatNode as? ChatControllerNode, let interfaceInteraction = chatNode.interfaceInteraction else {
            return false
        }
        interfaceInteraction.setupEditMessage(messageId, { _ in })
        return true
    }
    // «В начало чата» of the quick buttons: the first message, not the newest one (performScrollToTop).
    WGChatScreenHooks.scrollToStartOfHistory = { controller in
        (controller as? ChatControllerImpl)?.scrollToStartOfHistory()
    }
    WGFeatures.registerAll()
    WGCore.runGlobalMigrations()
    WGHookRegistry.freeze()
}

func wgApplicationDidBecomeActive() {
    WGForegroundTaskScheduler.shared.applicationDidBecomeActive()
    WGLifecycleHooks.notifyDidBecomeActive()
}

func wgApplicationWillResignActive() {
    WGForegroundTaskScheduler.shared.applicationWillResignActive()
    WGSettingsStore.shared.flush()
    WGLifecycleHooks.notifyWillResignActive()
}

func wgApplicationDidEnterBackground() {
    WGForegroundTaskScheduler.shared.applicationWillResignActive()
    WGSettingsStore.shared.flush()
    WGLifecycleHooks.notifyDidEnterBackground()
}

/// WRAITH hook target: SharedAccountContext, whenever the app's PresentationData strings change.
func wgTelegramLanguageDidChange(_ presentationData: PresentationData) {
    // A custom language pack has its own code; its base language decides then (not English).
    WGLocalization.shared.setTelegramLanguageCode(presentationData.strings.primaryComponent.languageCode, baseCode: presentationData.strings.baseLanguageCode)
}

// MARK: - Chat screen

func wgChatScreen(_ controller: ChatControllerImpl) -> WGChatScreen {
    var isPreview = false
    if case .standard(.previewing) = controller.presentationInterfaceState.mode {
        isPreview = true
    }
    return WGChatScreen(context: controller.context, chatLocation: controller.chatLocation, controller: controller, isPreview: isPreview)
}

private var wgChatOverlaysKey: UInt8 = 0

private final class WGChatOverlaysBox: NSObject {
    let overlays: [WGChatOverlay]

    init(overlays: [WGChatOverlay]) {
        self.overlays = overlays
    }
}

/// WRAITH hook target: ChatControllerNode.init, after the wallpaper and the history are added.
func wgInstallChatOverlays(_ node: ChatControllerNode, context: AccountContext, chatLocation: ChatLocation, controller: ChatControllerImpl?) {
    if WGChatScreenHooks.overlays.isEmpty {
        return
    }
    var isPreview = false
    if let controller, case .standard(.previewing) = controller.presentationInterfaceState.mode {
        isPreview = true
    }
    let overlays = WGChatScreenHooks.makeOverlays(WGChatScreen(context: context, chatLocation: chatLocation, controller: controller, isPreview: isPreview))
    if overlays.isEmpty {
        return
    }
    for overlay in overlays {
        switch overlay.placement {
        case .aboveWallpaper:
            node.backgroundNode.supernode?.insertSubnode(overlay.node, aboveSubnode: node.backgroundNode)
        case .aboveHistory:
            node.historyNodeContainer.supernode?.insertSubnode(overlay.node, aboveSubnode: node.historyNodeContainer)
        }
    }
    objc_setAssociatedObject(node, &wgChatOverlaysKey, WGChatOverlaysBox(overlays: overlays), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
}

/// WRAITH hook target: ChatControllerNode.containerLayoutUpdated, next to the wallpaper frame.
func wgLayoutChatOverlays(_ node: ChatControllerNode, bounds: CGRect, insets: UIEdgeInsets, transition: ContainedViewLayoutTransition) {
    guard let box = objc_getAssociatedObject(node, &wgChatOverlaysKey) as? WGChatOverlaysBox else {
        return
    }
    for overlay in box.overlays {
        transition.updateFrame(node: overlay.node, frame: bounds)
        overlay.updateLayout(bounds: bounds, insets: insets, transition: transition)
    }
}

private var wgChatChromeCaptureKey: UInt8 = 0

/// WRAITH hook target: ChatControllerNode.containerLayoutUpdated, after upstream's own capture
/// protection. Hides the chat's chrome (header, input panel, the panels over it, navigation buttons,
/// overlays above the history) from screenshots and recordings while a feature asks for it
/// (WGChatScreenHooks.hidesChromeFromCapture). The layers are only touched when the answer changes.
func wgUpdateChatChromeCaptureProtection(_ node: ChatControllerNode) {
    if WGChatScreenHooks.hidesChromeFromCapture.isEmpty {
        return
    }
    let hides = WGChatScreenHooks.hidesChromeFromCapture(context: node.context, chatLocation: node.chatLocation)
    let applied = (objc_getAssociatedObject(node, &wgChatChromeCaptureKey) as? NSNumber)?.boolValue ?? false
    if hides == applied {
        return
    }
    objc_setAssociatedObject(node, &wgChatChromeCaptureKey, NSNumber(value: hides), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    var layers: [CALayer] = [node.inputPanelContainerNode.layer, node.inputContextPanelContainer.layer, node.navigateButtons.layer]
    if let navigationBar = node.navigationBar {
        layers.append(navigationBar.layer)
    }
    if let box = objc_getAssociatedObject(node, &wgChatOverlaysKey) as? WGChatOverlaysBox {
        for overlay in box.overlays where overlay.placement == .aboveHistory {
            layers.append(overlay.node.layer)
        }
    }
    for layer in layers {
        setLayerDisableScreenshots(layer, hides)
    }
}

/// WRAITH hook target: ChatControllerNode.shouldAnimateMessageTransition — no send animation while the
/// chrome is hidden from capture (the animation carries the typed text through unprotected layers).
func wgChatChromeHiddenFromCapture(_ node: ChatControllerNode) -> Bool {
    return (objc_getAssociatedObject(node, &wgChatChromeCaptureKey) as? NSNumber)?.boolValue ?? false
}

/// WRAITH hook target: ChatControllerNode.sendCurrentMessage. `true` = a feature took over the send.
func wgInterceptSendCurrentMessage(_ node: ChatControllerNode, proceed: @escaping () -> Void) -> Bool {
    if WGChatScreenHooks.willSendText.isEmpty {
        return false
    }
    guard let textInputPanelNode = node.textInputPanelNode else {
        return false
    }
    return WGChatScreenHooks.interceptSend(owner: node, request: WGComposedTextRequest(
        context: node.context,
        chatLocation: node.chatLocation,
        state: textInputPanelNode.inputTextState,
        replace: { [weak node] state in
            node?.interfaceInteraction?.updateTextInputStateAndMode({ _, mode in
                return (state, mode)
            })
        }
    ), proceed: proceed)
}

/// WRAITH hook target: ChatMessageDisplaySendMessageOptions — features' items at the end of the
/// Send button's menu (WGChatScreenHooks.sendMenuItems).
func wgSendMenuItems(_ selfController: ChatControllerImpl) -> [ContextMenuItem] {
    guard let peerId = selfController.chatLocation.peerId else {
        return []
    }
    return WGChatScreenHooks.sendMenuItems(WGSendMenuContext(
        context: selfController.context,
        peerId: peerId,
        predictedLanguage: selfController.contentData?.state.translationState?.fromLang,
        inputText: selfController.presentationInterfaceState.interfaceState.effectiveInputState.inputText,
        replaceInput: { [weak selfController] text in
            selfController?.updateChatPresentationInterfaceState(animated: true, interactive: true, { state in
                return state.updatedInterfaceState { interfaceState in
                    return interfaceState.withUpdatedComposeInputState(ChatTextInputState(inputText: text))
                }
            })
        },
        dismiss: { [weak selfController] in
            selfController?.sendMessageActionsController?.dismiss()
        },
        present: { [weak selfController] controller in
            selfController?.present(controller, in: .window(.root))
        }
    ))
}

/// WRAITH hook target: OpenChatMessage — a downloaded document a feature may open itself
/// (WGChatScreenHooks.openDocument). nil when the file is not downloaded or has no name.
func wgOpenDocumentRequest(_ params: OpenChatMessageParams, file: TelegramMediaFile) -> WGOpenDocumentRequest? {
    guard let fileName = file.fileName, let path = params.context.account.postbox.mediaBox.completedResourcePath(file.resource) else {
        return nil
    }
    return WGOpenDocumentRequest(context: params.context, fileName: fileName, path: path, controller: params.navigationController?.topViewController as? ViewController)
}

// MARK: - Message decoration redraws

private var wgHistoryRedrawKey: UInt8 = 0

private final class WGHistoryRedrawSubscription {
    let disposable: Disposable

    init(disposable: Disposable) {
        self.disposable = disposable
    }

    deinit {
        self.disposable.dispose()
    }
}

/// WRAITH hook target: ChatHistoryListNodeImpl.init. Re-lays out the bubbles a feature asked for
/// with WGMessageDecorationHooks.redraw(messageIds:), and every visible bubble after a settings
/// change (a chat under the settings screen must not keep stale decorations until its history
/// updates). The subscriptions live as long as the node.
func wgObserveMessageDecorationRedraws(_ node: ChatHistoryListNodeImpl) {
    if !WGMessageDecorationHooks.needsRedraws {
        return
    }
    let disposables = DisposableSet()
    disposables.add((WGMessageDecorationHooks.redrawRequests
    |> deliverOnMainQueue).start(next: { [weak node] messageIds in
        guard let node else {
            return
        }
        for messageId in messageIds {
            node.requestMessageUpdate(messageId)
        }
    }))
    // The first value is the current revision (the node was just created): skip it. Bursts of
    // changes (a slider, an import, `redrawAll()`) re-lay out once, 0.3 s after the last one.
    let pendingRedraw = MetaDisposable()
    disposables.add(pendingRedraw)
    let scheduleRedrawOfVisibleMessages: () -> Void = { [weak node] in
        pendingRedraw.set((Signal<Void, NoError>.single(Void())
        |> delay(0.3, queue: Queue.mainQueue())).start(next: { _ in
            guard let node else {
                return
            }
            var messageIds: [EngineMessage.Id] = []
            node.forEachVisibleMessageItemNode { itemNode in
                if let item = itemNode.item {
                    messageIds.append(item.message.id)
                }
            }
            for messageId in messageIds {
                node.requestMessageUpdate(messageId)
            }
        }))
    }
    var isFirstRevision = true
    disposables.add((WGMessageDecorationHooks.settingsRevisions
    |> deliverOnMainQueue).start(next: { _ in
        if isFirstRevision {
            isFirstRevision = false
            return
        }
        scheduleRedrawOfVisibleMessages()
    }))
    disposables.add((WGMessageDecorationHooks.redrawAllRequests
    |> deliverOnMainQueue).start(next: { _ in
        scheduleRedrawOfVisibleMessages()
    }))
    objc_setAssociatedObject(node, &wgHistoryRedrawKey, WGHistoryRedrawSubscription(disposable: disposables), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
}
