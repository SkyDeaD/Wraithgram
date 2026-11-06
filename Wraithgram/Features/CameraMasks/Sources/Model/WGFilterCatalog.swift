import Foundation
import CoreImage

// The catalog of studio layers ("filter" effects): 105 ids in 9 categories, the same ids older
// Wraithgram versions wrote into masks, so their `.ggmask` files and catalog masks keep working.
// One descriptor = parameters (kind, range, default), cost in budget units (1 unit ≈ 0.25 ms of a
// 720p frame on an A13), what it needs from Vision, how the governor simplifies it, and the render.

enum WGFilterCategory: String, CaseIterable {
    case film
    case tone
    case light
    case retro
    case art
    case distort
    case blur
    case face
    case overlay
}

enum WGFilterParamKind: Equatable {
    case slider(min: Double, max: Double, step: Double)
    case toggle
    case color
    case point
    case anchor
    case blendMode
    /// The value lives in `effect.asset`.
    case image
    case emoji
    /// Five Y values at X = 0, .25, .5, .75, 1.
    case curve5
    /// Fifteen values: five per channel R, G, B.
    case curveRGB
}

struct WGFilterParam {
    let id: String
    let kind: WGFilterParamKind
    let defaultValue: WGMaskParamValue
}

/// One step the governor takes to make a heavy layer cheaper.
enum WGFilterDegradeStep {
    case scale(String, Double)
    case set(String, WGMaskParamValue)
    case disable
}

struct WGFilterDescriptor {
    let id: String
    let category: WGFilterCategory
    let params: [WGFilterParam]
    /// Budget units at full resolution.
    let cost: Int
    /// One of the expensive kernels (at most two per mask).
    let isHeavy: Bool
    /// A cheap colour op that fuses with its neighbours (consecutive ones cost 0.2×).
    let fuses: Bool
    let needs: WGVisionNeeds
    let isAnimated: Bool
    /// Minimum iOS major version (the app supports 15+, a few filters need 15).
    let minimumOS: Int
    let degrade: [WGFilterDegradeStep]
    let render: (WGFilterContext) -> CIImage

    init(_ id: String, _ category: WGFilterCategory, cost: Int, heavy: Bool = false, fuses: Bool = false, needs: WGVisionNeeds = [], animated: Bool = false, minimumOS: Int = 13, params: [WGFilterParam] = [], degrade: [WGFilterDegradeStep] = [], render: @escaping (WGFilterContext) -> CIImage) {
        self.id = id
        self.category = category
        self.params = params
        self.cost = cost
        self.isHeavy = heavy
        self.fuses = fuses
        self.needs = needs
        self.isAnimated = animated
        self.minimumOS = minimumOS
        self.degrade = degrade
        self.render = render
    }

    func param(_ id: String) -> WGFilterParam? {
        return self.params.first(where: { $0.id == id })
    }

    var needsImage: Bool {
        return self.params.contains(where: { $0.kind == .image })
    }

    /// The layer the studio adds: every parameter at its default.
    func makeEffect() -> WGMaskEffect {
        var params: [String: WGMaskParamValue] = [:]
        for param in self.params where param.kind != .image {
            params[param.id] = param.defaultValue
        }
        return WGMaskEffect.filter(self.id, params: params)
    }
}

private func slider(_ id: String, _ min: Double, _ max: Double, _ value: Double, step: Double = 0.01) -> WGFilterParam {
    return WGFilterParam(id: id, kind: .slider(min: min, max: max, step: step), defaultValue: .number(value))
}

private func toggle(_ id: String, _ value: Bool) -> WGFilterParam {
    return WGFilterParam(id: id, kind: .toggle, defaultValue: .bool(value))
}

private func color(_ id: String, _ hex: String) -> WGFilterParam {
    return WGFilterParam(id: id, kind: .color, defaultValue: .color(hex))
}

private func point(_ id: String, _ x: Double = 0.5, _ y: Double = 0.5) -> WGFilterParam {
    return WGFilterParam(id: id, kind: .point, defaultValue: .point(CGPoint(x: x, y: y)))
}

private func anchorParam(_ value: WGMaskAnchor) -> WGFilterParam {
    return WGFilterParam(id: "anchor", kind: .anchor, defaultValue: .text(value.rawValue))
}

private let blendParam = WGFilterParam(id: "blendMode", kind: .blendMode, defaultValue: .text(WGMaskBlendMode.normal.rawValue))
private let imageParam = WGFilterParam(id: "asset", kind: .image, defaultValue: .unknown)

enum WGFilterCatalog {
    static let all: [WGFilterDescriptor] = WGFilterCatalog.film + WGFilterCatalog.tone + WGFilterCatalog.light + WGFilterCatalog.retro + WGFilterCatalog.art + WGFilterCatalog.distort + WGFilterCatalog.blur + WGFilterCatalog.face + WGFilterCatalog.overlay

    private static let index: [String: WGFilterDescriptor] = {
        var result: [String: WGFilterDescriptor] = [:]
        for descriptor in WGFilterCatalog.all {
            result[descriptor.id] = descriptor
        }
        return result
    }()

    static func descriptor(_ id: String) -> WGFilterDescriptor? {
        return WGFilterCatalog.index[id]
    }

    static func descriptors(in category: WGFilterCategory) -> [WGFilterDescriptor] {
        return WGFilterCatalog.all.filter { $0.category == category }
    }

    /// What one effect needs from Vision (disabled effects need nothing).
    static func visionNeeds(of effect: WGMaskEffect) -> WGVisionNeeds {
        if !effect.isEnabled {
            return []
        }
        switch effect.type {
        case .sticker2d, .emojiHead, .faceDistort:
            return .face
        case .blur, .pixelate:
            return effect.anchor == .fullFrame ? [] : .face
        case .colorFilter, .glitchRGB:
            return []
        case .backgroundReplace:
            return .segmentation
        case .filter:
            guard let id = effect.filterId, let descriptor = WGFilterCatalog.descriptor(id) else {
                return []
            }
            // Anchor-aware overlays need a face only when they are anchored to one.
            if descriptor.id == "overlay.userImage" || descriptor.id == "overlay.emoji" {
                return (effect.effectiveAnchor ?? (descriptor.id == "overlay.userImage" ? .fullFrame : .face)) == .fullFrame ? [] : .face
            }
            return descriptor.needs
        }
    }

    // MARK: - Film (colour cubes)

    private static func look(_ name: String, intensity: Double, cost: Int = 2, extra: [WGFilterParam] = [], render extraRender: ((WGFilterContext, CIImage) -> CIImage)? = nil) -> WGFilterDescriptor {
        return WGFilterDescriptor("film." + name, .film, cost: cost, fuses: extra.isEmpty, params: [slider("intensity", 0.0, 1.0, intensity)] + extra) { c in
            guard let look = WGFilmLook.named(name) else {
                return c.source
            }
            let result = WGFilmLUT.apply(look, to: c.source, intensity: c.number("intensity"), extent: c.extent)
            return extraRender?(c, result) ?? result
        }
    }

    private static let film: [WGFilterDescriptor] = [
        WGFilterCatalog.look("portra", intensity: 1.0),
        WGFilterCatalog.look("kodachrome", intensity: 1.0),
        WGFilterCatalog.look("ektar", intensity: 1.0),
        WGFilterCatalog.look("provia", intensity: 1.0),
        WGFilterCatalog.look("velvia", intensity: 1.0),
        WGFilterCatalog.look("cinema", intensity: 0.85),
        WGFilterCatalog.look("bleach", intensity: 0.80),
        WGFilterCatalog.look("crossProcess", intensity: 0.90),
        WGFilterCatalog.look("polaroid", intensity: 1.0),
        WGFilterCatalog.look("lomo", intensity: 1.0, cost: 3, extra: [slider("vignette", 0.0, 1.0, 0.5)], render: { c, image in
            return WGMaskOps.apply("CIVignette", image, [kCIInputIntensityKey: c.number("vignette") * 1.6, kCIInputRadiusKey: 1.2], clamp: false, extent: c.extent)
        }),
        WGFilterCatalog.look("noirFilm", intensity: 1.0, extra: [slider("contrast", 0.8, 2.0, 1.35)], render: { c, image in
            return WGMaskOps.apply("CIColorControls", image, [kCIInputContrastKey: c.number("contrast")], clamp: false, extent: c.extent)
        }),
        WGFilterCatalog.look("archive", intensity: 0.90),
        WGFilterCatalog.look("fadedSummer", intensity: 0.85),
        WGFilterCatalog.look("winterAsh", intensity: 0.90),
        WGFilterCatalog.look("neonNight", intensity: 1.0),
        WGFilterCatalog.look("infrared", intensity: 1.0),
        WGFilterCatalog.look("autumn", intensity: 0.90),
        WGFilterCatalog.look("pastel", intensity: 0.80),
        WGFilterDescriptor("film.mono", .film, cost: 1, fuses: true, params: [color("color", "#8A8A8A"), slider("intensity", 0.0, 1.0, 1.0)]) { c in
            return c.apply("CIColorMonochrome", [kCIInputColorKey: c.color("color"), kCIInputIntensityKey: c.number("intensity")])
        },
        WGFilterDescriptor("film.custom", .film, cost: 2, fuses: true, params: [
            slider("exposure", -2.0, 2.0, 0.0), slider("contrast", 0.5, 2.0, 1.0), slider("saturation", 0.0, 2.0, 1.0),
            slider("liftR", -0.2, 0.2, 0.0, step: 0.005), slider("liftG", -0.2, 0.2, 0.0, step: 0.005), slider("liftB", -0.2, 0.2, 0.0, step: 0.005),
            slider("gammaR", 0.5, 2.0, 1.0), slider("gammaG", 0.5, 2.0, 1.0), slider("gammaB", 0.5, 2.0, 1.0),
            slider("gainR", 0.5, 1.5, 1.0), slider("gainG", 0.5, 1.5, 1.0), slider("gainB", 0.5, 1.5, 1.0),
            color("shadowTint", "#000000"), color("highlightTint", "#FFFFFF"), slider("splitAmount", 0.0, 1.0, 0.0),
            slider("intensity", 0.0, 1.0, 1.0)
        ]) { c in
            let shadow = c.color("shadowTint")
            let highlight = c.color("highlightTint")
            var look = WGFilmLook()
            look.exposure = c.number("exposure")
            look.contrast = c.number("contrast")
            look.saturation = c.number("saturation")
            look.lift = [c.number("liftR"), c.number("liftG"), c.number("liftB")]
            look.gamma = [c.number("gammaR"), c.number("gammaG"), c.number("gammaB")]
            look.gain = [c.number("gainR"), c.number("gainG"), c.number("gainB")]
            look.shadowTint = [Double(shadow.red), Double(shadow.green), Double(shadow.blue)]
            look.highlightTint = [Double(highlight.red), Double(highlight.green), Double(highlight.blue)]
            look.split = c.number("splitAmount")
            return WGFilmLUT.apply(look, to: c.source, intensity: c.number("intensity"), extent: c.extent)
        }
    ]

    // MARK: - Tone

    private static let tone: [WGFilterDescriptor] = [
        WGFilterDescriptor("tone.exposure", .tone, cost: 1, fuses: true, params: [slider("ev", -3.0, 3.0, 0.0)]) { c in
            return c.apply("CIExposureAdjust", [kCIInputEVKey: c.number("ev")])
        },
        WGFilterDescriptor("tone.controls", .tone, cost: 1, fuses: true, params: [slider("brightness", -0.5, 0.5, 0.0), slider("contrast", 0.25, 2.0, 1.0), slider("saturation", 0.0, 2.0, 1.0)]) { c in
            return c.apply("CIColorControls", [kCIInputBrightnessKey: c.number("brightness"), kCIInputContrastKey: c.number("contrast"), kCIInputSaturationKey: c.number("saturation")])
        },
        WGFilterDescriptor("tone.vibrance", .tone, cost: 1, fuses: true, params: [slider("amount", -1.0, 1.0, 0.0)]) { c in
            return c.apply("CIVibrance", ["inputAmount": c.number("amount")])
        },
        WGFilterDescriptor("tone.gamma", .tone, cost: 1, fuses: true, params: [slider("power", 0.3, 3.0, 1.0)]) { c in
            return c.apply("CIGammaAdjust", ["inputPower": c.number("power")])
        },
        WGFilterDescriptor("tone.temperature", .tone, cost: 1, fuses: true, params: [slider("temp", 3000.0, 10000.0, 6500.0, step: 50.0), slider("tint", -150.0, 150.0, 0.0, step: 1.0)]) { c in
            return c.apply("CITemperatureAndTint", ["inputNeutral": CIVector(x: 6500.0, y: 0.0), "inputTargetNeutral": CIVector(x: CGFloat(c.number("temp")), y: CGFloat(c.number("tint")))])
        },
        WGFilterDescriptor("tone.whitePoint", .tone, cost: 1, fuses: true, params: [color("color", "#FFFFFF")]) { c in
            return c.apply("CIWhitePointAdjust", [kCIInputColorKey: c.color("color")])
        },
        WGFilterDescriptor("tone.hue", .tone, cost: 1, fuses: true, params: [slider("angle", -Double.pi, Double.pi, 0.0)]) { c in
            return c.apply("CIHueAdjust", [kCIInputAngleKey: c.number("angle")])
        },
        WGFilterDescriptor("tone.curve", .tone, cost: 1, fuses: true, params: [WGFilterParam(id: "points", kind: .curve5, defaultValue: .numbers([0.0, 0.25, 0.5, 0.75, 1.0]))]) { c in
            var values = c.numbers("points")
            if values.count != 5 {
                values = [0.0, 0.25, 0.5, 0.75, 1.0]
            }
            var parameters: [String: Any] = [:]
            for i in 0 ..< 5 {
                parameters["inputPoint\(i)"] = CIVector(x: CGFloat(i) / 4.0, y: CGFloat(max(0.0, min(1.0, values[i]))))
            }
            return c.apply("CIToneCurve", parameters)
        },
        WGFilterDescriptor("tone.rgbCurves", .tone, cost: 1, fuses: true, params: [WGFilterParam(id: "curves", kind: .curveRGB, defaultValue: .numbers([0.0, 0.25, 0.5, 0.75, 1.0, 0.0, 0.25, 0.5, 0.75, 1.0, 0.0, 0.25, 0.5, 0.75, 1.0]))]) { c in
            var values = c.numbers("curves")
            if values.count != 15 {
                values = [0.0, 0.25, 0.5, 0.75, 1.0, 0.0, 0.25, 0.5, 0.75, 1.0, 0.0, 0.25, 0.5, 0.75, 1.0]
            }
            // 32 samples of each channel's piecewise-linear curve.
            var table: [Float] = []
            for sample in 0 ..< 32 {
                let x = Double(sample) / 31.0
                for channel in 0 ..< 3 {
                    let position = x * 4.0
                    let lower = min(3, Int(position))
                    let t = position - Double(lower)
                    let a = values[channel * 5 + lower]
                    let b = values[channel * 5 + lower + 1]
                    table.append(Float(max(0.0, min(1.0, a + (b - a) * t))))
                }
            }
            let data = table.withUnsafeBufferPointer { Data(buffer: $0) }
            return c.apply("CIColorCurves", ["inputCurvesData": data, "inputCurvesDomain": CIVector(x: 0.0, y: 1.0), "inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()])
        },
        WGFilterDescriptor("tone.highlightShadow", .tone, cost: 14, params: [slider("radius", 0.0, 12.0, 3.0), slider("shadows", -1.0, 1.0, 0.0), slider("highlights", 0.0, 1.0, 1.0)], degrade: [.scale("radius", 0.5), .disable]) { c in
            return c.apply("CIHighlightShadowAdjust", [kCIInputRadiusKey: c.number("radius"), "inputShadowAmount": c.number("shadows"), "inputHighlightAmount": c.number("highlights")])
        },
        WGFilterDescriptor("tone.clamp", .tone, cost: 1, fuses: true, params: [slider("low", 0.0, 0.4, 0.0), slider("high", 0.6, 1.0, 1.0)]) { c in
            let low = CGFloat(c.number("low"))
            let high = CGFloat(c.number("high"))
            return c.apply("CIColorClamp", ["inputMinComponents": CIVector(x: low, y: low, z: low, w: 0.0), "inputMaxComponents": CIVector(x: high, y: high, z: high, w: 1.0)])
        },
        WGFilterDescriptor("tone.invert", .tone, cost: 1, fuses: true) { c in
            return c.apply("CIColorInvert")
        }
    ]

    // MARK: - Light

    private static let light: [WGFilterDescriptor] = [
        WGFilterDescriptor("light.bloom", .light, cost: 8, params: [slider("radius", 1.0, 30.0, 10.0), slider("intensity", 0.0, 1.0, 0.5)], degrade: [.scale("radius", 0.5), .disable]) { c in
            return c.apply("CIBloom", [kCIInputRadiusKey: c.number("radius"), kCIInputIntensityKey: c.number("intensity")], clamp: true)
        },
        WGFilterDescriptor("light.gloom", .light, cost: 8, params: [slider("radius", 1.0, 30.0, 10.0), slider("intensity", 0.0, 1.0, 0.5)], degrade: [.scale("radius", 0.5), .disable]) { c in
            return c.apply("CIGloom", [kCIInputRadiusKey: c.number("radius"), kCIInputIntensityKey: c.number("intensity")], clamp: true)
        },
        WGFilterDescriptor("light.vignette", .light, cost: 1, params: [slider("intensity", 0.0, 2.0, 0.8), slider("radius", 0.0, 2.0, 1.2)]) { c in
            return c.apply("CIVignette", [kCIInputIntensityKey: c.number("intensity"), kCIInputRadiusKey: c.number("radius")])
        },
        WGFilterDescriptor("light.vignetteAt", .light, cost: 2, params: [point("center"), slider("radius", 0.0, 1.5, 0.7), slider("intensity", 0.0, 2.0, 1.0), slider("falloff", 0.0, 1.0, 0.5)]) { c in
            return c.apply("CIVignetteEffect", [kCIInputCenterKey: c.point("center"), kCIInputRadiusKey: c.fraction("radius"), kCIInputIntensityKey: c.number("intensity"), "inputFalloff": c.number("falloff")])
        },
        WGFilterDescriptor("light.vignetteFace", .light, cost: 2, needs: .face, params: [slider("radius", 0.4, 1.5, 0.8), slider("intensity", 0.0, 2.0, 1.0), slider("falloff", 0.0, 1.0, 0.5)]) { c in
            guard let face = c.face else {
                return c.source
            }
            return c.apply("CIVignetteEffect", [kCIInputCenterKey: CIVector(x: face.bounds.midX, y: face.bounds.midY), kCIInputRadiusKey: Double(max(face.bounds.width, face.bounds.height)) * c.number("radius"), kCIInputIntensityKey: c.number("intensity"), "inputFalloff": c.number("falloff")])
        },
        WGFilterDescriptor("light.spot", .light, cost: 4, params: [point("position"), point("target", 0.5, 0.4), slider("brightness", 0.0, 6.0, 3.0), slider("concentration", 0.001, 1.0, 0.1, step: 0.001), color("color", "#FFFFFF")]) { c in
            let height = c.frame.shortSide * 1.2
            let position = c.point("position")
            let target = c.point("target")
            return c.apply("CISpotLight", ["inputLightPosition": CIVector(x: position.x, y: position.y, z: height), "inputLightPointsAt": CIVector(x: target.x, y: target.y, z: 0.0), "inputBrightness": c.number("brightness"), "inputConcentration": c.number("concentration"), kCIInputColorKey: c.color("color")])
        },
        WGFilterDescriptor("light.spotFace", .light, cost: 4, needs: .face, params: [slider("brightness", 0.0, 6.0, 3.0), slider("concentration", 0.001, 1.0, 0.12, step: 0.001), color("color", "#FFFFFF")]) { c in
            guard let face = c.face else {
                return c.source
            }
            let height = c.frame.shortSide * 1.2
            return c.apply("CISpotLight", ["inputLightPosition": CIVector(x: face.bounds.midX, y: face.bounds.midY + face.bounds.height, z: height), "inputLightPointsAt": CIVector(x: face.bounds.midX, y: face.bounds.midY, z: 0.0), "inputBrightness": c.number("brightness"), "inputConcentration": c.number("concentration"), kCIInputColorKey: c.color("color")])
        },
        WGFilterDescriptor("light.sunbeams", .light, cost: 10, params: [point("center", 0.5, 0.75), slider("sunRadius", 0.0, 0.5, 0.1), slider("striationRadius", 0.0, 3.0, 2.58), slider("striationStrength", 0.0, 3.0, 0.5), slider("striationContrast", 0.0, 5.0, 1.375), color("color", "#FFDD88"), slider("time", 0.0, 1.0, 0.0)], degrade: [.scale("striationStrength", 0.5), .disable]) { c in
            let generated = CIFilter(name: "CISunbeamsGenerator", parameters: [kCIInputCenterKey: c.point("center"), kCIInputColorKey: c.color("color"), "inputSunRadius": c.fraction("sunRadius"), "inputMaxStriationRadius": c.number("striationRadius"), "inputStriationStrength": c.number("striationStrength"), "inputStriationContrast": c.number("striationContrast"), kCIInputTimeKey: c.number("time")])?.outputImage
            return WGMaskOps.composite(generated, over: c.source, filter: "CIAdditionCompositing", extent: c.extent)
        },
        WGFilterDescriptor("light.halo", .light, cost: 9, params: [point("center"), slider("haloRadius", 0.0, 0.5, 0.2), slider("haloWidth", 0.0, 0.3, 0.06), slider("striationStrength", 0.0, 2.0, 0.5), color("color", "#FFFFFF")], degrade: [.disable]) { c in
            let generated = CIFilter(name: "CILenticularHaloGenerator", parameters: [kCIInputCenterKey: c.point("center"), kCIInputColorKey: c.color("color"), "inputHaloRadius": c.fraction("haloRadius"), "inputHaloWidth": c.fraction("haloWidth"), "inputStriationStrength": c.number("striationStrength"), "inputStriationContrast": 1.0])?.outputImage
            return WGMaskOps.composite(generated, over: c.source, filter: "CIScreenBlendMode", extent: c.extent)
        },
        WGFilterDescriptor("light.star", .light, cost: 6, params: [point("center"), slider("radius", 0.0, 0.3, 0.08), slider("crossScale", 0.0, 30.0, 15.0), slider("crossAngle", -Double.pi, Double.pi, 0.6), slider("crossOpacity", -8.0, 0.0, -2.0), slider("crossWidth", 0.0, 10.0, 2.5), color("color", "#FFFFFF")], degrade: [.disable]) { c in
            let generated = CIFilter(name: "CIStarShineGenerator", parameters: [kCIInputCenterKey: c.point("center"), kCIInputColorKey: c.color("color"), kCIInputRadiusKey: c.fraction("radius"), "inputCrossScale": c.number("crossScale"), "inputCrossAngle": c.number("crossAngle"), "inputCrossOpacity": c.number("crossOpacity"), "inputCrossWidth": c.number("crossWidth"), "inputEpsilon": -2.0])?.outputImage
            return WGMaskOps.composite(generated, over: c.source, filter: "CIAdditionCompositing", extent: c.extent)
        }
    ]

    // MARK: - Retro

    private static func screen(_ id: String, _ filterName: String, cost: Int, hasAngle: Bool) -> WGFilterDescriptor {
        var params = [point("center")]
        if hasAngle {
            params.append(slider("angle", 0.0, Double.pi, 0.0))
        }
        params.append(slider("width", 1.0, 50.0, 6.0))
        params.append(slider("sharpness", 0.0, 1.0, 0.7))
        return WGFilterDescriptor(id, .retro, cost: cost, params: params, degrade: [.scale("width", 1.8), .disable]) { c in
            var parameters: [String: Any] = [kCIInputCenterKey: c.point("center"), kCIInputWidthKey: c.number("width"), kCIInputSharpnessKey: c.number("sharpness")]
            if hasAngle {
                parameters[kCIInputAngleKey] = c.number("angle")
            }
            return c.apply(filterName, parameters)
        }
    }

    private static let retro: [WGFilterDescriptor] = [
        WGFilterDescriptor("retro.grain", .retro, cost: 4, animated: true, params: [slider("amount", 0.0, 1.0, 0.25), slider("size", 0.5, 4.0, 1.0), toggle("animate", true)], degrade: [.set("animate", .bool(false)), .disable]) { c in
            var noise = WGMaskOps.noise().transformed(by: CGAffineTransform(scaleX: CGFloat(c.number("size")), y: CGFloat(c.number("size"))))
            if c.bool("animate") {
                let t = c.frame.time * 30.0
                noise = noise.transformed(by: CGAffineTransform(translationX: CGFloat(Int(t * 137.0) % 251), y: CGFloat(Int(t * 211.0) % 241)))
            }
            let overlaid = noise.cropped(to: c.extent).applyingFilter("CIOverlayBlendMode", parameters: [kCIInputBackgroundImageKey: c.source]).cropped(to: c.extent)
            return WGMaskOps.mix(base: c.source, overlay: overlaid, amount: c.number("amount"), extent: c.extent)
        },
        WGFilterDescriptor("retro.dither", .retro, cost: 2, minimumOS: 14, params: [slider("intensity", 0.0, 3.0, 1.0)]) { c in
            return c.apply("CIDither", [kCIInputIntensityKey: c.number("intensity")])
        },
        WGFilterDescriptor("retro.posterize", .retro, cost: 1, fuses: true, params: [slider("levels", 2.0, 30.0, 6.0, step: 1.0)]) { c in
            return c.apply("CIColorPosterize", ["inputLevels": c.number("levels")])
        },
        WGFilterDescriptor("retro.rgbSplit", .retro, cost: 5, params: [slider("offset", 0.0, 20.0, 5.0, step: 0.5), slider("angle", -Double.pi, Double.pi, 0.0)]) { c in
            return WGMaskOps.rgbSplit(c.source, offset: CGFloat(c.number("offset")), angle: CGFloat(c.number("angle")), extent: c.extent)
        },
        WGFilterDescriptor("retro.vhs", .retro, cost: 9, params: [slider("intensity", 0.0, 1.0, 0.6)], degrade: [.disable]) { c in
            let intensity = c.number("intensity")
            var image = WGMaskOps.rgbSplit(c.source, offset: CGFloat(8.0 * intensity), angle: 0.0, extent: c.extent)
            if let look = WGFilmLook.named("archive") {
                image = WGFilmLUT.apply(look, to: image, intensity: 0.7 * intensity, extent: c.extent)
            }
            return WGMaskOps.scanlines(image, width: 3.0, sharpness: 0.6, opacity: 0.35 * intensity, extent: c.extent)
        },
        WGFilterDescriptor("retro.scanlines", .retro, cost: 3, params: [slider("width", 1.0, 12.0, 3.0), slider("sharpness", 0.0, 1.0, 0.6), slider("opacity", 0.0, 1.0, 0.25)]) { c in
            return WGMaskOps.scanlines(c.source, width: c.number("width"), sharpness: c.number("sharpness"), opacity: c.number("opacity"), extent: c.extent)
        },
        WGFilterDescriptor("retro.crt", .retro, cost: 12, params: [slider("curvature", 0.0, 0.4, 0.15), slider("scanOpacity", 0.0, 1.0, 0.3)], degrade: [.set("curvature", .number(0.0)), .disable]) { c in
            var image = c.source
            let curvature = c.number("curvature")
            if curvature > 0.001 {
                image = c.apply("CIBumpDistortion", [kCIInputCenterKey: c.center, kCIInputRadiusKey: Double(max(c.extent.width, c.extent.height)) * 0.75, kCIInputScaleKey: curvature], clamp: true)
            }
            image = WGMaskOps.scanlines(image, width: 3.0, sharpness: 0.7, opacity: c.number("scanOpacity"), extent: c.extent)
            return WGMaskOps.apply("CIVignette", image, [kCIInputIntensityKey: 0.9, kCIInputRadiusKey: 1.1], clamp: false, extent: c.extent)
        },
        WGFilterCatalog.screen("retro.halftoneDot", "CIDotScreen", cost: 7, hasAngle: true),
        WGFilterCatalog.screen("retro.halftoneLine", "CILineScreen", cost: 6, hasAngle: true),
        WGFilterCatalog.screen("retro.halftoneHatch", "CIHatchedScreen", cost: 7, hasAngle: true),
        WGFilterCatalog.screen("retro.halftoneCircle", "CICircularScreen", cost: 7, hasAngle: false),
        WGFilterDescriptor("retro.cmyk", .retro, cost: 16, heavy: true, params: [point("center"), slider("width", 1.0, 50.0, 6.0), slider("angle", 0.0, Double.pi, 0.0), slider("sharpness", 0.0, 1.0, 0.7), slider("gcr", 0.0, 1.0, 1.0), slider("ucr", 0.0, 1.0, 0.5)], degrade: [.scale("width", 1.8), .disable]) { c in
            return c.apply("CICMYKHalftone", [kCIInputCenterKey: c.point("center"), kCIInputWidthKey: c.number("width"), kCIInputAngleKey: c.number("angle"), kCIInputSharpnessKey: c.number("sharpness"), "inputGCR": c.number("gcr"), "inputUCR": c.number("ucr")])
        }
    ]

    // MARK: - Art

    private static let art: [WGFilterDescriptor] = [
        WGFilterDescriptor("art.comic", .art, cost: 12, degrade: [.disable]) { c in
            return c.apply("CIComicEffect")
        },
        WGFilterDescriptor("art.crystallize", .art, cost: 22, heavy: true, params: [point("center"), slider("radius", 1.0, 30.0, 12.0)], degrade: [.scale("radius", 1.5), .disable]) { c in
            return c.apply("CICrystallize", [kCIInputCenterKey: c.point("center"), kCIInputRadiusKey: c.number("radius")], clamp: true)
        },
        WGFilterDescriptor("art.pointillize", .art, cost: 20, heavy: true, params: [point("center"), slider("radius", 1.0, 25.0, 8.0)], degrade: [.scale("radius", 1.5), .disable]) { c in
            return c.apply("CIPointillize", [kCIInputCenterKey: c.point("center"), kCIInputRadiusKey: c.number("radius")], clamp: true)
        },
        WGFilterDescriptor("art.hexPixel", .art, cost: 8, params: [point("center"), slider("scale", 2.0, 60.0, 12.0)], degrade: [.scale("scale", 1.6), .disable]) { c in
            return c.apply("CIHexagonalPixellate", [kCIInputCenterKey: c.point("center"), kCIInputScaleKey: c.number("scale")], clamp: true)
        },
        WGFilterDescriptor("art.pixelate", .art, cost: 5, params: [point("center"), slider("scale", 2.0, 60.0, 12.0)]) { c in
            return c.apply("CIPixellate", [kCIInputCenterKey: c.point("center"), kCIInputScaleKey: c.number("scale")], clamp: true)
        },
        WGFilterDescriptor("art.edgeWork", .art, cost: 14, params: [slider("radius", 0.1, 10.0, 1.0)], degrade: [.disable]) { c in
            return c.apply("CIEdgeWork", [kCIInputRadiusKey: c.number("radius")])
        },
        WGFilterDescriptor("art.lineArt", .art, cost: 15, params: [slider("noiseLevel", 0.0, 0.1, 0.07, step: 0.005), slider("sharpness", 0.0, 2.0, 0.71), slider("edgeIntensity", 0.0, 10.0, 1.0), slider("threshold", 0.0, 1.0, 0.1), slider("contrast", 0.25, 200.0, 50.0, step: 0.25)], degrade: [.disable]) { c in
            let lines = c.apply("CILineOverlay", ["inputNRNoiseLevel": c.number("noiseLevel"), "inputNRSharpness": c.number("sharpness"), "inputEdgeIntensity": c.number("edgeIntensity"), "inputThreshold": c.number("threshold"), "inputContrast": c.number("contrast")])
            return lines.composited(over: CIImage(color: CIColor(red: 1.0, green: 1.0, blue: 1.0)).cropped(to: c.extent)).cropped(to: c.extent)
        },
        WGFilterDescriptor("art.edgesGlow", .art, cost: 16, heavy: true, params: [slider("intensity", 0.0, 10.0, 1.0), slider("glow", 0.0, 1.0, 0.5)], degrade: [.set("glow", .number(0.0)), .disable]) { c in
            let edges = c.apply("CIEdges", [kCIInputIntensityKey: c.number("intensity")])
            let glow = c.number("glow")
            if glow < 0.01 {
                return edges
            }
            return WGMaskOps.apply("CIBloom", edges, [kCIInputRadiusKey: 8.0, kCIInputIntensityKey: glow], clamp: true, extent: c.extent)
        },
        WGFilterDescriptor("art.thermal", .art, cost: 2) { c in
            return c.apply("CIThermal")
        },
        WGFilterDescriptor("art.xray", .art, cost: 2) { c in
            return c.apply("CIXRay")
        },
        WGFilterDescriptor("art.falseColor", .art, cost: 1, fuses: true, params: [color("color0", "#001133"), color("color1", "#FF8800")]) { c in
            return c.apply("CIFalseColor", ["inputColor0": c.color("color0"), "inputColor1": c.color("color1")])
        },
        WGFilterDescriptor("art.spotColor", .art, cost: 3, params: [color("target", "#C04030"), color("replacement", "#C04030"), slider("closeness", 0.0, 1.0, 0.22), slider("contrast", 0.0, 1.0, 0.98)]) { c in
            let grey = CIColor(red: 0.5, green: 0.5, blue: 0.5)
            return c.apply("CISpotColor", ["inputCenterColor1": c.color("target"), "inputReplacementColor1": c.color("replacement"), "inputCloseness1": c.number("closeness"), "inputContrast1": c.number("contrast"), "inputCenterColor2": grey, "inputReplacementColor2": grey, "inputCloseness2": 0.0, "inputContrast2": 0.0, "inputCenterColor3": grey, "inputReplacementColor3": grey, "inputCloseness3": 0.0, "inputContrast3": 0.0])
        },
        WGFilterDescriptor("art.colorMap", .art, cost: 3, params: [color("colorA", "#0A0033"), color("colorB", "#C03080"), color("colorC", "#FFE080")]) { c in
            let gradient = WGFilterCatalog.gradientImage(c.color("colorA"), c.color("colorB"), c.color("colorC"))
            return c.apply("CIColorMap", ["inputGradientImage": gradient])
        },
        WGFilterDescriptor("art.morphSketch", .art, cost: 12, params: [slider("radius", 1.0, 8.0, 2.0), slider("contrast", 1.0, 4.0, 2.0)], degrade: [.disable]) { c in
            let gradient = c.apply("CIMorphologyGradient", [kCIInputRadiusKey: c.number("radius")], clamp: true)
            let inverted = WGMaskOps.apply("CIColorInvert", gradient, [:], clamp: false, extent: c.extent)
            return WGMaskOps.apply("CIColorControls", inverted, [kCIInputContrastKey: c.number("contrast"), kCIInputSaturationKey: 0.0], clamp: false, extent: c.extent)
        }
    ]

    /// 256×1 three-stop gradient (A → B → C).
    private static func gradientImage(_ a: CIColor, _ b: CIColor, _ c: CIColor) -> CIImage {
        let first = CIFilter(name: "CILinearGradient", parameters: ["inputPoint0": CIVector(x: 0.0, y: 0.0), "inputPoint1": CIVector(x: 128.0, y: 0.0), "inputColor0": a, "inputColor1": b])?.outputImage?.cropped(to: CGRect(x: 0.0, y: 0.0, width: 128.0, height: 1.0))
        let second = CIFilter(name: "CILinearGradient", parameters: ["inputPoint0": CIVector(x: 128.0, y: 0.0), "inputPoint1": CIVector(x: 256.0, y: 0.0), "inputColor0": b, "inputColor1": c])?.outputImage?.cropped(to: CGRect(x: 128.0, y: 0.0, width: 128.0, height: 1.0))
        guard let first, let second else {
            return CIImage(color: b).cropped(to: CGRect(x: 0.0, y: 0.0, width: 256.0, height: 1.0))
        }
        return second.composited(over: first).cropped(to: CGRect(x: 0.0, y: 0.0, width: 256.0, height: 1.0))
    }

    // MARK: - Distort

    private static func faceDistortion(_ id: String, _ filterName: String, scaleRange: ClosedRange<Double>) -> WGFilterDescriptor {
        return WGFilterDescriptor(id, .distort, cost: 4, needs: .face, params: [slider("radius", 0.3, 1.5, 0.6), slider("scale", scaleRange.lowerBound, scaleRange.upperBound, 0.4)]) { c in
            guard let face = c.face else {
                return c.source
            }
            let radius = max(face.bounds.width, face.bounds.height) * CGFloat(c.number("radius"))
            let center = CGPoint(x: face.bounds.midX, y: face.bounds.midY)
            let region = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2.0, height: radius * 2.0)
            return WGMaskOps.withinRegion(c.source, region: region, pad: radius * 0.4, extent: c.extent) { input in
                return WGMaskOps.apply(filterName, input, [kCIInputCenterKey: CIVector(x: center.x, y: center.y), kCIInputRadiusKey: radius, kCIInputScaleKey: c.number("scale")], clamp: false, extent: c.extent)
            }
        }
    }

    private static let distort: [WGFilterDescriptor] = [
        WGFilterDescriptor("distort.bulge", .distort, cost: 7, params: [point("center"), slider("radius", 0.1, 1.0, 0.4), slider("scale", -1.0, 1.0, 0.5)]) { c in
            return c.apply("CIBumpDistortion", [kCIInputCenterKey: c.point("center"), kCIInputRadiusKey: c.fraction("radius"), kCIInputScaleKey: c.number("scale")], clamp: true)
        },
        WGFilterCatalog.faceDistortion("distort.bulgeFace", "CIBumpDistortion", scaleRange: -1.0 ... 1.0),
        WGFilterDescriptor("distort.pinch", .distort, cost: 7, params: [point("center"), slider("radius", 0.1, 1.0, 0.4), slider("scale", 0.0, 1.0, 0.5)]) { c in
            return c.apply("CIPinchDistortion", [kCIInputCenterKey: c.point("center"), kCIInputRadiusKey: c.fraction("radius"), kCIInputScaleKey: c.number("scale")], clamp: true)
        },
        WGFilterCatalog.faceDistortion("distort.pinchFace", "CIPinchDistortion", scaleRange: 0.0 ... 1.0),
        WGFilterDescriptor("distort.twirl", .distort, cost: 7, params: [point("center"), slider("radius", 0.1, 1.0, 0.4), slider("angle", -Double.pi, Double.pi, Double.pi / 2.0)]) { c in
            return c.apply("CITwirlDistortion", [kCIInputCenterKey: c.point("center"), kCIInputRadiusKey: c.fraction("radius"), kCIInputAngleKey: c.number("angle")], clamp: true)
        },
        WGFilterDescriptor("distort.vortex", .distort, cost: 8, params: [point("center"), slider("radius", 0.1, 1.0, 0.5), slider("angle", -20.0, 20.0, 6.28)]) { c in
            return c.apply("CIVortexDistortion", [kCIInputCenterKey: c.point("center"), kCIInputRadiusKey: c.fraction("radius"), kCIInputAngleKey: c.number("angle")], clamp: true)
        },
        WGFilterDescriptor("distort.hole", .distort, cost: 6, params: [point("center"), slider("radius", 0.02, 0.4, 0.12)]) { c in
            return c.apply("CIHoleDistortion", [kCIInputCenterKey: c.point("center"), kCIInputRadiusKey: c.fraction("radius")], clamp: true)
        },
        WGFilterDescriptor("distort.splash", .distort, cost: 6, params: [point("center"), slider("radius", 0.05, 0.6, 0.2)]) { c in
            return c.apply("CICircleSplashDistortion", [kCIInputCenterKey: c.point("center"), kCIInputRadiusKey: c.fraction("radius")], clamp: true)
        },
        WGFilterDescriptor("distort.lightTunnel", .distort, cost: 9, params: [point("center"), slider("rotation", -Double.pi, Double.pi, 0.0), slider("radius", 0.02, 0.5, 0.15)], degrade: [.disable]) { c in
            return c.apply("CILightTunnel", [kCIInputCenterKey: c.point("center"), "inputRotation": c.number("rotation"), kCIInputRadiusKey: c.fraction("radius")], clamp: true)
        },
        WGFilterDescriptor("distort.glass", .distort, cost: 15, heavy: true, params: [point("center"), slider("scale", 1.0, 400.0, 120.0, step: 1.0)], degrade: [.scale("scale", 0.5), .disable]) { c in
            let texture = WGMaskOps.noise().applyingGaussianBlur(sigma: 6.0).cropped(to: CGRect(x: 0.0, y: 0.0, width: 512.0, height: 512.0))
            return c.apply("CIGlassDistortion", ["inputTexture": texture, kCIInputCenterKey: c.point("center"), kCIInputScaleKey: c.number("scale")], clamp: true)
        },
        WGFilterDescriptor("distort.selfDisplace", .distort, cost: 24, heavy: true, params: [slider("scale", 1.0, 200.0, 40.0, step: 1.0)], degrade: [.scale("scale", 0.5), .disable]) { c in
            let map = WGMaskOps.apply("CIPhotoEffectMono", c.source, [:], clamp: false, extent: c.extent).clampedToExtent().applyingGaussianBlur(sigma: 4.0).cropped(to: c.extent)
            return c.apply("CIDisplacementDistortion", ["inputDisplacementImage": map, kCIInputScaleKey: c.number("scale")], clamp: true)
        },
        WGFilterDescriptor("distort.kaleidoscope", .distort, cost: 11, params: [point("center"), slider("count", 2.0, 12.0, 6.0, step: 1.0), slider("angle", -Double.pi, Double.pi, 0.0)], degrade: [.scale("count", 0.5), .disable]) { c in
            return c.apply("CIKaleidoscope", ["inputCount": max(2.0, c.number("count")), kCIInputCenterKey: c.point("center"), kCIInputAngleKey: c.number("angle")], clamp: true)
        }
    ]

    // MARK: - Blur

    private static let blur: [WGFilterDescriptor] = [
        WGFilterDescriptor("blur.gaussianFrame", .blur, cost: 12, params: [slider("radius", 1.0, 60.0, 15.0)], degrade: [.scale("radius", 0.5), .disable]) { c in
            return WGMaskOps.blur(c.source, radius: c.number("radius"), region: nil, extent: c.extent)
        },
        WGFilterDescriptor("blur.gaussianFace", .blur, cost: 5, needs: .face, params: [slider("radius", 4.0, 90.0, 28.0)], degrade: [.scale("radius", 0.6)]) { c in
            guard let face = c.face else {
                return c.source
            }
            return WGMaskOps.blur(c.source, radius: c.number("radius"), region: face.bounds, extent: c.extent)
        },
        WGFilterDescriptor("blur.pixelFace", .blur, cost: 4, needs: .face, params: [slider("scale", 4.0, 60.0, 24.0)]) { c in
            guard let face = c.face else {
                return c.source
            }
            return WGMaskOps.pixelate(c.source, scale: c.number("scale"), region: face.bounds, extent: c.extent)
        },
        WGFilterDescriptor("blur.box", .blur, cost: 6, params: [slider("radius", 1.0, 40.0, 10.0)], degrade: [.scale("radius", 0.5), .disable]) { c in
            return c.apply("CIBoxBlur", [kCIInputRadiusKey: c.number("radius")], clamp: true)
        },
        WGFilterDescriptor("blur.disc", .blur, cost: 14, params: [slider("radius", 1.0, 30.0, 8.0)], degrade: [.scale("radius", 0.5), .disable]) { c in
            return c.apply("CIDiscBlur", [kCIInputRadiusKey: c.number("radius")], clamp: true)
        },
        WGFilterDescriptor("blur.bokeh", .blur, cost: 26, heavy: true, params: [slider("radius", 1.0, 20.0, 10.0), slider("ringAmount", 0.0, 1.0, 0.1), slider("ringSize", 0.0, 1.0, 0.1), slider("softness", 0.0, 10.0, 1.0)], degrade: [.scale("radius", 0.6), .disable]) { c in
            return c.apply("CIBokehBlur", [kCIInputRadiusKey: c.number("radius"), "inputRingAmount": c.number("ringAmount"), "inputRingSize": c.number("ringSize"), "inputSoftness": c.number("softness")], clamp: true)
        },
        WGFilterDescriptor("blur.motion", .blur, cost: 13, params: [slider("radius", 1.0, 40.0, 15.0), slider("angle", -Double.pi, Double.pi, 0.0)], degrade: [.scale("radius", 0.5), .disable]) { c in
            return c.apply("CIMotionBlur", [kCIInputRadiusKey: c.number("radius"), kCIInputAngleKey: c.number("angle")], clamp: true)
        },
        WGFilterDescriptor("blur.zoom", .blur, cost: 18, heavy: true, params: [point("center"), slider("amount", -60.0, 60.0, 20.0, step: 1.0)], degrade: [.scale("amount", 0.5), .disable]) { c in
            return c.apply("CIZoomBlur", [kCIInputCenterKey: c.point("center"), kCIInputAmountKey: c.number("amount")], clamp: true)
        },
        WGFilterDescriptor("blur.background", .blur, cost: 16, heavy: true, needs: .segmentation, minimumOS: 15, params: [slider("radius", 4.0, 50.0, 18.0)], degrade: [.scale("radius", 0.6), .disable]) { c in
            guard let mask = c.frame.segmentation else {
                return c.source
            }
            let blurred = WGMaskOps.blur(c.source, radius: c.number("radius"), region: nil, extent: c.extent)
            return WGMaskOps.masked(c.source, over: blurred, mask: mask, extent: c.extent)
        },
        WGFilterDescriptor("sharp.unsharp", .blur, cost: 7, params: [slider("radius", 0.5, 12.0, 2.5), slider("intensity", 0.0, 3.0, 0.5)], degrade: [.scale("radius", 0.5), .disable]) { c in
            return c.apply("CIUnsharpMask", [kCIInputRadiusKey: c.number("radius"), kCIInputIntensityKey: c.number("intensity")], clamp: true)
        }
    ]

    // MARK: - Face (landmarks)

    private static let face: [WGFilterDescriptor] = [
        WGFilterDescriptor("face.bigEyes", .face, cost: 6, needs: .landmarks, params: [slider("amount", 0.0, 1.0, 0.35), slider("radius", 1.0, 3.0, 1.6)], degrade: [.scale("amount", 0.5), .disable]) { c in
            return WGFaceEffects.eyes(c, amount: c.number("amount"))
        },
        WGFilterDescriptor("face.smallEyes", .face, cost: 6, needs: .landmarks, params: [slider("amount", 0.0, 1.0, 0.3), slider("radius", 1.0, 3.0, 1.6)], degrade: [.scale("amount", 0.5), .disable]) { c in
            return WGFaceEffects.eyes(c, amount: -c.number("amount"))
        },
        WGFilterDescriptor("face.slimFace", .face, cost: 8, needs: .landmarks, params: [slider("amount", 0.0, 1.0, 0.3)], degrade: [.scale("amount", 0.5), .disable]) { c in
            return WGFaceEffects.width(c, amount: c.number("amount"))
        },
        WGFilterDescriptor("face.wideFace", .face, cost: 8, needs: .landmarks, params: [slider("amount", 0.0, 1.0, 0.3)], degrade: [.scale("amount", 0.5), .disable]) { c in
            return WGFaceEffects.width(c, amount: -c.number("amount"))
        },
        WGFilterDescriptor("face.longChin", .face, cost: 7, needs: .landmarks, params: [slider("amount", 0.0, 1.0, 0.3), slider("radius", 0.4, 1.2, 0.6)], degrade: [.scale("amount", 0.5), .disable]) { c in
            return WGFaceEffects.chin(c)
        },
        WGFilterDescriptor("face.bigNose", .face, cost: 5, needs: .landmarks, params: [slider("amount", -1.0, 1.0, 0.4), slider("radius", 0.5, 2.0, 1.0)], degrade: [.scale("amount", 0.5), .disable]) { c in
            return WGFaceEffects.nose(c)
        },
        WGFilterDescriptor("face.bigMouth", .face, cost: 5, needs: .landmarks, params: [slider("amount", -1.0, 1.0, 0.35), slider("radius", 0.5, 2.0, 1.0)], degrade: [.scale("amount", 0.5), .disable]) { c in
            return WGFaceEffects.mouth(c)
        },
        WGFilterDescriptor("face.skinSmooth", .face, cost: 11, needs: .landmarks, params: [slider("amount", 0.0, 1.0, 0.5), toggle("keepDetail", true)], degrade: [.set("keepDetail", .bool(false)), .scale("amount", 0.5), .disable]) { c in
            return WGFaceEffects.skinSmooth(c)
        },
        WGFilterDescriptor("face.skinTone", .face, cost: 4, needs: .landmarks, params: [slider("warmth", -1.0, 1.0, 0.2), slider("evenness", 0.0, 1.0, 0.4)], degrade: [.disable]) { c in
            return WGFaceEffects.skinTone(c)
        },
        WGFilterDescriptor("face.lipstick", .face, cost: 5, needs: .landmarks, params: [color("color", "#C8304A"), slider("opacity", 0.0, 1.0, 0.6), slider("gloss", 0.0, 1.0, 0.2)], degrade: [.disable]) { c in
            return WGFaceEffects.lipstick(c)
        },
        WGFilterDescriptor("face.swapImage", .face, cost: 6, needs: .landmarks, params: [imageParam, slider("scale", 0.6, 2.0, 1.0), slider("offsetX", -0.5, 0.5, 0.0), slider("offsetY", -0.5, 0.5, 0.0), slider("feather", 0.0, 0.5, 0.15), slider("colorMatch", 0.0, 1.0, 0.35), slider("opacity", 0.0, 1.0, 1.0), toggle("followRoll", true), blendParam], degrade: [.set("colorMatch", .number(0.0)), .disable]) { c in
            return WGFaceEffects.swapImage(c)
        },
        WGFilterDescriptor("face.sticker", .face, cost: 3, needs: .landmarks, params: [imageParam, anchorParam(.face), slider("scale", 0.2, 3.0, 1.0), slider("offsetX", -1.0, 1.0, 0.0), slider("offsetY", -1.0, 1.0, 0.0), slider("rotation", -Double.pi, Double.pi, 0.0), slider("opacity", 0.0, 1.0, 1.0), toggle("rotateWithHead", true), blendParam]) { c in
            return WGFaceEffects.sticker(c)
        }
    ]

    // MARK: - Overlay

    private static let overlay: [WGFilterDescriptor] = [
        WGFilterDescriptor("overlay.userImage", .overlay, cost: 3, needs: .face, params: [imageParam, anchorParam(.fullFrame), slider("scale", 0.05, 4.0, 1.0), slider("offsetX", -1.0, 1.0, 0.0), slider("offsetY", -1.0, 1.0, 0.0), slider("rotation", -Double.pi, Double.pi, 0.0), slider("opacity", 0.0, 1.0, 1.0), toggle("fill", true), toggle("rotateWithHead", false), blendParam]) { c in
            return WGFaceEffects.imageLayer(c)
        },
        WGFilterDescriptor("overlay.emoji", .overlay, cost: 2, needs: .face, params: [WGFilterParam(id: "emoji", kind: .emoji, defaultValue: .text("🙂")), anchorParam(.face), slider("scale", 0.2, 3.0, 1.2)]) { c in
            guard let rect = WGMaskOps.anchorRect(c.anchor, face: c.face, extent: c.extent) else {
                return c.source
            }
            let scale = CGFloat(c.number("scale"))
            let inflated = rect.insetBy(dx: -rect.width * (scale - 1.0) / 2.0, dy: -rect.height * (scale - 1.0) / 2.0)
            return WGMaskOps.emojiHead(c.source, emoji: c.text("emoji"), rect: inflated, extent: c.extent)
        },
        WGFilterDescriptor("overlay.colorFill", .overlay, cost: 1, params: [color("color", "#000000"), slider("opacity", 0.0, 1.0, 0.3), blendParam]) { c in
            let fill = CIImage(color: c.color("color")).cropped(to: c.extent)
            let mode = WGMaskBlendMode(rawValue: c.text("blendMode")) ?? .normal
            return WGMaskOps.blend(layer: fill, over: c.source, mode: mode, opacity: c.number("opacity"), extent: c.extent)
        }
    ]
}
