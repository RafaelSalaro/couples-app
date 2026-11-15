// Production wiring: the service-role client and the caller's identity from their JWT.
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2.49.4";
import { ApiError } from "./http.ts";
import type { Deps } from "./api.ts";

let admin: SupabaseClient | null = null;

export function adminClient(): SupabaseClient {
  admin ??= createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return admin;
}

export function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing environment variable ${name}`);
  return value;
}

/** The user id of a valid Supabase JWT in the Authorization header. */
export async function userIdFromRequest(req: Request): Promise<string> {
  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) throw new ApiError("unauthorized", 401);
  const { data, error } = await adminClient().auth.getUser(token);
  if (error || !data.user) throw new ApiError("unauthorized", 401);
  return data.user.id;
}

export function liveDeps(): Deps {
  return {
    userId: userIdFromRequest,
    rpc: async (fn, args) => {
      const { data, error } = await adminClient().rpc(fn, args);
      return { data, error };
    },
    deleteAuthUser: async (userId) => {
      const { error } = await adminClient().auth.admin.deleteUser(userId);
      if (error) throw new ApiError("server_error", 500, error.message);
    },
    appDomain: Deno.env.get("APP_DOMAIN") ?? "example.com",
  };
}
