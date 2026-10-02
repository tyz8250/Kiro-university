FROM golang:1.23-alpine AS build

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY *.go ./
RUN CGO_ENABLED=0 go build -trimpath -o /out/network-fault-observation .

FROM alpine:3.19 AS run

RUN addgroup -S app && adduser -S -G app app
WORKDIR /app

COPY --from=build --chown=app:app /out/network-fault-observation ./network-fault-observation

USER app
EXPOSE 8080

ENTRYPOINT ["./network-fault-observation"]
