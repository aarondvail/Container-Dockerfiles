# OTS → OwnTracks bridge

Reads every CoT OpenTAKServer handles from its RabbitMQ `firehose` exchange, takes the
position reports (iTAK/ATAK phones and Meshtastic nodes), and publishes them to your MQTT broker
as standard OwnTracks `location` messages. The OwnTracks Recorder and openHAB
treat them like any other OwnTracks device.

```
iTAK (Green) ─┐
              ├─ OTS ─firehose─> bridge ──MQTT──> owntracks/itak/<callsign>
Meshtastic ───┘  (Orange)                       owntracks/mesh/<node id last 4>
                                                ├─> OwnTracks Recorder
                                                └─> openHAB
```

## What gets published

| CoT | OwnTracks |
|---|---|
| `__group@name` | first topic level (`Green` → `itak`, `Orange` → `mesh`) |
| `contact@callsign` | second topic level for iTAK (`Vail Max` → `vail-max`), card name |
| Meshtastic node ID | second topic level for mesh (`!xxxxf131` → `f131`) |
| `point` lat/lon/hae/ce | `lat`, `lon`, `alt`, `acc` (unknown 9999999 values are omitted) |
| `status@battery` | `batt` |
| `track` speed/course | `vel` (km/h), `cog` |
| `time` | `tst` |

Extra keys `tak_uid`, `tak_callsign`, `tak_team` and `tak_source`
(`meshtastic` / `iTAK` / ...) ride along for openHAB rules. OwnTracks apps ignore them.

Skipped: hand-dropped map markers, chat, drawings, nodes with no GPS fix
(0,0, such as the M7 base station), the bridge itself, and anything older than
`max_age` (OTS replays recent history on connect).

Messages are retained, and updates are limited to one every `min_interval` seconds per device.

## Install

1. Copy this folder to `/opt/port/docker/build/ots-owntracks-bridge/` and the
   rebuild script to `/root/`, then run it once. It creates
   `/opt/port/ots-owntracks-bridge/config.yaml` from the example and stops.
2. Edit `config.yaml`. Put secrets in `/opt/port/ots-owntracks-bridge/bridge.env`:
   ```
   MQTT_PASSWORD=...
   OTS_PASSWORD=...        # only if the OTS TCP port requires auth
   OTS_KEY_PASSWORD=...    # only for a client cert on 8089
   ```
3. Create an MQTT user for the bridge that can publish to `owntracks/#` and
   `ots-owntracks-bridge/#`.
4. Run `/root/rebuild-ots-owntracks-bridge.sh` and watch
   `docker logs -f ots-owntracks-bridge`. Every published update logs a line:
   ```
   Vail Max -> owntracks/itak/vail-max (27.77310, -82.64000) batt=83%
   ```

### Connecting to OTS

The bridge reads OTS's RabbitMQ `firehose` exchange (`input: rabbitmq`, the default).
OTS copies every CoT it handles there, so the bridge sees all groups (Green, Orange,
Meshtastic, `__ANON__`) without being a TAK client. It doesn't appear on anyone's map
and needs no certificate.

It needs to reach OTS's RabbitMQ on port 5672. Check from the host:
```
ss -ltnp | grep 5672
```
If OTS's RabbitMQ runs inside a container, publish 5672 on the host (bind it to
`127.0.0.1:5672:5672` so it isn't exposed on the LAN).

RabbitMQ only accepts the default `guest` user from localhost. Through Docker port
publishing, the connection often looks non-local, and you'll see `ACCESS_REFUSED` in the
log. In that case, create a dedicated read-only user (run inside the RabbitMQ container):
```
rabbitmqctl add_user owntracks-bridge '<password>'
rabbitmqctl set_permissions -p / owntracks-bridge '^amq\.gen-.*' '^amq\.gen-.*' '^(firehose|amq\.gen-.*)$'
```
then set `rabbitmq.username: owntracks-bridge` and put `RABBITMQ_PASSWORD=...` in `bridge.env`.
That user can only create its own temporary queue and read the firehose.

`input: tak` (connecting on 8088/8089 like an EUD) is still there, but OTS only routes a
TCP client the `__ANON__` group, so it misses iTAK users with group memberships and all
Meshtastic traffic (`Meshtastic.OUT`).

### Check it

```
mosquitto_sub -h localhost -u <user> -P <pass> -t 'owntracks/#' -v
mosquitto_sub -h localhost -u <user> -P <pass> -t 'ots-owntracks-bridge/status'
python bridge.py -c config.yaml --dump-config   # effective settings, secrets masked
```

## Notes

- **No positions logged?** Set `log_level: DEBUG` (or `LOG_LEVEL=DEBUG` in `bridge.env`)
  to see why each event was skipped. If nothing arrives at all, check that the
  phone and mesh nodes appear on the OTS web map. The firehose only carries what OTS
  itself receives.
- **Mesh node names.** OTS names nodes it hasn't heard a NodeInfo from
  `Meshtastic xxxx`, and gives them team Cyan unless set. The topic still comes from the
  node ID (`owntracks/mesh/f131`), so neither matters here.
- **Your phone running both OwnTracks and iTAK** shows up twice, as
  `owntracks/vail-phone/...` from the OwnTracks app and `owntracks/itak/<callsign>`
  from the bridge. Either keep them separate (openHAB can pick whichever is
  fresher) or exclude your callsign with `exclude_callsigns`.
- **openHAB.** If your existing setup discovers OwnTracks topics, the new
  devices appear like your phones. Otherwise add MQTT Things for
  `owntracks/itak/<callsign>` and `owntracks/mesh/<node>` the same way as `Vail-Phone`.
  The Recorder sees `itak` and `mesh` as two users, each tracker as one of their devices. Mesh nodes update at
  their PLI interval (often minutes), so give region presence some hysteresis.
- **Recorder.** No changes needed if it subscribes to `owntracks/#`.
  The `/info` card sets the display name.

## Tests

```
pip install -r requirements.txt pytest
python -m pytest -q
```
