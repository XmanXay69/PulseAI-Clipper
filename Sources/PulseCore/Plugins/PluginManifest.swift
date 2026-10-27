import Foundation

/// A plugin (#495) is a folder in Application Support/PULSE/Plugins with a `plugin.json`:
///
/// - an **effect** plugin names a chain of Core Image filters (from a safe list) with numeric inputs, some of
///   them exposed as sliders in the inspector;
/// - a **signal** plugin names a command that receives JSON about the recording on stdin and prints events
///   (`[{"time": 312.4, "kind": "kill", "text": "…"}]`) that score like banners.
public struct PluginManifest: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case effect, signal
    }

    /// A slider the inspector shows; `$key` in a filter input reads its value.
    public struct Parameter: Codable, Hashable, Sendable {
        public var key: String
        public var name: String
        public var min: Double
        public var max: Double
        public var `default`: Double

        public init(key: String, name: String, min: Double, max: Double, default value: Double) {
            self.key = key
            self.name = name
            self.min = min
            self.max = max
            self.default = value
        }
    }

    /// One Core Image filter: its name and numeric inputs (a number as text, or "$key" for a parameter).
    public struct FilterStep: Codable, Hashable, Sendable {
        public var filter: String
        public var inputs: [String: String]

        public init(filter: String, inputs: [String: String] = [:]) {
            self.filter = filter
            self.inputs = inputs
        }
    }

    public var id: String
    public var name: String
    public var version: String
    public var kind: Kind
    public var author: String?
    public var description: String?
    /// SF Symbol for menus.
    public var symbol: String?
    public var parameters: [Parameter]?
    /// Effect plugins: the filters, in order.
    public var filters: [FilterStep]?
    /// Signal plugins: the command and its arguments; a relative command runs from the plugin's folder.
    public var command: [String]?

    public init(id: String, name: String, version: String = "1.0", kind: Kind, author: String? = nil, description: String? = nil,
                symbol: String? = nil, parameters: [Parameter]? = nil, filters: [FilterStep]? = nil, command: [String]? = nil) {
        self.id = id
        self.name = name
        self.version = version
        self.kind = kind
        self.author = author
        self.description = description
        self.symbol = symbol
        self.parameters = parameters
        self.filters = filters
        self.command = command
    }

    public var symbolName: String { symbol ?? (kind == .effect ? "puzzlepiece.extension" : "waveform.path.ecg") }

    /// The sliders' defaults, keyed.
    public var defaultParameters: [String: Double] {
        Dictionary((parameters ?? []).map { ($0.key, $0.default) }, uniquingKeysWith: { a, _ in a })
    }
}

public enum PluginLoader {
    public static let manifestName = "plugin.json"

    /// Core Image filters a plugin may use: colour, blur, stylize — nothing that reads files or the network.
    public static let allowedFilters: Set<String> = [
        "CIColorControls", "CIExposureAdjust", "CIGammaAdjust", "CIHueAdjust", "CIVibrance", "CITemperatureAndTint", "CIWhitePointAdjust",
        "CISepiaTone", "CIColorMonochrome", "CIColorInvert", "CIColorPosterize", "CIPhotoEffectChrome", "CIPhotoEffectFade",
        "CIPhotoEffectInstant", "CIPhotoEffectMono", "CIPhotoEffectNoir", "CIPhotoEffectProcess", "CIPhotoEffectTonal", "CIPhotoEffectTransfer",
        "CIHighlightShadowAdjust", "CIGaussianBlur", "CIBoxBlur", "CIDiscBlur", "CIMotionBlur", "CIZoomBlur", "CIBloom", "CIGloom",
        "CIUnsharpMask", "CISharpenLuminance", "CINoiseReduction", "CIVignette", "CIVignetteEffect", "CIPixellate", "CIHexagonalPixellate",
        "CICrystallize", "CIPointillize", "CIComicEffect", "CIEdges", "CIEdgeWork", "CILineOverlay", "CIKaleidoscope", "CITwirlDistortion",
        "CIPinchDistortion", "CIBumpDistortion", "CIHoleDistortion", "CICircularWrap", "CIDotScreen", "CIHatchedScreen", "CILineScreen",
        "CICMYKHalftone", "CIColorClamp", "CIMorphologyMaximum", "CIMorphologyMinimum", "CIMedianFilter", "CISpotLight", "CIStraightenFilter",
    ]

    public static func parse(_ data: Data) -> PluginManifest? {
        try? JSONDecoder().decode(PluginManifest.self, from: data)
    }

    /// What stops a manifest from loading; empty = fine.
    public static func problems(in manifest: PluginManifest) -> [String] {
        var out: [String] = []
        if manifest.id.trimmingCharacters(in: .whitespaces).isEmpty { out.append("the id is empty") }
        if manifest.name.trimmingCharacters(in: .whitespaces).isEmpty { out.append("the name is empty") }
        let keys = Set((manifest.parameters ?? []).map(\.key))
        for p in manifest.parameters ?? [] where p.min > p.max { out.append("parameter “\(p.key)”: min is above max") }
        switch manifest.kind {
        case .effect:
            guard let filters = manifest.filters, !filters.isEmpty else { out.append("an effect needs at least one filter"); break }
            for step in filters {
                if !allowedFilters.contains(step.filter) { out.append("filter \(step.filter) isn't on the allowed list") }
                for (input, value) in step.inputs where value.hasPrefix("$") && !keys.contains(String(value.dropFirst())) {
                    out.append("\(step.filter).\(input) refers to a parameter “\(value)” that isn't declared")
                }
                for (input, value) in step.inputs where !value.hasPrefix("$") && Double(value) == nil {
                    out.append("\(step.filter).\(input) must be a number or $parameter")
                }
            }
        case .signal:
            if (manifest.command ?? []).isEmpty { out.append("a signal plugin needs a command") }
        }
        return out
    }

    /// The numeric inputs of a step with `$key` references filled from `values` (then the manifest's defaults).
    public static func resolve(_ step: PluginManifest.FilterStep, values: [String: Double], manifest: PluginManifest) -> [String: Double] {
        var out: [String: Double] = [:]
        let defaults = manifest.defaultParameters
        for (input, value) in step.inputs {
            if value.hasPrefix("$") {
                let key = String(value.dropFirst())
                if let v = values[key] ?? defaults[key] { out[input] = v }
            } else if let v = Double(value) {
                out[input] = v
            }
        }
        return out
    }

    /// Example manifests written into the plugins folder on first look, so the format is there to copy.
    public static let exampleEffect = PluginManifest(
        id: "example.warm-glow", name: "Warm Glow", version: "1.0", kind: .effect, author: "PULSE",
        description: "A soft bloom with a warm tint — an example effect plugin.", symbol: "sun.haze",
        parameters: [PluginManifest.Parameter(key: "glow", name: "Glow", min: 0, max: 1, default: 0.4),
                     PluginManifest.Parameter(key: "warmth", name: "Warmth", min: 5500, max: 8500, default: 7000)],
        filters: [PluginManifest.FilterStep(filter: "CIBloom", inputs: ["inputRadius": "14", "inputIntensity": "$glow"]),
                  PluginManifest.FilterStep(filter: "CITemperatureAndTint", inputs: ["inputTargetNeutral": "$warmth"])])

    public static let exampleSignal = PluginManifest(
        id: "example.every-five-minutes", name: "Every Five Minutes", version: "1.0", kind: .signal, author: "PULSE",
        description: "Prints a marker every five minutes — an example signal plugin (edit run.sh).", symbol: "clock",
        command: ["run.sh"])

    /// The script behind `exampleSignal`: reads the JSON on stdin, prints one event per five minutes.
    public static let exampleSignalScript = """
    #!/bin/sh
    # PULSE signal plugin example (#495). Input on stdin: {"mediaPath":…,"duration":…,"assetName":…,"transcript":[{"text":…,"start":…,"end":…}]}
    # Output on stdout: a JSON list of events {"time": seconds, "kind": kill|multiKill|death|objective|win|loss|clutch|achievement|levelUp, "text": …}
    duration=$(sed -n 's/.*"duration":\\([0-9.]*\\).*/\\1/p' | head -1)
    duration=${duration%%.*}
    printf '['
    t=300; first=1
    while [ "${t:-0}" -lt "${duration:-0}" ]; do
      [ $first -eq 1 ] || printf ','
      printf '{"time": %s, "kind": "objective", "text": "FIVE MINUTES"}' "$t"
      first=0; t=$((t + 300))
    done
    printf ']\\n'
    """
}
