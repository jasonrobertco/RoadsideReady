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
        // ─────────────────────────────────────────────────────────────────────
        // Flat Tire
        // ─────────────────────────────────────────────────────────────────────
        .init(
            id: "flat_tire_donut_limits",
            title: "Temporary spare (donut) limits",
            tags: ["Flat tire", "Aftercare", "Tires"],
            modes: [.flatTire],
            summary: "Many temporary spares are limited (often ~50 mph and ~50 miles). Check the sidewall and drive gently.",
            body: """
Temporary spares ("donuts") are designed to get you to service - not replace a normal tire.

Typical limits (varies by tire/vehicle):
• Max speed is often around 50 mph (80 km/h).
• Distance is often limited (commonly around 50 miles / 80 km).

Do:
• Check the spare's sidewall for the exact speed/distance limit.
• Drive smoothly: gentle acceleration, gentle braking, avoid hard cornering.
• Get the damaged tire repaired/replaced ASAP.

Avoid:
• High speeds, long distances, rough roads.
• Driving if the spare is visibly damaged or underinflated.
"""
        ),
        .init(
            id: "flat_tire_lug_torque",
            title: "Lug nuts: tightening + re-check",
            tags: ["Flat tire", "Safety", "Maintenance"],
            modes: [.flatTire],
            summary: "Snug in a star pattern, then tighten to the vehicle's torque spec. Re-check after a short drive if safe.",
            body: """
Correct lug nut tightening helps the wheel seat evenly.

Best practice:
1) Hand-thread all lug nuts first (prevents cross-threading).
2) Snug in a star pattern (don't fully tighten while the wheel is in the air).
3) Lower until the tire just touches the ground so it won't spin.
4) Tighten in a star pattern again.

If you have access to a torque wrench:
• Tighten to the torque spec for your exact vehicle (usually in the owner's manual).
• If the wheel was removed, it's smart to re-check lug tightness after a short drive, when safe.

If anything feels off (vibration, wobble, knocking): stop and get help.
"""
        ),
        .init(
            id: "flat_tire_tire_pressure_basics",
            title: "Tire pressure basics (including the spare)",
            tags: ["Tires", "Maintenance", "Safety"],
            modes: [.flatTire, .deadBattery],
            summary: "Check tire pressure at least monthly when tires are cold, and don't forget the spare.",
            body: """
Tire pressure affects handling, stopping distance, and tire damage risk.

Best practice:
• Check all tires - including the spare - at least once a month.
• Check when tires are "cold" (vehicle hasn't been driven for ~3 hours).
• Use the vehicle placard (door jamb) or owner's manual for the correct PSI - NOT the tire sidewall number.

If TPMS light is on:
• Check pressures soon.
• Inflate to the placard PSI and re-check.
"""
        ),

        // ─────────────────────────────────────────────────────────────────────
        // Dead Battery
        // ─────────────────────────────────────────────────────────────────────
        .init(
            id: "dead_battery_jump_order",
            title: "Jump-start cable order (common safe method)",
            tags: ["Battery", "Safety"],
            modes: [.deadBattery],
            summary: "A common safe order ends with the black clamp on a metal ground point (not the dead battery terminal).",
            body: """
Jump-start order can vary by vehicle - use your owner's manual when available.

Common safe sequence:
1) Red clamp to dead battery (+)
2) Red clamp to donor battery (+)
3) Black clamp to donor battery (-)
4) Final black clamp to a bare metal ground on the dead car (engine block or solid bracket), away from the battery

Then:
• Start the donor car and let it idle briefly.
• Try starting the dead car (short attempts, don't overheat the starter).

Disconnect in reverse order.

If you're unsure about terminals/ground point, stop and call for help.
"""
        ),
        .init(
            id: "dead_battery_when_not_to_jump",
            title: "When NOT to jump-start",
            tags: ["Battery", "Safety"],
            modes: [.deadBattery],
            summary: "Damage, leaks, swelling, or strong chemical smell = stop. Hybrids/EVs may require special procedures.",
            body: """
Do not jump-start if:
• Battery case is cracked, swollen, leaking, smoking, or smells strongly of chemicals.
• Cables/terminals are damaged or you cannot confidently identify + / -.
• You're in an unsafe location (traffic, poor visibility).

Extra caution:
• Some hybrids/EVs and certain modern vehicles have specific jump points/procedures.

If any of the above apply, call roadside assistance.
"""
        ),

        // ─────────────────────────────────────────────────────────────────────
        // General roadside issue
        // ─────────────────────────────────────────────────────────────────────
        .init(
            id: "overheating_what_to_do",
            title: "Engine overheating: what to do safely",
            tags: ["Overheating", "Safety"],
            modes: [.flatTire, .deadBattery],
            summary: "Turn off A/C, pull over safely, and let the engine cool. Never open the radiator cap while hot.",
            body: """
If the temperature gauge spikes or you see steam:

Do:
1) Turn off A/C. If you must keep moving briefly, turn the heater ON to help pull heat away from the engine.
2) Pull over safely as soon as you can and shut the engine off.
3) Let the vehicle cool fully before checking anything under the hood.

Critical safety:
• Never remove a radiator cap on a hot engine - hot coolant can spray out and cause severe burns.

If overheating repeats, you see leaks, or warning lights persist: get professional help / tow.
"""
        ),
    ]

    static func forMode(_ mode: RescueMode) -> [HelpArticle] {
        all.filter { $0.modes.contains(mode) }
    }
}
