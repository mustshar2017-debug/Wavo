import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { AccessToken, RoomServiceClient } from "npm:livekit-server-sdk@2.13.3";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return reply({ error: "Method not allowed" }, 405);

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const livekitUrl = Deno.env.get("LIVEKIT_URL")!;
    const livekitApiKey = Deno.env.get("LIVEKIT_API_KEY")!;
    const livekitApiSecret = Deno.env.get("LIVEKIT_API_SECRET")!;

    if (!supabaseUrl || !serviceRoleKey || !livekitUrl || !livekitApiKey || !livekitApiSecret) {
      return reply({ error: "Server configuration is incomplete" }, 500);
    }

    const authorization = req.headers.get("Authorization") ?? "";
    const jwt = authorization.replace(/^Bearer\s+/i, "");
    if (!jwt) return reply({ error: "Authentication required" }, 401);

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await admin.auth.getUser(jwt);
    const user = authData?.user;
    if (authError || !user) return reply({ error: "Invalid or expired login" }, 401);

    const body = await req.json();
    const action = String(body.action ?? "");
    const isOwner = await admin
      .from("wavo_live_admins")
      .select("user_id")
      .eq("user_id", user.id)
      .maybeSingle();

    if (isOwner.error) return reply({ error: "Could not verify live administrator" }, 500);
    const isAdmin = Boolean(isOwner.data);

    if (action === "start") {
      if (!isAdmin) {
        const { count, error } = await admin
          .from("wavo_follows")
          .select("id", { count: "exact", head: true })
          .eq("following_id", user.id);
        if (error) return reply({ error: "Could not verify follower count" }, 500);
        if ((count ?? 0) < 500) {
          return reply({ error: "Starting a live broadcast requires 500 followers", followers: count ?? 0, required: 500 }, 403);
        }
      }

      const title = String(body.title ?? "بث مباشر").trim().slice(0, 120) || "بث مباشر";
      const roomName = `wavo_${crypto.randomUUID().replaceAll("-", "")}`;
      const { data: session, error: insertError } = await admin
        .from("wavo_live_sessions")
        .insert({ room_name: roomName, host_user_id: user.id, title, status: "live" })
        .select("id, room_name, title, status, started_at, host_user_id")
        .single();

      if (insertError || !session) return reply({ error: "Could not create live session" }, 500);

      const token = new AccessToken(livekitApiKey, livekitApiSecret, {
        identity: user.id,
        name: user.user_metadata?.display_name ?? user.email ?? "WAVO host",
        ttl: "2h",
      });
      token.addGrant({ roomJoin: true, room: roomName, canPublish: true, canSubscribe: true });
      return reply({ session, token: await token.toJwt(), serverUrl: livekitUrl, role: "host" });
    }

    if (action === "watch") {
      const sessionId = String(body.session_id ?? "");
      if (!sessionId) return reply({ error: "session_id is required" }, 400);
      const { data: session, error } = await admin
        .from("wavo_live_sessions")
        .select("id, room_name, title, status, started_at, host_user_id")
        .eq("id", sessionId)
        .eq("status", "live")
        .maybeSingle();

      if (error) return reply({ error: "Could not load live session" }, 500);
      if (!session) return reply({ error: "This live broadcast has ended" }, 404);

      const token = new AccessToken(livekitApiKey, livekitApiSecret, {
        identity: user.id,
        name: user.user_metadata?.display_name ?? user.email ?? "WAVO viewer",
        ttl: "2h",
      });
      token.addGrant({ roomJoin: true, room: session.room_name, canPublish: false, canSubscribe: true });
      return reply({ session, token: await token.toJwt(), serverUrl: livekitUrl, role: "viewer" });
    }

    if (action === "end") {
      const sessionId = String(body.session_id ?? "");
      if (!sessionId) return reply({ error: "session_id is required" }, 400);
      const { data: session, error: loadError } = await admin
        .from("wavo_live_sessions")
        .select("id, room_name, host_user_id, status")
        .eq("id", sessionId)
        .maybeSingle();

      if (loadError) return reply({ error: "Could not load live session" }, 500);
      if (!session) return reply({ error: "Live session not found" }, 404);
      if (session.host_user_id !== user.id && !isAdmin) return reply({ error: "Not allowed to end this broadcast" }, 403);

      const { error: updateError } = await admin
        .from("wavo_live_sessions")
        .update({ status: "ended", ended_at: new Date().toISOString() })
        .eq("id", sessionId);
      if (updateError) return reply({ error: "Could not end live session" }, 500);

      try {
        const rooms = new RoomServiceClient(livekitUrl, livekitApiKey, livekitApiSecret);
        await rooms.deleteRoom(session.room_name);
      } catch (_) {
        // Session is marked ended even if LiveKit room cleanup is delayed.
      }
      return reply({ success: true, session_id: sessionId });
    }

    return reply({ error: "Unknown action. Use start, watch, or end." }, 400);
  } catch (error) {
    console.error("wavo-live-token error:", error);
    return reply({ error: "Unexpected server error" }, 500);
  }
});
