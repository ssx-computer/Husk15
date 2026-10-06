// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// iOS 15 compatibility, in one place.
///
/// Husk now targets iOS 15, and SwiftUI grew several APIs since then that the
/// app was written against. Each of them goes through one of the helpers here
/// so the 16+/15 split is readable rather than smeared across every screen.
/// Everything takes the modern path wherever it exists; the iOS 15 arms are
/// approximations, kept deliberately plain.
///
/// None of this is gated with `#if os(iOS)`: the deployment target is iOS, and
/// `#available` does the runtime part.

/// A navigation stack without a programmatic path.
///
/// `NavigationStack` is iOS 16+; on iOS 15 the stack style of `NavigationView`
/// behaves the same for the classic `NavigationLink { }` pushes these screens
/// use. The stack style is forced because iOS 15 defaults to a split view on
/// wide layouts, which is not what any of these screens draw for.
struct HuskNavStack<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack { content() }
        } else {
            NavigationView { content() }
                .navigationViewStyle(.stack)
        }
    }
}

/// A navigation stack driven by a value path.
///
/// iOS 16+ forwards to `NavigationStack(path:)` + `navigationDestination`,
/// unchanged from what the app was written against. iOS 15 has no programmatic
/// push at all, so the stack is rendered by hand: each entry in `path` draws
/// its leaf view over the previous one, and pushing or popping is a mutation of
/// `path` -- the same mutation that drives the real stack on iOS 16+.
///
/// That is why the screens using this replace their `NavigationLink(value:)`
/// with buttons that append to `path`: the same line of code pushes on both
/// branches, and `removeLast()` on the binding pops on both.
struct HuskNavPathStack<Dest: Hashable, Root: View, Leaf: View>: View {
    @Binding var path: [Dest]
    /// iOS 15's hand-rolled stack has no navigation bar, so a leaf's own
    /// toolbar buttons never appear. Provide this and the manual stack covers
    /// each leaf with a close button in the top corner; on iOS 16+ it is
    /// ignored and the leaf keeps its real toolbar.
    var manualClose: (() -> Void)? = nil
    @ViewBuilder var root: () -> Root
    @ViewBuilder var leaf: (Dest) -> Leaf

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack(path: $path) {
                root()
                    .navigationDestination(for: Dest.self) { leaf($0) }
            }
        } else {
            ZStack {
                root()
                ForEach(Array(path.enumerated()), id: \.element) { _, dest in
                    leaf(dest)
                        .transition(Self.pushPop)
                        // The close button a leaf would have put in the
                        // navigation bar. Only on the manual stack: on iOS 16+
                        // the leaf draws its own toolbar button.
                        .overlay(alignment: .topTrailing) {
                            if let manualClose {
                                Button(action: manualClose) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.text)
                                        .frame(width: 36, height: 36)
                                        .background(Theme.surfaceHigh, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 18).padding(.top, 10)
                                .accessibilityLabel("Close")
                            }
                        }
                }
            }
            // Pushes and pops are plain mutations of `path`; animating on it
            // gives the hand-rolled stack the transition the real one gets.
            .animation(.easeInOut(duration: 0.28), value: path)
        }
    }

    /// Sliding in from the trailing edge, the way a navigation push moves.
    static let pushPop = AnyTransition
        .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity))
}

extension Animation {
    /// `.snappy` is iOS 17+. This is the same idea -- a quick, low-bounce
    /// spring -- in the spring API that has been there since iOS 15. The
    /// default response matches snappy's default duration of 0.3.
    static let huskSnappy = Animation.spring(response: 0.3, dampingFraction: 0.8)

    static func huskSnappy(duration: Double) -> Animation {
        .spring(response: duration, dampingFraction: 0.8)
    }
}

extension View {
    /// Hides the system tab bar. iOS 16+ forwards to `.toolbar(_:for:)`;
    /// iOS 15 has no per-view way to hide it, so the bar is hidden globally
    /// through `UITabBar.appearance()` -- see Theme.applyBarAppearance.
    @ViewBuilder
    func huskToolbarHiddenTabBar() -> some View {
        if #available(iOS 16.0, *) {
            self.toolbar(.hidden, for: .tabBar)
        } else {
            self
        }
    }

    /// A sheet that is a fixed height rather than full-screen. iOS 16+
    /// forwards to `.presentationDetents`; on iOS 15 the sheet takes the
    /// system's default sizing, which is the only thing it could do anyway.
    @ViewBuilder
    func huskSheetHeight(_ height: CGFloat) -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents([.height(height)])
        } else {
            self
        }
    }

    /// Hides the home indicator and its overlay. iOS 16+ forwards to
    /// `.persistentSystemOverlays`; iOS 15 has no equivalent and simply keeps
    /// the indicator, which is a cosmetic difference only.
    @ViewBuilder
    func huskPersistentOverlaysHidden() -> some View {
        if #available(iOS 16.0, *) {
            self.persistentSystemOverlays(.hidden)
        } else {
            self
        }
    }

    /// Hides the status bar. `.statusBarHidden(_:)` is iOS 16+, but the same
    /// job has been done by `.statusBar(hidden:)` since iOS 13, and the old
    /// form is not deprecated -- so no gate is needed, this works everywhere.
    func huskStatusBarHidden(_ hidden: Bool = true) -> some View {
        statusBar(hidden: hidden)
    }

    /// Hides a Form/List's system background so the page shows through.
    /// iOS 16+ forwards to `.scrollContentBackground`; iOS 15 has no way to
    /// reach that layer from SwiftUI, so the system grey stays. A cosmetic
    /// difference only, and not worth the UITableView appearance hacks it
    /// would take to work around.
    @ViewBuilder
    func huskScrollBackgroundHidden() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}
