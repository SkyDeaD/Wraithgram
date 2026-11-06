import Foundation
import WGCore

// The studio's composed labels. The per-item names (filters, parameters, anchors…) are generated
// into WGMaskStudioNamesGenerated.swift.

extension WGMaskStudioNames {
    static func layerTitle(_ effect: WGMaskEffect) -> String {
        if effect.type == .filter, let id = effect.filterId, WGFilterCatalog.descriptor(id) != nil {
            return WGMaskStudioNames.filterTitle(id)
        }
        return WGMaskStudioNames.effectType(effect.type)
    }

    static func layerSubtitle(_ effect: WGMaskEffect) -> String {
        var parts: [String] = []
        if effect.type == .filter, let id = effect.filterId, let descriptor = WGFilterCatalog.descriptor(id) {
            parts.append(WGMaskStudioNames.category(descriptor.category))
            if descriptor.param("anchor") != nil, let anchor = effect.effectiveAnchor {
                parts.append(WGMaskStudioNames.anchor(anchor))
            }
        } else if let anchor = effect.anchor {
            parts.append(WGMaskStudioNames.anchor(anchor))
        }
        if !effect.isEnabled {
            parts.append(WGStrings.CameraMasks.Studio.layerOff)
        }
        return parts.joined(separator: " · ")
    }

    static func filterSubtitle(_ descriptor: WGFilterDescriptor) -> String {
        var text = WGStrings.CameraMasks.Studio.layerCost(units: "\(descriptor.cost)")
        if descriptor.isHeavy {
            text += " · " + WGStrings.CameraMasks.Studio.heavy
        }
        return text + WGMaskStudioNames.needsSuffix(descriptor.needs)
    }

    /// « · needs a face» and the like; empty when the layer needs nothing from Vision.
    static func needsSuffix(_ needs: WGVisionNeeds) -> String {
        if needs.contains(.segmentation) {
            return " · " + WGStrings.CameraMasks.Studio.needsSegmentation
        }
        if needs.contains(.landmarks) {
            return " · " + WGStrings.CameraMasks.Studio.needsLandmarks
        }
        if needs.contains(.face) {
            return " · " + WGStrings.CameraMasks.Studio.needsFace
        }
        return ""
    }

    static func violation(_ violation: WGMaskBudget.Violation) -> String {
        switch violation {
        case let .tooManyEffects(limit):
            return WGStrings.CameraMasks.Studio.Violation.tooManyEffects(count: limit)
        case .tooManyHeavy:
            return WGStrings.CameraMasks.Studio.Violation.tooManyHeavy
        case .tooManySegmentation:
            return WGStrings.CameraMasks.Studio.Violation.tooManySegmentation
        case .tooManyFaceWarps:
            return WGStrings.CameraMasks.Studio.Violation.tooManyFaceWarps
        case .tooManyAnimated:
            return WGStrings.CameraMasks.Studio.Violation.tooManyAnimated
        case .overBudget:
            return WGStrings.CameraMasks.Studio.Violation.overBudget
        }
    }
}
