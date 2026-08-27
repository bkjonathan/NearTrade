IMAGE ?= neartrade-api
TAG   ?= latest

.PHONY: build run migrate-up migrate-down docker-build docker-run docker-sh clean

build:
	@go build -o bin/api ./cmd/api

run: build
	@./bin/api

migrate-up:
	@go run ./cmd/migrate up

migrate-down:
	@go run ./cmd/migrate down

docker-build:
	@DOCKER_BUILDKIT=1 docker build -t $(IMAGE):$(TAG) .

docker-run: docker-build
	@docker run --rm -p 8090:8090 -e ENV=production $(IMAGE):$(TAG)

docker-sh:
	@docker run --rm -it --entrypoint /bin/sh $(IMAGE):$(TAG)

clean:
	@rm -rf bin
