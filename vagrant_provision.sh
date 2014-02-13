#!/bin/bash
set -e

function apt_get_install()
{
	apt-get install -q -y --force-yes --no-install-recommends "$@"
}

export DEBIAN_FRONTEND=noninteractive

set -x

if ! [[ -e /usr/bin/wget ]]; then
	apt-get update -qq
	apt_get_install wget
fi
wget -q -O - https://get.docker.io/gpg | apt-key add -
echo deb http://get.docker.io/ubuntu docker main > /etc/apt/sources.list.d/docker.list
apt-get update -qq
apt_get_install lxc-docker ruby1.9.3
usermod -a -G docker vagrant
gem install bundler rake --no-rdoc --no-ri

/vagrant/app/setup vagrant
