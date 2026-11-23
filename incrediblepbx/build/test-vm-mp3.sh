#!/usr/bin/env bash
# Build-time self-test for sendmail-vm-mp3: feeds it Asterisk-style voicemail
# emails with PCM wav and GSM (wav49) attachments and checks MP3 comes out.
set -euo pipefail
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
sox -q -n -r 8000 -c 1 -e signed-integer -b 16 "$T/pcm.wav" synth 3 sine 440
sox -q -n -r 8000 -c 1 -e gsm-full-rate "$T/gsm.wav" synth 3 sine 440

mkmail(){  # file name ctype
  cat <<EOF
From: "Voicemail" <asterisk@pbx.local>
To: "Test" <test@example.com>
Subject: New voicemail
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="----voicemail_0001"

------voicemail_0001
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 8bit

You have a new voicemail.

------voicemail_0001
Content-Type: $3; name="$2"
Content-Transfer-Encoding: base64
Content-Description: Voicemail sound attachment.
Content-Disposition: attachment; filename="$2"

$(base64 "$1")

------voicemail_0001--
EOF
}

rc=0
for case in "pcm.wav:msg0000.wav:audio/x-wav" "gsm.wav:msg0000.WAV:audio/x-WAV"; do
  IFS=: read -r f name ctype <<<"$case"
  mkmail "$T/$f" "$name" "$ctype" > "$T/in.eml"
  VM_SENDMAIL="tee $T/out.eml" /usr/local/sbin/sendmail-vm-mp3 < "$T/in.eml" >/dev/null
  if grep -q 'Content-Type: audio/mpeg; name="msg0000.mp3"' "$T/out.eml" \
     && python3 - "$T/out.eml" <<'PY'
import email, sys
m = email.message_from_binary_file(open(sys.argv[1], "rb"))
mp3 = [p for p in m.walk() if p.get_content_type() == "audio/mpeg"][0].get_payload(decode=True)
assert mp3[:3] == b"ID3" or (mp3[0] == 0xFF and mp3[1] & 0xE0 == 0xE0), "not an MP3"
assert any(p.get_content_type() == "text/plain" for p in m.walk()), "body lost"
PY
  then echo "vm-mp3 self-test OK: $ctype"
  else echo "vm-mp3 self-test FAILED: $ctype"; rc=1; fi
done

# A broken attachment must fall back to the original message
mkmail /etc/hostname "msg0001.wav" "audio/x-wav" > "$T/bad.eml"
VM_SENDMAIL="tee $T/out.eml" /usr/local/sbin/sendmail-vm-mp3 < "$T/bad.eml" >/dev/null
if cmp -s "$T/bad.eml" "$T/out.eml"; then echo "vm-mp3 self-test OK: fallback"
else echo "vm-mp3 self-test FAILED: fallback"; rc=1; fi
exit $rc
