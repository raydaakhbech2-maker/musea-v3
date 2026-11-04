import { createClient } from "npm:@supabase/supabase-js@2";
import Stripe from "npm:stripe@^22";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Méthode non autorisée." }, 405);
  const signature = req.headers.get("Stripe-Signature");
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
  const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SIGNING_SECRET");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!signature || !stripeKey || !webhookSecret || !supabaseUrl || !serviceKey) {
    return json({ error: "Configuration webhook incomplète." }, 503);
  }

  const stripe = new Stripe(stripeKey);
  const cryptoProvider = Stripe.createSubtleCryptoProvider();
  const rawBody = await req.text();
  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      rawBody, signature, webhookSecret, undefined, cryptoProvider,
    );
  } catch (_error) {
    return json({ error: "Signature Stripe invalide." }, 400);
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  async function saveSubscription(subscription: any) {
    const customerId = typeof subscription.customer === "string"
      ? subscription.customer : subscription.customer.id;
    let userId = subscription.metadata?.musea_user_id;
    if (!userId) {
      const { data: customerRow } = await admin.from("billing_customers")
        .select("user_id").eq("stripe_customer_id", customerId).maybeSingle();
      userId = customerRow?.user_id;
    }
    if (!userId) throw new Error("Abonné MUSEA introuvable pour cet abonnement.");
    const firstItem = subscription.items.data[0];
    // Stripe a déplacé les périodes de facturation vers les Subscription Items
    // dans les versions d'API récentes ; les deux formes sont lues pour rester robuste.
    const subscriptionRecord = subscription as Record<string, any>;
    const periodStart = subscriptionRecord.current_period_start ?? firstItem?.current_period_start ?? null;
    const periodEnd = subscriptionRecord.current_period_end ?? firstItem?.current_period_end ?? null;
    const { error } = await admin.from("billing_subscriptions").upsert({
      user_id: userId,
      stripe_subscription_id: subscription.id,
      stripe_customer_id: customerId,
      price_id: firstItem?.price?.id ?? null,
      status: subscription.status,
      current_period_start: periodStart
        ? new Date(periodStart * 1000).toISOString() : null,
      current_period_end: periodEnd
        ? new Date(periodEnd * 1000).toISOString() : null,
      cancel_at_period_end: subscription.cancel_at_period_end,
      updated_at: new Date().toISOString(),
    }, { onConflict: "stripe_subscription_id" });
    if (error) throw error;
    return userId;
  }

  try {
    if (event.type.startsWith("customer.subscription.")) {
      const subscriptionId = (event.data.object as Stripe.Subscription).id;
      // Relire l'état actuel chez Stripe évite qu'un webhook ancien arrivé en retard
      // écrase l'état plus récent de l'abonnement dans notre base.
      const currentSubscription = await stripe.subscriptions.retrieve(subscriptionId);
      await saveSubscription(currentSubscription);
    } else if (event.type === "checkout.session.completed") {
      const session = event.data.object as Stripe.Checkout.Session;
      const subscriptionId = typeof session.subscription === "string"
        ? session.subscription : session.subscription?.id;
      if (subscriptionId) {
        const subscription = await stripe.subscriptions.retrieve(subscriptionId);
        await saveSubscription(subscription);
      }
    } else if (event.type === "invoice.paid" || event.type === "invoice.payment_failed") {
      const invoiceEvent = event.data.object as Stripe.Invoice;
      const invoice = await stripe.invoices.retrieve(invoiceEvent.id) as any;
      const subscriptionId = invoice.subscription ??
        invoice.parent?.subscription_details?.subscription ?? null;
      let userId: string | null = null;
      if (subscriptionId) {
        const subscription = await stripe.subscriptions.retrieve(subscriptionId);
        userId = await saveSubscription(subscription);
      } else {
        const customerId = typeof invoice.customer === "string" ? invoice.customer : invoice.customer?.id;
        if (customerId) {
          const { data: customerRow } = await admin.from("billing_customers")
            .select("user_id").eq("stripe_customer_id", customerId).maybeSingle();
          userId = customerRow?.user_id ?? null;
        }
      }
      if (userId) {
        const customerId = typeof invoice.customer === "string" ? invoice.customer : invoice.customer?.id ?? "";
        const { error } = await admin.from("billing_invoices").upsert({
          stripe_invoice_id: invoice.id,
          user_id: userId,
          stripe_subscription_id: subscriptionId,
          status: invoice.status ?? (event.type === "invoice.paid" ? "paid" : "payment_failed"),
          currency: invoice.currency ?? "eur",
          amount_due: invoice.amount_due ?? 0,
          amount_paid: invoice.amount_paid ?? 0,
          hosted_invoice_url: invoice.hosted_invoice_url ?? null,
          invoice_pdf: invoice.invoice_pdf ?? null,
          invoice_created_at: invoice.created ? new Date(invoice.created * 1000).toISOString() : null,
          updated_at: new Date().toISOString(),
        }, { onConflict: "stripe_invoice_id" });
        if (error) throw error;
      }
    }

    const { error: eventLogError } = await admin.from("billing_webhook_events").upsert({
      stripe_event_id: event.id,
      event_type: event.type,
    }, { onConflict: "stripe_event_id", ignoreDuplicates: true });
    if (eventLogError) throw eventLogError;
    return json({ received: true });
  } catch (_error) {
    // Stripe doit réessayer si la mise à jour en base a échoué.
    return json({ error: "Événement reçu mais non enregistré. Une nouvelle tentative sera demandée." }, 500);
  }
});
