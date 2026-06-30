BINARY := kudorad
OUT_DIR := out
BUILD_DIR := build
DOCKER_IMAGE := kudora/kudorad:localnet
PING_DASHBOARD_IMAGE := kudora/ping-dashboard:localnet

.PHONY: build install test tidy lint verify-no-forks verify-clean-reset verify-no-secrets verify-integrity-generic dependency-audit audit-evm-precompile-surface assert-evm-precompile-policy vulncheck phase0-validate phase0.1-validate phase-1-validate phase-2-validate phase-2.1-validate phase-3-validate phase-3.2-validate phase-4-validate phase-5-validate phase-5.1-validate phase-12-validate phase-12.1-lite-validate phase-13-validate phase-13.1-validate phase-14-validate phase-15-validate phase-16-validate phase-16.1-validate phase-17-validate docker-build docker-version docker-smoke-test evm-smoke-test evm-transaction-smoke-test evm-contract-smoke-test wasm-smoke-test integrity-smoke-test localnet-init localnet-up localnet-down localnet-reset localnet-logs localnet-smoke-test blockscout-up blockscout-down blockscout-reset blockscout-smoke-test ping-dashboard-up ping-dashboard-down ping-dashboard-reset ping-dashboard-smoke-test explorers-up explorers-down explorers-reset explorers-logs explorers-smoke-test monitoring-up monitoring-down monitoring-reset monitoring-logs monitoring-smoke-test mainnet-genesis-build mainnet-genesis-validate mainnet-genesis-inspect-supply mainnet-genesis-inspect-policy release-build-binaries release-package release-verify release-docker-build release-docker-verify cosmovisor-image-build cosmovisor-layout-verify cosmovisor-smoke-test zip

build:
	@mkdir -p $(BUILD_DIR)
	@go build -o $(BUILD_DIR)/$(BINARY) ./cmd/$(BINARY)

install:
	@go install ./cmd/$(BINARY)

test:
	@go test ./...

tidy:
	@go mod tidy

lint:
	@go vet ./...

verify-no-forks:
	@./scripts/verify-no-forks.sh

verify-clean-reset:
	@./scripts/verify-clean-reset.sh

verify-no-secrets:
	@./scripts/verify-no-secrets.sh

verify-integrity-generic:
	@./scripts/verify-integrity-generic.sh

dependency-audit:
	@./scripts/dependency-audit.sh

audit-evm-precompile-surface:
	@./scripts/audit-evm-precompile-surface.sh

assert-evm-precompile-policy:
	@./scripts/assert-evm-precompile-policy.sh

vulncheck:
	@./scripts/vulncheck.sh

phase0-validate:
	@./scripts/phase-0-validate.sh

phase0.1-validate:
	@./scripts/phase-0.1-validate.sh

phase-1-validate:
	@./scripts/phase-1-validate.sh

phase-2-validate:
	@./scripts/phase-2-validate.sh

phase-2.1-validate:
	@./scripts/phase-2.1-validate.sh

phase-3-validate:
	@./scripts/phase-3-validate.sh

phase-3.2-validate:
	@./scripts/phase-3.2-validate.sh

phase-4-validate:
	@./scripts/phase-4-validate.sh

phase-5-validate:
	@./scripts/phase-5-validate.sh

phase-5.1-validate:
	@./scripts/phase-5.1-validate.sh

phase-12-validate:
	@./scripts/phase-12-validate.sh

phase-12.1-lite-validate:
	@./scripts/phase-12.1-lite-validate.sh

phase-13-validate:
	@./scripts/phase-13-validate.sh

phase-13.1-validate:
	@./scripts/phase-13.1-validate.sh

phase-14-validate:
	@./scripts/phase-14-validate.sh

phase-15-validate:
	@./scripts/phase-15-validate.sh

phase-16-validate:
	@./scripts/phase-16-validate.sh

phase-16.1-validate:
	@./scripts/phase-16.1-validate.sh

phase-17-validate:
	@./scripts/phase-17-validate.sh

docker-build:
	@DOCKER_BUILDKIT=1 docker buildx build --load --tag $(DOCKER_IMAGE) --file Dockerfile .

docker-version:
	@docker run --rm $(DOCKER_IMAGE)

docker-smoke-test:
	@docker run --rm $(DOCKER_IMAGE) version --long >/dev/null
	@docker run --rm $(DOCKER_IMAGE) --help >/dev/null
	@user="$$(docker image inspect $(DOCKER_IMAGE) --format '{{.Config.User}}')"; \
		if [ -z "$$user" ] || [ "$$user" = "0" ] || [ "$$user" = "root" ]; then \
			echo "docker-smoke-test: image must run as a non-root user" >&2; \
			exit 1; \
		fi
	@ports="$$(docker image inspect $(DOCKER_IMAGE) --format '{{json .Config.ExposedPorts}}')"; \
		printf '%s\n' "$$ports" | rg '"26656/tcp"' >/dev/null; \
		printf '%s\n' "$$ports" | rg '"26657/tcp"' >/dev/null; \
		printf '%s\n' "$$ports" | rg '"1317/tcp"' >/dev/null; \
		printf '%s\n' "$$ports" | rg '"9090/tcp"' >/dev/null; \
		printf '%s\n' "$$ports" | rg '"8545/tcp"' >/dev/null; \
		printf '%s\n' "$$ports" | rg '"8546/tcp"' >/dev/null
	@cid="$$(docker create $(DOCKER_IMAGE))"; \
		trap 'docker rm -f "$$cid" >/dev/null 2>&1 || true' EXIT; \
		docker export "$$cid" | tar -tf - | { \
			if rg -n '(^|/)\.kudora/|(^|/)\.env(\..*)?$$|(^|/)priv_validator_key\.json$$|(^|/)node_key\.json$$|(^|/)key_seed\.json$$|\.pem$$|\.key$$|\.seed$$|\.mnemonic$$' >/dev/null; then \
				echo "docker-smoke-test: forbidden local state or secret-bearing files found in image filesystem" >&2; \
				exit 1; \
			fi; \
		}

evm-smoke-test:
	@./scripts/evm-smoke-test.sh

evm-transaction-smoke-test:
	@./scripts/evm-transaction-smoke-test.sh

evm-contract-smoke-test:
	@./scripts/evm-contract-smoke-test.sh

wasm-smoke-test:
	@./scripts/wasm-smoke-test.sh

integrity-smoke-test:
	@./scripts/integrity-smoke-test.sh

localnet-init:
	@./deploy/localnet/scripts/init-localnet.sh

localnet-up:
	@./deploy/localnet/scripts/start-localnet.sh

localnet-down:
	@./deploy/localnet/scripts/reset-localnet.sh --keep-state

localnet-reset:
	@./deploy/localnet/scripts/reset-localnet.sh

localnet-logs:
	@./deploy/localnet/scripts/start-localnet.sh --logs

localnet-smoke-test:
	@./deploy/localnet/scripts/smoke-localnet.sh

blockscout-up:
	@./deploy/explorers/blockscout/scripts/start-blockscout.sh

blockscout-down:
	@./deploy/explorers/blockscout/scripts/stop-blockscout.sh

blockscout-reset:
	@./deploy/explorers/blockscout/scripts/reset-blockscout.sh

blockscout-smoke-test:
	@./deploy/explorers/blockscout/scripts/smoke-blockscout.sh

ping-dashboard-up:
	@./deploy/explorers/ping-dashboard/scripts/start-ping-dashboard.sh

ping-dashboard-down:
	@./deploy/explorers/ping-dashboard/scripts/stop-ping-dashboard.sh

ping-dashboard-reset:
	@./deploy/explorers/ping-dashboard/scripts/reset-ping-dashboard.sh

ping-dashboard-smoke-test:
	@./deploy/explorers/ping-dashboard/scripts/smoke-ping-dashboard.sh

explorers-up:
	@./deploy/explorers/blockscout/scripts/start-blockscout.sh
	@./deploy/explorers/ping-dashboard/scripts/start-ping-dashboard.sh

explorers-down:
	@./deploy/explorers/ping-dashboard/scripts/stop-ping-dashboard.sh
	@./deploy/explorers/blockscout/scripts/stop-blockscout.sh

explorers-reset:
	@./deploy/explorers/ping-dashboard/scripts/reset-ping-dashboard.sh
	@./deploy/explorers/blockscout/scripts/reset-blockscout.sh

explorers-logs:
	@bash -lc 'source deploy/explorers/common.sh; require_compose; COMPOSE_PROJECT_NAME="kudora-explorers" LOCALNET_DOCKER_NETWORK="$$LOCALNET_DOCKER_NETWORK" BLOCKSCOUT_BACKEND_IMAGE="$$BLOCKSCOUT_BACKEND_IMAGE" BLOCKSCOUT_FRONTEND_IMAGE="$$BLOCKSCOUT_FRONTEND_IMAGE" PING_DASHBOARD_IMAGE="$$PING_DASHBOARD_IMAGE" PING_DASHBOARD_UPSTREAM_COMMIT="$$PING_DASHBOARD_UPSTREAM_COMMIT" "$${COMPOSE_CMD[@]}" -f "$$BLOCKSCOUT_COMPOSE_FILE" -f "$$PING_DASHBOARD_COMPOSE_FILE" logs -f'

explorers-smoke-test:
	@./deploy/explorers/blockscout/scripts/smoke-blockscout.sh
	@./deploy/explorers/ping-dashboard/scripts/smoke-ping-dashboard.sh

monitoring-up:
	@./deploy/monitoring/scripts/start-monitoring.sh

monitoring-down:
	@./deploy/monitoring/scripts/stop-monitoring.sh

monitoring-reset:
	@./deploy/monitoring/scripts/reset-monitoring.sh

monitoring-logs:
	@bash -lc 'source deploy/monitoring/common.sh; monitoring_compose logs -f'

monitoring-smoke-test:
	@./deploy/monitoring/scripts/smoke-monitoring.sh

mainnet-genesis-build:
	@./scripts/mainnet/build-genesis.sh

mainnet-genesis-validate:
	@./scripts/mainnet/validate-genesis.sh

mainnet-genesis-inspect-supply:
	@./scripts/mainnet/inspect-genesis-supply.sh

mainnet-genesis-inspect-policy:
	@./scripts/mainnet/inspect-genesis-policy.sh

release-build-binaries:
	@./scripts/release/build-binaries.sh

release-package:
	@./scripts/release/package-release.sh

release-verify:
	@./scripts/release/verify-release.sh

release-docker-build:
	@./scripts/release/build-docker-image.sh

release-docker-verify:
	@./scripts/release/verify-docker-image.sh

cosmovisor-image-build:
	@./scripts/release/build-cosmovisor-image.sh

cosmovisor-layout-verify:
	@./scripts/release/verify-cosmovisor-layout.sh

cosmovisor-smoke-test:
	@./deploy/cosmovisor/scripts/smoke-cosmovisor.sh

zip:
	@./scripts/make-zip.sh
