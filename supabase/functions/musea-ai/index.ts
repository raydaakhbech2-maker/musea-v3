import { createClient } from "npm:@supabase/supabase-js@2";

const APP_ORIGIN = "https://raydaakhbech2-maker.github.io";
const corsHeaders = {
  "Access-Control-Allow-Origin": APP_ORIGIN,
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

const allowedTasks = new Set(["assistant", "translate", "creative_ideas", "caption"]);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Méthode non autorisée." }, 405);

  const origin = req.headers.get("Origin");
  if (origin && origin !== APP_ORIGIN) return json({ error: "Origine non autorisée." }, 403);

  const authorization = req.headers.get("Authorization") || "";
  if (!authorization.startsWith("Bearer ")) return json({ error: "Connexion requise." }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const openaiKey = Deno.env.get("OPENAI_API_KEY");
  if (!supabaseUrl || !supabaseAnonKey || !openaiKey) {
    return json({ error: "Configuration serveur incomplète. Vérifie les secrets Supabase." }, 500);
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) return json({ error: "Session invalide. Reconnecte-toi." }, 401);

    const body = await req.json().catch(() => null);
    const task = typeof body?.task === "string" ? body.task : "assistant";
    const prompt = typeof body?.prompt === "string" ? body.prompt.trim() : "";
    const targetLanguage = typeof body?.targetLanguage === "string" ? body.targetLanguage.slice(0, 40) : "Français";
    const context = typeof body?.context === "string" ? body.context.slice(0, 3000) : "";

    if (!allowedTasks.has(task)) return json({ error: "Action non autorisée." }, 400);
    if (!prompt || prompt.length > 8000) return json({ error: "Le texte doit contenir entre 1 et 8 000 caractères." }, 400);

    const instructions = task === "translate"
      ? `Tu es le traducteur intégré de MUSEA. Traduis fidèlement le texte fourni en ${targetLanguage}. Conserve le sens, le ton, les noms propres et la mise en forme. Retourne uniquement la traduction.`
      : task === "creative_ideas"
      ? "Tu es le partenaire créatif de MUSEA. Propose des idées originales, concrètes et adaptées au brief. Ne prétends pas avoir créé une image ou publié quoi que ce soit."
      : task === "caption"
      ? "Tu aides à rédiger une légende de publication MUSEA. Propose un texte naturel, original, adapté au contexte et sans hashtags excessifs."
      : "Tu es l'assistant de MUSEA, un réseau social créatif. Réponds clairement, utilement et en français sauf demande contraire. N'affirme jamais avoir effectué une action dans l'application.";

    const userContent = context ? `Contexte :\n${context}\n\nDemande :\n${prompt}` : prompt;
    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${openaiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4.1-mini",
        messages: [
          { role: "system", content: instructions },
          { role: "user", content: userContent },
        ],
        temperature: task === "translate" ? 0.2 : 0.7,
        max_tokens: 1200,
      }),
    });

    const result = await response.json().catch(() => ({}));
    if (!response.ok) {
      console.error("OpenAI API error:", response.status, result?.error?.type || result?.error?.code || "unknown");
      const status = response.status === 429 ? 429 : 502;
      return json({ error: response.status === 429
        ? "Limite d’utilisation atteinte ou crédit API insuffisant."
        : "Le service IA est momentanément indisponible." }, status);
    }

    const output = result?.choices?.[0]?.message?.content?.trim();
    if (!output) return json({ error: "L’IA n’a pas renvoyé de réponse exploitable." }, 502);
    return json({ result: output, usage: result?.usage ?? null });
  } catch (error) {
    console.error("musea-ai error:", error instanceof Error ? error.message : "unknown");
    return json({ error: "Une erreur est survenue lors du traitement IA." }, 500);
  }
});
