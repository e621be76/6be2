# build for both amd64 & arm64
FROM --platform=$BUILDPLATFORM golang:1.27.3-trixie AS build
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src
COPY go.mod ./
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags="-s -w" -o /quote-api .

# static binary, no shell, uid 65532
FROM gcr.io/distroless/static-debian13:nonroot
COPY --from=build /quote-api /quote-api
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/quote-api"]
