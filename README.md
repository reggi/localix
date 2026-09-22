# Localix website

The React + TypeScript + Vite website for [Localix](https://github.com/reggi/localix), intended for https://reggi.github.io/localix/. This is an independent, orphan `gh-pages` branch containing website source only. The native macOS app remains on `main`. The original app icon is retained in `public/localix-icon.png`. The menu bar illustration uses `public/localix-recording.png`, rendered from the app's native `text.bubble` symbol and red recording background.

## Local development

Use Node.js 24 and npm.

```sh
npm ci
npm run dev -- --host 127.0.0.1
```

Open the `/localix/` path printed by Vite. Development and production builds fetch the latest stable GitHub release and require its macOS archive and checksum to exist. To use an exact release, set `RELEASE_TAG=v0.3.0`. Optionally provide `GH_TOKEN` in your environment if unauthenticated GitHub API requests are rate-limited. Never commit tokens.

```sh
npm run lint
npm test
RELEASE_TAG=v0.3.0 npm run build
npm run preview -- --host 127.0.0.1
```

The build writes release metadata into an ignored generated file. GitHub authentication is used only by the Node build script, not the browser bundle. The finished site makes no release API requests, uses no analytics or third-party fonts, and requests no microphone access.

## Deployment

GitHub Pages uses Actions, not branch-based static-file publishing. The `pages.yml` workflow lives on `main`, checks out this branch, runs the commands above, and deploys `dist/` using the official Pages actions. Successful app releases invoke it after their download assets have uploaded, so the website links to the exact completed release. Editing this branch alone does not deploy it.

To rebuild and deploy for an existing release:

```sh
gh workflow run pages.yml --repo reggi/localix --ref main -f tag=v0.3.0
```

Keep `vite.config.ts` configured with `base: '/localix/'` for the repository Pages URL. Do not copy Swift source, local recordings, app binaries, or build output into this branch.
