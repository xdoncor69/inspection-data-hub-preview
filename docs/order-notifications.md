# Order notifications

The web interface now has Settings → Order notifications and a Notifications shortcut. Notices are created from committed database events; there is no historical backfill. The list remains until Close is selected.

- Non-administrator uploads a nonempty private PO draft: administrator receives a pending-approval summary, once per draft ID. Editing or retrying does not emit duplicate events.
- Delivery first: administrator receives the delivery number, optional explicitly supplied PO number, and customer. No fabricated PO identifier is shown as a user-supplied reference.
- Administrator approves a PO: the certificate preparer receives its approval notice. If the same transaction also creates an associated ready delivery, the single notice includes that delivery.
- A ready delivery saved against an approved PO: the certificate preparer receives “Delivery available · ready to process.” This does not claim a separate administrator delivery approval. Unresolved or stale matches do not generate a ready notice.

Ariadna's existing Auth account is the initial certificate recipient. Only an administrator can change that recipient in Settings; this changes notification routing only. Existing catalog, private-draft, file and inspection-evidence permissions remain. A private-draft notice contains a summary and does not grant access to another user's draft contents.

## Current activation state

Backend event creation and the persistent notification list are active. External Web Push delivery is **disabled** (inspection_internal.push_settings.delivery_enabled=false). Automatic approval review rejected deploying the edge sender because PO/customer payloads would be transmitted to external browser push providers without separate explicit authorization. No native push delivery has been performed or claimed.

The reviewed sender is prepared at supabase/functions/inspection-push/index.ts with pinned web-push@3.6.7. VAPID signing and worker-authentication secrets are in Supabase Vault and never in HTML or git. After explicit authorization, deploy the sender with custom x-inspection-worker authentication (verify_jwt=false), check authentication and an empty worker batch, then enable delivery_enabled. Do not enable before deployment verification.

## Device behavior

Enable or disable separately in each browser/device after setup authorization. Enabling uses an explicit permission button. iPhone/iPad require the web app to be added to Home Screen and opened from there. The manifest uses standalone display. The service worker handles only notifications; it does not intercept fetch or cache the application/catalog.

The sender uses encrypted standards-based Web Push to the subscription's provider (Apple, Google, Mozilla or Microsoft). The worker requests requireInteraction and Open app / Close actions, but OS/browser support determines notification duration and available buttons. The in-app list provides reliable persistence until manual dismissal. Native Close actions are queued locally and applied to the correct account's inbox when the app next connects.

Logout clears the worker's active-account binding, disables the subscription best-effort, unsubscribes the browser, and closes visible notifications without blocking offline logout. Delayed messages for a different or signed-out account show no PO/customer information. No access/refresh token is stored in the worker database.

## Backend protections and delivery

Notifications and subscriptions have owner-scoped RLS and no client write grants. Authenticated RPCs enforce account and administrator checks; worker RPCs are service-role-only. Event payloads contain only PO/delivery/customer summaries and status, never line data, physical evidence, or private snapshots. Provider endpoints are allowlisted and validated in both database and sender. A minute cron job dispatches only due work when enabled; per-subscription leases, event keys, backoff and stable notification tags protect retries. Expired endpoints are disabled on 404/410. Web Push is at-least-once; tags reduce duplicate visible notices after uncertain transport results.

## Validation

- SQL role tests: administrator/certificate role routing, normal-user recipient-management denial, inability to forge notifications, blocked worker-secret reads, external delivery disabled.
- Transactional fixture test in tests/order-notifications.sql: pending-draft deduplication, delivery-only naming, combined approval, no duplicate delivery event. All fixtures rolled back; no inspection records created.
- Node worker test: requireInteraction, Close, leading zeros, account isolation and durable dismissal queue. Run node tests/notification-service-worker.test.cjs preview/notification-sw.js in the private repository, or use notification-sw.js in the public repository.
- Pinned Web Push library generated an encrypted aes128gcm request locally without sending a network notification.
- Inline JavaScript and service worker parse checks passed.
- Supabase security advisor: no new warning/error; private worker tables intentionally have RLS and no client policies. An existing leaked-password-protection warning is unrelated to this change.

Native notification display, browser permission acceptance and end-to-end delivery remain untested on real devices. The sender deployment and payload authorization remain pending.
