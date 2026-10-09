# t3code-dokploy

A Docker image and Dokploy template for the [T3 Code](https://t3.codes) server.

The image unpacks upstream's official self-contained release archive
(`t3-<version>-linux-<arch>.tar.gz`, checked against the release's
`SHA256SUMS`) and adds Claude Code and the GitHub CLI. Nothing in T3 Code is
patched or rebuilt.

- Image: `ghcr.io/goktugsenkal/t3code:<t3 version>`, for amd64 and arm64
- Runs `t3 serve --host 0.0.0.0 --port 3773` as user `t3` (uid 1000)
- Volumes: `/home/t3` (T3 home, Claude Code, logins, git config, SSH keys) and
  `/workspace` (projects)

## Deploy on Dokploy

1. Create a **Compose** service, open **Advanced → Import**, and paste the
   output of `scripts/dokploy-import.sh`. Or paste
   `blueprint/t3code/docker-compose.yml` and add a domain for service `t3code`,
   port `3773`, with HTTPS.
2. Deploy.
3. Pair your browser. In the service's **Terminal**, run:

   ```sh
   t3 auth pairing create --base-url https://<your-domain>
   ```

   and open the printed link. The startup log also prints a token; it works as
   `https://<your-domain>/pair#token=<token>`, but its connection string shows
   the container's internal address. Treat pairing links as passwords.
4. Sign in to Claude in the same terminal:

   ```sh
   claude auth login
   ```

5. Set your git identity:

   ```sh
   git config --global user.name "…"
   git config --global user.email "…"
   ```

6. Connect GitHub, either as a [GitHub App](#github-app) (an organization's
   server, acting as its own bot account) or as a person:

   ```sh
   gh auth login --with-token   # paste the token, Enter, then Ctrl+D
   ```

   A token acts as the account that created it, even when its resource owner
   is an organization. Either way, choose **Settings → Source Control →
   Rescan** in T3 Code afterwards.

Then add a project under `/workspace` from the T3 Code UI. The desktop app,
mobile app, and [app.t3.codes](https://app.t3.codes) can pair with the same
domain.

## GitHub App

With a GitHub App, pull requests, pushes, and commits come from the app's bot
account (`<app-name>[bot]`) instead of a person. The image's `gh` mints the
app's short-lived installation tokens on demand, and git uses the same token
for clone and push.

1. In the organization's **Settings → Developer settings → GitHub Apps**,
   create a **New GitHub App**:
   - Homepage URL: anything, such as the server's domain
   - Webhook: clear **Active**
   - Repository permissions: Contents, Pull requests: read and write.
     Checks, Commit statuses, Issues: read. Workflows: read and write, if
     agents may edit `.github/workflows`.
   - Where can this GitHub App be installed: **Only on this account**
2. On the app's page, note the **App ID** and **Generate a private key**.
3. **Install App** on the organization, for the repositories the server
   should work on.
4. In Dokploy, set the service's environment and redeploy:

   ```
   GITHUB_APP_ID=<app id>
   GITHUB_APP_PRIVATE_KEY=<the .pem file, base64-encoded>
   ```

   Encode the key with `base64 -w0 key.pem`, or in PowerShell with
   `[Convert]::ToBase64String([IO.File]::ReadAllBytes("key.pem"))`. Set
   `GITHUB_APP_INSTALLATION_ID` only if the app is installed on more than one
   account.

The startup log then shows `GitHub: signed in as <app-name>[bot]`. If git has
no identity yet, commits are attributed to the bot; to switch an existing
identity, run `git config --global --unset user.name`, the same for
`user.email`, and redeploy.

Anything that runs in the container, agents included, can act as the app, so
install it only on the repositories the server needs.

## Updating

CI checks upstream every three hours. On a new stable release it builds,
smoke-tests, pushes `ghcr.io/goktugsenkal/t3code:<version>`, and commits the
version bump here. Change the image tag in Dokploy and redeploy. The in-app
**Update server** action does not apply to this container.

Packaging changes are re-pushed under the same T3 Code version tag. The
template's `pull_policy: always` makes a plain redeploy pick them up.

Clients newer than the server are refused, and the desktop and mobile apps
update themselves, so don't let the server fall far behind.

Claude Code lives in the home volume and updates itself, including from
**Settings → Providers** in T3 Code.

## Local test

```sh
docker compose up --build
scripts/smoke-test.sh <image>
```

`scripts/bump.sh <version>` points every file at another upstream version.
