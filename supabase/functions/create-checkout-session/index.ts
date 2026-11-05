import { createClient } from "npm:@supabase/supabase-js@2";
import Stripe from "npm:stripe@^22";

const APP_ORIGIN = "https://raydaakhbech2-maker.github.io";
const APP_URL = "https://raydaakhbech2-maker.github.io/musea-v3/";
const corsHeaders = {
  "Access-Control-Allow-Origin": APP_ORIGIN,
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { ...corsHeaders, "Content-Type": "application/json" },
});

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Méthode non autorisée." }, 405);
  const origin = req.headers.get("Origin");
  if (origin && origin !== APP_ORIGIN) return json({ error: "Origine non autorisée." }, 403);
  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return json({ error: "Connexion requise." }, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
  const priceId = Deno.env.get("STRIPE_PRICE_SIGNATURE_MONTHLY");
  const billingEnabled = Deno.env.get("MUSEA_BILLING_ENABLED") === "true";
  if (!url || !anonKey || !serviceKey || !stripeKey || !priceId) {
    return json({ error: "La configuration de paiement est incomplète." }, 503);
  }
  // Keep this deployment in Stripe test mode. Live charges require separate adult approval and review.
  if (!stripeKey.startsWith("sk_test_")) {
    return json({ error: "Seul le mode test Stripe est autorisé sur cette version." }, 503);
  }
  if (!billingEnabled) return json({ error: "Les souscriptions sont temporairement désactivées." }, 403);

  const userClient = createClient(url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authorization } },
  });
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return json({ error: "Session invalide." }, 401);
  if (!user.email) return json({ error: "Une adresse e-mail vérifiée est nécessaire." }, 400);

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: eligibility, error: eligibilityError } = await admin
    .from("billing_checkout_eligibility")
    .select("adult_verified,verified_at")
    .eq("user_id", user.id)
    .maybeSingle();
  if (eligibilityError) return json({ error: "Vérification d'éligibilité indisponible." }, 500);
  if (!eligibility?.adult_verified || !eligibility.verified_at) {
    return json({ error: "La souscription nécessite une validation préalable du titulaire majeur du compte." }, 403);
  }

  const { data: existing, error: existingError } = await admin.from("billing_subscriptions")
    .select("status,current_period_end")
    .eq("user_id", user.id)
    .in("status", ["active", "trialing", "past_due", "incomplete", "unpaid"])
    .order("updated_at", { ascending: false }).limit(1).maybeSingle();
  if (existingError) return json({ error: "État de l'abonnement indisponible." }, 500);
  if (existing && ["active", "trialing", "past_due", "incomplete", "unpaid"].includes(existing.status)) {
    return json({ error: "Un abonnement ou un paiement en cours existe déjà. Utilise le portail de facturation." }, 409);
  }

  const lockToken = crypto.randomUUID();
  const { data: claimed, error: lockError } = await admin.rpc("musea_claim_billing_checkout", {
    p_user_id: user.id, p_lock_token: lockToken,
  });
  if (lockError) return json({ error: "Impossible de réserver cette demande de paiement." }, 500);
  if (claimed !== true) return json({ error: "Une demande de paiement est déjà en cours. Réessaie dans quelques instants." }, 409);

  let keepLock = false;
  try {
    const stripe = new Stripe(stripeKey);
    let customerId: string | null = null;
    const { data: customerRow, error: customerReadError } = await admin.from("billing_customers")
      .select("stripe_customer_id").eq("user_id", user.id).maybeSingle();
    if (customerReadError) throw new Error("Impossible de retrouver le compte client.");
    if (customerRow?.stripe_customer_id) {
      const customer = await stripe.customers.retrieve(customerRow.stripe_customer_id);
      if (!("deleted" in customer) && customer.metadata?.musea_user_id === user.id) {
        customerId = customer.id;
      }
    }
    if (!customerId) {
      const customer = await stripe.customers.create({
        email: user.email,
        name: String(user.user_metadata?.display_name || user.email).slice(0, 120),
        metadata: { musea_user_id: user.id },
      }, { idempotencyKey: "musea-customer-" + user.id });
      customerId = customer.id;
      const { error: saveCustomerError } = await admin.from("billing_customers").upsert({
        user_id: user.id, stripe_customer_id: customerId, updated_at: new Date().toISOString(),
      }, { onConflict: "user_id" });
      if (saveCustomerError) throw new Error("Impossible d'enregistrer le compte de facturation.");
    }

    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      customer: customerId,
      line_items: [{ price: priceId, quantity: 1 }],
      client_reference_id: user.id,
      metadata: { musea_user_id: user.id, musea_checkout_lock_token: lockToken },
      subscription_data: { metadata: { musea_user_id: user.id, musea_checkout_lock_token: lockToken } },
      success_url: APP_URL + "?billing=success",
      cancel_url: APP_URL + "?billing=cancelled",
      allow_promotion_codes: false,
    }, { idempotencyKey: "musea-checkout-" + lockToken });

    if (!session.url || !session.url.startsWith("https://checkout.stripe.com/")) {
      throw new Error("Stripe n'a pas retourné une adresse Checkout valide.");
    }
    keepLock = true;
    return json({ checkout_url: session.url });
  } catch (error) {
    console.error("MUSEA checkout error:", error);
    return json({ error: "Impossible de préparer le paiement. Aucun prélèvement n'a été effectué." }, 503);
  } finally {
    if (!keepLock) {
      await admin.rpc("musea_release_billing_checkout", {
        p_user_id: user.id, p_lock_token: lockToken,
      });
    }
  }
});
