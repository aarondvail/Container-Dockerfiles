# Build from the repo root:  docker build -f ots-owntracks-bridge.dockerfile .
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    BRIDGE_CONFIG=/config/config.yaml

WORKDIR /app
COPY ots-owntracks-bridge/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY ots-owntracks-bridge/bridge.py .

USER 1000:1000
VOLUME ["/config"]
ENTRYPOINT ["python", "/app/bridge.py"]
