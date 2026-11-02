# Getting started with a LinuxServer Labs image

This repository is a starter kit for packaging your application as a
[LinuxServer Labs](https://linuxserverlabs-playground.github.io/site/) container image. You copy it into your own
GitHub account or organisation, fill it in for your app, and build and run the image on your own machine. When it
works, you propose it to Labs and link your copy, and a team member builds the Labs image from it.

Nothing is published from your copy. It has no workflows that run, and it needs no secrets: the image you build and
run locally is the evidence that your app works in the LinuxServer container design.

The kit follows the same layout as every LinuxServer image:

| Path | What it is |
| --- | --- |
| `image.yml` | The manifest: name, upstream release source, ports, volumes, documentation. Everything else about the image (its README, its build workflow, its page on the Labs site) is generated from it. |
| `Dockerfile`, `Dockerfile.aarch64` | The amd64 and arm64 builds. Each starts from a playground base image and downloads your app's release asset for the release tag it is given. |
| `root/` | Copied over the image's filesystem. `root/etc/s6-overlay/s6-rc.d/` holds the [s6-overlay](https://github.com/just-containers/s6-overlay) services that start your app. |
| `variants/selkies/` | The files to swap in when your app is a desktop program rather than a web app (see step 2). |
| `README.md` | A placeholder. `builder render` replaces it with the generated README. |

## Before you start

- Read [what qualifies](https://github.com/linuxserverlabs-playground/proposals#what-qualifies). In short: your
  app's source repository belongs to an organisation, has an open-source licence, and cuts stable releases with
  ready-built files (release assets) whose names stay the same from release to release, apart from the version.
- Install Docker, and the [GitHub CLI](https://cli.github.com/) if you want to use the `gh` commands below.

The kit assumes your app ships a release asset per architecture: a tarball with a binary in it, or a `.deb` for a
desktop app. An app installed another way (from a source archive, with npm or pip) uses the same layout; only the
`RUN` step in the Dockerfiles changes.

## 1. Create your repository

Name it `docker-<name>`, where `<name>` is the image name you want: lowercase letters, digits and dashes.

On GitHub, open [docker-template](https://github.com/linuxserverlabs-playground/docker-template) and choose
**Use this template**, then **Create a new repository** under your account or organisation. Or, with the GitHub CLI:

```bash
gh repo create <your-org>/docker-<name> --public --clone \
  --template linuxserverlabs-playground/docker-template
cd docker-<name>
```

## 2. Desktop app? Swap in the Selkies variant

Skip this step for a web app.

A desktop program runs in the browser on the playground's
[Selkies](https://github.com/selkies-project/selkies) base, which serves the desktop on ports 3000 (http) and 3001
(https). It needs no s6 service of its own: the base starts the program named in `root/defaults/autostart`.

```bash
cp variants/selkies/Dockerfile variants/selkies/Dockerfile.aarch64 variants/selkies/image.yml .
rm -rf root
mv variants/selkies/root root
rm -rf variants
```

Then fill in the files as below, skipping step 4. In `root/defaults/`, `autostart` and `autostart_wayland` hold
the command that starts your program, and `menu.xml` and `menu_wayland.xml` the desktop's right-click menu.

For a web app, you can delete `variants/` once you no longer need it.

## 3. Fill in image.yml

Every placeholder is marked `TODO` in a comment above it. Find them all with:

```bash
grep -rn TODO image.yml Dockerfile Dockerfile.aarch64 root
```

The fields that matter most:

| Field | What to put there |
| --- | --- |
| `name` | The image name, the same as in `docker-<name>`. |
| `maintainers` | GitHub logins without the `@`: you and anyone maintaining the image with you. They are credited on the image's page and mentioned when it needs attention. |
| `summary` | A sentence or two on what the app is, with a link to its homepage. |
| `upstream.version.repo` | `owner/repo` of your app's source repository. The image follows its latest stable GitHub release. |
| `upstream.version.require_assets` | One regular expression per release asset the Dockerfiles download, matched against the file name. Use `.*` where the version appears (`'^myapp-.*-linux-amd64\.tar\.gz$'`). A new release is only built once every asset is uploaded. |
| `build.version_arg` | The `ARG` the Dockerfiles read the release tag from, by convention `<NAME>_RELEASE`. |
| `build.platforms` | `amd64` and `arm64`, or only `amd64` (then delete `Dockerfile.aarch64` and the arm64 `require_assets` entry). |
| `test.web.port`, `runtime.ports` | The port your app's web interface listens on. The pipeline's smoke test checks that it answers. |
| `runtime.env` | Environment variables users may set, or delete the list. |
| `docs.setup` | What a user does after starting the container: where the web interface is, the default login or the setup wizard. |
| `proxy` | The web port again, and whether the app works under a subfolder (`/myapp/`) behind a reverse proxy. |

The full list of fields, with a description of each, is in the
[image.yml schema](https://github.com/linuxserver-playground/builder/blob/main/schemas/image.schema.json).

## 4. Name the s6 services after your app

A web app runs as two s6-overlay services, both in `root/etc/s6-overlay/s6-rc.d/`:

- `init-myapp-config` is a oneshot that runs as root on every start, before any service. It creates the folders
  your app writes to under `/config` and hands them to `abc`, the unprivileged user whose IDs come from `PUID` and
  `PGID`. Add first-run setup here, such as copying a default config file into `/config` when none exists.
- `svc-myapp` is a longrun service that starts your app in the foreground as `abc` (`s6-setuidgid abc`). It must
  listen on all interfaces on the port in `image.yml` and keep all its state under `/config`. The
  `s6-notifyoncheck ... -c "nc -z localhost 8080"` wrapper marks the service ready once the port answers; change the
  port there too.

The empty files wire them in: `user/contents.d/` lists the services s6 starts, `init-myapp-config/dependencies.d/`
runs the oneshot after the base image's own setup (`init-config`), `init-config-end/dependencies.d/` makes the
base wait for it, and `svc-myapp/dependencies.d/init-services` starts the app once setup is done.

Rename them for your app (here for an image called `myname`):

```bash
NAME=myname
(
  cd root/etc/s6-overlay/s6-rc.d
  mv init-myapp-config "init-${NAME}-config"
  mv svc-myapp "svc-${NAME}"
  mv init-config-end/dependencies.d/init-myapp-config "init-config-end/dependencies.d/init-${NAME}-config"
  mv user/contents.d/init-myapp-config "user/contents.d/init-${NAME}-config"
  mv user/contents.d/svc-myapp "user/contents.d/svc-${NAME}"
  sed -i "s/init-myapp-config/init-${NAME}-config/" "init-${NAME}-config/up"
)
```

Then edit the command in `svc-${NAME}/run`. Keep the first two lines of every `run` script
(`#!/usr/bin/with-contenv bash` and `# shellcheck shell=bash`) and keep the scripts executable: `builder check`
requires both.

## 5. Fill in the Dockerfiles

`Dockerfile` (amd64) and `Dockerfile.aarch64` (arm64) differ only in their `FROM` line and the asset they
download. In both:

- set `ARG` to your `build.version_arg`, and rename it everywhere it is used;
- set the upstream repository in the two URLs: the `releases/latest` lookup a plain local build uses, and the
  download;
- set the asset's file name for that architecture. `${MYAPP_RELEASE}` is the release tag (`v1.2.3`) and
  `${MYAPP_RELEASE#v}` the tag without a leading `v` (`1.2.3`), for asset names that carry the version;
- unpack the asset into `/app/<name>`, and add any runtime packages your app needs to `apk add` (the Selkies
  variant installs a `.deb` with `apt-get` instead: add the libraries it needs to that line);
- set `EXPOSE` to your web port.

Keep the `FROM` lines on the playground's base images: Labs builds only on them.

## 6. Build it

```bash
docker build -t <name> .
```

Without a version argument the build downloads the latest release. To build a specific one, as the pipeline does:

```bash
docker build --build-arg MYAPP_RELEASE=v1.2.3 -t <name> .
```

For arm64, on an arm64 machine:

```bash
docker build -f Dockerfile.aarch64 -t <name> .
```

## 7. Run it

```bash
docker run -d --name <name> \
  -p 127.0.0.1:8080:8080 \
  -e PUID=1000 -e PGID=1000 -e TZ=Etc/UTC \
  -v "$PWD/config":/config \
  <name>
docker logs -f <name>
```

The log shows the base image's setup, then your init and service. When it prints `[ls.io-init] done.`, open
http://localhost:8080/, or check the status code with
`curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/` (the pipeline's smoke test wants below 500). A Selkies image is at
https://localhost:3001/: publish `-p 127.0.0.1:3001:3001` instead and add `--shm-size=1gb`.

Check that it behaves like a LinuxServer image:

- the app process runs as your `PUID`/`PGID`, not root: `docker top <name>`;
- everything it writes is under `./config`, owned by that user;
- it starts again with its data after `docker restart <name>`, and after removing the container and running it
  again with the same `./config`.

Clean up with `docker rm -f <name>`.

## 8. Check it with builder

`builder` is the tool every LinuxServer image is checked and rendered with. Run it from the repository root, with
`GITHUB_REPOSITORY` naming the Labs repository your image will have. That makes it apply the Labs checks (for
example, that `maintainers` is set and that the image builds on a playground base image) and render the Labs
version of the generated files.

Render the generated files (README.md, AGENTS.md, LICENSE, `.github/FUNDING.yml` and the workflows):

```bash
docker run --rm -v "$PWD":/repo --user "$(id -u):$(id -g)" \
  -e GITHUB_REPOSITORY=linuxserverlabs-playground/docker-<name> \
  ghcr.io/linuxserver-playground/builder:latest render
```

Then check everything:

```bash
docker run --rm -v "$PWD":/repo \
  -e GITHUB_REPOSITORY=linuxserverlabs-playground/docker-<name> \
  ghcr.io/linuxserver-playground/builder:latest check
```

It prints `ok` when nothing is wrong, or one line per problem with the file, the field and the line. Run `render`
again after every change to `image.yml`, or `check` reports the generated files as out of date. A warning that the
two Dockerfiles' non-FROM lines differ is expected: they download different assets.

`render` writes `.github/workflows/`, the workflows a Labs repository runs. This kit's `.gitignore` keeps them out
of your repository, so nothing runs in your copy. Read the rendered README.md: it is what users will see.

## 9. Propose it

Push your work, then fill in the
[proposal form](https://github.com/linuxserverlabs-playground/proposals/issues/new?template=proposal.yml). Put your
repository's URL in **Working repository**. The proposal's automatic check confirms that it is public and has
`image.yml` and both Dockerfiles at its root, and a team member starts the Labs image from your `image.yml`,
Dockerfiles and `root/` instead of from scratch.

What happens after that, from the trial to the first release, is in the proposals repository's
[README](https://github.com/linuxserverlabs-playground/proposals#what-happens-next). The Labs image lives in its own
repository in the Labs organisation; you improve it there with pull requests from a fork.
