#!/bin/bash
set -e

function apt_get_install()
{
	apt-get install -q -y --force-yes --no-install-recommends "$@"
}

export DEBIAN_FRONTEND=noninteractive

set -x

apt-get update
apt_get_install ruby1.9.3 ruby1.9.1-dev nodejs runit wget
gem install bundler rake --no-rdoc --no-ri

ln -sf /vagrant/app /appa
/vagrant/app/setup vagrant
