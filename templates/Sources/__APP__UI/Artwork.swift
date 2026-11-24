import AppKit
import SwiftUI

/// The panel's artwork and its colours: what the instrument looks like. The template's are the
/// system's own colours and no images; a run puts its instrument's palette here and its images
/// into Resources/Art (copied into the bundle by build.sh), and every image that is missing falls
/// back to a plain look.
@MainActor
public enum Artwork {

    /// The bundle that holds the artwork: the app, or the plug-in when the
    /// panel is shown in a host, where `Bundle.main` is the host's. Set it
    /// before the first panel is made.
    public static var bundle = Bundle.main

    /// Behind the whole panel (`Art/background.png`); `deep` without it.
    public static let background = image("background")
    /// The instrument, standing on the keyboard's card and beside the pad inspector (`Art/figure.png`).
    public static let figure = image("figure")
    /// The part of `figure` that shows the instrument, in parts of its size from the top left.
    public static let figureBounds = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// The emblem beside the wordmark (`Art/logo.png`).
    public static let logo = image("logo")
    /// The part of `logo` that shows the emblem.
    public static let logoBounds = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// A knob's cap, without a pointer: the cap stands still and the pointer is drawn (`Art/knob.png`).
    public static let knob = image("knob")
    /// A band, tileable from left to right (`Art/ornament.png`).
    public static let ornament = image("ornament")

    /// The ground: behind the panel without a background, the dark text on lit controls, the black keys.
    public static let deep = Color(nsColor: .windowBackgroundColor)
    /// The tint of the glass cards and the fill of what sits on a card (the pads, the Last note box).
    public static let glass = Color(nsColor: .controlBackgroundColor)
    /// The wordmark, the titles, the names of the controls and their values.
    public static let ink = Color.primary
    /// Value arcs and what is chosen, held or listening.
    public static let accent = Color.accentColor
    /// Captions and the second line of a pad.
    public static let muted = Color.secondary
    /// LFO 1.
    public static let sky = Color.cyan
    /// LFO 2.
    public static let mint = Color.mint

    /// The colour of an LFO (0 for the first): its button in the header and its
    /// arcs on the knobs it moves.
    public static func lfo(_ index: Int) -> Color {
        index == 0 ? sky : mint
    }

    /// The colour of the velocity: the VEL button and its arcs on the knobs.
    public static let vel = Color.orange

    private static func image(_ name: String) -> NSImage? {
        guard let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "Art") else { return nil }
        return NSImage(contentsOf: url)
    }
}

public extension View {
    /// The background behind the panel, covering the view's whole frame;
    /// plain `deep` where the artwork is missing.
    func instrumentBackground() -> some View {
        background {
            if let background = Artwork.background {
                Image(nsImage: background).resizable().scaledToFill()
            } else {
                Artwork.deep
            }
        }
        .clipped()
        .preferredColorScheme(.dark)
    }

    /// A card of the panel: glass over the background, with rounded corners.
    func instrumentCard(cornerRadius: CGFloat = 14) -> some View {
        glassEffect(.regular.tint(Artwork.glass.opacity(0.45)), in: .rect(cornerRadius: cornerRadius))
    }
}
