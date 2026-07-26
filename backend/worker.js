/**
 * OAuth-only backend for Health Insights.
 *
 * This is the *entire* server: a tiny, stateless Cloudflare Worker whose only
 * job is the OAuth token exchange/refresh for Oura and Withings — because
 * Withings (and, safely, Oura) require a client secret that must never ship
 * inside the iOS app.
 *
 * It stores NOTHING and never sees health data: the app requests tokens here,
 * keeps them in the iOS Keychain, and then calls the provider APIs directly and
 * processes everything on-device.
 *
 * Secrets are provided as Worker environment variables (see wrangler.toml):
 *   OURA_CLIENT_ID, OURA_CLIENT_SECRET
 *   WITHINGS_CLIENT_ID, WITHINGS_CLIENT_SECRET
 *   ALLOWED_REDIRECT  (e.g. healthinsights://oauth)
 *
 * Routes (all POST, JSON body):
 *   /oauth/oura/exchange      { code, redirect_uri, code_verifier? }
 *   /oauth/oura/refresh       { refresh_token }
 *   /oauth/withings/exchange  { code, redirect_uri }
 *   /oauth/withings/refresh   { refresh_token }
 */

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }

    try {
      switch (url.pathname) {
        case "/oauth/oura/exchange":
          return await ouraToken(request, env, "authorization_code");
        case "/oauth/oura/refresh":
          return await ouraToken(request, env, "refresh_token");
        case "/oauth/withings/exchange":
          return await withingsToken(request, env, "authorization_code");
        case "/oauth/withings/refresh":
          return await withingsToken(request, env, "refresh_token");
        default:
          return json({ error: "not_found" }, 404);
      }
    } catch (err) {
      return json({ error: "server_error", detail: String(err) }, 500);
    }
  },
};

// --- Oura -------------------------------------------------------------------

async function ouraToken(request, env, grantType) {
  const body = await request.json();
  const form = new URLSearchParams();
  form.set("grant_type", grantType);
  form.set("client_id", env.OURA_CLIENT_ID);
  form.set("client_secret", env.OURA_CLIENT_SECRET);

  if (grantType === "authorization_code") {
    if (!isAllowedRedirect(body.redirect_uri, env)) {
      return json({ error: "invalid_redirect" }, 400);
    }
    form.set("code", body.code);
    form.set("redirect_uri", body.redirect_uri);
    if (body.code_verifier) form.set("code_verifier", body.code_verifier); // PKCE
  } else {
    form.set("refresh_token", body.refresh_token);
  }

  const resp = await fetch("https://api.ouraring.com/oauth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form,
  });
  return passthrough(resp);
}

// --- Withings ---------------------------------------------------------------

async function withingsToken(request, env, grantType) {
  const body = await request.json();
  const form = new URLSearchParams();
  form.set("action", "requesttoken");
  form.set("grant_type", grantType);
  form.set("client_id", env.WITHINGS_CLIENT_ID);
  form.set("client_secret", env.WITHINGS_CLIENT_SECRET);

  if (grantType === "authorization_code") {
    if (!isAllowedRedirect(body.redirect_uri, env)) {
      return json({ error: "invalid_redirect" }, 400);
    }
    form.set("code", body.code);
    form.set("redirect_uri", body.redirect_uri);
  } else {
    form.set("refresh_token", body.refresh_token);
  }

  const resp = await fetch("https://wbsapi.withings.net/v2/oauth2", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form,
  });
  return passthrough(resp);
}

// --- helpers ----------------------------------------------------------------

function isAllowedRedirect(redirect, env) {
  if (!env.ALLOWED_REDIRECT) return true; // not configured → don't block in dev
  return typeof redirect === "string" && redirect.startsWith(env.ALLOWED_REDIRECT);
}

async function passthrough(resp) {
  const text = await resp.text();
  return new Response(text, {
    status: resp.status,
    headers: { "Content-Type": "application/json" },
  });
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
