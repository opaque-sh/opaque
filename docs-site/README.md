# Opaque docs

The content and theme for the Opaque documentation site. It targets [Fumadocs](https://fumadocs.dev) (Next.js), the same stack as the reference docs we looked at.

Status: **content and theme only**. The app shell is not in this folder, because the package registry was blocked where this was written, so nothing here has been installed or built. Generate the shell locally, then drop these files in.

## Option A: build the docs inside the Lovable site

`lovable/docs/*.md` is the same content as plain markdown (the Fumadocs callouts and cards are converted to GitHub-style alerts and bullet lists), and `lovable/sidebar.json` is the sidebar order. Copy them into the Lovable project's repository under `src/content/docs/` (through its GitHub sync), then run the prompt that builds the `/docs` routes. This serves `opaque.sh/docs` with no proxy.

## Option B: a separate Fumadocs app

Use the steps below. This is the better tool for search and MDX, and needs its own deployment (for example `docs.opaque.sh`).

## Set up (Option B)

1. Generate a shell, outside this repo or in a separate repo (for example `opaque-sh/docs`):

   ```
   npm create fumadocs-app@latest opaque-docs
   ```

   Choose Next.js and Fumadocs MDX. Keep the default search.

2. Replace the scaffold's `content/docs` folder with `docs-site/content/docs` from this repo. The sidebar order and section labels live in `meta.json`.

3. Copy `styles/opaque-theme.css` into the shell and import it last in `app/global.css`, after the Fumadocs preset import (see the comment at the top of the file).

4. Fonts. Install `geist` and add both variables to the root layout:

   ```
   npm i geist
   ```

   ```tsx
   import { GeistSans } from "geist/font/sans";
   import { GeistMono } from "geist/font/mono";
   // <html className={`${GeistSans.variable} ${GeistMono.variable}`} suppressHydrationWarning>
   ```

5. Force the dark theme on the provider:

   ```tsx
   <RootProvider theme={{ forcedTheme: "dark", defaultTheme: "dark" }}>{children}</RootProvider>
   ```

6. Navigation. In the shell's shared layout options, set the title to the sliced-ring mark plus the lowercase "opaque" wordmark with "docs" in muted text (SVGs are in `brand/logo/`), and add top links: GitHub (`https://github.com/opaque-sh`), X, and the app. Keep the app link disabled with a "soon" tag until it is live.

7. Deploy to a host of your choice and point `docs.opaque.sh` at it.

## Components used in the pages

The pages use only `Callout` and `Cards` / `Card`, which the default Fumadocs MDX components provide, plus plain markdown tables and fenced code. If the scaffold's `mdx-components.tsx` does not include them, spread `defaultMdxComponents` from `fumadocs-ui/mdx`.

## Optional: "Copy Markdown" and "Open" buttons

The reference docs have these under each title. Fumadocs documents a pattern for it (an LLM-friendly markdown route plus a copy button). Add it after the shell works.

## Rules for editing the content

- Mark anything not built as planned or SOON. Do not describe the app as live.
- No fee percentages, holder share numbers or contract addresses until they are final.
- No em dashes.
- Keep these pages in step with `docs/DESIGN.md`, `docs/TRUST.md` and `contracts/src/`.
