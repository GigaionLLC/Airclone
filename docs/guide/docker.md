# Running Airclone in Docker

The Docker image runs Airclone on a server and serves its [Web UI](web-ui.md) to your browser. It is
the same app as every other download: the Linux build, in a container, with nothing to install on
the host but Docker.

It is published to the GitHub Container Registry as `ghcr.io/gigaionllc/airclone`, for **x86_64 and
ARM64** (Raspberry Pi 4/5 on a 64-bit OS, ARM servers). Docker picks the right one by itself.
Available from v0.24.0.

## Start it

Save this as `docker-compose.yml` (it is also in the repository at
[`docker/docker-compose.yml`](../../docker/docker-compose.yml)):

```yaml
services:
  airclone:
    image: ghcr.io/gigaionllc/airclone:latest   # or pin a version, e.g. :0.24.0
    container_name: airclone
    restart: unless-stopped
    ports:
      - "5799:5799"   # Web UI. To use another port, change the LEFT number only.
    environment:
      # Your own login (optional). Leave these commented out and a strong
      # password is generated on first start: read it with `docker logs airclone`.
      # AIRCLONE_WEBUI_USER: airclone
      # AIRCLONE_WEBUI_PASSWORD: choose-a-long-password
      PUID: 1000      # files Airclone writes to your folders belong to this user...
      PGID: 1000      # ...and group. Run `id` on the server to see yours.
      TZ: Etc/UTC     # your time zone, for scheduled backups (e.g. America/New_York)
    volumes:
      - ./config:/config                # Airclone's settings, remotes and login. Back this up.
      - /path/on/your/server:/data      # what shows as "Home" in Airclone
```

Change `/path/on/your/server` to the folder you want Airclone to see, then:

```bash
docker compose up -d
```

## Sign in

1. Open **`https://<your-server>:5799`**. It is `https`, not `http`: the Web UI only speaks HTTPS.
2. Your browser warns about the certificate **the first time**. That is expected: Airclone made its
   own certificate, because nobody can issue a trusted one for a machine on your home network.
   Accept it once. The [Web UI page](web-ui.md) explains how to check its fingerprint. To use your
   own certificate, put `cert.pem` and `key.pem` in
   `config/com.gigaionllc.airclone/webui/imported/` and restart the container.
3. Sign in as **`airclone`**. The password is either the one you set, or the generated one:

   ```bash
   docker logs airclone
   ```

## Your own password

Set `AIRCLONE_WEBUI_PASSWORD` (and optionally `AIRCLONE_WEBUI_USER`) in the compose file and run
`docker compose up -d` again. A password from the environment always wins, and it is **never written
to disk**. Without one, the generated password is kept in `/config` and reused on every restart.

To keep the password out of the compose file, put it in a `.env` file beside it:

```bash
AIRCLONE_WEBUI_PASSWORD=choose-a-long-password
```

and in the compose file replace the `environment` password line with `env_file: .env`.

There is no way to run it **without** a password, on purpose: the Web UI can reach every remote you
have, so it is never left open.

## Your files

- **`/config`** holds everything Airclone keeps: your rclone remotes, saved tasks, the Web UI login
  and certificate. Back this folder up; it is your whole setup.
- **`/data`** is what Airclone shows as **Home**. Mount as many folders as you like under it, for
  example `- /mnt/photos:/data/photos` and `- /srv/backups:/data/backups`.
- Already have an `rclone.conf`? Import it in Airclone (**Settings → Config → Import**) and you see
  every remote before anything is saved.

## Update

```bash
docker compose pull
docker compose up -d
```

Your settings stay in `/config`. To stay on one version, use a version tag (`:0.24.0`) instead of
`:latest`. `:latest` moves only when a release is complete on every platform.

## Things to know

- **Do not publish port 5799 to the internet** as it is. It is fine on your home network or behind a
  VPN. To reach it from outside, put it behind a reverse proxy with a real certificate, and keep the
  password strong.
- **Mounting a cloud as a drive is off** in the container: it needs FUSE, which a container only gets
  with extra privileges (`--device /dev/fuse --cap-add SYS_ADMIN`). Browsing, copying, syncing and
  backups all work without it.
- **Scheduled backups** run while the container runs. With `restart: unless-stopped` that is always.
