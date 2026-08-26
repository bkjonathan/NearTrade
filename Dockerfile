# syntax=docker/dockerfile:1

# Pinned so a rebuild six months from now produces the same binary.
ARG GO_VERSION=1.26.1
ARG ALPINE_VERSION=3.22

# ---------------------------------------------------------------------------
# Stage 1 — build
# ---------------------------------------------------------------------------
FROM golang:${GO_VERSION}-alpine AS build

WORKDIR /src

# Dependencies are copied on their own so this layer stays cached until
# go.mod/go.sum actually change — source edits don't re-download modules.
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY . .

# Predefined platform args. They must be redeclared WITHOUT a default --
# a default here shadows the value BuildKit injects and silently cross-compiles
# for the wrong architecture. The shell fallbacks below cover the legacy builder.
ARG TARGETOS
ARG TARGETARCH

# CGO off  -> fully static binary, no libc dependency at runtime.
# -trimpath -> strips local paths, makes builds reproducible.
# -s -w     -> drops the symbol table and DWARF data (~30% smaller).
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH:-amd64} \
    go build -trimpath -ldflags='-s -w' -o /out/api ./cmd/api

# ---------------------------------------------------------------------------
# Stage 2 — runtime
# ---------------------------------------------------------------------------
# Alpine rather than distroless/scratch: Coolify's health checks and
# `docker exec` debugging both need a shell, for ~4 MB extra.
FROM alpine:${ALPINE_VERSION} AS runtime

RUN apk add --no-cache ca-certificates tzdata \
    && addgroup -g 10001 -S app \
    && adduser -u 10001 -S app -G app -h /app

WORKDIR /app
COPY --from=build --chown=app:app /out/api /app/api

ENV PORT=8090 \
    ENV=production \
    TZ=UTC

USER app:app

EXPOSE 8090

# Uses the app's own /healthz. Coolify gates zero-downtime rollouts on this:
# the new container only takes traffic once it reports healthy.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -qO- "http://127.0.0.1:${PORT}/healthz" || exit 1

# Exec form: the Go process is PID 1 and receives SIGTERM directly,
# which main.go turns into a graceful shutdown.
ENTRYPOINT ["/app/api"]
