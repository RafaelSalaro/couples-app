// The signed-in API (docs/05 §3). Every function is a thin wrapper around one SQL function
// `api_<name>(p_user, …)` that holds the rules (decision E14): this file only checks the
// caller, validates the body, calls the SQL function and shapes the answer for the app.
import { ApiError, fromDatabaseError, readBody, respond } from "./http.ts";
import * as v from "./input.ts";

type Body = Record<string, unknown>;
type Json = Record<string, unknown> | unknown[] | string | number | boolean | null;

export interface Deps {
  /** The caller's user id from their JWT, or throws `unauthorized`. */
  userId(req: Request): Promise<string>;
  /** Calls a SQL function with the service role. */
  rpc(fn: string, args: Record<string, unknown>): Promise<{ data: Json; error: { code?: string; message?: string } | null }>;
  /** Removes the auth user after their data is deleted. */
  deleteAuthUser(userId: string): Promise<void>;
  /** The website's domain, for invite links (`https://<domain>/i/<token>`). */
  appDomain: string;
}

interface Endpoint {
  rpc: string;
  args(body: Body): Record<string, unknown>;
  /** Shapes the SQL result for the app. Default: the result as is. */
  result?(data: Json, deps: Deps): Json;
  /** Runs after the SQL function succeeded. */
  after?(userId: string, deps: Deps): Promise<void>;
}

const pick = (key: string) => (data: Json) => (data as Record<string, Json>)?.[key] ?? null;

export const endpoints: Record<string, Endpoint> = {
  create_invite: {
    rpc: "api_create_invite",
    args: () => ({}),
    result: (data, deps) => {
      const d = data as Record<string, Json>;
      return { id: d.id, code: d.code, link: `https://${deps.appDomain}/i/${d.link_token}`, expires_at: d.expires_at };
    },
  },
  revoke_invite: { rpc: "api_revoke_invite", args: () => ({}), result: () => null },
  accept_invite: {
    rpc: "api_accept_invite",
    args: (b) => {
      const code = v.optionalText(b, "code", 6) ?? v.optionalText(b, "link_token", 128);
      if (!code) throw new ApiError("invalid_input");
      return { p_code_or_token: code.trim() };
    },
  },
  unpair: { rpc: "api_unpair", args: () => ({}) },
  rotate_qr_secret: { rpc: "api_rotate_qr_secret", args: () => ({}) },

  create_unlock_request: {
    rpc: "api_create_unlock_request",
    args: (b) => ({ p_minutes: v.int(b, "minutes"), p_reason: v.optionalText(b, "reason", 140) }),
  },
  respond_unlock_request: {
    rpc: "api_respond_unlock_request",
    args: (b) => ({ p_request: v.uuid(b, "request_id"), p_approve: v.bool(b, "approve") }),
  },
  redeem_accountability_code: {
    rpc: "api_redeem_accountability_code",
    args: (b) => ({ p_request: v.uuid(b, "request_id"), p_code: v.text(b, "code", 12) }),
    result: pick("unlock"),
  },
  spend_minutes_unlock: {
    rpc: "api_spend_minutes_unlock",
    args: (b) => ({ p_minutes: v.int(b, "minutes"), p_client_event_id: v.uuid(b, "client_event_id") }),
    result: pick("unlock"),
  },
  emergency_unlock: {
    rpc: "api_emergency_unlock",
    args: (b) => ({ p_client_event_id: v.uuid(b, "client_event_id") }),
    result: pick("unlock"),
  },
  // Doc 05 lists a client_event_id too; ending is idempotent by unlock id, so it is accepted and not needed.
  end_unlock_early: {
    rpc: "api_end_unlock_early",
    args: (b) => { v.optionalUuid(b, "client_event_id"); return { p_unlock: v.uuid(b, "unlock_id") }; },
    result: pick("unlock"),
  },
  sync_qr_unlocks: {
    rpc: "api_sync_qr_unlocks",
    args: (b) => ({ p_items: v.array(b, "unlocks", 50) }),
  },

  complete_challenge: {
    rpc: "api_complete_challenge",
    args: (b) => ({ p_challenge: v.uuid(b, "challenge_id"), p_note: v.optionalText(b, "note", 280) }),
  },
  confirm_completion: { rpc: "api_confirm_completion", args: (b) => ({ p_completion: v.uuid(b, "completion_id") }) },
  create_custom_challenge: {
    rpc: "api_create_custom_challenge",
    args: (b) => ({
      p_title: v.text(b, "title", 80), p_description: v.optionalText(b, "description", 280) ?? "",
      p_minutes: v.int(b, "minutes"), p_category: v.text(b, "category", 20), p_is_shared: v.bool(b, "is_shared"),
    }),
  },
  respond_challenge_value: {
    rpc: "api_respond_challenge_value",
    args: (b) => ({ p_challenge: v.uuid(b, "challenge_id"), p_approve: v.bool(b, "approve"), p_counter_minutes: v.optionalInt(b, "counter_minutes") }),
  },
  // The receiver is always the caller's partner; `receiver_id` from the app is not trusted.
  give_kudos: {
    rpc: "api_give_kudos",
    args: (b) => ({ p_minutes: v.int(b, "minutes"), p_message: v.optionalText(b, "message", 140) ?? "", p_challenge: v.optionalUuid(b, "challenge_id") }),
  },

  propose_reset: { rpc: "api_propose_reset", args: (b) => ({ p_standard_minutes: v.optionalInt(b, "standard_minutes") }) },
  respond_reset: { rpc: "api_respond_reset", args: (b) => ({ p_proposal: v.uuid(b, "proposal_id"), p_accept: v.bool(b, "accept") }) },
  propose_schedule_change: {
    rpc: "api_propose_schedule_change",
    args: (b) => ({ p_schedule: v.optionalUuid(b, "schedule_id"), p_proposed: v.object(b, "proposed") }),
  },
  respond_schedule_change: {
    rpc: "api_respond_schedule_change",
    args: (b) => ({ p_request: v.uuid(b, "request_id"), p_approve: v.bool(b, "approve") }),
  },

  export_my_data: { rpc: "api_export_my_data", args: () => ({}) },
  delete_account: {
    rpc: "api_delete_account",
    args: () => ({}),
    result: () => null,
    after: (userId, deps) => deps.deleteAuthUser(userId),
  },
};

/** Handles one signed-in API call end to end. */
export function apiHandler(name: string, deps: Deps): (req: Request) => Promise<Response> {
  const endpoint = endpoints[name];
  if (!endpoint) throw new Error(`Unknown function ${name}`);
  return (req) =>
    respond(req, async () => {
      const userId = await deps.userId(req);
      const body = await readBody(req);
      const { data, error } = await deps.rpc(endpoint.rpc, { p_user: userId, ...endpoint.args(body) });
      if (error) throw fromDatabaseError(error);
      // Some outcomes must persist a status change (an expired request, a wrong code), so the
      // SQL function returns them as {error} instead of raising.
      if (data && typeof data === "object" && !Array.isArray(data) && typeof (data as Body).error === "string") {
        const code = (data as Body).error as string;
        throw new ApiError(code, code === "too_many_attempts" ? 429 : 409);
      }
      if (endpoint.after) await endpoint.after(userId, deps);
      return endpoint.result ? endpoint.result(data, deps) : data;
    });
}
