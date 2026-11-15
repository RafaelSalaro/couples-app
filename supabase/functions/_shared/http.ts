// The envelope every function returns (docs/05 §3): {ok, data} or {ok:false, error:{code, message}}.

export class ApiError extends Error {
  constructor(public code: string, public status = 400, message?: string) {
    super(message ?? code);
  }
}

/** CORS for the website's calls (waitlist, approve page) and the app's. */
export function corsHeaders(origin: string | null, allowed: string[] = allowedOrigins()): Record<string, string> {
  const headers: Record<string, string> = {
    "access-control-allow-methods": "POST, OPTIONS",
    "access-control-allow-headers": "authorization, apikey, content-type, x-client-info",
    "vary": "origin",
  };
  if (origin && (allowed.includes("*") || allowed.includes(origin))) headers["access-control-allow-origin"] = origin;
  return headers;
}

/** `ALLOWED_ORIGINS`: comma-separated site origins; defaults to the site's domain from `APP_DOMAIN`. */
export function allowedOrigins(): string[] {
  const raw = Deno.env.get("ALLOWED_ORIGINS");
  if (raw) return raw.split(",").map((s) => s.trim()).filter(Boolean);
  const domain = Deno.env.get("APP_DOMAIN");
  return domain ? [`https://${domain}`, `https://www.${domain}`] : [];
}

export function json(body: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...headers },
  });
}

export const ok = (data: unknown, headers?: Record<string, string>) => json({ ok: true, data: data ?? null }, 200, headers);

export const fail = (code: string, status = 400, message?: string, headers?: Record<string, string>) =>
  json({ ok: false, error: { code, message: message ?? code } }, status, headers);

/** Business errors raised by SQL functions arrive as SQLSTATE CAERR with the code as message. */
export function fromDatabaseError(error: { code?: string; message?: string } | null): ApiError {
  if (error?.code === "CAERR" && error.message) return new ApiError(error.message, statusFor(error.message));
  if (error?.code === "42501") return new ApiError("forbidden", 403);
  // Details go to the function log, never to the caller.
  console.error("database error", error?.code, error?.message);
  return new ApiError("server_error", 500);
}

/** HTTP status for an error code. The app reads the code; the status is for logs and proxies. */
export function statusFor(code: string): number {
  switch (code) {
    case "unauthorized": return 401;
    case "forbidden": case "not_partner": case "premium_required": return 403;
    case "not_found": return 404;
    case "rate_limited": return 429;
    case "server_error": return 500;
    default: return 409;
  }
}

/** Runs a handler with the envelope, CORS and error mapping every function shares. */
export async function respond(req: Request, handler: () => Promise<unknown>): Promise<Response> {
  const cors = corsHeaders(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") return fail("method_not_allowed", 405, undefined, cors);
  try {
    return ok(await handler(), cors);
  } catch (error) {
    if (error instanceof ApiError) return fail(error.code, error.status, error.message, cors);
    console.error(error);
    return fail("server_error", 500, undefined, cors);
  }
}

export async function readBody(req: Request): Promise<Record<string, unknown>> {
  const text = await req.text();
  if (!text) return {};
  try {
    const value = JSON.parse(text);
    if (value && typeof value === "object" && !Array.isArray(value)) return value as Record<string, unknown>;
  } catch { /* fall through */ }
  throw new ApiError("invalid_input");
}
