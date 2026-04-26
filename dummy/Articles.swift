import Foundation

struct HelpArticle: Identifiable, Hashable {
    let id: String
    let title: String
    let tags: [String]
    let modes: [RescueMode]
    let summary: String
    let body: String
}

enum ArticlesStore {
    static let all: [HelpArticle] = [
        .init(
            id: "flat_tire_donut_limits",
            title: "Donut spare limits",
            tags: ["Flat tire", "Aftercare"],
            modes: [.flatTire],
            summary: "Most temporary spares have speed and distance limits—drive cautiously and service ASAP.",
            body: """
Most temporary (donut) spares have speed and distance limits.

Do:
• Drive cautiously and avoid hard braking.
• Check the spare pressure when you can.
• Get the damaged tire repaired/replaced ASAP.

Avoid:
• Highway speeds if your spare specifies lower limits.
• Long distances on a temporary spare.
"""
        ),
        .init(
            id: "flat_tire_when_to_tow",
            title: "When to stop and get a tow",
            tags: ["Flat tire", "Safety"],
            modes: [.flatTire],
            summary: "If the location or equipment makes the change unsafe, the correct move is to stop and call for help.",
            body: """
Stop and call roadside assistance / tow if:
• You are in an unsafe location (narrow shoulder, poor visibility).
• The spare is missing/damaged, or you lack the right tools.
• The car can’t be safely lifted (soft ground, unstable jack point).
• You’re unsure about any step.

Safety beats speed.
"""
        ),
        .init(
            id: "dead_battery_jump_order",
            title: "Jump start order (high level)",
            tags: ["Battery", "Safety"],
            modes: [.deadBattery],
            summary: "Correct order reduces sparks risk; stop if the battery looks damaged or leaking.",
            body: """
High-level jump start safety:
• If the battery is cracked, leaking, swollen, or smoking: stop.
• Keep metal tools away from terminals.
• Follow your vehicle manual for the correct connection order.

If unsure, call for help.
"""
        )
    ]

    static func forMode(_ mode: RescueMode) -> [HelpArticle] {
        all.filter { $0.modes.contains(mode) }
    }
}
