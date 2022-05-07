#!/bin/bash

# install python3-pip
# pip install docker-squash
# https://github.com/goldmann/docker-squash

# to modify
IMG=ghcr.io/manprint/ubuntu-dind-jammy:latest-committed
CNT=ubuntu-dind

# clean (for debian images)
docker exec -it $CNT apt clean
docker exec -it $CNT apt autoclean
docker exec -it $CNT apt autoremove -y
docker exec -it $CNT rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# commit
docker commit $CNT $IMG

# stop and remove
docker stop $CNT
docker rm $CNT

# squash
docker-squash -f $(($(docker history $IMG | wc -l | xargs)-1)) -t $IMG $IMG

# remove dangling
echo "y" | docker image prune

# remove cache builder
echo "y" | docker builder prune

# modify makefile and start container with committed image