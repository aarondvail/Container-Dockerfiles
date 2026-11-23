# OpenTAKServer in Docker (host networking, existing Postgres + SWAG)

## What's in here

| File | Goes where | Purpose |
|---|---|---|
| `Dockerfile` | build folder | Builds `aarondvail/opentakserver`: Debian + OTS from PyPI in a venv, runs as user `ots` (UID 1000) |
| `entrypoint.sh` | build folder (copied into the image) | First start: generates `config.yml`, creates the CA, runs DB migrations. Then runs all four OTS processes (`opentakserver`, `cot_parser`, `eud_handler`, `eud_handler --ssl`) |
| `env.example` | rename to `.env` next to `run.sh` | DB password, DB/RabbitMQ hosts, Meshtastic on/off |
| `run.sh` | run on the Docker host | Starts RabbitMQ and OpenTAKServer (your `docker run` command + data volume + env file) |
| `rabbitmq/rabbitmq.conf` | copied by `run.sh` | MQTT listener on 1884, MQTT logins checked against OTS users |
| `rabbitmq/enabled_plugins` | copied by `run.sh` | Turns on management, MQTT and HTTP-auth plugins |
| `postgres-setup.sql` | run once against your Postgres | Creates `ots` role, `ots` DB, PostGIS extension |
| `swag/opentakserver.subdomain.conf` | SWAG `/config/nginx/proxy-confs/` | Web UI at `https://tak.<domain>` (Let's Encrypt cert) |
| `swag/opentakserver-tak-ports.conf` | SWAG `/config/nginx/site-confs/` | TAK client ports 8443 (Marti API, client certs) and 8446 (enrollment), using the OTS CA |
| `fetch-ots-ui.sh` | run on the Docker host | Downloads the OTS web UI into SWAG's `www/opentakserver` |
| `mosquitto-bridge.conf` | your MQTT broker's config | Bridges the Meshtastic topic from your broker into RabbitMQ on 1884 |

## Ports on the host

| Port | Service |
|---|---|
| 5672, 15672, 4369, 1884 | RabbitMQ (AMQP, management UI, epmd, MQTT) |
| 7081 | OTS API, behind SWAG (`OTS_LISTENER_PORT` in `.env`) |
| 8088 / 8089 | TAK TCP / SSL CoT streaming (direct to OTS) |
| 443, 8443, 8446 | SWAG (web UI, Marti API, enrollment) |

## Order of operations

1. **Postgres:** make sure your Postgres image includes PostGIS (`postgis/postgis:<same major>-3.x`), then
   `docker exec -i <pg-container> psql -U postgres < postgres-setup.sql`
   (set the same password in the SQL and in `.env`).
2. **Build:** `docker build -t aarondvail/opentakserver .`
3. **Env:** `cp env.example .env` and edit it.
4. **Start:** `./run.sh`, then watch `docker logs -f OpenTAKServer` until migrations and CA creation finish.
5. **SWAG:**
   - Replace `OTS_HOST` in both `swag/*.conf` files with the host's LAN IP (or `127.0.0.1` if SWAG uses host networking).
   - Copy them into place.
   - Add to SWAG's run command: `-v /opt/port/docker/opentakserver/ots/ca:/ots-ca:ro -p 8443:8443 -p 8446:8446`.
   - Run `./fetch-ots-ui.sh /path/to/swag/config`, then recreate SWAG.
6. **MQTT bridge:**
   - Create an OTS user in the web UI.
   - Fill in `mosquitto-bridge.conf` with that user and with the topic your Meshtastic nodes publish under.
   - Add the file to your broker and restart the broker.

## Checks

- openHAB defaults to HTTPS on 8443. Move it if it's on this host, or SWAG won't bind 8443.
- If nothing arrives from Meshtastic, enable the RabbitMQ management UI (port 15672) to see whether bridged messages land.
- If `pip install` fails on `debian:stable-slim`, change the base to `debian:bookworm-slim`.
