import asyncio
import json
import os
import sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import bridge  # noqa: E402


def iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%S.%fZ")


NOW = datetime.now(timezone.utc)

ITAK_PLI = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<event version="2.0" uid="E1F7A2C0-1111-2222-3333-444455556666" type="a-f-G-U-C" how="m-g"
 time="{iso(NOW)}" start="{iso(NOW)}" stale="{iso(NOW + timedelta(minutes=2))}">
 <point lat="27.7731" lon="-82.6400" hae="12.4" ce="5.0" le="9999999.0"/>
 <detail>
  <contact callsign="Vail Max" endpoint="*:-1:stcp"/>
  <__group name="Green" role="Team Member"/>
  <status battery="83"/>
  <track speed="2.5" course="271.6"/>
  <takv platform="iTAK" version="2.12" device="iPhone" os="18"/>
 </detail>
</event>"""

MESH_PLI = f"""<event version="2.0" uid="!a1b2f131" type="a-f-G-U-C" how="m-g"
 time="{iso(NOW)}" start="{iso(NOW)}" stale="{iso(NOW + timedelta(minutes=30))}">
 <point lat="27.7800" lon="-82.6500" hae="9999999.0" ce="9999999.0" le="9999999.0"/>
 <detail><contact callsign="T1000"/><__group name="Orange" role="Team Member"/>
 <status battery="100"/></detail></event>"""

NOFIX = f"""<event version="2.0" uid="!0c0d35e8" type="a-f-G-U-C" how="m-g"
 time="{iso(NOW)}" start="{iso(NOW)}" stale="{iso(NOW)}">
 <point lat="0.0" lon="0.0" hae="0" ce="9999999" le="9999999"/>
 <detail><contact callsign="M7 Base"/></detail></event>"""

MARKER = f"""<event version="2.0" uid="marker-1" type="a-h-G" how="h-g-i-g-o"
 time="{iso(NOW)}" start="{iso(NOW)}" stale="{iso(NOW)}">
 <point lat="27.0" lon="-82.0" hae="0" ce="10" le="10"/>
 <detail><contact callsign="Hazard"/></detail></event>"""

CHAT = f"""<event version="2.0" uid="GeoChat.x" type="b-t-f" how="h-g-i-g-o"
 time="{iso(NOW)}" start="{iso(NOW)}" stale="{iso(NOW)}">
 <point lat="27.1" lon="-82.1" hae="0" ce="10" le="10"/><detail/></event>"""


def cfg():
    return bridge.load_config(None)


# ---- parsing --------------------------------------------------------------

def test_parse_itak():
    p = bridge.parse_event(ITAK_PLI.split("?>", 1)[1])
    assert p.callsign == "Vail Max" and p.group == "Green"
    assert p.battery == 83 and p.platform == "iTAK"
    assert p.ce == 5.0 and p.hae == 12.4 and p.course == 271.6


def test_parse_unknown_sentinels_dropped():
    p = bridge.parse_event(MESH_PLI)
    assert p.hae is None and p.ce is None


def test_parse_no_fix_is_none():
    assert bridge.parse_event(NOFIX) is None


def test_parse_garbage():
    assert bridge.parse_event(b"<event uid='x'><point") is None
    assert bridge.parse_event(b"<auth/>") is None


def test_time_with_long_fraction():
    t = bridge._parse_time("2026-11-11T21:10:05.123456789Z")
    assert t.year == 2026 and t.tzinfo is not None


# ---- splitter -------------------------------------------------------------

def test_splitter_handles_fragments_and_headers():
    s = bridge.CotStreamSplitter()
    stream = (ITAK_PLI + MESH_PLI + CHAT).encode()
    out = []
    for i in range(0, len(stream), 37):  # awkward chunking on purpose
        out += s.feed(stream[i : i + 37])
    assert len(out) == 3
    assert all(e.startswith(b"<event") and e.endswith(b"</event>") for e in out)


def test_splitter_self_closing():
    s = bridge.CotStreamSplitter()
    out = s.feed(b'<event uid="a" type="t-x-c-t"/>' + MESH_PLI.encode())
    assert len(out) == 2


# ---- mapping --------------------------------------------------------------

def test_itak_mapping():
    m = bridge.Mapper(cfg())
    p = bridge.parse_event(ITAK_PLI.split("?>", 1)[1])
    assert m.accept(p) == (True, "")
    topic, msg = m.to_owntracks(p)
    assert topic == "owntracks/itak/vail-max"
    assert msg["_type"] == "location" and msg["tid"] == "VM"
    assert msg["batt"] == 83 and msg["vel"] == 9 and msg["cog"] == 272
    assert msg["acc"] == 5 and msg["alt"] == 12
    assert msg["tak_source"] == "iTAK" and msg["tak_team"] == "Green"


def test_mesh_mapping():
    m = bridge.Mapper(cfg())
    p = bridge.parse_event(MESH_PLI)
    topic, msg = m.to_owntracks(p)
    assert topic == "owntracks/mesh/f131"
    assert msg["tak_source"] == "meshtastic"
    assert "alt" not in msg and "acc" not in msg
    assert msg["tid"] == "31"


def test_mesh_detected_without_team():
    m = bridge.Mapper(cfg())
    p = bridge.parse_event(MESH_PLI.replace('<__group name="Orange" role="Team Member"/>', ""))
    assert m.to_owntracks(p)[0] == "owntracks/mesh/f131"


def test_override():
    c = cfg()
    c["mapping"]["overrides"] = {"Vail Max": {"name": "max", "tid": "MX"}}
    m = bridge.Mapper(c)
    p = bridge.parse_event(ITAK_PLI.split("?>", 1)[1])
    topic, msg = m.to_owntracks(p)
    assert topic == "owntracks/itak/max" and msg["tid"] == "MX"


def test_filters():
    m = bridge.Mapper(cfg())
    assert m.accept(bridge.parse_event(MARKER))[0] is False  # hand-placed marker
    assert m.accept(bridge.parse_event(CHAT))[0] is False    # not an atom
    old = bridge.parse_event(MESH_PLI)
    old.time = NOW - timedelta(hours=2)
    assert m.accept(old) == (False, "too old")


def test_exclude_callsign():
    c = cfg()
    c["filter"]["exclude_callsigns"] = ["^T1000$"]
    m = bridge.Mapper(c)
    assert m.accept(bridge.parse_event(MESH_PLI))[0] is False


def test_throttle():
    t = bridge.Throttle(15)
    msg = {"tst": 100, "lat": 1.0, "lon": 2.0}
    assert t.allow("a", msg, now=0)
    assert not t.allow("a", msg, now=100)                                 # duplicate
    assert not t.allow("a", {"tst": 101, "lat": 1.1, "lon": 2.0}, now=5)  # too soon
    assert t.allow("a", {"tst": 102, "lat": 1.2, "lon": 2.0}, now=20)
    assert not t.allow("a", {"tst": 50, "lat": 9.0, "lon": 9.0}, now=99)  # out of order


def test_auth_message_escapes():
    c = cfg()
    c["ots"]["username"] = "bridge"
    c["ots"]["password"] = 'p"w<d'
    assert b'password=\'p"w&lt;d\'' in bridge.auth_message(c)


# ---- end to end over a fake OTS socket ------------------------------------

class FakePublisher:
    def __init__(self):
        self.out = []

    def publish(self, topic, payload, retain=None):
        self.out.append((topic, payload, retain))


def test_end_to_end_fake_ots():
    received_from_bridge = []

    async def run():
        async def handler(reader, writer):
            received_from_bridge.append(await reader.read(4096))
            for chunk in (ITAK_PLI, MESH_PLI[:50], MESH_PLI[50:] + MARKER, NOFIX, ITAK_PLI):
                writer.write(chunk.encode())
                await writer.drain()
                await asyncio.sleep(0.02)
            await asyncio.sleep(0.2)
            writer.close()

        server = await asyncio.start_server(handler, "127.0.0.1", 0)
        port = server.sockets[0].getsockname()[1]
        c = cfg()
        c["ots"]["port"] = port
        pub = FakePublisher()
        b = bridge.Bridge(c, pub)
        try:
            await asyncio.wait_for(b._session(), timeout=3)
        except ConnectionError:
            pass
        server.close()
        return pub, b

    pub, b = asyncio.run(run())
    topics = [t for t, _, _ in pub.out]
    assert topics == [
        "owntracks/itak/vail-max/info",
        "owntracks/itak/vail-max",
        "owntracks/mesh/f131/info",
        "owntracks/mesh/f131",
    ], topics
    assert b.stats == {"events": 5, "published": 2, "filtered": 2, "throttled": 1}
    assert b"t-x-c-t" in received_from_bridge[0]  # bridge pinged on connect
    json.dumps([p for _, p, _ in pub.out])  # payloads are JSON-serialisable


def test_mesh_name_by_callsign():
    c = cfg()
    c["mapping"]["mesh_name"] = "callsign"
    m = bridge.Mapper(c)
    assert m.to_owntracks(bridge.parse_event(MESH_PLI))[0] == "owntracks/mesh/t1000"


def test_mesh_uid_with_prefix():
    m = bridge.Mapper(cfg())
    p = bridge.parse_event(MESH_PLI.replace('uid="!a1b2f131"', 'uid="meshtastic-a1b2f131"'))
    assert m.to_owntracks(p)[0] == "owntracks/mesh/f131"
