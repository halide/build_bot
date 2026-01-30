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
COPY --from=builder /buildbot/.venv /buildbot/.venv
ENV PATH="/buildbot/.venv/bin:$PATH" \
    VIRTUAL_ENV="/buildbot/.venv"

# Copy master source files
COPY master/master.cfg \
     master/custom_steps.py \
     master/buildbot.tac \
     master/toolchain.linux-arm32.cmake \
     /buildbot/master/

COPY master.sh /buildbot/master.sh
RUN chmod +x /buildbot/master.sh

# Ensure buildbot owns its home directory
RUN chown -R buildbot:buildbot /buildbot

USER buildbot
WORKDIR /buildbot

EXPOSE 8012 9990

ENTRYPOINT ["tini", "--"]
CMD ["/buildbot/master.sh", "start", "--nodaemon"]
