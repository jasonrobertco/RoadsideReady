//
//  Flows.swift
//  RoadsideReady
//
//  Created by Jason Co on 2/15/26.
//

import Foundation

enum Flows {
    static let flatTire: RescueFlow = .init(
        mode: .flatTire,
        startStepID: "ft_safety",
        stepsInOrder: [
            .init(
                id: "ft_safety",
                title: "Safety check",
                body: """
1) Turn on hazard lights.
2) Pull over to a flat, stable surface away from traffic.
3) Set parking brake. Put the car in Park (or 1st gear for manual).
4) Keep passengers away from the roadway.

If anything feels unsafe, stop and call for help.
""",
                safety: [.traffic, .stopIfUnsure],
                nextStepID: "ft_tools",
                choices: []
            ),
            
                .init(
                    id: "ft_tools",
                    title: "Gather tools",
                    body: """
Find:
- Spare tire (or donut)
- Jack
- Lug wrench
- Wheel chock (or a rock/wood block)
- Flashlight + gloves (optional)
""",
                    safety: [.heavyLift],
                    nextStepID: "ft_spare_check",
                    choices: []
                ),
            
                .init(
                    id: "ft_spare_check",
                    title: "Spare tire check",
                    body: """
If you don’t have a spare/donut, the safest plan is roadside assistance or a tow.

If you do have a spare:
- Not flat or visibly damaged
- Correct type/size for your vehicle
- You have the lug key/adapter if needed

If unsure, stop and get help.
""",
                    safety: [.stopIfUnsure],
                    nextStepID: "ft_chock",
                    choices: []
                ),
            
                .init(
                    id: "ft_chock",
                    title: "Chock the wheels",
                    body: """
Place a wheel chock (or block) against a tire that will stay on the ground to prevent rolling.

If your car has a wheel cover/hubcap, remove it (if needed) before loosening lug nuts.
""",
                    safety: [.traffic],
                    nextStepID: "ft_loosen",
                    choices: []
                ),
            
                .init(
                    id: "ft_loosen",
                    title: "Loosen lug nuts (before lifting)",
                    body: """
Use the lug wrench to loosen each lug nut 1/4–1/2 turn.

Do NOT fully remove them yet.
Loosening while the tire is on the ground prevents the wheel from spinning.
""",
                    safety: [.pinchPoints, .heavyLift],
                    nextStepID: "ft_jackpoint",
                    choices: []
                ),
            
                .init(
                    id: "ft_jackpoint",
                    title: "Find the jack point",
                    body: """
Locate the correct jacking point (often marked near the pinch weld).

If you’re unsure:
- Check the vehicle manual.
- Wrong placement can damage the car or cause it to slip.
""",
                    safety: [.pinchPoints, .stopIfUnsure],
                    nextStepID: "ft_jackup",
                    choices: []
                ),
            
                .init(
                    id: "ft_jackup",
                    title: "Position jack and lift",
                    body: """
Position the jack at the jack point.
Lift until the flat tire is just off the ground.

Keep hands/feet clear of the underside.
""",
                    safety: [.pinchPoints, .heavyLift],
                    nextStepID: "ft_remove",
                    choices: []
                ),
            
                .init(
                    id: "ft_remove",
                    title: "Remove the wheel",
                    body: """
1) Remove lug nuts completely.
2) Pull the wheel straight off and place it flat on the ground.

Keep lug nuts together (a pocket/container helps).
""",
                    safety: [.heavyLift, .pinchPoints],
                    nextStepID: "ft_mount",
                    choices: []
                ),
            
                .init(
                    id: "ft_mount",
                    title: "Mount the spare",
                    body: """
1) Align the spare with the wheel studs.
2) Push it on fully.
3) Hand-tighten lug nuts in a star pattern.
""",
                    safety: [.heavyLift],
                    nextStepID: "ft_lower",
                    choices: []
                ),
            
                .init(
                    id: "ft_lower",
                    title: "Lower the car",
                    body: """
Lower until the tire touches the ground and won’t spin.

Then tighten lug nuts firmly (still in a star pattern).
""",
                    safety: [.pinchPoints],
                    nextStepID: "ft_aftercare",
                    choices: []
                ),
            
                .init(
                    id: "ft_aftercare",
                    title: "Aftercare",
                    body: """
- Fully lower and remove the jack.
- Tighten lug nuts again in a star pattern.
- Check spare pressure when you can.
- Donut spares often have speed/distance limits — drive carefully and get the tire serviced ASAP.
""",
                    safety: [.stopIfUnsure],
                    nextStepID: nil,
                    choices: []
                ),
        ]
    )
    
    static let deadBattery: RescueFlow = .init(
        mode: .deadBattery,
        startStepID: "db_overview",
        stepsInOrder: [
            .init(
                id: "db_overview",
                title: "Dead battery: what you’re seeing",
                body:
"""
Common signs:
- Clicking sound, no crank
- Dim headlights / interior lights
- Electronics flicker or reset

This guide is offline and general. Your owner’s manual is the source of truth for your vehicle.
""",
                safety: [.stopIfUnsure],
                nextStepID: "db_safety",
                choices: []
            ),
            
                .init(
                    id: "db_safety",
                    title: "Safety first",
                    body:
"""
Battery safety:
- Remove metal jewelry (rings/bracelets).
- Keep sparks/flames away.
- Avoid touching both terminals with any metal tool.
- If you see cracks, leaks, or smell strong chemicals: STOP.
""",
                    safety: [.sparks, .chemicals, .stopIfUnsure],
                    nextStepID: "db_quickchecks",
                    choices: []
                ),
            
                .init(
                    id: "db_quickchecks",
                    title: "Quick checks",
                    body:
"""
Before jump-starting:
- Try a spare key / check key fob battery symptoms.
- Check if headlights turn on at all.
- Make sure terminals feel snug (don’t overtighten).
""",
                    safety: [.stopIfUnsure],
                    nextStepID: "db_inspect",
                    choices: []
                ),
            
                .init(
                    id: "db_inspect",
                    title: "Inspect the battery area",
                    body:
"""
Look for:
- White/blue corrosion on terminals
- Loose or damaged cables
- Cracked case, swelling, or leaks

If damaged/leaking: do not jump-start — call for help.
""",
                    safety: [.chemicals, .stopIfUnsure],
                    nextStepID: "db_jumpchecklist",
                    choices: []
                ),
            
                .init(
                    id: "db_jumpchecklist",
                    title: "Jump-start checklist",
                    body:
"""
You need:
- Jumper cables in good condition
- A donor vehicle (or jump pack)
- Both vehicles in Park, parking brakes set

Never let the clamps touch each other once connected.
""",
                    safety: [.sparks, .stopIfUnsure],
                    nextStepID: "db_jumpsteps",
                    choices: []
                ),
            
                .init(
                    id: "db_jumpsteps",
                    title: "Jump-start steps (general order)",
                    body:
"""
General safe order (varies by vehicle):
1) Red clamp to dead battery (+)
2) Red clamp to donor battery (+)
3) Black clamp to donor battery (-)
4) Black clamp to a metal ground on the dead car (not the battery terminal)

Start donor car, wait a minute, then try starting the dead car.
""",
                    safety: [.sparks, .stopIfUnsure],
                    nextStepID: "db_afterstart",
                    choices: []
                ),
            
                .init(
                    id: "db_afterstart",
                    title: "After it starts",
                    body:
"""
- Let the car run (or drive) to recharge.
- If it dies again soon, the battery may be failing or the alternator may be an issue.
- If warning lights appear, stop and seek service.
""",
                    safety: [.stopIfUnsure],
                    nextStepID: "db_callhelp",
                    choices: []
                ),
            
                .init(
                    id: "db_callhelp",
                    title: "When to call for help",
                    body:
"""
Call roadside assistance if:
- Battery is damaged/leaking
- You’re unsure about the correct terminals/ground point
- Jump-start fails repeatedly
- Vehicle is a hybrid/EV with special procedures

Safety > speed.
""",
                    safety: [.stopIfUnsure],
                    nextStepID: nil,
                    choices: []
                )
        ]
    )
}

