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
  if (!url || !anonKey || !serviceKey || !stripeKey) return json({ error: "Configuration incomplète." }, 503);

  const userClient = createClient(url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authorization } },
  });
  const { data: { user }, error } = await userClient.auth.getUser();
  if (error || !user) return json({ error: "Session invalide." }, 401);

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: customer, error: customerError } = await admin.from("billing_customers")
    .select("stripe_customer_id").eq("user_id", user.id).maybeSingle();
  if (customerError) return json({ error: "Impossible de retrouver le compte de facturation." }, 500);
  if (!customer?.stripe_customer_id) return json({ error: "Aucun compte de facturation associé." }, 404);

  try {
    const stripe = new Stripe(stripeKey);
    const session = await stripe.billingPortal.sessions.create({
      customer: customer.stripe_customer_id,
      return_url: APP_URL,
    });
    return json({ portal_url: session.url });
  } catch (_error) {
    return json({ error: "Le portail de facturation n'est pas encore configuré." }, 503);
  }
});
