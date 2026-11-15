// Small validators for request bodies. Every failure is the same calm `invalid_input`.
import { ApiError } from "./http.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function uuid(body: Record<string, unknown>, key: string): string {
  const value = body[key];
  if (typeof value !== "string" || !UUID.test(value)) throw new ApiError("invalid_input", 400, `${key} must be a uuid`);
  return value.toLowerCase();
}

export function optionalUuid(body: Record<string, unknown>, key: string): string | null {
  return body[key] === undefined || body[key] === null ? null : uuid(body, key);
}

export function int(body: Record<string, unknown>, key: string): number {
  const value = body[key];
  if (typeof value !== "number" || !Number.isInteger(value)) throw new ApiError("invalid_input", 400, `${key} must be a whole number`);
  return value;
}

export function optionalInt(body: Record<string, unknown>, key: string): number | null {
  return body[key] === undefined || body[key] === null ? null : int(body, key);
}

export function bool(body: Record<string, unknown>, key: string): boolean {
  const value = body[key];
  if (typeof value !== "boolean") throw new ApiError("invalid_input", 400, `${key} must be true or false`);
  return value;
}

export function text(body: Record<string, unknown>, key: string, max: number): string {
  const value = body[key];
  if (typeof value !== "string" || value.length > max) throw new ApiError("invalid_input", 400, `${key} must be text up to ${max}`);
  return value;
}

export function optionalText(body: Record<string, unknown>, key: string, max: number): string | null {
  return body[key] === undefined || body[key] === null ? null : text(body, key, max);
}

export function object(body: Record<string, unknown>, key: string): Record<string, unknown> {
  const value = body[key];
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new ApiError("invalid_input", 400, `${key} must be an object`);
  return value as Record<string, unknown>;
}

export function array(body: Record<string, unknown>, key: string, max: number): unknown[] {
  const value = body[key];
  if (!Array.isArray(value) || value.length > max) throw new ApiError("invalid_input", 400, `${key} must be a list`);
  return value;
}
