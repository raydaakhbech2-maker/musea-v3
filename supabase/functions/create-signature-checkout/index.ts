import { createClient } from "npm:@supabase/supabase-js@2";
import Stripe from "npm:stripe@^22";

const APP_ORIGIN = "https://raydaakhbech2-maker.github.io";
const APP_URL = "https://raydaakhbech2-maker.github.io/musea-v3/";
const corsHeaders = {
  "Access-Control-Allow-Origin": APP_ORIGIN,
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json" },
});

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Méthode non autorisée." }, 405);
  const origin = req.headers.get("Origin");
  if (origin !== APP_ORIGIN) return json({ error: "Origine non autorisée." }, 403);
  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return json({ error: "Connexion requise." }, 401);

  // Double verrou serveur : le titulaire légal doit explicitement autoriser la facturation
  // après avoir finalisé la conformité et l'onboarding du compte marchand.
  if (Deno.env.get("MUSEA_BILLING_ENABLED") !== "true" ||
      Deno.env.get("MUSEA_MERCHANT_READY") !== "true") {
    return json({ error: "La facturation MUSEA n'est pas encore autorisée par le titulaire du compte marchand." }, 503);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
  const priceId = Deno.env.get("STRIPE_SIGNATURE_PRICE_ID");
  if (!supabaseUrl || !anonKey || !serviceKey || !stripeKey || !priceId) {
    return json({ error: "Configuration de paiement incomplète. Aucun paiement n'a été lancé." }, 503);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authorization } },
  });
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return json({ error: "Session invalide." }, 401);
  if (!user.email || !user.email_confirmed_at) {
    return json({ error: "Une adresse e-mail vérifiée est nécessaire." }, 403);
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const stripe = new Stripe(stripeKey);
    const configuredPrice = await stripe.prices.retrieve(priceId);
    if (!configuredPrice.active || configuredPrice.type !== "recurring" ||
        configuredPrice.currency !== "eur" || configuredPrice.recurring?.interval !== "month" ||
        configuredPrice.recurring?.interval_count !== 1 || Number(configuredPrice.unit_amount) <= 0) {
      return json({ error: "Le tarif Signature doit être un abonnement mensuel actif en euros." }, 503);
    }

    const { data: existingCustomer, error: customerReadError } = await admin
      .from("billing_customers")
      .select("stripe_customer_id")
      .eq("user_id", user.id)
      .maybeSingle();
    if (customerReadError) return json({ error: "Impossible de préparer le compte de paiement." }, 500);

    let customerId = existingCustomer?.stripe_customer_id;
    if (customerId) {
      const customer = await stripe.customers.retrieve(customerId);
      if (!("metadata" in customer) || customer.metadata?.musea_user_id !== user.id) {
        return json({ error: "Le compte client du prestataire ne correspond pas à ce compte MUSEA." }, 409);
      }
    } else {
      const customer = await stripe.customers.create(
        { email: user.email, metadata: { musea_user_id: user.id } },
        { idempotencyKey: "musea-customer-" + user.id },
      );
      customerId = customer.id;
      const { error: saveCustomerError } = await admin.from("billing_customers").upsert({
        user_id: user.id,
        stripe_customer_id: customerId,
        updated_at: new Date().toISOString(),
      });
      if (saveCustomerError) return json({ error: "Impossible d'associer le compte de paiement." }, 500);
    }

    // Stripe reste la source d'autorité pour éviter un second abonnement en cas
    // de webhook retardé ou d'état local temporairement désynchronisé.
    const existingSubscriptions = await stripe.subscriptions.list({
      customer: customerId,
      status: "all",
      limit: 100,
    });
    const blockingStatuses = new Set(["active", "trialing", "past_due", "unpaid", "incomplete", "paused"]);
    if (existingSubscriptions.data.some((subscription) => blockingStatuses.has(subscription.status))) {
      return json({ error: "Un abonnement ou une régularisation existe déjà. Utilise le portail de facturation." }, 409);
    }

    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      customer: customerId,
      client_reference_id: user.id,
      line_items: [{ price: priceId, quantity: 1 }],
      subscription_data: { metadata: { musea_user_id: user.id } },
      success_url: APP_URL + "?billing=success",
      cancel_url: APP_URL + "?billing=cancelled",
      billing_address_collection: "required",
      allow_promotion_codes: false,
    });
    if (!session.url) return json({ error: "Le prestataire n'a pas fourni de page de paiement." }, 502);
    return json({ checkout_url: session.url });
  } catch (_error) {
    return json({ error: "La préparation du paiement a échoué. Aucun accès Signature n'a été accordé." }, 502);
  }
});
