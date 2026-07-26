# Optional OAuth backend

**You almost certainly don't need this.** The app now performs the entire
Oura/Withings OAuth flow **on-device**, storing your own developer credentials in
the iPhone Keychain (set up from **Settings ▸ Integrations** in the app). No
server is involved and no health data ever leaves your phone.

This folder is kept for two optional situations:

1. **Withings HTTPS redirect helper.** Withings sometimes requires an `https://`
   callback URL and may reject the app's `healthinsights://` custom scheme. If
   that happens, host a tiny HTTPS page that 302-redirects to
   `healthinsights://oauth/withings` (preserving the query string) and register
   *that* URL with Withings.
2. **Backend token exchange.** If you'd rather not keep a client secret on the
   device at all, the stateless Worker below performs the token exchange/refresh
   server-side instead. It stores nothing and never sees health data.

Apple Health needs none of this.

## What it does

| Route | Purpose |
|-------|---------|
| `POST /oauth/oura/exchange` | Swap an authorization `code` for tokens (Oura) |
| `POST /oauth/oura/refresh` | Refresh an expired Oura access token |
| `POST /oauth/withings/exchange` | Swap a `code` for tokens (Withings) |
| `POST /oauth/withings/refresh` | Refresh an expired Withings access token |

The app opens the provider's consent page with `ASWebAuthenticationSession`,
receives the `code` on the `healthinsights://oauth/...` redirect, posts it here,
and stores the returned tokens in the iOS Keychain. Subsequent provider API
calls (reading Oura/Withings data) go **directly** from the app to the provider.

## Deploy (Cloudflare Workers, free tier)

```bash
npm i -g wrangler
cd ios/backend
wrangler deploy
wrangler secret put OURA_CLIENT_SECRET
wrangler secret put WITHINGS_CLIENT_SECRET
```

Then set the client IDs in `wrangler.toml` (`[vars]`), and put the resulting
Worker URL into the app's `Info.plist` under `OAuthBackendBaseURL`
(e.g. `https://health-insights-oauth.<you>.workers.dev`). Until that key is set,
the Oura/Withings rows in Settings show as "unavailable" by design.

> The same handler is trivially portable to Vercel/Netlify functions or AWS
> Lambda; only the request/response wrapper differs.

## Register the developer apps

- **Oura**: https://cloud.ouraring.com/oauth/applications — redirect URI
  `healthinsights://oauth/oura`.
- **Withings**: https://developer.withings.com/ — redirect URI
  `healthinsights://oauth/withings`.
