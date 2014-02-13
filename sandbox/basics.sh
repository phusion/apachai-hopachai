#!/bin/bash
set -ex

export DEBIAN_FRONTEND=noninteractive
echo force-unsafe-io > /etc/dpkg/dpkg.cfg.d/02apt-speedup

# Disable SSH.
rm -rf /etc/service/sshd /etc/my_init.d/00_regen_ssh_host_keys.sh

# Create user and give it sudo access.
addgroup --gid 1000 appa
adduser --uid 1000 --gid 1000 --disabled-password --gecos "Apachai Hopachai" appa
usermod -a -G sudo appa
echo appa:appa | chpasswd

# Install developer tools.
apt-get update
apt-get install -y build-essential nano curl git python sudo lsb-release
apt-get install -y apache2-mpm-worker apache2-threaded-dev libcurl4-openssl-dev
apt-get clean

# Enable sudo.
sed -i -E 's/^%sudo.*/%sudo  ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers
