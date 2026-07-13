# ADR-0009: Upload directly to storage through signed intents

- Status: Accepted
- Date: 2026-07-13

## Context

Proxying image bytes through the Worker increases memory pressure, latency, and cost. Allowing unrestricted client storage writes weakens path and tenant controls.

## Decision

The authenticated client requests a signed upload intent from the Worker. The Worker creates the receipt ID and exact company-scoped object path, then returns a short-lived signed upload URL. The client uploads directly to Supabase Storage and calls a completion endpoint. The Worker verifies the object exists before queueing extraction.

## Consequences

- large bytes bypass the API process;
- object paths are deterministic and tenant-scoped;
- signed URL expiry and completion semantics become security-sensitive;
- the extraction consumer still verifies actual bytes, type, size, and hash.
