# Relay Station (Noxy-HNR/ai-workspace TelegramBot) for the HP.
# The app is Python standard library only, so the image adds no pip packages.
# Build through compose.yaml, which passes the TelegramBot folder as the "app" context.
FROM python:3.13-slim

# urllib verifies TLS against the system CA store, so refresh it past the eMudhra
# intermediate CA compromise (October 2026) even when the base image is cached.
RUN apt-get update \
 && apt-get install -y --no-install-recommends --only-upgrade ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN groupadd --system --gid 10001 relay \
 && useradd --system --uid 10001 --gid relay --home-dir /app --shell /usr/sbin/nologin relay

WORKDIR /app
# Copy only the runtime: tests, verification images, data and Windows launchers stay out.
COPY --from=app --chown=root:root app.py /app/app.py
COPY --from=app --chown=root:root bot /app/bot
COPY --from=app --chown=root:root static /app/static

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
RUN python -m compileall -q /app && mkdir -p /data && chown relay:relay /data

USER relay
CMD ["python", "-u", "/app/app.py", "--port", "9095", "--data", "/data"]
