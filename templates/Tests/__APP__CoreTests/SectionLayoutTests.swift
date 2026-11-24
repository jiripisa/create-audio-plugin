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

    // MARK: The cards on the panel

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
