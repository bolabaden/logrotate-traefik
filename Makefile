# Makefile for logrotate-traefik
SHELL := /bin/bash
IMAGE_NAME := logrotate-traefik
VERSION := 1.0.0
REGISTRY ?= your-registry
TAG := $(REGISTRY)/$(IMAGE_NAME):$(VERSION)
LATEST_TAG := $(REGISTRY)/$(IMAGE_NAME):latest

# Default target
.PHONY: help
help: ## Show this help message
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: build
build: ## Build the Docker image
	docker build -t $(IMAGE_NAME):$(VERSION) -t $(IMAGE_NAME):latest .
	@echo "Built $(IMAGE_NAME):$(VERSION) and $(IMAGE_NAME):latest"

.PHONY: build-no-cache
build-no-cache: ## Build the Docker image without cache
	docker build --no-cache -t $(IMAGE_NAME):$(VERSION) -t $(IMAGE_NAME):latest .

.PHONY: test
test: build ## Run basic tests on the built image
	@echo "Testing container startup..."
	docker run --rm -d \
		--name test-$(IMAGE_NAME) \
		-v /tmp/test-traefik-logs:/var/log/traefik \
		-e LOG_LEVEL=debug \
		$(IMAGE_NAME):latest
	@sleep 5
	@echo "Checking if container is running..."
	docker ps | grep test-$(IMAGE_NAME)
	@echo "Checking logs..."
	docker logs test-$(IMAGE_NAME)
	@echo "Stopping test container..."
	docker stop test-$(IMAGE_NAME)
	@echo "Test completed successfully"

.PHONY: run
run: build ## Run the container locally for testing
	@mkdir -p ./test-logs
	@echo '{"time":"2024-01-01T12:00:00Z","level":"info","msg":"test","ClientAddr":"192.168.1.100:54321","DownstreamStatus":200,"RequestHost":"example.com","RequestMethod":"GET","RequestPath":"/api/test","Duration":1500000,"ServiceName":"test-service"}' > ./test-logs/traefik.log
	docker run --rm -it \
		--name $(IMAGE_NAME)-dev \
		-v $(PWD)/test-logs:/var/log/traefik \
		-e LOG_LEVEL=debug \
		-e LOGROTATE_LOOP_SLEEP=60 \
		$(IMAGE_NAME):latest

.PHONY: shell
shell: build ## Run an interactive shell in the container
	docker run --rm -it \
		--name $(IMAGE_NAME)-shell \
		-v $(PWD)/test-logs:/var/log/traefik \
		$(IMAGE_NAME):latest bash

.PHONY: tag
tag: ## Tag the image for registry
	docker tag $(IMAGE_NAME):$(VERSION) $(TAG)
	docker tag $(IMAGE_NAME):latest $(LATEST_TAG)
	@echo "Tagged as $(TAG) and $(LATEST_TAG)"

.PHONY: push
push: tag ## Push the image to registry
	docker push $(TAG)
	docker push $(LATEST_TAG)
	@echo "Pushed $(TAG) and $(LATEST_TAG)"

.PHONY: clean
clean: ## Clean up local images and test files
	-docker rmi $(IMAGE_NAME):$(VERSION) $(IMAGE_NAME):latest $(TAG) $(LATEST_TAG)
	-rm -rf ./test-logs
	@echo "Cleaned up images and test files"

.PHONY: compose-up
compose-up: ## Start the service using docker-compose
	docker-compose -f examples/docker-compose.yml up -d

.PHONY: compose-down
compose-down: ## Stop the service using docker-compose
	docker-compose -f examples/docker-compose.yml down

.PHONY: compose-logs
compose-logs: ## Show logs from docker-compose
	docker-compose -f examples/docker-compose.yml logs -f logrotate-traefik

.PHONY: lint
lint: ## Lint shell scripts
	@command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck not installed"; exit 1; }
	shellcheck scripts/*.sh

.PHONY: format
format: ## Format shell scripts
	@command -v shfmt >/dev/null 2>&1 || { echo "shfmt not installed"; exit 1; }
	shfmt -w -i 4 scripts/*.sh

.PHONY: security-scan
security-scan: build ## Run security scan on the image
	@command -v trivy >/dev/null 2>&1 || { echo "trivy not installed"; exit 1; }
	trivy image $(IMAGE_NAME):latest

.PHONY: size
size: build ## Show image size information
	@echo "Image sizes:"
	docker images | grep $(IMAGE_NAME)
	@echo ""
	@echo "Layer information:"
	docker history $(IMAGE_NAME):latest

.PHONY: env-example
env-example: ## Create .env file from example
	cp config/environment.env.example .env
	@echo "Created .env file from example. Please customize it for your environment."

# Development targets
.PHONY: dev-setup
dev-setup: env-example ## Set up development environment
	@echo "Setting up development environment..."
	@mkdir -p test-logs
	@echo "Development environment ready!"
	@echo "Run 'make run' to test the container locally"

.PHONY: release
release: lint build test tag push ## Complete release pipeline
	@echo "Release $(VERSION) completed successfully!"
