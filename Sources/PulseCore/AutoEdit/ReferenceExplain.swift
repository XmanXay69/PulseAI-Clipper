import Foundation

extension ReferenceStyle {
    /// What copying this style changes and why (#368): one plain line per setting, from the measurements.
    public func explain(_ answers: ReferenceAnswers) -> [String] {
        let options = longFormOptions(answers)
        let tuning = options.style
        var lines: [String] = []
        let closely = answers.closeness == .closely
        lines.append("Energy: \(options.restraint.displayName.lowercased()) — the reference cuts \(String(format: "%.1f", cutsPerMinute)) times a minute (\(pace.displayName.lowercased()) pace)")
        if answers.copyPacing {
            let pauses = pauseRatio.map { "\(Int(($0 * 100).rounded())) % pauses" } ?? "no pause measure"
            lines.append("Pacing: \(options.silencePreset.displayName.lowercased()) silence cuts — \(pauses)\(closely ? "" : ", softened toward normal")")
        }
        if answers.copyZooms {
            if options.zooms, let spacing = tuning?.zoomSpacing, let scale = tuning?.zoomScale {
                lines.append("Zooms: every \(Int(spacing.rounded())) s at \(String(format: "%.2f", scale))× — the reference zooms \(String(format: "%.1f", zoomsPerMinute)) times a minute")
            } else {
                lines.append("Zooms: off — the reference hardly zooms (\(String(format: "%.1f", zoomsPerMinute)) a minute)")
            }
        }
        if answers.copyCaptions {
            if options.captions, let c = captions {
                lines.append("Captions: on, \(c.lineHeight >= 0.055 ? "big" : "small")\(c.uppercase ? " ALL-CAPS" : ""), at \(Int((c.positionY * 100).rounded())) % height — on screen \(Int((c.coverage * 100).rounded())) % of the time")
            } else {
                lines.append("Captions: \(options.captions ? "on" : "off") — the reference shows them \(Int(((captions?.coverage ?? 0) * 100).rounded())) % of the time")
            }
        }
        if answers.copyMusic {
            lines.append("Music: \(options.music ? "on" : "off") — a bed under \(Int((musicBed * 100).rounded())) % of the reference")
        }
        if answers.copySoundEffects {
            lines.append("Sound effects: \(options.soundEffects ? "on, about every \(Int((tuning?.whooshSpacing ?? 60).rounded())) s" : "off") — the reference uses \(String(format: "%.1f", effectsPerMinute)) a minute")
        }
        if answers.copyPopups {
            lines.append("Pop-ups: \(options.memes ? "on, about every \(Int((tuning?.memeSpacing ?? 90).rounded())) s" : "off") — the reference shows \(String(format: "%.1f", popupsPerMinute)) a minute")
        }
        if answers.copyTransitions {
            lines.append("Transitions: \(hasTransitions ? "fades like the reference" : "cuts only, like the reference")")
        }
        lines.append("Length: \(Timecode.duration(options.minimumLength)) – \(Timecode.duration(options.maximumLength))\(options.coldOpen ? ", opens cold" : "")")
        return lines
    }
}
