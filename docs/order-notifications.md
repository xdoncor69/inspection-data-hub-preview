# Order notifications

The web interface now has Settings → Order notifications and a Notifications shortcut. Notices are created from committed database events; there is no historical backfill. The list remains until Close is selected.

- Non-administrator uploads a nonempty shared PO draft: administrator receives a pending-approval summary, once per draft ID. Editing or retrying does not emit duplicate events.
- Delivery first: administrator receives the delivery number, optional explicitly supplied PO number, and customer. No fabricated PO identifier is shown as a user-supplied reference.
- Administrator approves a PO: the certificate preparer receives its approval notice. If the same transaction also creates an associated ready delivery, the single notice includes that delivery.
- A ready delivery saved against an approved PO: the certificate preparer receives “Delivery available · ready to process.” This does not claim a separate administrator delivery approval. Unresolved or stale matches do not generate a ready notice.

Ariadna's existing Auth account is the initial certificate recipient. Only an administrator can change that recipient in Settings; this changes notification routing only. Drafts are centralized: all signed-in users can view the shared list, normal users edit or delete their own drafts, and the administrator can inspect and approve any draft. Inspection evidence stays administrator-only in backend responses and exports. The pending notice refers to this same shared draft.

## Current activation state

Backend event creation and the persistent notification list are active. On 2026-10-14, the administrator explicitly authorized encrypted transmission of PO/delivery numbers and customer names through browser/device push providers. The `inspection-push` Edge Function version 1 is ACTIVE and `inspection_internal.push_settings.delivery_enabled=true`. Each device still requires its own browser permission and subscription. No device subscription or visible native delivery has been tested or claimed.

The deployed sender matches supabase/functions/inspection-push/index.ts with pinned web-push@3.6.7. VAPID signing and worker-authentication secrets remain in Supabase Vault and never in HTML or git. The function uses custom x-inspection-worker authentication (verify_jwt=false). A request without the worker credential returned HTTP 401; an authenticated server-side empty batch returned HTTP 200 with sent=0 and failed=0 before enabling delivery. The existing minute dispatcher is active. No schema migrations were repeated; activation changed only the existing delivery_enabled setting.

## Device behavior

Enable or disable separately in each browser/device after granting permission on that device. Settings shows one device action: Enable notifications or Disable notifications. Each action explains its effect and asks for confirmation; cancel makes no change. Browser permission (Allowed, Blocked, Not requested or Unavailable) is displayed separately from actual device subscription and server delivery readiness. A browser permission alone is never reported as active push. Pending server setup, offline/error/unknown state and busy operations are explicit; unknown status disables the action until Refresh succeeds. Enabling requests browser permission directly after the synchronous user confirmation. iPhone/iPad require the web app to be added to Home Screen and opened from there. The manifest uses standalone display. The service worker handles only notifications; it does not intercept fetch or cache the application/catalog.

The sender uses encrypted standards-based Web Push to the subscription's provider (Apple, Google, Mozilla or Microsoft). The worker requests requireInteraction and Open app / Close actions, but OS/browser support determines notification duration and available buttons. The in-app list provides reliable persistence until manual dismissal. Native Close actions are queued locally and applied to the correct account's inbox when the app next connects.

Logout clears the worker's active-account binding, disables the subscription best-effort, unsubscribes the browser, and closes visible notifications without blocking offline logout. Delayed messages for a different or signed-out account show no PO/customer information. No access/refresh token is stored in the worker database.

## Backend protections and delivery

Notifications and subscriptions have owner-scoped RLS and no client write grants. Authenticated RPCs enforce account and administrator checks; worker RPCs are service-role-only. Event payloads contain only PO/delivery/customer summaries and status, never line data, physical evidence, or private snapshots. Provider endpoints are allowlisted and validated in both database and sender. A minute cron job dispatches only due work when enabled; per-subscription leases, event keys, backoff and stable notification tags protect retries. Expired endpoints are disabled on 404/410. Web Push is at-least-once; tags reduce duplicate visible notices after uncertain transport results.

## Validation

- SQL role tests: administrator/certificate role routing, normal-user recipient-management denial, inability to forge notifications, blocked worker-secret reads. The initial disabled state and subsequent authorized activation were checked separately.
- Transactional fixture test in tests/order-notifications.sql: pending-draft deduplication, delivery-only naming, combined approval, no duplicate delivery event. All fixtures rolled back; no inspection records created.
- Node worker test: requireInteraction, Close, leading zeros, account isolation and durable dismissal queue. Run node tests/notification-service-worker.test.cjs preview/notification-sw.js in the private repository, or use notification-sw.js in the public repository.
- Pinned Web Push library generated an encrypted aes128gcm request locally without sending a network notification.
- Inline JavaScript and service worker parse checks passed.
- Supabase security advisor: no new warning/error; private worker tables intentionally have RLS and no client policies. An existing leaked-password-protection warning is unrelated to this change.

Native notification display, browser permission acceptance and end-to-end delivery remain untested on real devices. The sender is deployed and payload transmission is authorized; real-device permission acceptance and native delivery still require device enrollment.


## Historical device-control check before activation (2026-10-14)

Code-only checks passed (no browser, screenshots or device notification sends). Both administrator and certificate preparer can read status/inbox RPCs. The server reported delivery_enabled=false, zero active subscriptions and two saved in-app notices. No Edge Functions were deployed. Native push is not operating; the in-app inbox is independent. At that check, the sender was pending authorization; the subsequent activation is documented above. Tests: node tests/push-device-controls.cjs preview/index.html (public: index.html).

## Authorized activation checks (2026-10-14)

- Edge Function inspection-push version 1 deployed and its source retrieved for confirmation.
- Anonymous POST rejected with HTTP 401; authenticated server-side worker request returned HTTP 200, sent=0, failed=0. The secret stayed inside the server-side request.
- Existing dispatcher schedule confirmed active every minute; delivery_enabled changed to true only after the live worker passed.
- David and Ariadna status RPCs report eligible=true and deliveryReady=true. Authenticated client access to worker secrets remains denied.
- Zero active device subscriptions at activation. No fake subscriptions, products, physical observations or test order notices were created.
- Security advisor unchanged: pre-existing leaked-password-protection warning and intentionally policy-free private worker tables.
- No browser, screenshots or device prompts opened. On iPhone/iPad, add the site to Home Screen and open that app before enabling notifications. The device selects its provider automatically; there is no provider selector.
