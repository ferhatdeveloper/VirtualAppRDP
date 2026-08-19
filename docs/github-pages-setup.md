# GitHub Pages Setup

This document describes how to publish project documentation on GitHub Pages
for [ferhatdeveloper/VirtualAppRDP](https://github.com/ferhatdeveloper/VirtualAppRDP).
**This must be run by a user with admin/maintainer rights on the repository.**

## Goal

Serve `docs/index.html` (and the rest of `docs/`) at
`https://ferhatdeveloper.github.io/VirtualAppRDP/`, using **GitHub Actions**
as the deployment source (no `gh-pages` branch required).

## Method A — GitHub UI (recommended)

1. Open **Settings → Pages** in the repository.
2. Under **Source**, select **GitHub Actions**.
3. GitHub will offer a starter workflow titled *"Pages Jekyll"* or you can keep
   the existing custom workflow in `.github/workflows/`.
4. If you want a static deployment of `docs/`, create
   `.github/workflows/pages.yml` with the content shown below.
5. Once the workflow runs, the URL
   `https://ferhatdeveloper.github.io/VirtualAppRDP/` becomes live.

## Method B — `gh` CLI

```bash
gh api -X POST \
  /repos/ferhatdeveloper/VirtualAppRDP/pages \
  -f source='{"type":"workflow"}'
```

If the endpoint returns `409 Conflict`, Pages is already configured and you can
update the source with:

```bash
gh api -X PUT \
  /repos/ferhatdeveloper/VirtualAppRDP/pages \
  -f source='{"type":"workflow"}'
```

## Method C — `curl`

```bash
curl -X POST \
  -H "Authorization: token <TOKEN>" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/ferhatdeveloper/VirtualAppRDP/pages \
  -d '{"source":{"type":"workflow"}}'
```

## Suggested Workflow

`.github/workflows/pages.yml`:

```yaml
name: Deploy GitHub Pages

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: true

jobs:
  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Pages
        uses: actions/configure-pages@v5

      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: docs

      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

## Verifying

After the workflow runs:

```bash
gh api /repos/ferhatdeveloper/VirtualAppRDP/pages
```

The response should include a `html_url` pointing to
`https://ferhatdeveloper.github.io/VirtualAppRDP/`.
