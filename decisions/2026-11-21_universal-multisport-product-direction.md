# Decision — Cyclift is a universal multisport athlete platform (permanent product direction)

**Date:** 21 Nov 2026, 00:49 (Dubai), with the clarification of 00:46 · **Decided by:** owner · **Status:** approved, permanent.
Supersedes the framing of Cyclift as a cycling-and-strength application wherever earlier documents imply it.

## The decision

1. **Multisport onboarding, now.** Every activity in the Cyclift catalogue is selectable: road, indoor, mountain, gravel and commuting cycling; gym strength, free weights, machines, bodyweight and calisthenics; road, trail and treadmill running; pool and open-water swimming; walking, hiking and outdoor activities; mobility, stretching and recovery; further sports through an extensible activity registry. Athletes may select several activities and choose any of them as their primary sport. Nobody is forced into a cycling, strength or cycling/strength identity. "Unsupported sport" / "not supported" is never shown as a permanent classification.
2. **Sport-specific goals.** Goal categories adapt to every sport selected. Initial, PROVISIONAL categories (not approved until reviewed): Running — Distance, Pace, Endurance, Race Preparation; Swimming — Technique, Endurance, Speed, Event Preparation; Strength — Strength, Muscle Growth, Muscular Endurance, Maintenance; Cycling — Endurance, Power, Climbing, Sprint, Event Preparation; Mobility — Flexibility, Mobility, Recovery. Multiple goals, exactly one primary goal. Compact Build 6 card design, one-screen layout. The cycling/strength balance is not asked again.
3. **Every athlete completes onboarding.** Where planning exists, the existing planner is used. Otherwise the profile, sports, goals and preferences are saved and no training session is fabricated ("profile-only" outcome). The Blueprint and Home handle an athlete without a plan safely. No cycling or strength programme is ever assigned silently. With supported and other activities together, plans are generated only for supported goals the athlete explicitly selected; a cycling or strength goal is never added automatically.
4. **AI Coach architecture to be prepared.** Modular, sport-specific training knowledge; the data model is to accommodate sport and discipline, athlete experience, primary and secondary goals, training frequency and availability, relevant measurements and sensors, session types, recovery and progression, and sport-specific rules and safety requirements. No fake prescriptions. Generic AI-generated plans are never presented as scientifically validated sport-specific coaching. The existing rules-based cycling and strength functionality stays operational.
5. **Presentation.** The experience feels like a complete multisport platform. No technical language ("unsupported engine", "not implemented", "planner unavailable", "AI capability missing"). Where something is genuinely unavailable it is said simply and truthfully, e.g. "Your running goals are saved. Personalized running plans are coming soon." A feature is not marked available until it works.
6. **Later, not now.** After onboarding and the approved screens are final: structured research into sport-specific training methods, then development and verification of Coach capabilities, planning engines, recording integrations and progression rules. Training engines are not expanded during the screen-approval process.
7. **Records.** Five things are always distinguished: multisport UI support · athlete-profile and goal storage · actual workout planning · recording · AI Coach support. A future capability is never marked implemented because the UI lets an athlete select the sport.

## Capability today (21 Nov 2026) — five separate facts per sport

| Sport / discipline | Selectable in the UI | Profile and goal storage | Workout planning | Recording | AI Coach |
|---|---|---|---|---|---|
| Road cycling | Yes | Yes | Yes — existing rules-based planner | Yes — cycling recorder | No — rules-based Coach only; no AI model connected |
| Indoor, mountain, gravel, commuting cycling | Yes | Yes | As general cycling only (not discipline-specific) | As a cycling ride | No |
| Gym strength | Yes | Yes | Yes — existing rules-based strength planner | Yes — strength recorder | No — rules-based only |
| Free weights, machines | Yes | Yes | As gym training only | As gym training | No |
| Bodyweight, calisthenics | Yes | Yes | No | No | No |
| Running (road, trail, treadmill) | Yes | Yes | No | No | No |
| Swimming (pool, open water) | Yes | Yes | No | No | No |
| Walking, hiking | Yes | Yes | No | No | No |
| Mobility, stretching, recovery | Yes | Yes | No | No | No |

"Yes" in the first two columns means implemented in code on the development branch; its verification state is tracked per screen in `docs/design/CYCLIFT_APPROVED_SCREENS.md` (Screens 3 and 4). Nothing here is in a TestFlight build.

## Follow-up recorded, not started

- A route for a profile-only athlete to set up a plan later, once they add a planned sport and goal.
- The Coach data model for all sports (point 4).
- Research and engines per sport (point 6).
- Review of the provisional goal categories (point 2).
