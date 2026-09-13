# EasyReel

Slot-replacement video app. Pick a template, add photos, generate, share.

## Run the frontend

```bash
cd apps/web
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

Demo:

- Language: Hindi or English
- Phone OTP: any 10-digit number, code `111111`
- Email: any address, password `reel123`
- Google: one-tap demo user
- Admin: “Enter as admin” or phone `9999990000`

## What’s in the web app

User: home, catalog, preview, slot fill, generating, ready/share, my videos, devotion, AI reel, custom edit, book a shoot, premium, profile.

Admin: analytics, users, templates, jobs, orders.

Data is stored in the browser for now. The API and Remotion worker come next.

## Planning docs

- [docs/schema.sql](docs/schema.sql)
- [docs/api.md](docs/api.md)
- [docs/template.schema.json](docs/template.schema.json)
