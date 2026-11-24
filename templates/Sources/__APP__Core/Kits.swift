import {{APP}}DSP
import Foundation

/// All sixteen pads (their notes, mute groups and sounds) saved under a name.
public struct Kit: Codable, Equatable, Sendable {
    public var name: String
    public var pads: [PadState]

    public init(name: String, pads: [PadState]) {
        self.name = name
        self.pads = pads
    }

    /// A field the data lacks gets its default (no name, no pads, which leaves the pads alone); a
    /// field this version does not know is ignored.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        pads = try container.decodeIfPresent([PadState].self, forKey: .pads) ?? []
    }
}

/// The player's kits, in `.{{APP_LOWER}}kit` files.
public typealias KitLibrary = FileLibrary<Kit>

extension FileLibrary where Content == Kit {

    public static var fileExtension: String { "{{APP_LOWER}}kit" }

    /// `~/Library/Application Support/{{APP}}/Kits`.
    public static var standard: KitLibrary {
        KitLibrary(folder: standardFolder("Kits"), fileExtension: fileExtension)
    }
}

extension Synth {

    /// The sixteen pads as they are now, with no name: the library or the caller names it.
    public var kit: Kit {
        Kit(name: "", pads: state.pads)
    }

    /// Replaces the pads with a kit's. Fewer than sixteen leave the rest alone; the mode and the
    /// keyboard set are not touched.
    public func apply(_ kit: Kit) {
        for (pad, saved) in kit.pads.prefix(Int({{APP_UPPER}}_NUM_PADS)).enumerated() {
            setPadNote(saved.note, pad: pad)
            setPadGroup(saved.group, pad: pad)
            apply(saved.set, to: .pad(pad))
        }
    }
}
