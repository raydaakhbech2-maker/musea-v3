const APP_ORIGIN = "https://raydaakhbech2-maker.github.io";
const corsHeaders = { "Access-Control-Allow-Origin": APP_ORIGIN, "Access-Control-Allow-Headers": "content-type, stripe-signature", "Access-Control-Allow-Methods": "POST, OPTIONS", "Vary": "Origin" };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
function env(name: string) { const value = Deno.env.get(name); if (!value) throw new Error("Configuration serveur manquante : " + name); return value; }
function hex(bytes: Uint8Array) { return Array.from(bytes).map(b => b.toString(16).padStart(2, "0")).join(""); }
async function validSignature(payload: string, header: string, secret: string) {
  const parts = Object.fromEntries(header.split(",").map(x => x.split("=", 2)));
  const timestamp = parts.t;
  const signature = parts.v1;
  if (!timestamp || !signature || Math.abs(Date.now() / 1000 - Number(timestamp)) > 300) return false;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const digest = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(timestamp + "." + payload)));
  const expected = hex(digest);
  if (expected.length !== signature.length) return false;
  let diff = 0; for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ signature.charCodeAt(i);
  return diff === 0;
}
async function stripeGet(path: string) {
  const response = await fetch("https://api.stripe.com/v1/" + path, { headers: { Authorization: "Bearer " + env("STRIPE_SECRET_KEY") } });
  const data = await response.json(); if (!response.ok) throw new Error(data?.error?.message || "Erreur Stripe"); return data;
}
async function db(path: string, method = "GET", body?: unknown) {
  const response = await fetch(env("SUPABASE_URL") + "/rest/v1/" + path, {
    method, headers: { apikey: env("SUPABASE_SERVICE_ROLE_KEY"), Authorization: "Bearer " + env("SUPABASE_SERVICE_ROLE_KEY"), "Content-Type": "application/json", Prefer: "resolution=merge-duplicates,return=minimal" },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!response.ok) throw new Error("Erreur d'écriture dans la base de facturation (" + response.status + "): " + await response.text());
  return response;
}
async function claimBillingEvent(eventId: string, eventType: string) {
  const response = await fetch(env("SUPABASE_URL") + "/rest/v1/rpc/musea_claim_billing_event", {
    method: "POST",
    headers: {
      apikey: env("SUPABASE_SERVICE_ROLE_KEY"),
      Authorization: "Bearer " + env("SUPABASE_SERVICE_ROLE_KEY"),
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ p_stripe_event_id: eventId, p_event_type: eventType }),
  });
  if (!response.ok) throw new Error("Impossible de réserver l’événement Stripe (" + response.status + ").");
  return await response.json() === true;
}
async function completeBillingEvent(eventId: string, errorMessage?: string) {
  const response = await fetch(env("SUPABASE_URL") + "/rest/v1/rpc/musea_complete_billing_event", {
    method: "POST",
    headers: {
      apikey: env("SUPABASE_SERVICE_ROLE_KEY"),
      Authorization: "Bearer " + env("SUPABASE_SERVICE_ROLE_KEY"),
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ p_stripe_event_id: eventId, p_error: errorMessage || null }),
  });
  if (!response.ok) throw new Error("Impossible de clôturer l’événement Stripe (" + response.status + ").");
}
async function userForSubscription(subscription: any) {
  let userId = subscription?.metadata?.user_id;
  if (userId) return userId;
  const id = subscription?.id;
  if (!id) return null;
  const url = new URL(env("SUPABASE_URL") + "/rest/v1/billing_subscriptions");
  url.searchParams.set("select", "user_id"); url.searchParams.set("stripe_subscription_id", "eq." + id); url.searchParams.set("limit", "1");
  const response = await fetch(url, { headers: { apikey: env("SUPABASE_SERVICE_ROLE_KEY"), Authorization: "Bearer " + env("SUPABASE_SERVICE_ROLE_KEY") } });
  if (!response.ok) throw new Error("Recherche de l'abonné impossible.");
  return (await response.json())?.[0]?.user_id || null;
}
async function saveSubscription(sub: any, userId?: string) {
  const owner = userId || await userForSubscription(sub);
  if (!owner || !sub?.id) throw new Error("Abonnement reçu sans identifiant de compte MUSEA.");
  const item = sub.items?.data?.[0];
  await db("billing_subscriptions?on_conflict=stripe_subscription_id", "POST", {
    user_id: owner, stripe_subscription_id: sub.id, stripe_customer_id: typeof sub.customer === "string" ? sub.customer : sub.customer?.id,
    price_id: item?.price?.id || null, status: sub.status,
    current_period_start: sub.current_period_start ? new Date(sub.current_period_start * 1000).toISOString() : null,
    current_period_end: sub.current_period_end ? new Date(sub.current_period_end * 1000).toISOString() : null,
    cancel_at_period_end: !!sub.cancel_at_period_end, updated_at: new Date().toISOString(),
  });
}
async function saveInvoice(invoice: any) {
  const subId = typeof invoice.subscription === "string" ? invoice.subscription : invoice.parent?.subscription_details?.subscription;
  let owner = invoice.metadata?.user_id || null;
  let sub = null;
  if (subId) { sub = await stripeGet("subscriptions/" + subId); owner = owner || await userForSubscription(sub); }
  if (!owner || !invoice?.id) return;
  await db("billing_invoices?on_conflict=stripe_invoice_id", "POST", {
    stripe_invoice_id: invoice.id, user_id: owner, stripe_subscription_id: subId || null,
    status: invoice.status || "draft", currency: (invoice.currency || "eur").toLowerCase(),
    amount_due: invoice.amount_due || 0, amount_paid: invoice.amount_paid || 0,
    hosted_invoice_url: invoice.hosted_invoice_url || null, invoice_pdf: invoice.invoice_pdf || null,
    invoice_created_at: invoice.created ? new Date(invoice.created * 1000).toISOString() : new Date().toISOString(),
    updated_at: new Date().toISOString(),
  });
}
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Méthode non autorisée." }, 405);
  let eventId: string | null = null;
  let eventType: string | null = null;
  try {
    const raw = await req.text();
    const signature = req.headers.get("Stripe-Signature") || "";
    if (!await validSignature(raw, signature, env("STRIPE_WEBHOOK_SECRET"))) return json({ error: "Signature Stripe invalide." }, 400);
    const event = JSON.parse(raw);
    eventId = typeof event.id === "string" ? event.id : null;
    eventType = typeof event.type === "string" ? event.type : null;
    if (!eventId || !eventType) return json({ error: "Événement Stripe incomplet." }, 400);
    const object = event.data?.object;
    const claimed = await claimBillingEvent(eventId, eventType);
    if (!claimed) return json({ received: true, duplicate: true });
    switch (event.type) {
      case "checkout.session.completed":
      case "checkout.session.async_payment_succeeded": {
        if (object?.mode === "subscription" && object.subscription) {
          const sub = await stripeGet("subscriptions/" + object.subscription);
          await saveSubscription(sub, object.client_reference_id || object.metadata?.user_id || sub.metadata?.user_id);
        }
        break;
      }
      case "customer.subscription.created":
      case "customer.subscription.updated":
      case "customer.subscription.deleted":
        await saveSubscription(object);
        break;
      case "invoice.created":
      case "invoice.finalized":
      case "invoice.paid":
      case "invoice.payment_failed":
      case "invoice.updated":
      case "invoice.voided":
        await saveInvoice(object);
        break;
      case "charge.refunded":
      case "charge.dispute.created":
      case "radar.early_fraud_warning.created":
        // Conservés dans le journal d'événements pour rapprochement et traitement antifraude.
        break;
      default:
        break;
    }
    await completeBillingEvent(eventId);
    return json({ received: true });
  } catch (error) {
    console.error("stripe-webhook:", error);
    const message = error instanceof Error ? error.message : "Erreur interne.";
    if (eventId) {
      try {
        await completeBillingEvent(eventId, message.slice(0, 1000));
      } catch (logError) {
        console.error("stripe-webhook journal:", logError);
      }
    }
    return json({ error: message }, message.startsWith("Configuration serveur manquante") ? 503 : 500);
  }
});