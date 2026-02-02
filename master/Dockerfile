# ── Builder stage ────────────────────────────────────────────────────────────
FROM ghcr.io/astral-sh/uv:0.6-python3.12-bookworm-slim AS builder

WORKDIR /buildbot

COPY pyproject.toml uv.lock ./
COPY master/pyproject.toml master/pyproject.toml
COPY worker/pyproject.toml worker/pyproject.toml

RUN uv sync --package master --frozen --no-dev --no-editable

# ── Runtime stage ────────────────────────────────────────────────────────────
FROM python:3.12-slim-bookworm

# git  – needed by GitPoller and GitHub source steps
# tini – simplest possible init system (reaps zombies, handles signals)
RUN apt-get update \
    && apt-get install -y --no-install-recommends git tini \
    && rm -rf /var/lib/apt/lists/*

# Non-root user
RUN useradd --create-home --home-dir /buildbot buildbot

# Copy virtual environment from builder
COPY --from=builder --chown=buildbot:buildbot /buildbot/.venv /buildbot/.venv
ENV PATH="/buildbot/.venv/bin:$PATH" \
    VIRTUAL_ENV="/buildbot/.venv"

# Copy source files
COPY --chown=buildbot:buildbot master/ master/
COPY --chown=buildbot:buildbot master.sh master.sh

USER buildbot
WORKDIR /buildbot

EXPOSE 8012 9990

ENTRYPOINT ["tini", "--"]
CMD ["/buildbot/master.sh", "start", "--nodaemon"]
