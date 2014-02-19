#!/bin/bash
set -e

function apt_get_install()
{
	apt-get install -q -y --force-yes --no-install-recommends "$@"
}

export DEBIAN_FRONTEND=noninteractive

set -x

if ! grep -q setterm /etc/rc.local; then
	sed -i 's/^exit 0$//' /etc/rc.local
	cat >>/etc/rc.local <<-EOF
	# Increase kernel logging level. This ensures that all kernel
	# messages are forwarded to the log host through netconsole.
	dmesg -n 7

	# Disable Linux console blanking so that we can see kernel panics
	setterm -blank 0 </dev/console >/dev/console
	setterm -powerdown 0 </dev/console >/dev/console
	setterm -powersave off </dev/console >/dev/console
	EOF
fi

dmesg -n 7
setterm -blank 0 </dev/console >/dev/console
setterm -powerdown 0 </dev/console >/dev/console
setterm -powersave off </dev/console >/dev/console

if ! [[ -e /etc/apt/sources.list.d/brightbox.list ]]; then
	apt-key adv --keyserver keyserver.ubuntu.com --recv-keys C3173AA6
	echo deb http://ppa.launchpad.net/brightbox/ruby-ng/ubuntu precise main > /etc/apt/sources.list.d/brightbox.list
fi
if ! [[ -e /etc/apt/sources.list.d/nodejs.list ]]; then
	apt-key adv --keyserver keyserver.ubuntu.com --recv-keys C7917B12
	echo deb http://ppa.launchpad.net/chris-lea/node.js/ubuntu precise main > /etc/apt/sources.list.d/nodejs.list
fi
if ! [[ -e /etc/apt/sources.list.d/redis.list ]]; then
	apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 5862E31D
	echo deb http://ppa.launchpad.net/rwky/redis/ubuntu precise main > /etc/apt/sources.list.d/redis.list
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

cp app/resources/setuser /sbin/

if ! [[ -e /appa ]]; then
	ln -s /vagrant/app /appa
fi
/vagrant/app/setup vagrant
