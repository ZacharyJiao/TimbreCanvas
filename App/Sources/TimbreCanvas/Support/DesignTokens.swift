import SwiftUI

enum StudioDesign {
    static let accent = Color(red: 0.16, green: 0.31, blue: 0.78)
    static let accentSecondary = Color(red: 0.93, green: 0.36, blue: 0.25)
    static let paper = Color(red: 0.975, green: 0.968, blue: 0.945)
    static let graphite = Color(red: 0.16, green: 0.16, blue: 0.15)
    static let cornerRadius: CGFloat = 8
    static let compactCornerRadius: CGFloat = 6
}

struct PaperTexture: View {
    var opacity = 0.34

    var body: some View {
        Image("PaperTexture", bundle: .studioResources)
            .resizable(resizingMode: .tile)
            .opacity(opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct PaperBackground: View {
    var body: some View {
        ZStack {
            StudioDesign.paper
            PaperTexture(opacity: 0.28)
        }
        .ignoresSafeArea()
    }
}

struct StudioSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    StudioDesign.paper
                    PaperTexture(opacity: 0.38)
                }
                .clipShape(RoundedRectangle(cornerRadius: StudioDesign.cornerRadius))
            }
            .overlay {
                RoundedRectangle(cornerRadius: StudioDesign.cornerRadius)
                    .strokeBorder(StudioDesign.graphite.opacity(0.34), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.07), radius: 3, y: 2)
    }
}

struct DeckledPaperSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                Image("DeckledPaper", bundle: .studioResources)
                    .resizable(
                        capInsets: EdgeInsets(top: 64, leading: 64, bottom: 64, trailing: 64),
                        resizingMode: .stretch
                    )
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                    .accessibilityHidden(true)
            }
    }
}

extension View {
    func studioSurface() -> some View { modifier(StudioSurface()) }
    func deckledPaperSurface() -> some View { modifier(DeckledPaperSurface()) }
}
