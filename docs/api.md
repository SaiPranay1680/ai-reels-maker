# API v1

Base path: `/api/v1`  
Auth: `Authorization: Bearer <access>` (15 min). Web also sets a rotating httpOnly refresh cookie.  
Idempotency: send `Idempotency-Key` on `POST /projects/{id}/render` and `/billing/checkout`.

## Auth

| Method | Path | Auth | Body | Result |
| --- | --- | --- | --- | --- |
| POST | `/auth/otp/start` | public | `{ phone }` | `{ challenge_id, expires_in }` |
| POST | `/auth/otp/verify` | public | `{ challenge_id, code }` | `{ user, access_token }` + refresh |
| POST | `/auth/google` | public | `{ id_token }` | same as verify |
| POST | `/auth/refresh` | refresh | — | new access + rotated refresh |
| POST | `/auth/logout` | user | — | 204 |

Rate limit `otp/start` to 5/hour/phone and 20/hour/IP. Store only `code_hash`.

## Users

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/users/me` | profile, locale, plan, remaining renders |
| PATCH | `/users/me` | `display_name`, `locale`, `region_state` |

## Catalog

| Method | Path | Query |
| --- | --- | --- |
| GET | `/categories` | — |
| GET | `/templates` | `q`, `category`, `tier`, `ratio` |
| GET | `/templates/{slug}` | returns slot schema + signed preview URL |
| GET | `/devotional/today` | `locale` — weekday deity + template |

Cache catalog GETs in Redis for 5 minutes. Bust on admin publish.

## Uploads

Never stream bytes through FastAPI.

1. `POST /uploads/presign` `{ filename, content_type, byte_size, kind }`
2. Client PUT to S3/R2
3. `POST /uploads/complete` `{ key, checksum_sha256 }`

Allow: `image/jpeg`, `image/png`, `image/webp`, `video/mp4`, `audio/mpeg`. Max 25 MB. Reject by magic bytes, not extension.

## Projects and jobs

| Method | Path | Notes |
| --- | --- | --- |
| POST | `/projects` | `{ template_id }` — freezes `config_version` |
| GET | `/projects` | current user, newest first |
| GET | `/projects/{id}` | slots + latest job |
| PUT | `/projects/{id}/slots/{slot_id}` | `{ file_id }` or `{ text }` or `{ music_track_id }` |
| POST | `/projects/{id}/render` | 202 `{ job_id }`. Reuses active job if slot hash matches |
| GET | `/jobs/{id}` | `{ status, progress_pct, error_code }` |
| GET | `/projects/{id}/output` | 302 or JSON with signed URL, 1 hour |

Render is rejected if any required slot is empty. Free plan: watermark + 720p. Premium: 1080p, priority queue.

Job states: `queued → processing → uploading → completed`. Terminal: `failed`, `canceled`.

## Billing

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/plans` | public |
| POST | `/billing/checkout` | creates Razorpay order |
| POST | `/webhooks/razorpay` | signature required; only path that upgrades a plan |

Never trust the client to flip `subscriptions.status`.

## Custom orders (Service 2, waitlist-grade)

| Method | Path | Notes |
| --- | --- | --- |
| POST | `/orders` | files + occasion + description + due date |
| GET | `/orders` | current user |
| GET | `/orders/{id}` | includes payment and delivery file |

Admin assigns `editor_id` from `/admin/orders/{id}`.

## Admin

All routes require `role=admin`.

- `GET /admin/users`
- `POST /admin/templates` — preview, thumbnail, config JSON, music, category
- `PATCH /admin/templates/{id}` — publish / unpublish
- `GET /admin/jobs?status=`
- `GET /admin/orders`
- `GET /admin/analytics/overview` — users, renders, paid conversion, queue lag

## Errors

```json
{ "error": { "code": "SLOT_REQUIRED", "message": "Photo 2 is missing", "slot_id": "photo2" } }
```

Stable codes: `OTP_EXPIRED`, `OTP_INVALID`, `SLOT_REQUIRED`, `PLAN_LIMIT`, `UPLOAD_REJECTED`, `JOB_FAILED`, `FORBIDDEN`, `NOT_FOUND`.
