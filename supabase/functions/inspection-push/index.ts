import webpush from 'npm:web-push@3.6.7';

const base = Deno.env.get('SUPABASE_URL')!;
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
async function rpc(name: string, body: unknown = {}) {
  const response = await fetch(base + '/rest/v1/rpc/' + name, {
    method: 'POST',
    headers: { apikey: serviceKey, Authorization: 'Bearer ' + serviceKey, 'Content-Type': 'application/json' },
    body: JSON.stringify(body), signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw new Error('Notification database request failed: ' + response.status);
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}
function equalSecret(a: string, b: string) {
  if (!a || !b || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
function supportedEndpoint(endpoint: string) {
  const url = new URL(endpoint);
  return url.protocol === 'https:' && !url.port && !url.username && !url.password &&
    /^(fcm\.googleapis\.com|updates\.push\.services\.mozilla\.com|[a-zA-Z0-9.-]+\.push\.apple\.com|[a-zA-Z0-9.-]+\.notify\.windows\.com)$/.test(url.hostname);
}
Deno.serve(async (request: Request) => {
  if (request.method !== 'POST') return new Response('Method not allowed', { status: 405 });
  const supplied = request.headers.get('x-inspection-worker') || '';
  if (!/^[a-f0-9]{64}$/.test(supplied)) return new Response('Unauthorized', { status: 401 });
  try {
    // Custom authentication is required for pg_cron; no user can invoke the worker.
    const config = await rpc('inspection_push_worker_config');
    if (!equalSecret(supplied, config.workerSecret)) return new Response('Unauthorized', { status: 401 });
    const jobs = await rpc('inspection_push_claim_jobs');
    let sent = 0, failed = 0;
    for (let i = 0; i < jobs.length; i += 5) {
      await Promise.all(jobs.slice(i, i + 5).map(async (job: any) => {
        let status = 0;
        try {
          if (!supportedEndpoint(job.subscription.endpoint)) status = 410;
          else {
            const result = await webpush.sendNotification(job.subscription, JSON.stringify(job.payload), {
              TTL: 86400, urgency: 'normal', timeout: 10000,
              vapidDetails: { subject: 'mailto:david.rodriguez@hapcor.com', publicKey: config.publicKey, privateKey: config.privateKey },
            });
            status = result.statusCode;
          }
        } catch (error) { status = Number((error as any)?.statusCode) || 0; }
        await rpc('inspection_push_finish_job', { notification_id: job.notificationId, subscription_id: job.subscriptionId, lease_id: job.leaseId, status });
        if (status >= 200 && status < 300) sent++; else failed++;
      }));
    }
    return Response.json({ sent, failed });
  } catch {
    // Never log endpoints, subscriptions, message content, tokens, or signing keys.
    return new Response('Notification dispatch unavailable; queued jobs will retry.', { status: 503 });
  }
});
