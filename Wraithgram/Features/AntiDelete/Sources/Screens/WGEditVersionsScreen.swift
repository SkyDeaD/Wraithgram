import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting
import AccountContext
import Pasteboard
import WGCore
import WGFeaturesShared

/// «История правок» of one message: the current text and every saved version with its server
/// date. A long tap copies a version. No alert with an unbounded text: a list.
func wgMakeEditVersionsController(context: AccountContext, messageId: MessageId) -> ViewController {
    weak var weakController: ViewController?
    let message = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Messages.Message(id: messageId))

    let model = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, message)
    |> map { presentationData, message -> WGADScreenModel in
        var model = WGADScreenModel(title: .text(WGStrings.AntiDelete.Versions.title), sections: [])
        guard let message = message?._asMessage() else {
            model.sections.append(WGADSection(id: "empty", rows: [WGADRow(id: "empty", kind: .footer(WGStrings.AntiDelete.Versions.gone))]))
            return model
        }
        let state = WGAntiDeleteMessageState(attributes: message.attributes)
        let current = message.wgEffectiveText
        var currentText = current.text
        if currentText.isEmpty, let token = wgAntiDeleteMediaToken(message.media) {
            currentText = wgAntiDeleteMediaTitle(token)
        }
        model.sections.append(WGADSection(id: "current", rows: [
            WGADRow(id: "current.header", kind: .header(WGStrings.AntiDelete.Versions.current)),
            WGADRow(id: "current", kind: .text(currentText))
        ]))
        model.tap["current"] = {
            storeMessageTextInPasteboard(current.text, entities: current.entities)
        }

        let versions = state.history?.versions ?? []
        if versions.isEmpty {
            model.sections.append(WGADSection(id: "none", rows: [WGADRow(id: "none", kind: .footer(WGStrings.AntiDelete.Versions.none))]))
        } else {
            var rows: [WGADRow] = []
            for (index, version) in versions.enumerated().reversed() {
                let date = stringForMediumDate(timestamp: version.date, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat)
                var text = version.text
                if let media = version.mediaDescription {
                    let mediaTitle = wgAntiDeleteMediaTitle(media)
                    text = text.isEmpty ? mediaTitle : mediaTitle + "\n" + text
                }
                rows.append(WGADRow(id: "version.\(index).header", kind: .header(date)))
                rows.append(WGADRow(id: "version.\(index)", kind: .text(text)))
                model.tap["version.\(index)"] = {
                    storeMessageTextInPasteboard(version.text, entities: version.entities)
                }
            }
            rows.append(WGADRow(id: "versions.footer", kind: .footer(WGStrings.AntiDelete.Versions.copyHint)))
            model.sections.append(WGADSection(id: "versions", rows: rows))
        }

        var actions: [WGADRow] = [WGADRow(id: "open", kind: .action(title: WGStrings.AntiDelete.History.openInChat, destructive: false))]
        model.tap["open"] = {
            if let navigationController = weakController?.navigationController as? NavigationController {
                wgOpenMessage(context: context, navigationController: navigationController, messageId: messageId, threadId: message.threadId)
            }
        }
        if !versions.isEmpty {
            actions.append(WGADRow(id: "clear", kind: .action(title: WGStrings.AntiDelete.History.clearVersions, destructive: true)))
            model.tap["clear"] = {
                let _ = WGAntiDeleteOperations.removeEditHistory(postbox: context.account.postbox, accountId: context.account.id, messageIds: [messageId]).start()
            }
        }
        model.sections.append(WGADSection(id: "actions", rows: actions))
        return model
    }

    let controller = wgMakeADListController(context: context, model: model)
    weakController = controller
    return controller
}
