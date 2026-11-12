#!/usr/bin/env python3
"""
Local fix for OpenTAKServer 1.8.0: meshtastic_controller.insert_or_update_eud

Problems:
  1. It emits the EUD to the web map before the team is looked up and without
     last_status, so the map draws mesh nodes as disconnected with no team color.
  2. For existing nodes (update_if_exists=False) it never refreshes last_status or
     last_event_time in the database.

Fix:
  - Set last_status="Connected" and last_event_time=now on every packet.
  - Emit the EUD after the team lookup, with the team attached.
  - For existing nodes, update last_status and last_event_time in the database.

Safe to run more than once. Fails the build if the upstream code has changed,
so you know to revisit this patch.
"""
import glob
import sys

MARKER = "local fix: eud status"

matches = glob.glob(
    "/home/ots/.opentakserver_venv/lib/python3*/site-packages/"
    "opentakserver/controllers/meshtastic_controller.py"
)
if not matches:
    sys.exit("patch_mesh_eud: meshtastic_controller.py not found")
f = matches[0]

s = open(f).read()
if MARKER in s:
    print(f"patch_mesh_eud: already patched ({f})")
    sys.exit(0)

old_emit = '''        with self.context:
            socketio.emit("eud", eud.to_json(), namespace="/socket.io")

        with self.context:
            team = db.session.execute(
                db.session.query(Team).filter_by(name=self.meshtastic_devices[from_id]["team"])
            ).scalar()
            if team:
                eud.team_id = team.id
'''

new_emit = '''        # local fix: eud status - mark mesh EUDs connected, emit after team is known
        eud.last_status = "Connected"
        eud.last_event_time = datetime.datetime.now(datetime.timezone.utc)

        with self.context:
            team = db.session.execute(
                db.session.query(Team).filter_by(name=self.meshtastic_devices[from_id]["team"])
            ).scalar()
            if team:
                eud.team_id = team.id
                eud.team = team
            socketio.emit("eud", eud.to_json(), namespace="/socket.io")
'''

old_upd = '''                if update_if_exists:
                    db.session.execute(
                        sqlalchemy.update(EUD).where(EUD.uid == uid).values(**eud.serialize())
                    )
                    db.session.commit()
'''

new_upd = old_upd + '''                else:
                    db.session.execute(
                        sqlalchemy.update(EUD).where(EUD.uid == uid).values(
                            last_status="Connected", last_event_time=eud.last_event_time)
                    )
                    db.session.commit()
'''

if s.count(old_emit) != 1:
    sys.exit("patch_mesh_eud: emit block not found - upstream code changed, review the patch")
if s.count(old_upd) != 1:
    sys.exit("patch_mesh_eud: update block not found - upstream code changed, review the patch")

s = s.replace(old_emit, new_emit).replace(old_upd, new_upd)
with open(f, "w") as fh:
    fh.write(s)
print(f"patch_mesh_eud: patched {f}")
