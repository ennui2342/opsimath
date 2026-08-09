# syntax=docker/dockerfile:1
# check=error=true

# Production image for the cover-compare sidecar (see docs/INTEGRATIONS.md's
# Phase 3 addendum). Deps baked in at build time, no bind mounts, no
# --reload — see Dockerfile.dev for local development instead. Single
# stage: every dependency (fastapi/uvicorn/opencv-python-headless/numpy/
# python-multipart) ships a prebuilt manylinux wheel, so unlike the Rails
# app's own multi-stage Dockerfile there's no compiler/build-only tooling
# to discard afterward.

FROM python:3.12-slim

WORKDIR /app
ENV PYTHONUNBUFFERED=1

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Run as a non-root user, same reasoning as the Rails app's own Dockerfile.
RUN groupadd --system --gid 1000 compare && \
    useradd compare --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

EXPOSE 8000

CMD ["python", "-m", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
