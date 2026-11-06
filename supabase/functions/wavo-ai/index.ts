// WAVO AI Edge Function — deploy as supabase/functions/wavo-ai/index.ts
// Supabase verifies the user JWT before this function runs (verify_jwt=true by default).
const corsHeaders = { "Access-Control-Allow-Origin": "https://mustshar2017-debug.github.io", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS", "Content-Type": "application/json; charset=utf-8" };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: corsHeaders });
const modes = new Set(["assistant", "caption", "hashtags", "translate"]);
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) return json({ error: "AI service is not configured. Add OPENAI_API_KEY to Supabase Edge Function secrets." }, 503);
  try {
    const body = await req.json();
    const message = typeof body.message === "string" ? body.message.trim() : "";
    const mode = modes.has(body.mode) ? body.mode : "assistant";
    const language = ["ar", "en", "fr"].includes(body.language) ? body.language : "ar";
    if (!message) return json({ error: "Message is required" }, 400);
    if (message.length > 2500) return json({ error: "Message is too long" }, 413);
    const langName = language === "ar" ? "Arabic" : language === "fr" ? "French" : "English";
    const modeInstructions: Record<string, string> = {
      assistant: "You are WAVO AI, a helpful, respectful assistant inside the WAVO short-video community. Help with platform use, ideas, and general questions. Never claim you performed an action you did not perform.",
      caption: "Create an engaging, natural short-video caption from the user description. Give one polished caption and keep it concise.",
      hashtags: "Suggest 8 to 12 relevant, non-misleading hashtags for the described video. Return hashtags only, separated by spaces.",
      translate: "Translate the user text. If the target language is not specified, translate it into the requested interface language. Preserve meaning and formatting."
    };
    const history = Array.isArray(body.history) ? body.history.slice(-8).filter((m: any) => ["user", "assistant"].includes(m?.role) && typeof m?.content === "string").map((m: any) => ({ role: m.role, content: m.content.slice(0, 2500) })) : [];
    const input = [{ role: "system", content: modeInstructions[mode] + " Respond in " + langName + ", unless the user explicitly requests another language. Keep answers suitable for a general audience." }, ...history, { role: "user", content: message }];
    const upstream = await fetch("https://api.openai.com/v1/responses", { method: "POST", headers: { "Authorization": "Bearer " + apiKey, "Content-Type": "application/json" }, body: JSON.stringify({ model: Deno.env.get("OPENAI_MODEL") || "gpt-4.1-mini", input, max_output_tokens: 550, store: false }) });
    const result = await upstream.json();
    if (!upstream.ok) { console.error("OpenAI API error", upstream.status, result?.error?.code || "unknown"); return json({ error: "AI provider request failed", provider_status: upstream.status }, 502); }
    const reply = (result.output || []).flatMap((item: any) => item.content || []).filter((part: any) => part.type === "output_text").map((part: any) => part.text).join("\n").trim();
    if (!reply) return json({ error: "The AI provider returned an empty response." }, 502);
    return json({ reply });
  } catch (error) { console.error("WAVO AI function error", error); return json({ error: "Invalid request or temporary AI service error." }, 500); }
});
