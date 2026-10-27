FROM golang:1.24-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY *.go ./
COPY admin ./admin
COPY public ./public
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /ivy-gateway . && mkdir /data

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /ivy-gateway /ivy-gateway
COPY --from=build --chown=65532:65532 /data /data
ENV IVY_DATA_DIR=/data
ENTRYPOINT ["/ivy-gateway"]
