import { createClient } from "npm:@supabase/supabase-js@2";

const APP_ORIGIN = "https://raydaakhbech2-maker.github.io";
const corsHeaders = {
  "Access-Control-Allow-Origin": APP_ORIGIN,
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" },
});

type AIAction = "develop_idea" | "caption" | "translate" | "generate_image" | "edit_image";

function cleanText(value: unknown, max: number): string {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function extractResponseText(payload: any): string {
  if (typeof payload?.output_text === "string" && payload.output_text.trim()) {
    return payload.output_text.trim();
  }
  const chunks: string[] = [];
  for (const item of payload?.output ?? []) {
    for (const part of item?.content ?? []) {
      if (part?.type === "output_text" && typeof part.text === "string") chunks.push(part.text);
    }
  }
  return chunks.join("\n").trim();
}

function buildTextInput(action: Exclude<AIAction, "generate_image">, text: string, style: string, language: string) {
  const safeStyle = style || "libre";
  if (action === "develop_idea") {
    return {
      instructions: "Tu es l'assistant créatif de MUSEA Studio. Aide à développer une intention personnelle sans prendre les décisions à la place du créateur. Réponds en français, de façon concrète, originale et concise. Ne prétends jamais avoir créé ou publié un visuel. Propose un concept, une composition, une ambiance et quelques détails visuels exploitables. Évite les clichés et les imitations directes d'artistes vivants ou de marques.",
      input: "Univers : " + safeStyle + "\nIntention du créateur : " + text + "\nDéveloppe cette idée en un brief créatif clair et original, sans dépasser 220 mots."
    };
  }
  if (action === "caption") {
    return {
      instructions: "Tu es l'assistant éditorial de MUSEA. Rédige une légende naturelle et personnelle qui accompagne une création. N'invente pas de faits sur l'œuvre. Évite les hashtags automatiques, les emojis excessifs et les formules publicitaires. Réponds uniquement avec la légende proposée, en français.",
      input: "Univers : " + safeStyle + "\nNotes du créateur : " + text + "\nÉcris une légende de 1 à 3 phrases."
    };
  }
  return {
    instructions: "Tu es un traducteur attentif. Traduis le texte fourni vers la langue demandée. Préserve le sens, le ton, les noms propres et la mise en forme. N'ajoute aucune explication ni commentaire.",
    input: "Langue cible : " + (language || "English") + "\nTexte à traduire :\n" + text
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Méthode non autorisée." }, 405);
  if (req.headers.get("Origin") !== APP_ORIGIN) return json({ error: "Origine non autorisée." }, 403);

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return json({ error: "Connexion requise." }, 401);

  if (Deno.env.get("MUSEA_AI_ENABLED") !== "true") {
    return json({ error: "L'assistant IA n'est pas encore activé sur le serveur." }, 503);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const openaiKey = Deno.env.get("OPENAI_API_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey || !openaiKey) {
    return json({ error: "Configuration IA incomplète. Aucune requête externe n'a été lancée." }, 503);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authorization } },
  });
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return json({ error: "Session invalide." }, 401);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "Requête JSON invalide." }, 400); }

  const action = body?.action as AIAction;
  if (!["develop_idea", "caption", "translate", "generate_image", "edit_image"].includes(action)) {
    return json({ error: "Action IA inconnue." }, 400);
  }

  const prompt = cleanText(body?.prompt, 1800);
  const style = cleanText(body?.style, 60);
  const language = cleanText(body?.language, 40);
  const imageDataUrl = typeof body?.image_data_url === "string" ? body.image_data_url : "";
  if (prompt.length < 3) return json({ error: "Ajoute quelques mots pour guider l'assistant." }, 400);
  if (action === "translate" && !language) return json({ error: "Choisis une langue cible." }, 400);
  if (action === "edit_image" && (!/^data:image\/webp;base64,[A-Za-z0-9+/=]+$/.test(imageDataUrl) || imageDataUrl.length > 12_000_000)) {
    return json({ error: "Importe d’abord un visuel WebP valide de moins de 8 Mo dans le Studio." }, 400);
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let isSignature = false;
  const { data: subscriptions, error: subscriptionError } = await admin
    .from("billing_subscriptions")
    .select("status,current_period_end")
    .eq("user_id", user.id)
    .in("status", ["active", "trialing"])
    .order("updated_at", { ascending: false })
    .limit(3);
  if (!subscriptionError) {
    const now = Date.now();
    isSignature = (subscriptions ?? []).some((row: any) =>
      !row.current_period_end || new Date(row.current_period_end).getTime() > now
    );
  }

  const isImage = action === "generate_image" || action === "edit_image";
  const dailyLimit = isImage
    ? (isSignature ? 5 : 1)
    : (isSignature ? 80 : 8);
  const { data: claimed, error: quotaError } = await admin.rpc("musea_claim_ai_usage", {
    p_user_id: user.id,
    p_kind: isImage ? "image" : "text",
    p_daily_limit: dailyLimit,
  });
  if (quotaError) return json({ error: "Le contrôle de quota IA est indisponible. Réessaie plus tard." }, 503);
  if (claimed !== true) {
    return json({
      error: isImage
        ? "La limite quotidienne de génération d'images est atteinte. Réessaie demain."
        : "La limite quotidienne de l'assistant est atteinte. Réessaie demain.",
      quota_reached: true,
    }, 429);
  }

  try {
    if (isImage) {
      const imagePrompt = [
        action === "edit_image"
          ? "Edit the supplied image according to the creator's direction. Preserve the important subject, intent and details unless the creator explicitly asks to change them."
          : "Create one original, polished, age-appropriate visual artwork for a creative social platform.",
        "Do not add typography, watermarks, logos, signatures, or UI.",
        "Creative direction: " + (style || "open visual exploration"),
        "Creator direction: " + prompt,
      ].join("\n");
      const imageEndpoint = action === "edit_image"
        ? "https://api.openai.com/v1/images/edits"
        : "https://api.openai.com/v1/images/generations";
      const imageModel = action === "edit_image"
        ? (Deno.env.get("OPENAI_EDIT_MODEL") || "gpt-image-2.5-sunburst")
        : (Deno.env.get("OPENAI_IMAGE_MODEL") || "gpt-image-2.5-flare");
      const imageBody: Record<string, unknown> = {
        model: imageModel,
        prompt: imagePrompt,
        size: "1024x1024",
        quality: "medium",
        output_format: "webp",
        moderation: "auto",
        n: 1,
      };
      if (action === "edit_image") imageBody.images = [{ image_url: imageDataUrl }];
      const imageResponse = await fetch(imageEndpoint, {
        method: "POST",
        headers: { "Authorization": "Bearer " + openaiKey, "Content-Type": "application/json" },
        body: JSON.stringify(imageBody),
        signal: AbortSignal.timeout(90000),
      });
      const imagePayload = await imageResponse.json().catch(() => ({}));
      if (!imageResponse.ok) {
        console.error("OpenAI image error", imageResponse.status, imagePayload?.error?.code || imagePayload?.error?.type || "unknown");
        return json({ error: "La génération d'image a échoué. Vérifie la configuration IA ou réessaie plus tard." }, 502);
      }
      const imageBase64 = imagePayload?.data?.[0]?.b64_json;
      if (typeof imageBase64 !== "string" || imageBase64.length < 100) {
        return json({ error: "Le service IA n'a pas renvoyé d'image exploitable." }, 502);
      }
      return json({ image_base64: imageBase64, mime_type: "image/webp", model: imageModel });
    }

    const model = Deno.env.get("OPENAI_TEXT_MODEL") || "gpt-6-luna";
    const request = buildTextInput(action, prompt, style, language);
    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: { "Authorization": "Bearer " + openaiKey, "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        instructions: request.instructions,
        input: request.input,
        max_output_tokens: 600,
        reasoning: { effort: "low" },
        store: false,
      }),
      signal: AbortSignal.timeout(45000),
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      console.error("OpenAI text error", response.status, payload?.error?.code || payload?.error?.type || "unknown");
      return json({ error: "L'assistant n'a pas pu répondre. Réessaie dans un instant." }, 502);
    }
    const result = extractResponseText(payload);
    if (!result) return json({ error: "L'assistant n'a pas renvoyé de texte exploitable." }, 502);
    return json({ text: result, model });
  } catch (error) {
    console.error("MUSEA AI request failed", error instanceof Error ? error.message : "unknown");
    return json({ error: "Le service IA est momentanément indisponible." }, 502);
  }
});
