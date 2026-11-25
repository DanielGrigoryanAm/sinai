#!/usr/bin/env bash
# One-time preparation of a fresh Ubuntu 24.04 server, run as root:
#   ssh root@SERVER 'bash -s' < deploy/setup-server.sh
#
# Installs Docker from Docker's own apt repository, opens only SSH, HTTP
# and HTTPS in the firewall, turns on automatic security updates and
# makes /opt/sinai for the app.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl ufw unattended-upgrades rsync

# Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker

# Firewall: SSH, HTTP (certificates) and HTTPS only. Postgres and Redis
# stay on Docker's private network.
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp
ufw --force enable

# Security updates install themselves.
dpkg-reconfigure -f noninteractive unattended-upgrades

mkdir -p /opt/sinai
echo "Server ready. Now run deploy/deploy.sh from your Mac."
