.PHONY: help \
		clean build build_no_cache pull publish \
		create_persistence_folder create_persistence_volume destroy_all \
		volume_prune down stop start up up_dev up_sysbox up_sysbox_dev \
		connect ssh chrome_webssh firefox_webssh chrome_cloudcmd firefox_cloudcmd \
		context_create context_enable context_disable context_remove

TITLE_MAKEFILE = Dind Ubuntu Jammy Supervisord with Ssh, Wssh, Terraform, Rclone and Cron

.ONESHELL:
SHELL=/bin/bash
.SHELLFLAGS += -eo pipefail

export CURRENT_DIR := $(shell pwd)
export RED := $(shell tput setaf 1)
export RESET := $(shell tput sgr0)
export DATE_NOW := $(shell date)
export GITHUB_CREDS := $(shell pass Github/Manprint/Token)

.DEFAULT := help

help:
	@printf "\n$(RED)$(TITLE_MAKEFILE)$(RESET)\n"
	@awk 'BEGIN {FS = ":.*##"; printf "\n\033[1mUsage:\n  make \033[36m<target>\033[0m\n"} \
	/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2 } /^##@/ \
	{ printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	@echo

export IMAGE := ghcr.io/manprint/ubuntu-dind-jammy:latest
export CNT_NAME := ubuntu-dind
export CNT_HOSTNAME := dind-srv01

##@ Build Image

clean: ## Docker image prune and builder prune
	-@echo "y" | docker image prune
	-@echo "y" | docker builder prune
	-@echo "y" | docker volume prune

build: clean ## Build docker image
	@DOCKER_BUILDKIT=1 docker build --force-rm --rm --tag ${IMAGE} .

build_no_cache: clean ## Build docker image no cache
	@DOCKER_BUILDKIT=1 docker build --no-cache --force-rm --rm --tag ${IMAGE} .

pull: ## Pull image
	@docker pull $(IMAGE)

publish: build ## Push image
	@echo "$(RED)Create in repo folder the "github.token" file for publish image...$(RESET)"
	echo ${GITHUB_CREDS} | docker login ghcr.io -u manprint --password-stdin
	@docker push $(IMAGE)
	$(MAKE) clean

##@ Persistence

create_persistence_folder: ## Create persistent folders
	-@mkdir -vp ${CURRENT_DIR}/data/{docker,ubuntu}

create_persistence_volume: ## Create volumes
	-@docker volume create \
		--driver local \
		--opt type=none \
		--opt device=${CURRENT_DIR}/data/docker \
		--opt o=bind \
		vol_${CNT_NAME}_docker
	-@docker volume create \
		--driver local \
		--opt type=none \
		--opt device=${CURRENT_DIR}/data/ubuntu \
		--opt o=bind \
		vol_${CNT_NAME}_ubuntu

destroy_all: down ## Destroy container and persistence (remove all!)
	@sudo rm -Ir ${CURRENT_DIR}/data

##@ Container

volume_prune: ## Remove dangling volume
	-@echo "y" | docker volume prune

down: ## Stop and remove container (not preserving ephimeral data)
	-@docker stop ${CNT_NAME}
	-@docker rm ${CNT_NAME}
	-@docker volume rm vol_${CNT_NAME}_docker vol_${CNT_NAME}_ubuntu
	$(MAKE) volume_prune

stop: ## Stop dind container (preserve ephimeral data)
	@docker stop $(CNT_NAME)

start: ## Start container (if exist)
	@docker start $(CNT_NAME)

up: down create_persistence_folder create_persistence_volume ## Stop, remove and start ubuntu-dind container privileged
	@docker run -d \
		--privileged \
		--name=${CNT_NAME} \
		--hostname=${CNT_HOSTNAME} \
		--publish=2375:2375/tcp \
		--publish=2260:22/tcp \
		--publish=8888:8888/tcp \
		--publish=8889:8889/tcp \
		--volume=vol_${CNT_NAME}_docker:/var/lib/docker \
		--volume=vol_${CNT_NAME}_ubuntu:/home/ubuntu \
		${IMAGE}

up_dev: down ## (DEV) Stop, remove and start ubuntu-dind container privileged
	@docker run -d \
		--privileged \
		--name=${CNT_NAME} \
		--hostname=${CNT_HOSTNAME} \
		--publish=2375:2375/tcp \
		--publish=2260:22/tcp \
		--publish=8889:8889/tcp \
		${IMAGE}

up_sysbox: down create_persistence_folder create_persistence_volume ## Stop, remove and start ubuntu-dind container not privileged (sysbox)
	@docker run -d \
		--runtime=sysbox-runc \
		--name=${CNT_NAME} \
		--hostname=${CNT_HOSTNAME} \
		--publish=2375:2375/tcp \
		--publish=2260:22/tcp \
		--publish=8889:8889/tcp \
		--volume=vol_${CNT_NAME}_docker:/var/lib/docker \
		--volume=vol_${CNT_NAME}_ubuntu:/home/ubuntu \
		${IMAGE}

up_sysbox_dev: down ## (DEV) Stop, remove and start ubuntu-dind container not privileged (sysbox)
	@docker run -d \
		--runtime=sysbox-runc \
		--name=${CNT_NAME} \
		--hostname=${CNT_HOSTNAME} \
		--publish=2375:2375/tcp \
		--publish=2260:22/tcp \
		--publish=8889:8889/tcp \
		${IMAGE}

##@ Container Connection

connect: ## Connect to container (default user: ubuntu (1000:1000))
	@echo "Wait for docker container $(CNT_NAME) ..."
	@sleep 3 # wait for container
	@docker exec -it $(CNT_NAME) bash -l

ssh: ## Connect via ssh (password: ubuntu)
	@echo "Wait for ssh service in $(CNT_NAME) ..."
	@sleep 5 # wait for ssh
	@sshpass -p ubuntu ssh -o 'StrictHostKeyChecking no' -p 2260 ubuntu@localhost

chrome_webssh: ## Open chrome webssh
	@google-chrome "http://localhost:8888/?hostname=localhost&username=ubuntu&password=dWJ1bnR1Cg==&title=$(CNT_NAME)" > /dev/null 2>&1 &

firefox_webssh: ## Open firefox webssh
	@firefox "http://localhost:8888/?hostname=localhost&username=ubuntu&password=dWJ1bnR1Cg==&title=$(CNT_NAME)" > /dev/null 2>&1 &

chrome_cloudcmd: ## Open cloudcmd chrome
	@google-chrome "http://localhost:8889" > /dev/null 2>&1 &

firefox_cloudcmd: ## OPen cloudcmd firefox
	@firefox "http://localhost:8889" > /dev/null 2>&1 &

##@ Docker context

context_create: ## Create docker context for dind container
	@docker context create $(CNT_NAME) \
		--description "Docker Dind Ubuntu" \
		--docker "host=tcp://localhost:2375"

context_enable: ## Enable context for dind container
	@docker context use $(CNT_NAME)

context_disable: ## Disable context for dind (switch to default)
	@docker context use default

context_remove: context_disable ## Disable dind context, switch to default and remove
	@docker context rm $(CNT_NAME)