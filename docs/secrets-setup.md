# Secrets & Variables Setup

This document describes which repository secrets and variables are required by
the workflows in `.github/workflows/`. **Secrets are only visible to users with
admin/maintainer rights and must be added from
Settings → Secrets and variables → Actions.**

## Repository Secrets

| Name           | Required? | Purpose                                                        | How to obtain                                   |
| -------------- | --------- | -------------------------------------------------------------- | ----------------------------------------------- |
| `GITHUB_TOKEN` | Automatic | Provided by GitHub Actions on every run. No manual setup.      | Already injected by GitHub.                     |
| `CODECOV_TOKEN`| Optional  | Uploads coverage reports from the test workflow to codecov.io. | <https://codecov.io> → add the repo → copy the token. |

### Adding `CODECOV_TOKEN` via the UI

1. Open **Settings → Secrets and variables → Actions**.
2. Click **New repository secret**.
3. **Name:** `CODECOV_TOKEN`
4. **Value:** the token from codecov.io (or the empty string to disable upload).
5. Click **Add secret**.

### Adding via `gh` CLI

```bash
gh secret set CODECOV_TOKEN --body "<paste token here>"
```

> **Never** commit a real token to the repository. Use the GitHub UI or a
> `gh secret set` invocation; the value above is a placeholder.

### Verifying

```bash
gh secret list
```

## Repository Variables

| Name             | Default | Purpose                                              |
| ---------------- | ------- | ---------------------------------------------------- |
| `PYTHON_VERSION` | `3.11`  | Python version used by the test workflow.            |
| `POWERSHELL_VERSION` | `7.4` | PowerShell version installed in the CI image.        |

### Adding via `gh` CLI

```bash
gh variable set PYTHON_VERSION --body "3.11"
gh variable set POWERSHELL_VERSION --body "7.4"
```

## Environment Secrets (optional)

If you want to gate production deployments behind an environment:

1. **Settings → Environments → New environment** → name it `production`.
2. Add required reviewers (the maintainer team).
3. Add any deployment-only secrets under that environment.

## Verifying Everything

```bash
gh secret list
gh variable list
gh api /repos/ferhatdeveloper/VirtualAppRDP/environments
```

The first two commands list repository-scoped secrets/variables; the third
lists environments with their protection rules.
