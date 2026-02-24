//
//  RootView.swift
//  RoadsideReady
//
//  Created by Jason Co on 2/15/26.
//

import SwiftUI

private extension View {
    func rrActionPill() -> some View {
        self
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentColor, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
    }
}

struct RootView: View {
    @StateObject private var engine = FlowEngine()

    private enum DrawerState { case hidden, peek, open }
    @State private var drawerState: DrawerState = .hidden
    @GestureState private var dragX: CGFloat = 0

    private func clamp(_ x: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { min(max(x, a), b) }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let peekWidth = min(420, max(320, geo.size.width * 0.25))
                let openWidth = geo.size.width
                let drawerWidth = (drawerState == .open) ? openWidth : peekWidth

                let baseX: CGFloat = (drawerState == .hidden) ? -drawerWidth : 0
                let offsetX = clamp(baseX + dragX, -drawerWidth, 0)
                let isVisible = drawerState != .hidden

                ZStack(alignment: .leading) {
                    // MAIN CONTENT
                    VStack(spacing: 16) {
                        headerBar
                        FlowScreen(engine: engine)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding()

                    // DIM BACKDROP (only when visible)
                    if isVisible {
                        Color.black.opacity(0.18)
                            .ignoresSafeArea()
                            .onTapGesture { closeDrawer() }
                    }

                    // DRAWER (visible states only)
                    if isVisible {
                        ManualDrawer(
                            isPresented: Binding(
                                get: { drawerState != .hidden },
                                set: { newValue in
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                        drawerState = newValue ? .peek : .hidden
                                    }
                                }
                            ),
                            mode: engine.mode,
                            isFlowComplete: !engine.canGoNext
                        )
                        .frame(width: drawerWidth)
                        .frame(maxHeight: .infinity)
                        .background(Color(uiColor: .systemBackground))
                        .offset(x: offsetX)
                        .shadow(color: .black.opacity(0.18), radius: 24, x: 10, y: 0)
                        .gesture(
                            DragGesture(minimumDistance: 8)
                                .updating($dragX) { v, s, _ in s = v.translation.width }
                                .onEnded { v in
                                    let proposed = clamp(baseX + v.translation.width, -drawerWidth, 0)
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                        if proposed < -drawerWidth * 0.5 {
                                            drawerState = .hidden
                                        } else {
                                            drawerState = (drawerState == .open) ? .open : .peek
                                        }
                                    }
                                }
                        )

                        // PULL TAB (only when drawer is not hidden)
                        ArticlesPullTab(isOpen: drawerState == .open)
                            .offset(x: offsetX + drawerWidth - 10)
                            .frame(maxHeight: .infinity, alignment: .center)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                    drawerState = (drawerState == .open) ? .peek : .open
                                }
                            }
                            .gesture(
                                DragGesture(minimumDistance: 8)
                                    .updating($dragX) { v, s, _ in s = v.translation.width }
                                    .onEnded { v in
                                        let proposed = clamp(baseX + v.translation.width, -drawerWidth, 0)
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                            if proposed < -drawerWidth * 0.5 {
                                                drawerState = .hidden
                                            } else {
                                                drawerState = (proposed > -drawerWidth * 0.15) ? .open : .peek
                                            }
                                        }
                                    }
                            )
                    }
                }
            }
            .navigationBarHidden(true)
        }
    }

    // Header: left Articles, centered title, right issue menu
    private var headerBar: some View {
        ZStack {
            Text("Roadside Ready")
                .font(.largeTitle.weight(.semibold))

            HStack {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        drawerState = .peek
                    }
                } label: {
                    Label("Articles", systemImage: "newspaper")
                        .rrActionPill()
                }
                .buttonStyle(.plain)

                Spacer()

                issueMenu
            }
        }
    }

    private var issueMenu: some View {
        Menu {
            Button("Flat Tire") { engine.setMode(.flatTire) }
            Button("Dead Battery") { engine.setMode(.deadBattery) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                Text(engine.mode.rawValue)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
            .rrActionPill()
            .frame(minWidth: 150)
        }
        .transaction { $0.animation = nil }
    }

    private func closeDrawer() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            drawerState = .hidden
        }
    }
}

private struct ArticlesPullTab: View {
    let isOpen: Bool

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color(uiColor: .secondarySystemBackground))
                .frame(width: 26, height: 96)
                .overlay(Capsule().stroke(Color.black.opacity(0.10), lineWidth: 1))
                .shadow(color: .black.opacity(0.10), radius: 10, x: 2, y: 0)

            Image(systemName: isOpen ? "chevron.left" : "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Articles panel")
        .accessibilityHint(isOpen ? "Collapse articles" : "Expand articles")
    }
}

