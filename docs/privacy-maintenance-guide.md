# Privacy Policy Maintenance Guide

## When to Update PRIVACY_POLICY.md

Update the privacy policy whenever the app starts collecting a **new category** of personal data or changes **how** existing data is used. You do NOT need to update for every code change.

### Triggers That Require a Privacy Policy Update

| Trigger | Example | What to Update |
|---|---|---|
| New data type collected from user | Workout history, body measurements, goals | Section 2 (What Data We Collect) |
| New third-party service integrated | Analytics (e.g., Firebase Analytics), crash reporting, push notifications | Section 7 (Third-Party Services) |
| Data shared with new parties | Coaches seeing athlete data, leaderboards | Section 3 (How We Use Your Data) |
| New communication channel | In-app messaging, push notifications, email | Section 2 and Section 3 |
| Data export or portability feature | JSON export of workout history | Section 6 (Your Rights) |
| Change in data storage region | Multi-region Firestore setup | Section 4 (Where Data Is Stored) |
| Monetization or advertising added | Ads, premium subscriptions with payment data | New section needed |

### Triggers That Do NOT Require an Update

- Refactoring existing code without changing data collected
- Adding UI screens that display existing data
- Bug fixes
- New Cloud Functions that operate on existing data types
- Firestore security rule changes

## Checklist for New Features

Before shipping a new feature, ask:

1. Does this feature collect data the user hasn't already provided?
2. Does this feature share user data with a new party or service?
3. Does this feature change how long we retain data?

If **any answer is yes**, update `PRIVACY_POLICY.md` and bump the "Last updated" date.

## Upcoming Features That Will Likely Need Updates

- [ ] Workout instance tracking (workout history, exercise actuals, RPE data)
- [ ] Program enrollment (sharing user data with program owner/coach)
- [ ] In-app messaging (direct messages between users)
- [ ] Push notifications (if added)
- [ ] Firebase Analytics or Crashlytics (if added)
- [ ] Data export feature
