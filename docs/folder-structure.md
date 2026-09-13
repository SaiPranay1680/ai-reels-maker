# Repository layout

```
ai-video-platform/
  apps/
    web/                     # Next.js — user app + /admin
      app/
        (public)/            # home, templates, login
        (app)/               # slot editor, jobs, account
        admin/               # role-gated
      components/
      lib/api.ts
    api/                     # FastAPI
      app/main.py
      app/api/v1/
      app/core/              # config, security, redis
      app/models/
      app/schemas/
      app/services/
      alembic/
      tests/
    renderer/                # Node — Remotion + BullMQ
      src/worker.ts
      src/queue.ts
      src/ffmpeg.ts
      src/s3.ts
      src/compositions/
      remotion.config.ts
    mobile/                  # Flutter — Phase 5
  packages/
    template-schema/         # JSON Schema + generated TS/Pydantic
    api-types/               # OpenAPI clients
  infra/
    docker/                  # api.Dockerfile, renderer.Dockerfile, compose.yml
    terraform/               # VPC, RDS, Redis, ECS/Fly, buckets, CDN
  docs/
    schema.sql
    template.schema.json
    api.md
    folder-structure.md
```

## Runtime split

| App | Language | Why it exists |
| --- | --- | --- |
| `apps/web` | TypeScript | Fastest path to a PWA India users can install |
| `apps/api` | Python | Auth, Razorpay, catalog, job records |
| `apps/renderer` | Node | Remotion cannot run in Python |
| `apps/mobile` | Dart | Native share sheet and OTP autofill after API is stable |

`packages/template-schema` is the contract. A template that fails schema validation must not publish.
