import AppKit
import SwiftUI
import {{APP}}Core

/// The bottom of the panel, the same in the app's window and in the
/// plug-in's: one glass card that follows the mode, as in the mockups.
///
/// - Keyboard: "Keyboard", an ornament band with the instrument's figure
///   standing on the keys (where the artwork has one), the last note played, the "Send to pad" button (`SendToPadView`)
///   and three octaves of keys (`KeyboardStripView`).
/// - Pads: the sixteen pads on the left (`PadGridView`) and the selected
///   pad's pitch and group and the Kit menu on the right (`PadInspectorView`).
///
/// Both modes are the same height, so the window keeps its size when the
/// mode changes.
public struct ModeFooterView: View {

    private let model: any InstrumentModel

    /// The footer's height in either mode.
    public static var height: CGFloat { PadGridView.height + 2 * padding }

    private static let padding: CGFloat = 10
    private static let keyboardRow: CGFloat = 60
    /// How tall the figure stands: taller than its row, it reaches up over the card's edge.
    private static let figureHeight: CGFloat = 100

    @State private var sending = false

    public init(model: any InstrumentModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            switch model.mode {
            case .keyboard: keyboard
            case .pads: pads
            }
        }
        .padding(Self.padding)
        .frame(height: Self.height)
        .instrumentCard(cornerRadius: 16)
    }

    private var keyboard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                Text("Keyboard")
                    .font(.system(size: 30, weight: .semibold, design: .serif))
                    .foregroundStyle(Artwork.ink)
                    .fixedSize()
                    .padding(.leading, 8)
                OrnamentBand()
                    .frame(maxWidth: .infinity)
                // A box as wide as the figure, which stands on the keys and reaches up out of it.
                Color.clear
                    .frame(width: FigureView.width(height: Self.figureHeight), height: Self.keyboardRow)
                    .overlay(alignment: .bottom) {
                        FigureView()
                            .frame(height: Self.figureHeight)
                            .offset(y: 6)
                    }
                OrnamentBand()
                    .frame(maxWidth: .infinity)
                Rectangle().fill(Artwork.ink.opacity(0.3)).frame(width: 1, height: 40)
                lastNote
                sendButton
            }
            .frame(height: Self.keyboardRow)
            .zIndex(1)
            KeyboardStripView(model: model)
                .frame(maxHeight: .infinity)
        }
    }

    /// The pitch "Send to pad" gives a pad, in a box as the mockup draws it.
    private var lastNote: some View {
        VStack(spacing: 3) {
            Text("Last note")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Artwork.ink)
            Text(Notes.name(PadLabel.sendPitch(lastNote: model.lastNote)))
                .font(.system(size: 22, weight: .semibold, design: .serif).monospacedDigit())
                .foregroundStyle(Artwork.ink)
                .frame(width: 76, height: 34)
                .background(Artwork.deep.opacity(0.6), in: .rect(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Artwork.ink.opacity(0.25), lineWidth: 1) }
        }
        .accessibilityElement(children: .combine)
        .help("The pitch Send to pad gives a pad: the last note played, C2 before any")
    }

    private var sendButton: some View {
        Button {
            sending = true
        } label: {
            Text("Send to pad")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Artwork.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(.glass)
        .help("Copy the keyboard's sound, at the last note played, to a pad")
        // Beside the button, to its left: centred over it, the popover would hang past the
        // window's right edge.
        .popover(isPresented: $sending, arrowEdge: .leading) {
            SendToPadView(model: model, isPresented: $sending)
        }
        .padding(.trailing, 6)
    }

    private var pads: some View {
        HStack(alignment: .top, spacing: 12) {
            PadGridView(model: model)
                .frame(maxWidth: .infinity)
            Rectangle().fill(Artwork.ink.opacity(0.25)).frame(width: 1)
            PadInspectorView(model: model)
                .frame(width: PadInspectorView.width)
        }
    }
}

/// The instrument's figure, cropped to `Artwork.figureBounds`; nothing (and no width) without
/// the artwork.
struct FigureView: View {

    /// The width the figure takes at a height.
    @MainActor static func width(height: CGFloat) -> CGFloat {
        guard let figure = Artwork.figure, figure.size.height > 0 else { return 0 }
        let bounds = Artwork.figureBounds
        return height * figure.size.width * bounds.width / (figure.size.height * bounds.height)
    }

    var body: some View {
        if let figure = Artwork.figure {
            CroppedArt(image: figure, bounds: Artwork.figureBounds)
        }
    }
}

/// The emblem beside the wordmark, cropped to `Artwork.logoBounds`.
struct LogoView: View {

    /// The width the emblem takes at a height.
    @MainActor static func width(height: CGFloat) -> CGFloat {
        guard let logo = Artwork.logo, logo.size.height > 0 else { return 0 }
        let bounds = Artwork.logoBounds
        return height * logo.size.width * bounds.width / (logo.size.height * bounds.height)
    }

    var body: some View {
        if let logo = Artwork.logo {
            CroppedArt(image: logo, bounds: Artwork.logoBounds)
        }
    }
}

/// A part of an artwork, `bounds` in parts of its size from the top left, at
/// the proportions of that part. Only a picture: it never takes a click, so
/// whatever it reaches over (the figure over a card's edge) keeps working.
struct CroppedArt: View {

    let image: NSImage
    let bounds: CGRect

    var body: some View {
        let size = image.size
        let aspect = size.height > 0 && bounds.height > 0 ? size.width * bounds.width / (size.height * bounds.height) : 1
        Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                GeometryReader { geometry in
                    let width = geometry.size.width / bounds.width
                    let height = geometry.size.height / bounds.height
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: width, height: height)
                        .offset(x: -bounds.minX * width, y: -bounds.minY * height)
                }
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
