# Challenges

Group fitness competitions for Apple rings — extends Apple's native Activity Sharing to groups of 2–20 people using the same ring-based scoring system users already know.

## What it does

Apple's built-in Fitness competitions only support head-to-head matchups. Challenges removes that limit: invite a group, compete over a custom date range, and see a live leaderboard updated in real time. Apple Watch users score on all three rings; iPhone-only users score on three matched metrics (steps, exercise minutes, active energy) — both paths use the same formula so everyone competes fairly.

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

Each contribution is capped at 2× so exceeding a goal still rewards effort. Max is 1200 pts/day (all three metrics at 200%). Scoring mode is determined at join time by the Watch detected on-device and never changes mid-competition.

## Features

- **Group competitions** — unlimited participants, custom start and end dates
- **Late joining** — participants can join active challenges; scoring starts from their join date
- **Live leaderboard** — CloudKit subscriptions push score updates in near real-time, active and completed challenges both show ranked participant list
- **Invite codes** — 6-character codes (e.g. `FX4K9R`) shareable via link, copy-paste, or system share sheet
- **Fair scoring** — Watch and non-Watch users compete on equal footing with matched 3-metric formulas; scoring mode is locked at join time
- **Score deduplication** — aggregator deduplicates CloudKit records by calendar day (keeps highest) to prevent point inflation from save retries
- **Score history chart** — line chart of daily points across the full challenge window, shown for both active and completed challenges
- **Today's activity card** — Apple Fitness-style ring stack with Move/Exercise/Stand (Watch) or Steps/Exercise/Energy (iPhone) metrics; respects user's units preference (Imperial/Metric) for distance
- **Instant home screen** — cache pre-populated before first SwiftUI frame so challenges appear immediately on every launch with no blank flash
- **Watch ring fallback** — if the activity summary hasn't synced yet (common early morning), falls back to individual HealthKit queries so rings are never stuck at zero
- **Profile photos** — avatar with crop/zoom, cached locally, synced to CloudKit
- **Units preference** — Imperial/Metric toggle in Profile; distance displayed in chosen units everywhere
- **Siri & Shortcuts** — "What's my rank in [challenge]?" returns a spoken result without opening the app; works with Apple Intelligence natural language on iOS 18.1+
- **Spotlight search** — challenges indexed in Core Spotlight; tap a result to jump straight to the detail view
- **Home Screen widget** — shows current rank, points, days remaining, and participant count; Smart Stack relevance hints surface it at 7am and 7pm
- **Local notifications** — day-before reminder, first-day and last-day nudges, and final standings alert; per-type toggles in Profile; respects iOS notification permission state
- **Background sync** — HealthKit → CloudKit sync every 15 minutes via `BGAppRefreshTask`; also triggered by the widget timeline reload

## Project structure

```
Challenges/
├── AppIntents/          Siri/Shortcuts intents and entity queries
├── Core/
│   ├── Auth/            Sign in with Apple, UserSession
│   ├── Cache/           ChallengeCache (UserDefaults-based, pre-populates home on launch)
│   ├── CloudKit/        CloudKitManager, RecordMapper
│   ├── HealthKit/       ActivityDataFetcher, HealthKitManager, WatchDetector
│   ├── Intelligence/    SpotlightIndexer, WidgetDataWriter
│   ├── Sync/            SyncCoordinator, NotificationScheduler, BackgroundTaskScheduler
│   └── Utils/           Shared utilities
├── Extensions/          Date+Competition and other Swift extensions
├── Features/
│   ├── Challenges/      New challenge + join views and view models
│   ├── Detail/          ChallengeDetailView, leaderboard, MyProgressView, DailyBreakdownView, ScoreHistoryChart
│   ├── Home/            HomeView + HomeViewModel (rings card, challenge cards, empty state)
│   ├── Onboarding/      Sign in, HealthKit explanation, name/photo entry
│   ├── Profile/         Data source, health permissions, notification settings, units
│   └── Today/           TodayItem model
├── Models/              Challenge, Participation, DailyScore, AppUser, RingData
├── Scoring/             PointsCalculator, GoalResolver, ScoreAggregator
└── UI/
    ├── Components/      Reusable views (ThreeRingView, EmptyStateView, etc.)
    └── Styles/          Colors, typography, card backgrounds

ChallengesWidget/        WidgetKit extension — rank, points, days remaining (systemSmall + systemMedium)
```

## Data flow

```
HealthKit → SyncCoordinator → CloudKit (DailyScore records)
                ↓ (returns merged scores directly, bypasses read-after-write latency)
         ChallengeDetailViewModel / HomeViewModel
                ↓
           ScoreAggregator (dedup by day, sum, rank)
                ↓
           SwiftUI views + Widget (via App Group UserDefaults)
```

Sync runs on open (detail view), on home screen load, and every 15 minutes in the background. The sync result is injected directly into the UI rather than re-fetching from CloudKit, which avoids the read-after-write consistency window inherent in the public CloudKit database.

## Apple Intelligence integration

On iOS 18.1+ with Apple Intelligence enabled, Siri understands natural language requests semantically — no exact phrase matching required.

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
4. Register App Group `group.studio.ssb.challenges` in the Apple Developer portal for both App IDs (required for the widget to read data written by the main app)

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
