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

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Méthode non autorisée." }, 405);
  const origin = req.headers.get("Origin");
  if (origin && origin !== APP_ORIGIN) return json({ error: "Origine non autorisée." }, 403);

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return json({ error: "Connexion requise." }, 401);

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

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: activeRows, error: activeError } = await admin
    .from("billing_subscriptions")
    .select("stripe_subscription_id,status,current_period_end")
    .eq("user_id", user.id)
    .in("status", ["active", "trialing"])
    .order("current_period_end", { ascending: false })
    .limit(1);
  if (activeError) return json({ error: "Impossible de vérifier l'abonnement." }, 500);
  if (activeRows?.length) return json({ error: "Un abonnement Signature est déjà actif." }, 409);

  const stripe = new Stripe(stripeKey);
  const { data: existingCustomer, error: customerReadError } = await admin
    .from("billing_customers")
    .select("stripe_customer_id")
    .eq("user_id", user.id)
    .maybeSingle();
  if (customerReadError) return json({ error: "Impossible de préparer le compte de paiement." }, 500);

  let customerId = existingCustomer?.stripe_customer_id;
  if (!customerId) {
    const customer = await stripe.customers.create(
      { email: user.email, metadata: { musea_user_id: user.id } },
      { idempotencyKey: `musea-customer-${user.id}` },
    );
    customerId = customer.id;
    const { error: saveCustomerError } = await admin.from("billing_customers").upsert({
      user_id: user.id,
      stripe_customer_id: customerId,
      updated_at: new Date().toISOString(),
    });
    if (saveCustomerError) return json({ error: "Impossible d'associer le compte de paiement." }, 500);
  }

  try {
    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      customer: customerId,
      client_reference_id: user.id,
      line_items: [{ price: priceId, quantity: 1 }],
      subscription_data: { metadata: { musea_user_id: user.id } },
      success_url: APP_URL + "?billing=success",
      cancel_url: APP_URL + "?billing=cancelled",
      allow_promotion_codes: false,
    });
    if (!session.url) return json({ error: "Le prestataire n'a pas fourni de page de paiement." }, 502);
    return json({ checkout_url: session.url });
  } catch (_error) {
    return json({ error: "La session de paiement n'a pas pu être créée." }, 502);
  }
});
