# Deployment

This repo is set up for:

- `frontend/` on Vercel
- `backend/` on Modal using a Docker image

## Architecture

- Vercel serves the Vite React app from `frontend/`
- Modal serves the FastAPI backend from `backend/modal_app.py`
- Supabase remains the database and document storage backend

## Frontend on Vercel

Create a Vercel project with the root directory set to `frontend`.

### Required Vercel environment variables

- `VITE_API_BASE_URL`
  Example: `https://intellimed-backend.modal.run/api`
- `VITE_GOOGLE_CLIENT_ID`

### Vercel build settings

These are already encoded in [frontend/vercel.json](/c:/Projects/IntelliMed-AI/frontend/vercel.json):

- Framework: `vite`
- Build command: `npm run build`
- Output directory: `dist`
- SPA rewrite to `index.html`

### Deploy commands

From `frontend/`:

```bash
npm install
vercel link --yes
vercel env add VITE_API_BASE_URL production
vercel env add VITE_GOOGLE_CLIENT_ID production
vercel --prod
```

## Backend on Modal

The backend entrypoint is [backend/modal_app.py](/c:/Projects/IntelliMed-AI/backend/modal_app.py). Modal builds from [backend/Dockerfile](/c:/Projects/IntelliMed-AI/backend/Dockerfile).

### Required Modal secret values

Create a Modal secret named `intellimed-backend-secrets` unless you override `MODAL_SECRET_NAME`.

Required keys:

- `DATABASE_URL`
- `DIRECT_URL`
- `SECRET_KEY`
- `GOOGLE_CLIENT_ID`
- `SUPABASE_URL`
- `SUPABASE_SERVICE_KEY`
- `SUPABASE_STORAGE_BUCKET`
- `CORS_ORIGINS`

Recommended optional keys:

- `CORS_ORIGIN_REGEX`
  Example: `https://.*\.vercel\.app`
- `MAX_UPLOAD_SIZE_MB`
- `CACHE_TTL_SECONDS`
- `MAX_CONCURRENT_HEAVY`
- `USE_OPENDATALOADER_FOR_PDFS`
- `OPENDATALOADER_USE_STRUCT_TREE`
- `OPENDATALOADER_HYBRID`
- `OPENDATALOADER_HYBRID_URL`
- `OPENDATALOADER_HYBRID_TIMEOUT`

### Create the Modal secret

```bash
modal secret create intellimed-backend-secrets \
  DATABASE_URL="postgresql://..." \
  DIRECT_URL="postgresql://..." \
  SECRET_KEY="replace-with-long-random-secret" \
  GOOGLE_CLIENT_ID="your-google-client-id" \
  SUPABASE_URL="https://your-project.supabase.co" \
  SUPABASE_SERVICE_KEY="your-service-role-key" \
  SUPABASE_STORAGE_BUCKET="medical-documents" \
  CORS_ORIGINS="https://your-production-domain.vercel.app" \
  CORS_ORIGIN_REGEX="https://.*\\.vercel\\.app"
```

### Deploy the backend

From the repo root:

```bash
pip install modal
modal deploy backend/modal_app.py
```

After deployment, Modal will print the public URL for the ASGI app.

## Local Docker backend

You can also run the backend container locally:

```bash
docker build -f backend/Dockerfile -t intellimed-backend .
docker run --env-file backend/.env -p 8000:8000 intellimed-backend
```

## Local Docker Compose

For local end-to-end testing with both frontend and backend:

```bash
docker compose up --build
```

Services:

- Frontend: `http://localhost:5173`
- Backend: `http://localhost:8000`

Notes:

- The compose setup uses [docker-compose.yml](/c:/Projects/IntelliMed-AI/docker-compose.yml).
- The frontend dev container uses [frontend/Dockerfile.dev](/c:/Projects/IntelliMed-AI/frontend/Dockerfile.dev).
- Backend environment variables are loaded from `backend/.env`.
- If Google OAuth is needed in the frontend during local compose testing, set `VITE_GOOGLE_CLIENT_ID` in your shell before starting Compose or add it to a root `.env` file used by Docker Compose.

## Post-deploy wiring

1. Deploy the Modal backend and copy its public URL.
2. Set `VITE_API_BASE_URL` in Vercel to `https://<your-modal-url>/api`.
3. Set backend CORS to allow your Vercel production domain.
4. Redeploy the Vercel frontend.

## Notes

- The frontend now reads its API base URL from `VITE_API_BASE_URL` and falls back to `http://localhost:8000/api` in local development.
- The backend supports both `CORS_ORIGINS` and `CORS_ORIGIN_REGEX`, which is useful for Vercel preview deployments.
- `backend/.env` should stay local only. Use Modal secrets and Vercel environment variables in production.
