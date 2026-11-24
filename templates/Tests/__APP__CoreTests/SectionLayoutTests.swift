import Testing
@testable import {{APP}}Core

/// Where the panel puts the controls of each section, and where it puts the sections.
@Suite("Section layout")
struct SectionLayoutTests {

    private static func ids(_ row: SectionLayout.Row) -> [String] {
        switch row {
        case .cells(let parameters): parameters.map(\.identifier)
        case .wide(let parameter): [parameter.identifier]
        case .rule: []
        }
    }

    private static func section(_ title: String) -> ParameterSection {
        ParameterSection.all.first { $0.title == title }!
    }

    private static func knob(_ identifier: String) -> Parameter { TestKnobs.named(identifier) }

    @Test("A switch names its choices; a knob has none")
    func choices() {
        #expect(Self.knob("voicemode").choices == ["Poly", "Mono", "Legato"])
        #expect(Self.knob("lfostart").isChoice)
        #expect(Self.knob("volume").choices.isEmpty)
        #expect(!Self.knob("volume").isChoice && !Self.knob("octave").isChoice)
    }

    @Test("Every control of a section is laid out once, and nothing else")
    func everyControlOnce() {
        for section in ParameterSection.all {
            let laidOut = SectionLayout.of(section).rows.flatMap(Self.ids)
            #expect(laidOut.sorted() == section.parameters.map(\.identifier).sorted(), "\(section.title)")
        }
    }

    @Test("No row holds more cells than its section has columns")
    func rowsFit() {
        for section in ParameterSection.all {
            let layout = SectionLayout.of(section)
            for row in layout.rows {
                if case .cells(let parameters) = row { #expect(parameters.count <= layout.columns, "\(section.title)") }
            }
        }
    }

    // Without a plan of the instrument's, Master flows in two columns (the narrow card on the right):
    // its knobs in table order, then each switch in a row of its own.
    @Test("Master flows: its knobs two to a row, then its switches")
    func masterFlows() {
        let layout = SectionLayout.of(Self.section("Master"))
        #expect(layout.columns == 2)
        #expect(layout.rows.map(Self.ids) == [["volume", "pan"], ["tune", "octave"], ["bendup", "benddown"], ["glide", "lfo1rate"],
                                              ["lfo2rate", "velsens"], ["voicemode"], ["lfostart"], ["lfo1shape"], ["lfo2shape"]])
    }

    @Test("A section without a plan flows in reading order, three to a row, its switches in rows of their own")
    func unknownSection() {
        let parameters = ["volume", "voicemode", "pan", "tune", "lfostart", "octave"].map(Self.knob)
        let layout = SectionLayout.of(ParameterSection(title: "Elsewhere", parameters: parameters))
        #expect(layout.columns == 3)
        #expect(layout.rows.map(Self.ids) == [["volume", "pan", "tune"], ["octave"], ["voicemode"], ["lfostart"]])
    }

    // MARK: A section with a plan

    /// Made-up plans over the platform's knobs, as an instrument's mockup would draw them: a card
    /// of knobs in pairs, then the two LFO shapes and the two switches, each part under a rule; a
    /// card of three columns whose switch comes first; a card of four.
    private static let plans: [String: SectionLayout.Plan] = [
        "Mixer": (2, [.cells(["volume", "pan"]), .cells(["tune", "octave"]), .rule, .wide("lfo1shape"), .wide("lfo2shape"),
                      .rule, .wide("voicemode"), .wide("lfostart")]),
        "Pitch": (3, [.wide("voicemode"), .cells(["tune", "octave", "glide"]), .cells(["bendup", "benddown"])]),
        "Wide": (4, [.cells(["lfo1rate", "lfo2rate", "velsens", "glide"])]),
    ]

    /// A section of the platform's knobs under `title`.
    private static func planned(_ title: String, _ identifiers: [String]) -> ParameterSection {
        ParameterSection(title: title, parameters: identifiers.map(knob))
    }

    private static let mixer = planned("Mixer", ["volume", "pan", "tune", "octave", "lfo1shape", "lfo2shape", "voicemode", "lfostart"])
    private static let pitch = planned("Pitch", ["tune", "octave", "glide", "bendup", "benddown", "voicemode"])
    private static let wide = planned("Wide", ["lfo1rate", "lfo2rate", "velsens", "glide"])

    @Test("A planned section has the plan's columns and rows; its switches get rows of their own")
    func plannedRows() {
        let mixer = SectionLayout.of(Self.mixer, plans: Self.plans)
        #expect(mixer.columns == 2)
        #expect(mixer.rows.map(Self.ids) == [["volume", "pan"], ["tune", "octave"], [], ["lfo1shape"], ["lfo2shape"], [],
                                             ["voicemode"], ["lfostart"]])
        #expect(mixer.rows.last == .wide(Self.knob("lfostart")))
        let pitch = SectionLayout.of(Self.pitch, plans: Self.plans)
        #expect(pitch.columns == 3)
        #expect(pitch.rows.map(Self.ids) == [["voicemode"], ["tune", "octave", "glide"], ["bendup", "benddown"]])
        #expect(pitch.rows.first == .wide(Self.knob("voicemode")))
        #expect(SectionLayout.of(Self.wide, plans: Self.plans).columns == 4)
        for section in [Self.mixer, Self.pitch, Self.wide] {
            let layout = SectionLayout.of(section, plans: Self.plans)
            #expect(layout.rows.flatMap(Self.ids).sorted() == section.parameters.map(\.identifier).sorted(), "\(section.title)")
            for row in layout.rows {
                if case .cells(let parameters) = row { #expect(parameters.count <= layout.columns, "\(section.title)") }
            }
        }
    }

    @Test("A plan's rules part the knobs from the shapes, and the shapes from the switches")
    func plannedRules() {
        let mixer = SectionLayout.of(Self.mixer, plans: Self.plans).rows
        #expect(mixer.indices.filter { mixer[$0] == .rule } == [2, 5])
        #expect(!SectionLayout.of(Self.pitch, plans: Self.plans).rows.contains(.rule))
    }

    @Test("A control the engine adds to a planned section is not lost: it follows the plan's rows")
    func addedControl() {
        let added = ParameterSection(title: Self.pitch.title, parameters: Self.pitch.parameters + [Self.knob("velsens")])
        let laidOut = SectionLayout.of(added, plans: Self.plans).rows.flatMap(Self.ids)
        #expect(laidOut.last == "velsens")
        #expect(laidOut.count == Self.pitch.parameters.count + 1)
    }

    @Test("A planned control the section does not have is left out, and so is a row left empty")
    func missingPlannedControl() {
        let fewer = Self.planned("Pitch", ["tune", "glide", "voicemode"])
        #expect(SectionLayout.of(fewer, plans: Self.plans).rows.map(Self.ids) == [["voicemode"], ["tune", "glide"]])
    }

    @Test("A planned rule with nothing below it is left out")
    func ruleWithoutSwitches() {
        let knobsOnly = ParameterSection(title: Self.mixer.title, parameters: Self.mixer.parameters.filter { !$0.isChoice })
        let rows = SectionLayout.of(knobsOnly, plans: Self.plans).rows
        #expect(!rows.contains(.rule))
        #expect(rows.map(Self.ids) == [["volume", "pan"], ["tune", "octave"]])
        // Nor one with nothing above it.
        let switchesOnly = ParameterSection(title: Self.mixer.title, parameters: [Self.knob("voicemode")])
        #expect(SectionLayout.of(switchesOnly, plans: Self.plans).rows.map(Self.ids) == [["voicemode"]])
    }

    // MARK: The cards on the panel

    /// Planned rows of cards, as an instrument's mockup would place them.
    private static let plannedRows = [["Mixer", "Pitch"], ["Wide"]]
    private static let master = ParameterSection.all.first { $0.title == "Master" }!

    @Test("Planned rows of cards as the plan says, and Master the full height on the right")
    func plannedPanelRows() {
        let panel = PanelLayout.of([Self.wide, Self.pitch, Self.master, Self.mixer], plannedRows: Self.plannedRows)
        #expect(panel.rows.map { $0.map(\.title) } == [["Mixer", "Pitch"], ["Wide"]])
        #expect(panel.side?.title == "Master")
    }

    @Test("With planned rows, a section no row names joins the last row")
    func plannedPanelHoldsEverySection() {
        let extra = ParameterSection(title: "Elsewhere", parameters: [Self.knob("glide")])
        let panel = PanelLayout.of([Self.mixer, Self.pitch, Self.wide, Self.master, extra], plannedRows: Self.plannedRows)
        #expect(panel.rows.map { $0.map(\.title) } == [["Mixer", "Pitch"], ["Wide", "Elsewhere"]])
    }

    @Test("Without Master there is no card on the right, and a row of missing sections is dropped")
    func plannedPanelWithout() {
        let panel = PanelLayout.of([Self.mixer, Self.pitch], plannedRows: Self.plannedRows)
        #expect(panel.side == nil)
        #expect(panel.rows.map { $0.map(\.title) } == [["Mixer", "Pitch"]])
    }

    @Test("A planned row's cards share its width in proportion to their planned columns")
    func plannedWidths() {
        let row = [Self.pitch, Self.mixer, Self.wide]                     // 3, 2 and 4 columns
        let widths = PanelLayout.widths(of: row, in: 920, spacing: 10, inset: 20, plans: Self.plans)
        // 920 − 2 gaps of 10 − 3 insets of 20 = 840 for 9 columns: 280, 186.7, 373.3, plus the inset.
        #expect(widths.count == 3)
        #expect(abs(widths[0] - 300) < 1e-9)
        #expect(abs(widths[1] - (20 + 840 * 2 / 9)) < 1e-9)
        #expect(abs(widths[2] - (20 + 840 * 4 / 9)) < 1e-9)
        #expect(abs(widths.reduce(0, +) + 20 - 920) < 1e-9)
    }

    // MARK: The cards on the panel without a plan

    @Test("The instrument's sections in a row, and Master the full height on the right")
    func panelRows() {
        let panel = PanelLayout.of(ParameterSection.all)
        #expect(panel.rows.flatMap { $0.map(\.title) } == ParameterSection.all.dropLast().map(\.title))
        #expect(panel.side?.title == "Master")
    }

    @Test("Every section is on the panel once; one it does not know joins the last row")
    func panelHoldsEverySection() {
        let extra = ParameterSection(title: "Elsewhere", parameters: [Self.knob("glide")])
        let panel = PanelLayout.of(ParameterSection.all + [extra])
        let titles = panel.rows.flatMap { $0.map(\.title) } + [panel.side?.title].compactMap { $0 }
        #expect(titles.sorted() == (ParameterSection.all.map(\.title) + ["Elsewhere"]).sorted())
        #expect(panel.rows.last?.last?.title == "Elsewhere")
    }

    @Test("Without Master there is no card on the right")
    func panelWithout() {
        let panel = PanelLayout.of(ParameterSection.all.filter { $0.title != "Master" })
        #expect(panel.side == nil)
        #expect(panel.rows.flatMap { $0.map(\.title) } == ParameterSection.all.dropLast().map(\.title))
    }

    @Test("A row's cards share its width in proportion to their columns, after the gaps and their insets")
    func widths() {
        let master = Self.section("Master")                                      // 2 columns
        let other = ParameterSection(title: "Elsewhere", parameters: [Self.knob("volume")])   // 3 columns
        let widths = PanelLayout.widths(of: [master, other, master], in: 920, spacing: 10, inset: 20)
        // 920 − 2 gaps of 10 − 3 insets of 20 = 840 for 7 columns: 240, 360, 240, plus the inset.
        #expect(widths.count == 3)
        #expect(abs(widths[0] - 260) < 1e-9)
        #expect(abs(widths[1] - 380) < 1e-9)
        #expect(abs(widths[2] - 260) < 1e-9)
        #expect(abs(widths.reduce(0, +) + 20 - 920) < 1e-9)
        #expect(PanelLayout.widths(of: [], in: 920, spacing: 10, inset: 20).isEmpty)
    }
}
