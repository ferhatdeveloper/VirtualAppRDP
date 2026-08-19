# Branch Protection Setup — `main`

This document describes how to enable branch protection for the `main` branch of
the [ferhatdeveloper/VirtualAppRDP](https://github.com/ferhatdeveloper/VirtualAppRDP)
repository. **This must be run by a user with admin/maintainer rights on the
repository.** The automation in this repo could not apply the rule because the
GitHub CLI was not authenticated in the execution environment.

## Recommended Rule

| Setting                              | Value                                                  |
| ------------------------------------ | ------------------------------------------------------ |
| Branch name pattern                  | `main`                                                 |
| Require status checks to pass        | **On**                                                 |
| Require branches to be up to date    | **On**                                                 |
| Status checks that are required      | `build` (CI workflow from `.github/workflows/`)        |
| Require pull request reviews         | **On**                                                 |
| Required approving reviewers         | `1`                                                    |
| Dismiss stale pull request approvals | **On**                                                 |
| Require code owner reviews           | Optional — only if you add a `CODEOWNERS` file         |
| Restrict who can push                | **Off** (no team restrictions)                         |
| Allow force pushes                   | **Off**                                                 |
| Allow deletions                      | **Off**                                                 |
| Do not allow bypassing the rule      | **Off** (admins can still merge hotfixes)              |

## Apply via GitHub UI

1. Open **Settings → Branches** in the repository.
2. Click **Add rule** (or edit the existing `main` rule).
3. Set **Branch name pattern** to `main`.
4. Tick **Require a pull request before merging** and set
   *Required approving reviews* to `1`.
5. Tick **Dismiss stale pull request approvals when new commits are pushed**.
6. Tick **Require status checks to pass before merging** and select the `build`
   check from the workflow run list (run the CI once first so it appears).
7. Tick **Require branches to be up to date before merging**.
8. Click **Create** / **Save changes**.

## Apply via `gh` CLI

If `gh` is installed and authenticated (`gh auth login`), the same rule can be
applied with a single API call:

```bash
gh api -X PUT \
  /repos/ferhatdeveloper/VirtualAppRDP/branches/main/protection \
  -H "Accept: application/vnd.github+json" \
  -f required_status_checks='{"strict":true,"contexts":["build"]}' \
  -f enforce_admins=false \
  -f required_pull_request_reviews='{"dismiss_stale_reviews":true,"required_approving_review_count":1}' \
  -f restrictions=null
```

> **Note:** the `contexts` array must reference checks that already ran at
> least once on a pull request targeting `main`. Run the CI workflow once
> before enabling the rule, otherwise GitHub will reject the payload.

## Apply via `curl` (fine-grained PAT)

If a fine-grained personal access token with **Administration: write** is
available, the equivalent `curl` invocation is:

```bash
curl -X PUT \
  -H "Authorization: token <TOKEN>" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/ferhatdeveloper/VirtualAppRDP/branches/main/protection \
  -d '{
    "required_status_checks": {"strict": true, "contexts": ["build"]},
    "enforce_admins": false,
    "required_pull_request_reviews": {
      "dismiss_stale_reviews": true,
      "required_approving_review_count": 1
    },
    "restrictions": null
  }'
```

## Verifying

After applying, run:

```bash
gh api /repos/ferhatdeveloper/VirtualAppRDP/branches/main/protection
```

You should see the same JSON echoed back (with `url`, `required_signatures`,
etc.). The branch page in the GitHub UI will display a green
"Branch protection rule" badge next to `main`.
