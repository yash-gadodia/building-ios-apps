# Go-Live Checklist

The app is built to run as a zero-setup demo (gated stubs). This is the ordered path to a real, shipped app — earlier steps gate later ones. Most is infra/creds.

## 1. Identity & build pipeline
- [ ] Real iOS `bundleIdentifier` in `app.json` (replace `com.anonymous.*`).
- [ ] `npx eas init` → adds EAS `projectId` (unlocks push tokens + builds).
- [ ] `EXPO_TOKEN` repo secret for CI/CD.
- [ ] Apple Developer account → App Store Connect record → enable TestFlight.

## 2. Production backend
- [ ] Create prod Supabase project. `supabase link`.
- [ ] `supabase db push` to apply all migrations `0001`→`00NN`.
- [ ] Set auth redirect URL (`<scheme>://auth-callback`).
- [ ] Deploy edge functions; set `verify_jwt = true`; rate-limit any that spend tokens (AI).
- [ ] Put prod URL + anon key in the app env.

## 3. Keys / providers (each unlocks a gated stub)
- [ ] AI provider key (set as a Supabase secret).
- [ ] Payments (RevenueCat): SDK keys + products + entitlement + pricing.
- [ ] Google / Apple OAuth → Supabase providers.
- [ ] Email (Resend etc.): verify domain + SMTP password (prod confirmation emails).
- [ ] Analytics key (optional; no-ops until set).

## 4. Push notifications
- [ ] EAS: APNs (iOS) + FCM (Android) via `eas credentials`.
- [ ] Pass `projectId` to `getExpoPushTokenAsync`.

## 5. Recurring jobs
- [ ] Schedule any daily/cron DB function (pg_cron or scheduled edge fn) — it won't run in prod until something calls it.

## 6. Compliance (App Store checks)
- [ ] Privacy Policy + Terms URLs (mandatory for personal data).
- [ ] Full account deletion incl. the Supabase **Auth** record (a `service_role` step beyond the data delete).
- [ ] Cost budgets/alerts (AI + Supabase + EAS).

## 7. Before public launch
- [ ] Staging env (separate Supabase project + EAS preview channel).
- [ ] Universal (https) deep links if used.
- [ ] Gate any demo-only RPC (e.g. a solo self-reveal) out of prod.

## Verify locally any time
```bash
npm install --legacy-peer-deps && npm run typecheck && npx jest --ci && npx expo export -p ios
supabase db reset && supabase test db
```
