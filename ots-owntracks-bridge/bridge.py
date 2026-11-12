#!/usr/bin/env python3
"""
OTS -> OwnTracks bridge.

Connects to OpenTAKServer as a TAK client, reads the CoT stream, and
republishes position reports (iTAK/ATAK PLI and Meshtastic nodes) as
OwnTracks location messages on MQTT, so the OwnTracks Recorder and
openHAB pick them up like any other OwnTracks device.
"""

from __future__ import annotations

import argparse
import asyncio
import copy
import json
import logging
import os
import re
import signal
import ssl
import sys
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Any

import yaml

log = logging.getLogger("ots-owntracks")

# --------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------

DEFAULTS: dict[str, Any] = {
    # Where positions come from:
    #   rabbitmq - read OTS's "firehose" exchange (every CoT OTS handles, all groups). Recommended.
    #   tak      - connect to OTS as a TAK client on 8088/8089 (only sees the groups that client is in)
    "input": "rabbitmq",
    "rabbitmq": {
        "host": "127.0.0.1",
        "port": 5672,
        "username": "guest",      # OTS default; RabbitMQ only allows guest from localhost
        "password": "guest",
        "vhost": "/",
        "exchange": "firehose",
    },
    "ots": {
        "host": "127.0.0.1",
        "port": 8088,
        "tls": False,
        "ca_file": None,          # OTS CA (ca.pem) to verify the server
        "cert_file": None,        # client cert (PEM) for port 8089
        "key_file": None,         # client key (PEM)
        "key_password": None,
        "verify_hostname": False, # OTS certs rarely match the hostname you dial
        "username": None,         # optional <auth> for TCP streaming with auth on
        "password": None,
        "uid": None,              # defaults to a stable "ots-owntracks-bridge-<host>"
        "callsign": "OwnTracks-Bridge",
        "ping_interval": 30,
        "announce": False,        # send a self SA event (some setups need it before they route traffic)
        "announce_lat": 0.0,
        "announce_lon": 0.0,
    },
    "mqtt": {
        "host": "127.0.0.1",
        "port": 1883,
        "username": None,
        "password": None,
        "tls": False,
        "ca_file": None,
        "client_id": "ots-owntracks-bridge",
        "topic_prefix": "owntracks",
        "qos": 1,
        "retain": True,
        "publish_cards": True,    # OwnTracks "card" with the callsign as display name
        "status_topic": "ots-owntracks-bridge/status",
    },
    "filter": {
        "type_prefixes": ["a-"],      # atoms only (units), not drawings/markers types like u-d-*
        "machine_only": True,         # only how="m-*" (device-generated), drops hand-dropped map markers
        "include_uids": [],           # regexes; if set, only matching uids pass
        "exclude_uids": [],           # regexes
        "exclude_callsigns": [],      # regexes
        "min_interval": 15,           # seconds between publishes per device
        "max_age": 900,               # drop reports whose CoT time is older than this (s); 0 = off
    },
    "mapping": {
        # Topic is <topic_prefix>/<source>/<name>, e.g. owntracks/itak/vail-max
        "group_sources": {            # TAK team color -> source (first topic level)
            "Orange": "mesh",
            "Green": "itak",
        },
        "meshtastic_source": "mesh",  # used when a Meshtastic node (!xxxxxxxx) has no team
        "default_source": "tak",
        "mesh_name": "node_id",       # mesh nodes: "node_id" (last 4 hex, e.g. f131) or "callsign"
        "tak_name": "callsign",       # TAK clients: "callsign" or "uid"
        "overrides": {},              # uid or callsign -> {source, name, tid}
    },
    "log_level": "INFO",
}


def deep_merge(base: dict, extra: dict) -> dict:
    out = copy.deepcopy(base)
    for k, v in (extra or {}).items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = deep_merge(out[k], v)
        else:
            out[k] = v
    return out


ENV_OVERRIDES = {
    "OTS_HOST": ("ots", "host", str),
    "OTS_PORT": ("ots", "port", int),
    "OTS_USERNAME": ("ots", "username", str),
    "OTS_PASSWORD": ("ots", "password", str),
    "OTS_KEY_PASSWORD": ("ots", "key_password", str),
    "BRIDGE_INPUT": (None, "input", str),
    "RABBITMQ_HOST": ("rabbitmq", "host", str),
    "RABBITMQ_PORT": ("rabbitmq", "port", int),
    "RABBITMQ_USERNAME": ("rabbitmq", "username", str),
    "RABBITMQ_PASSWORD": ("rabbitmq", "password", str),
    "MQTT_HOST": ("mqtt", "host", str),
    "MQTT_PORT": ("mqtt", "port", int),
    "MQTT_USERNAME": ("mqtt", "username", str),
    "MQTT_PASSWORD": ("mqtt", "password", str),
    "LOG_LEVEL": (None, "log_level", str),
}


def load_config(path: str | None) -> dict:
    cfg = copy.deepcopy(DEFAULTS)
    if path and os.path.exists(path):
        with open(path, "r", encoding="utf-8") as fh:
            cfg = deep_merge(cfg, yaml.safe_load(fh) or {})
    elif path:
        log.warning("Config file %s not found, using defaults + environment", path)
    # Environment wins, so secrets can stay out of the YAML file.
    for env, (section, key, cast) in ENV_OVERRIDES.items():
        val = os.environ.get(env)
        if val is None or val == "":
            continue
        if section:
            cfg[section][key] = cast(val)
        else:
            cfg[key] = cast(val)
    if not cfg["ots"].get("uid"):
        cfg["ots"]["uid"] = f"ots-owntracks-bridge-{os.uname().nodename}"
    return cfg


# --------------------------------------------------------------------------
# CoT parsing
# --------------------------------------------------------------------------

UNKNOWN_ERR = 9_999_999.0
MESHTASTIC_UID = re.compile(r"^!?[0-9a-fA-F]{8}$")


@dataclass
class Position:
    uid: str
    type: str
    how: str
    time: datetime
    stale: datetime | None
    lat: float
    lon: float
    hae: float | None = None
    ce: float | None = None
    callsign: str | None = None
    group: str | None = None
    role: str | None = None
    battery: int | None = None
    speed: float | None = None   # m/s
    course: float | None = None  # degrees
    platform: str | None = None  # takv platform (iTAK, ATAK-CIV, Meshtastic, ...)
    meshtastic_id: str | None = None
    device: str | None = None    # takv device
    extra: dict = field(default_factory=dict)


def _parse_time(value: str | None) -> datetime | None:
    if not value:
        return None
    v = value.strip().replace("Z", "+00:00")
    # Some clients send more than 6 fractional digits; trim for fromisoformat.
    m = re.match(r"^(.*?\.\d{1,6})\d*(.*)$", v)
    if m:
        v = m.group(1) + m.group(2)
    try:
        dt = datetime.fromisoformat(v)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def _float(value: str | None) -> float | None:
    if value is None or value == "":
        return None
    try:
        f = float(value)
    except ValueError:
        return None
    if f != f or abs(f) >= UNKNOWN_ERR:  # NaN or the CoT "unknown" sentinel
        return None
    return f


def parse_event(xml: str | bytes) -> Position | None:
    """Parse one <event> into a Position, or None if it carries no usable fix."""
    try:
        root = ET.fromstring(xml)
    except ET.ParseError as exc:
        log.debug("Unparseable CoT (%s): %.200s", exc, xml)
        return None
    if root.tag != "event":
        return None
    point = root.find("point")
    if point is None:
        return None
    lat = _float(point.get("lat"))
    lon = _float(point.get("lon"))
    if lat is None or lon is None:
        return None
    if lat == 0.0 and lon == 0.0:
        return None  # no-fix placeholder (common for GPS-less mesh nodes)
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        return None

    evt_time = _parse_time(root.get("time")) or datetime.now(timezone.utc)
    pos = Position(
        uid=root.get("uid", ""),
        type=root.get("type", ""),
        how=root.get("how", ""),
        time=evt_time,
        stale=_parse_time(root.get("stale")),
        lat=lat,
        lon=lon,
        hae=_float(point.get("hae")),
        ce=_float(point.get("ce")),
    )

    detail = root.find("detail")
    if detail is not None:
        contact = detail.find("contact")
        if contact is not None:
            pos.callsign = contact.get("callsign") or None
        grp = detail.find("__group")
        if grp is not None:
            pos.group = grp.get("name") or None
            pos.role = grp.get("role") or None
        status = detail.find("status")
        if status is not None:
            b = _float(status.get("battery"))
            if b is not None:
                pos.battery = max(0, min(100, int(round(b))))
        track = detail.find("track")
        if track is not None:
            pos.speed = _float(track.get("speed"))
            pos.course = _float(track.get("course"))
        takv = detail.find("takv")
        if takv is not None:
            pos.platform = takv.get("platform") or None
            pos.device = takv.get("device") or None
            pos.meshtastic_id = takv.get("meshtastic_id") or None
        uid_el = detail.find("uid")
        if uid_el is not None and not pos.callsign:
            pos.callsign = uid_el.get("Droid") or None
    return pos


class CotStreamSplitter:
    """Splits a TCP byte stream of back-to-back CoT documents into single <event>s."""

    START = re.compile(rb"<event[\s>]")
    END = b"</event>"

    def __init__(self, max_buffer: int = 4 * 1024 * 1024) -> None:
        self.buf = bytearray()
        self.max_buffer = max_buffer

    def feed(self, data: bytes) -> list[bytes]:
        self.buf.extend(data)
        events: list[bytes] = []
        while True:
            m = self.START.search(self.buf)
            if not m:
                # Keep a small tail in case "<event" is split across reads.
                if len(self.buf) > 16:
                    del self.buf[:-16]
                break
            if m.start():
                del self.buf[: m.start()]  # drop <?xml?> headers, keepalives, junk
            # Self-closing <event .../> (rare, but legal XML)
            gt = self.buf.find(b">")
            if gt != -1 and self.buf[gt - 1 : gt] == b"/":
                events.append(bytes(self.buf[: gt + 1]))
                del self.buf[: gt + 1]
                continue
            end = self.buf.find(self.END)
            if end == -1:
                if len(self.buf) > self.max_buffer:
                    log.warning("CoT buffer overflow, discarding %d bytes", len(self.buf))
                    self.buf.clear()
                break
            stop = end + len(self.END)
            events.append(bytes(self.buf[:stop]))
            del self.buf[:stop]
        return events


# --------------------------------------------------------------------------
# Filtering and OwnTracks mapping
# --------------------------------------------------------------------------

def _slug(text: str) -> str:
    s = re.sub(r"[^A-Za-z0-9_-]+", "-", text.strip()).strip("-").lower()
    return s or "unknown"


def _tid(name: str) -> str:
    letters = re.sub(r"[^A-Za-z0-9]", "", name)
    if not letters:
        return "??"
    # Prefer initials ("Vail Max" -> "VM"); otherwise last two characters
    # (Meshtastic short names / node ids end in the distinguishing digits).
    words = [w for w in re.split(r"[\s_\-.]+", name) if w]
    if len(words) >= 2:
        return (words[0][0] + words[1][0]).upper()
    return letters[-2:].upper()


class Mapper:
    def __init__(self, cfg: dict) -> None:
        f = cfg["filter"]
        self.type_prefixes = tuple(f["type_prefixes"] or ())
        self.machine_only = bool(f["machine_only"])
        self.include_uids = [re.compile(p) for p in f["include_uids"] or []]
        self.exclude_uids = [re.compile(p) for p in f["exclude_uids"] or []]
        self.exclude_callsigns = [re.compile(p) for p in f["exclude_callsigns"] or []]
        self.max_age = float(f["max_age"] or 0)
        self.m = cfg["mapping"]
        self.self_uid = cfg["ots"]["uid"]
        self.prefix = cfg["mqtt"]["topic_prefix"].rstrip("/")

    def accept(self, p: Position, now: datetime | None = None) -> tuple[bool, str]:
        if not p.uid or p.uid == self.self_uid:
            return False, "self/empty uid"
        if self.type_prefixes and not p.type.startswith(self.type_prefixes):
            return False, f"type {p.type}"
        if self.machine_only and not p.how.startswith("m"):
            return False, f"how {p.how}"
        if self.include_uids and not any(r.search(p.uid) for r in self.include_uids):
            return False, "not in include_uids"
        if any(r.search(p.uid) for r in self.exclude_uids):
            return False, "excluded uid"
        if p.callsign and any(r.search(p.callsign) for r in self.exclude_callsigns):
            return False, "excluded callsign"
        if self.max_age:
            now = now or datetime.now(timezone.utc)
            if (now - p.time).total_seconds() > self.max_age:
                return False, "too old"
        return True, ""

    def is_meshtastic(self, p: Position) -> bool:
        uid = p.uid.split("-")[-1] if p.uid.lower().startswith("meshtastic") else p.uid
        return bool(MESHTASTIC_UID.match(uid)) or "meshtastic" in (p.platform or "").lower()

    def mesh_node_id(self, p: Position) -> str | None:
        for candidate in (p.uid, p.meshtastic_id or ""):
            m = re.search(r"([0-9a-fA-F]{8})$", candidate)
            if m:
                return m.group(1).lower()
        return None

    def identity(self, p: Position) -> tuple[str, str, str]:
        """Return (source, name, tid) -> topic <prefix>/<source>/<name>."""
        ov = self.m["overrides"].get(p.uid) or (
            self.m["overrides"].get(p.callsign) if p.callsign else None
        ) or {}
        mesh = self.is_meshtastic(p)

        source = ov.get("source")
        if not source:
            if p.group and p.group in self.m["group_sources"]:
                source = self.m["group_sources"][p.group]
            elif mesh:
                source = self.m["meshtastic_source"]
            else:
                source = self.m["default_source"]

        name = ov.get("name")
        if not name:
            node_id = self.mesh_node_id(p) if mesh else None
            if mesh and self.m["mesh_name"] == "node_id" and node_id:
                name = node_id[-4:]  # Meshtastic's default short name, e.g. f131
            elif not mesh and self.m["tak_name"] == "uid":
                name = p.uid
            else:
                name = p.callsign or p.uid
        tid = (ov.get("tid") or _tid(name))[:2]
        return _slug(source), _slug(name), tid

    def to_owntracks(self, p: Position) -> tuple[str, dict]:
        source, name, tid = self.identity(p)
        msg: dict[str, Any] = {
            "_type": "location",
            "lat": round(p.lat, 7),
            "lon": round(p.lon, 7),
            "tst": int(p.time.timestamp()),
            "tid": tid,
            "t": "p",
            "created_at": int(time.time()),
        }
        if p.hae is not None:
            msg["alt"] = int(round(p.hae))
        if p.ce is not None:
            msg["acc"] = int(round(p.ce))
        if p.battery is not None:
            msg["batt"] = p.battery
        if p.speed is not None:
            msg["vel"] = int(round(p.speed * 3.6))  # OwnTracks wants km/h
        if p.course is not None:
            msg["cog"] = int(round(p.course)) % 360
        # Non-standard keys are ignored by OwnTracks clients but kept by the
        # Recorder, which makes them handy in openHAB rules.
        msg["tak_uid"] = p.uid
        if p.callsign:
            msg["tak_callsign"] = p.callsign
        if p.group:
            msg["tak_team"] = p.group
        msg["tak_source"] = "meshtastic" if self.is_meshtastic(p) else (p.platform or "tak")
        return f"{self.prefix}/{source}/{name}", msg

    def card(self, p: Position) -> tuple[str, dict]:
        source, name, tid = self.identity(p)
        return (
            f"{self.prefix}/{source}/{name}/info",
            {"_type": "card", "name": p.callsign or p.uid, "tid": tid},
        )


class Throttle:
    """Per-topic rate limit and duplicate suppression."""

    def __init__(self, min_interval: float) -> None:
        self.min_interval = float(min_interval or 0)
        self.last: dict[str, tuple[float, int, float, float]] = {}

    def allow(self, topic: str, msg: dict, now: float | None = None) -> bool:
        now = time.monotonic() if now is None else now
        prev = self.last.get(topic)
        if prev:
            sent_at, tst, lat, lon = prev
            if msg["tst"] < tst:
                return False  # out-of-order / replayed history
            if msg["tst"] == tst and msg["lat"] == lat and msg["lon"] == lon:
                return False  # exact duplicate (OTS often repeats the latest SA on connect)
            if now - sent_at < self.min_interval:
                return False
        self.last[topic] = (now, msg["tst"], msg["lat"], msg["lon"])
        return True


# --------------------------------------------------------------------------
# MQTT
# --------------------------------------------------------------------------

class MqttPublisher:
    def __init__(self, cfg: dict) -> None:
        import paho.mqtt.client as mqtt

        self.cfg = cfg["mqtt"]
        self.client = mqtt.Client(
            mqtt.CallbackAPIVersion.VERSION2,
            client_id=self.cfg["client_id"],
            clean_session=True,
        )
        if self.cfg.get("username"):
            self.client.username_pw_set(self.cfg["username"], self.cfg.get("password"))
        if self.cfg.get("tls"):
            self.client.tls_set(ca_certs=self.cfg.get("ca_file"))
        st = self.cfg.get("status_topic")
        if st:
            self.client.will_set(st, "offline", qos=1, retain=True)
        self.client.reconnect_delay_set(min_delay=1, max_delay=60)
        self.client.on_connect = self._on_connect
        self.client.on_disconnect = self._on_disconnect

    def _on_connect(self, client, userdata, flags, reason_code, properties):
        if reason_code.is_failure:
            log.error("MQTT connect failed: %s", reason_code)
            return
        log.info("MQTT connected to %s:%s", self.cfg["host"], self.cfg["port"])
        st = self.cfg.get("status_topic")
        if st:
            client.publish(st, "online", qos=1, retain=True)

    def _on_disconnect(self, client, userdata, flags, reason_code, properties):
        if reason_code.is_failure:
            log.warning("MQTT disconnected (%s), will reconnect", reason_code)

    def start(self) -> None:
        self.client.connect_async(self.cfg["host"], int(self.cfg["port"]), keepalive=60)
        self.client.loop_start()

    def publish(self, topic: str, payload: dict, retain: bool | None = None) -> None:
        self.client.publish(
            topic,
            json.dumps(payload, separators=(",", ":")),
            qos=int(self.cfg["qos"]),
            retain=self.cfg["retain"] if retain is None else retain,
        )

    def stop(self) -> None:
        st = self.cfg.get("status_topic")
        if st:
            self.client.publish(st, "offline", qos=1, retain=True).wait_for_publish(2)
        self.client.loop_stop()
        self.client.disconnect()


# --------------------------------------------------------------------------
# OTS connection
# --------------------------------------------------------------------------

def _cot_time(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")[:-4] + "Z"


def ping_event(uid: str) -> bytes:
    now = datetime.now(timezone.utc)
    return (
        f'<event version="2.0" uid="{uid}-ping" type="t-x-c-t" how="h-g-i-g-o" '
        f'time="{_cot_time(now)}" start="{_cot_time(now)}" '
        f'stale="{_cot_time(now + timedelta(seconds=20))}">'
        f'<point lat="0" lon="0" hae="0" ce="{UNKNOWN_ERR}" le="{UNKNOWN_ERR}"/>'
        f"<detail/></event>"
    ).encode()


def announce_event(cfg: dict) -> bytes:
    o = cfg["ots"]
    now = datetime.now(timezone.utc)
    return (
        f'<event version="2.0" uid="{o["uid"]}" type="a-f-G-E-S" how="h-g-i-g-o" '
        f'time="{_cot_time(now)}" start="{_cot_time(now)}" '
        f'stale="{_cot_time(now + timedelta(minutes=5))}">'
        f'<point lat="{o["announce_lat"]}" lon="{o["announce_lon"]}" hae="0" '
        f'ce="{UNKNOWN_ERR}" le="{UNKNOWN_ERR}"/>'
        f'<detail><contact callsign="{o["callsign"]}"/>'
        f'<takv platform="ots-owntracks-bridge" version="1.0" device="server" os="linux"/>'
        f"</detail></event>"
    ).encode()


def auth_message(cfg: dict) -> bytes | None:
    o = cfg["ots"]
    if not o.get("username"):
        return None
    from xml.sax.saxutils import quoteattr

    return (
        f"<auth><cot username={quoteattr(o['username'])} "
        f"password={quoteattr(o.get('password') or '')} uid={quoteattr(o['uid'])}/></auth>"
    ).encode()


def build_ssl_context(o: dict) -> ssl.SSLContext:
    ctx = ssl.create_default_context(cafile=o.get("ca_file") or None)
    if not o.get("ca_file"):
        log.warning("No ots.ca_file set: server certificate will NOT be verified")
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    else:
        ctx.check_hostname = bool(o.get("verify_hostname"))
    if o.get("cert_file"):
        ctx.load_cert_chain(o["cert_file"], o.get("key_file"), o.get("key_password"))
    return ctx


class Bridge:
    def __init__(self, cfg: dict, publisher) -> None:
        self.cfg = cfg
        self.publisher = publisher
        self.mapper = Mapper(cfg)
        self.throttle = Throttle(cfg["filter"]["min_interval"])
        self.cards_sent: dict[str, str] = {}
        self.stats = {"events": 0, "published": 0, "filtered": 0, "throttled": 0}
        self._stop = asyncio.Event()

    def handle_event(self, raw: bytes) -> None:
        self.stats["events"] += 1
        pos = parse_event(raw)
        if pos is None:
            self.stats["filtered"] += 1
            log.debug("skip (no usable position): %.300s", raw)
            return
        ok, why = self.mapper.accept(pos)
        if not ok:
            self.stats["filtered"] += 1
            log.debug("skip %s (%s): %s", pos.uid, pos.callsign, why)
            return
        topic, msg = self.mapper.to_owntracks(pos)
        if not self.throttle.allow(topic, msg):
            self.stats["throttled"] += 1
            return
        if self.cfg["mqtt"]["publish_cards"]:
            card_topic, card = self.mapper.card(pos)
            if self.cards_sent.get(card_topic) != card["name"]:
                self.publisher.publish(card_topic, card, retain=True)
                self.cards_sent[card_topic] = card["name"]
        self.publisher.publish(topic, msg)
        self.stats["published"] += 1
        log.info(
            "%s -> %s (%.5f, %.5f)%s",
            pos.callsign or pos.uid, topic, pos.lat, pos.lon,
            f" batt={pos.battery}%" if pos.battery is not None else "",
        )

    async def _pinger(self, writer: asyncio.StreamWriter) -> None:
        interval = max(5, int(self.cfg["ots"]["ping_interval"]))
        while True:
            await asyncio.sleep(interval)
            writer.write(ping_event(self.cfg["ots"]["uid"]))
            if self.cfg["ots"]["announce"]:
                writer.write(announce_event(self.cfg))
            await writer.drain()

    async def _session(self) -> None:
        o = self.cfg["ots"]
        ctx = build_ssl_context(o) if o["tls"] else None
        log.info("Connecting to OTS %s:%s (%s)", o["host"], o["port"], "TLS" if ctx else "TCP")
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(o["host"], int(o["port"]), ssl=ctx), timeout=15
        )
        log.info("Connected to OTS as uid=%s", o["uid"])
        auth = auth_message(self.cfg)
        if auth:
            writer.write(auth)
        writer.write(ping_event(o["uid"]))
        if o["announce"]:
            writer.write(announce_event(self.cfg))
        await writer.drain()

        splitter = CotStreamSplitter()
        pinger = asyncio.create_task(self._pinger(writer))
        # TAK servers send pings/SA regularly; silence this long means a dead link.
        idle_timeout = max(90, 3 * int(o["ping_interval"]))
        try:
            while not self._stop.is_set():
                data = await asyncio.wait_for(reader.read(65536), timeout=idle_timeout)
                if not data:
                    raise ConnectionError("OTS closed the connection")
                for raw in splitter.feed(data):
                    try:
                        self.handle_event(raw)
                    except Exception:  # never let one bad event kill the session
                        log.exception("Error handling event: %.300s", raw)
        finally:
            pinger.cancel()
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass

    def handle_firehose(self, body: bytes) -> None:
        """Firehose messages are JSON: {"uid": <sender uid>, "cot": "<event ...>"}."""
        try:
            cot = json.loads(body)["cot"]
        except (ValueError, KeyError, TypeError):
            cot = body  # tolerate raw CoT, just in case
        if isinstance(cot, str):
            cot = cot.encode()
        self.handle_event(cot)

    async def _rabbit_session(self) -> None:
        import aio_pika

        r = self.cfg["rabbitmq"]
        log.info("Connecting to RabbitMQ %s:%s, exchange %s", r["host"], r["port"], r["exchange"])
        conn = await aio_pika.connect(
            host=r["host"], port=int(r["port"]), login=r["username"],
            password=r["password"], virtualhost=r["vhost"], timeout=15,
            client_properties={"connection_name": "ots-owntracks-bridge"},
        )
        try:
            channel = await conn.channel()
            await channel.set_qos(prefetch_count=100)
            # passive: never (re)declare OTS's exchange, just fail until OTS has created it
            exchange = await channel.get_exchange(r["exchange"], ensure=True)
            queue = await channel.declare_queue(
                "", exclusive=True, auto_delete=True, arguments={"x-message-ttl": 60000}
            )
            await queue.bind(exchange)
            log.info("Subscribed to OTS %s", r["exchange"])
            closed = asyncio.Event()
            conn.close_callbacks.add(lambda *_: closed.set())

            async def on_message(message) -> None:
                async with message.process(ignore_processed=True):
                    try:
                        self.handle_firehose(message.body)
                    except Exception:
                        log.exception("Error handling event: %.300s", message.body)

            await queue.consume(on_message)
            stop_wait = asyncio.create_task(self._stop.wait())
            closed_wait = asyncio.create_task(closed.wait())
            done, pending = await asyncio.wait(
                {stop_wait, closed_wait}, return_when=asyncio.FIRST_COMPLETED
            )
            for t in pending:
                t.cancel()
            if closed_wait in done and not self._stop.is_set():
                raise ConnectionError("RabbitMQ connection closed")
        finally:
            await conn.close()

    async def run(self) -> None:
        backoff = 2
        mode = str(self.cfg.get("input", "rabbitmq")).lower()
        session = self._rabbit_session if mode == "rabbitmq" else self._session
        while not self._stop.is_set():
            started = time.monotonic()
            try:
                await session()
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                log.warning("%s session ended: %s", mode, exc or type(exc).__name__)
            if self._stop.is_set():
                break
            if time.monotonic() - started > 60:
                backoff = 2  # it was a healthy session, reconnect quickly
            log.info("Reconnecting in %ss (stats: %s)", backoff, self.stats)
            try:
                await asyncio.wait_for(self._stop.wait(), timeout=backoff)
            except asyncio.TimeoutError:
                pass
            backoff = min(backoff * 2, 60)

    def stop(self) -> None:
        self._stop.set()


async def amain(cfg: dict) -> None:
    publisher = MqttPublisher(cfg)
    publisher.start()
    bridge = Bridge(cfg, publisher)
    loop = asyncio.get_running_loop()
    task = asyncio.create_task(bridge.run())

    def _shutdown() -> None:
        log.info("Shutting down")
        bridge.stop()
        task.cancel()

    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, _shutdown)
    try:
        await task
    except asyncio.CancelledError:
        pass
    finally:
        publisher.stop()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    ap.add_argument("-c", "--config", default=os.environ.get("BRIDGE_CONFIG", "/config/config.yaml"))
    ap.add_argument("--dump-config", action="store_true", help="print effective config (secrets masked) and exit")
    args = ap.parse_args()

    cfg = load_config(args.config)
    logging.basicConfig(
        level=getattr(logging, str(cfg["log_level"]).upper(), logging.INFO),
        format="%(asctime)s %(levelname)-7s %(message)s",
        stream=sys.stdout,
    )
    if args.dump_config:
        shown = json.loads(json.dumps(cfg))
        for sec in ("ots", "mqtt", "rabbitmq"):
            for k in ("password", "key_password"):
                if shown[sec].get(k):
                    shown[sec][k] = "***"
        print(yaml.safe_dump(shown, sort_keys=False))
        return
    asyncio.run(amain(cfg))


if __name__ == "__main__":
    main()
