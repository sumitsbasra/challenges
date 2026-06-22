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

Mirrors Apple's Activity Competitions: points are the **sum of your ring percentages**, capped at **600 points/day**. All three rings at 100% = 300 points; you earn more by exceeding goals, up to the daily cap.

**Apple Watch (3 rings)**
```
pts = min(600, (move/moveGoal + exercise/30min + stand/12hr) × 100)
```

**iPhone only (3 metrics)**
```
pts = min(600, (steps/10000 + exercise/30min + activeEnergy/500kcal) × 100)
```

A single over-achieved ring can reach the cap on its own, just like Apple. Scoring mode is determined at join time by the Watch detected on-device and never changes mid-competition.

## Features

- **Group competitions** — unlimited participants, custom start and end dates
- **Late joining** — participants can join active challenges; scoring starts from their join date
- **Live leaderboard** — CloudKit subscriptions push score updates in near real-time, active and completed challenges both show ranked participant list
- **Invite codes** — 6-character codes (e.g. `FX4K9R`) shareable via link, copy-paste, or system share sheet
- **Fair scoring** — Watch and non-Watch users compete on equal footing with matched 3-metric formulas; scoring mode is locked at join time
- **Score deduplication** — aggregator deduplicates CloudKit records by calendar day (keeps highest) to prevent point inflation from save retries
- **Score history chart** — line chart of daily points across the full challenge window, shown for both active and completed challenges
- **Workout list** — each device syncs its own HealthKit workout summaries (type, duration, energy, distance) to CloudKit, so any participant's detail sheet shows the activities they logged
- **Today's activity card** — Apple Fitness-style ring stack with Move/Exercise/Stand (Watch) or Steps/Exercise/Energy (iPhone) metrics; respects user's units preference (Imperial/Metric) for distance
- **Instant home screen** — cache pre-populated before first SwiftUI frame so challenges appear immediately on every launch with no blank flash
- **Watch ring fallback** — if the activity summary hasn't synced yet (common early morning), falls back to individual HealthKit queries so rings are never stuck at zero
- **Profile photos** — avatar with crop/zoom, cached locally, synced to CloudKit
- **Units preference** — Imperial/Metric toggle in Profile; distance displayed in chosen units everywhere
- **Siri & Shortcuts** — "What's my rank in [challenge]?" returns a spoken result without opening the app; works with Apple Intelligence natural language on iOS 18.1+
- **Spotlight search** — challenges indexed in Core Spotlight; tap a result to jump straight to the detail view
- **Home Screen widget** — shows current rank, points, days remaining, and participant count; Smart Stack relevance hints surface it at 7am and 7pm
- **Local notifications** — day-before reminder (5 PM), first-day and last-day nudges, a daily progress reminder, and a final-standings alert the morning after the challenge ends; copy rotates to stay fresh; per-type toggles in Profile; respects iOS notification permission state
- **Background sync** — HealthKit background delivery (observer queries) wakes the app to sync scores when new activity data arrives, even when the app is closed; backed up by a `BGAppRefreshTask` every 15 minutes and the widget timeline reload

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
│   ├── Home/            HomeView, HomeViewModel, HomeChallengeRows (rings card, challenge cards, empty state)
│   ├── Onboarding/      Sign in, HealthKit explanation, name/photo entry
│   ├── Profile/         Data source, health permissions, notification settings, units
│   └── Today/           TodayItem model
├── Models/              Challenge, Participation, DailyScore, AppUser, RingData
├── Scoring/             PointsCalculator, GoalResolver, ScoreAggregator
└── UI/
    ├── Components/      Reusable views (ThreeRingView, EmptyStateView, etc.)
    └── Styles/          Colors, typography, card backgrounds

challenges widget/       WidgetKit extension (target: challenges widgetExtension) — rank, points, days remaining (systemSmall + systemMedium)

ChallengesTests/         Unit tests — PointsCalculator, ScoreAggregator, challenge countdown formatting
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

Sync runs on open (detail view), on home screen load, on HealthKit background delivery (new activity data while the app is closed), and every 15 minutes via background app refresh. The sync result is injected directly into the UI rather than re-fetching from CloudKit, which avoids the read-after-write consistency window inherent in the public CloudKit database.

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
2. Set your development team in both the `Challenges` and `challenges widgetExtension` targets
3. Enable capabilities: **HealthKit** (including **Background Delivery**), **CloudKit**, **Push Notifications**, **Background Modes** (fetch, processing, remote-notification), **Sign in with Apple**, **App Groups**
4. Register App Group `group.studio.ssb.challenges` in the Apple Developer portal for both App IDs (required for the widget to read data written by the main app)

## CloudKit indexes

Set these in the CloudKit Dashboard (required for queries to work):

| Record type | Queryable fields |
|---|---|
| `Challenge` | `inviteCode`, `status`, `startDate`, `creatorRef` |
| `Participation` | `challengeRef`, `userRef`, `status` |
| `DailyScore` | `challengeRef`, `participationRef`, `date` |
| `Workout` | `challengeRef`, `participationRef` |

> **Deploy the schema to Production before distributing.** CloudKit's Development (Xcode runs) and Production (TestFlight/App Store) environments have separate schemas and data. New fields and indexes — e.g. the `Users.avatarAsset` field — must be pushed via **CloudKit Dashboard → Deploy Schema Changes**, or that data silently fails to persist for TestFlight/App Store users.

## Requirements

- iOS 17.0+
- Xcode 16+
- An Apple Developer account (CloudKit and HealthKit require a provisioned device)
