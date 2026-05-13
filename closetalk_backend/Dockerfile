# syntax=docker/dockerfile:1
FROM golang:1.26-alpine AS builder

RUN apk add --no-cache git ca-certificates gcc musl-dev

WORKDIR /build

COPY go.mod go.sum ./
RUN go mod download

COPY . .

ARG SERVICE=auth-service
ARG PORT=8081
RUN GOOS=linux GOARCH=amd64 \
    go build -ldflags="-s -w" -o /app ./cmd/$SERVICE

FROM alpine:3.21

ARG PORT=8081

RUN apk add --no-cache ca-certificates tzdata

RUN adduser -D -g '' closetalk
USER closetalk

COPY --from=builder /app /app/service

EXPOSE $PORT

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:$PORT/health || exit 1

ENTRYPOINT ["/app/service"]
