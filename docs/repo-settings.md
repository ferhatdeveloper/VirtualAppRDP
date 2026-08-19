# Repository Metadata Setup

This document describes how to configure the basic metadata for
[ferhatdeveloper/VirtualAppRDP](https://github.com/ferhatdeveloper/VirtualAppRDP).
**This must be run by a user with admin/maintainer rights on the repository.**
The automation could not apply the changes because the GitHub CLI was not
authenticated in the execution environment.

## Desired Settings

| Setting     | Value                                                                            |
| ----------- | -------------------------------------------------------------------------------- |
| Description | `Rdp Virtual Box App - RemoteApp setup wizard for Windows Server with 5 connection strategies` |
| Homepage    | `https://github.com/ferhatdeveloper/VirtualAppRDP`                                |
| Topics      | `remoteapp`, `rdp`, `windows-server`, `powershell`, `guacamole`, `setup-wizard`    |
| Issues      | **Enabled**                                                                      |
| Wiki        | **Enabled**                                                                      |
| Projects    | **Enabled**                                                                      |
| Discussions | Optional (recommended for community support)                                     |

## Apply via `gh` CLI

```bash
gh repo edit ferhatdeveloper/VirtualAppRDP \
  --description "Rdp Virtual Box App - RemoteApp setup wizard for Windows Server with 5 connection strategies" \
  --homepage "https://github.com/ferhatdeveloper/VirtualAppRDP" \
  --enable-issues \
  --enable-wiki \
  --enable-projects \
  --add-topic remoteapp \
  --add-topic rdp \
  --add-topic windows-server \
  --add-topic powershell \
  --add-topic guacamole \
  --add-topic setup-wizard
```

## Apply via the GitHub UI

1. Open the repository page on GitHub.
2. Click the ⚙️ **Settings** gear next to **About** on the right sidebar.
3. Fill in:
   - **Description:** `Rdp Virtual Box App - RemoteApp setup wizard for Windows Server with 5 connection strategies`
   - **Website:** `https://github.com/ferhatdeveloper/VirtualAppRDP`
4. Add the topics listed above in the **Topics** field.
5. Tick **Releases**, **Packages**, and **Contributors** as desired.
6. Scroll down to **Features** and enable:
   - ✅ Issues
   - ✅ Wiki (optional — recommend disabling in favor of `docs/`)
   - ✅ Projects
   - ✅ Discussions (optional)

## Apply via `curl`

```bash
curl -X PATCH \
  -H "Authorization: token <TOKEN>" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/ferhatdeveloper/VirtualAppRDP \
  -d '{
    "description": "Rdp Virtual Box App - RemoteApp setup wizard for Windows Server with 5 connection strategies",
    "homepage": "https://github.com/ferhatdeveloper/VirtualAppRDP",
    "has_issues": true,
    "has_wiki": true,
    "has_projects": true,
    "has_discussions": true,
    "topics": ["remoteapp", "rdp", "windows-server", "powershell", "guacamole", "setup-wizard"]
  }'

# Topics require a separate call:
curl -X PUT \
  -H "Authorization: token <TOKEN>" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/ferhatdeveloper/VirtualAppRDP/topics \
  -d '{"names":["remoteapp","rdp","windows-server","powershell","guacamole","setup-wizard"]}'
```

## Verifying

```bash
gh repo view ferhatdeveloper/VirtualAppRDP
```

The output should show the new description, homepage, and topics at the top.
