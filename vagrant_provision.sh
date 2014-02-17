#!/bin/bash
set -e

function apt_get_install()
{
	apt-get install -q -y --force-yes --no-install-recommends "$@"
}

export DEBIAN_FRONTEND=noninteractive

set -x

# Allow seeing kernel errors.
dmesg -n 7
setterm -blank 0

if ! [[ -e /etc/apt/sources.list.d/brightbox.list ]]; then
	apt-key adv --keyserver keyserver.ubuntu.com --recv-keys C3173AA6
	echo deb http://ppa.launchpad.net/brightbox/ruby-ng/ubuntu precise main > /etc/apt/sources.list.d/brightbox.list
fi

apt-get update
apt_get_install apt-transport-https ca-certificates
if ! [[ -e /etc/apt/sources.list.d/passenger.list ]]; then
	apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 561F9B9CAC40B2F7
	echo deb https://oss-binaries.phusionpassenger.com/apt/passenger precise main > /etc/apt/sources.list.d/passenger.list
	apt-get update
fi
apt_get_install ruby2.1 ruby2.1-dev ruby-switch nodejs runit wget nginx-extras passenger
ruby-switch --set ruby2.1
gem install bundler rake --no-rdoc --no-ri

ln -sf /vagrant/app /appa
/vagrant/app/setup vagrant
