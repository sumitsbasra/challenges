# Challenges

Group fitness competitions for Apple rings — extend Apple's native 1-on-1 Activity Sharing to groups of 2–20 people using the same ring-based points system users already know.

## What it does

Apple's built-in Fitness competitions only support head-to-head matchups. Challenges removes that limit: invite a group, compete over a custom date range, and see a live leaderboard updated in real time. Apple Watch users score on all three rings; iPhone-only users also score on three metrics (steps, exercise minutes, active energy) — both paths use the same formula so everyone competes fairly.

## Tech stack

| Layer | Choice |
|---|---|
| UI | SwiftUI (iOS 17+) |
| Auth | Sign in with Apple |
| Backend | CloudKit (Public DB) |
| Real-time | CKQuerySubscription + silent push |
| Health data | HealthKit |
| Intelligence | App Intents + Core Spotlight + WidgetKit |

## Points system

**Apple Watch (3 rings)**
```
pts = ((move/moveGoal + exercise/30min + stand/12hr) / 3) × 600
```

**iPhone only (3 metrics)**
```
pts = ((steps/10000 + exercise/30min + activeEnergy/500kcal) / 3) × 600
```

Each contribution is capped at 2× so exceeding a goal still rewards effort. Max is 1200 pts/day (all three metrics at 200%). Scoring mode is snapshotted at join time and never changes mid-competition.

## Features

- **Group competitions** — 2–20 participants, custom start and end dates
- **Late joining** — participants can join active challenges; scoring starts from their join date
- **Live leaderboard** — CloudKit subscriptions push updates in near real-time
- **Invite codes** — 6-character codes (e.g. `FX4K9R`) shareable via link or copy-paste
- **Fair scoring** — Watch and non-Watch users compete on equal footing with matched 3-metric formulas
- **Score history chart** — line chart of daily points across the challenge window
- **Podium view** — gold/silver/bronze results screen when a challenge completes
- **Profile photos** — avatar with crop/zoom, cached locally
- **Siri & Shortcuts** — "What's my rank in Summer Ring Crush?" returns a spoken result without opening the app
- **Spotlight search** — challenges appear in system search; tap to jump straight to the detail view
- **Home Screen widget** — shows your current rank and points; rises to the top of the Smart Stack at 7am and 7pm
- **Background sync** — HealthKit data synced every 15 minutes via BGAppRefreshTask

## Project structure

```
Challenges/
├── AppIntents/          Siri/Shortcuts intents and entity query
├── Core/
│   ├── Auth/            Sign in with Apple, UserSession
│   ├── CloudKit/        CloudKitManager, RecordMapper
│   ├── HealthKit/       ActivityDataFetcher, WatchDetector
│   ├── Intelligence/    SpotlightIndexer, WidgetDataWriter
│   └── Sync/            SyncCoordinator, NotificationScheduler, background task scheduler
├── Features/
│   ├── Challenges/      List, New, Join views + view models
│   ├── Detail/          Detail, Leaderboard, MyProgress, ScoreHistoryChart
│   ├── Onboarding/      Sign in + HealthKit explanation + name/photo entry
│   └── Profile/         Health permissions, notification settings
├── Models/              Challenge, Participation, DailyScore, AppUser, RingData
├── Scoring/             PointsCalculator, GoalResolver, ScoreAggregator
└── UI/                  Components, colors, typography

ChallengesWidget/        WidgetKit extension (separate Xcode target)
```

## Apple Intelligence integration

On iOS 18.1+ with Apple Intelligence enabled, Siri understands natural language requests semantically — no exact phrase matching required. The same `AppIntent` conformances that power Shortcuts work for free with the AI upgrade.

| Capability | How to trigger |
|---|---|
| Check rank | "What's my rank in [challenge]?" |
| Open challenge | "Show me [challenge] in Challenges" |
| Create challenge | "Create a challenge in Challenges" |
| List active | "Show my active challenges in Challenges" |
| Spotlight | Search any challenge title in system search |
| Widget | Add "My Rank" widget; Smart Stack surfaces it at 7am/7pm |

## Xcode setup

1. Open `Challenges.xcodeproj`
2. Set your development team in both the `Challenges` and `ChallengesWidget` targets
3. Enable capabilities: **HealthKit**, **CloudKit**, **Push Notifications**, **Background Modes** (fetch, processing, remote-notification), **Sign in with Apple**, **App Groups**
4. Register App Group `group.studio.ssb.challenges` in the Apple Developer portal for both App IDs

## CloudKit indexes

Set these in the CloudKit Dashboard (required for queries to work):

| Record type | Queryable fields |
|---|---|
| `Challenge` | `inviteCode`, `status`, `startDate`, `creatorRef` |
| `Participation` | `challengeRef`, `userRef`, `status` |
| `DailyScore` | `challengeRef`, `participationRef`, `date` |

## Requirements

- iOS 17.0+
- Xcode 16+
- An Apple Developer account (CloudKit and HealthKit require a provisioned device)
