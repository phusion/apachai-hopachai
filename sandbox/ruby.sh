#!/bin/bash
set -ex

export DEBIAN_FRONTEND=noninteractive

curl -L https://get.rvm.io | sudo -u appa sudo bash -s stable
usermod -a -G rvm appa
sudo -u appa -H bash -lc 'rvm install 1.8.7'
sudo -u appa -H bash -lc 'rvm install 1.9.3'
sudo -u appa -H bash -lc 'rvm install 2.0.0'
sudo -u appa -H bash -lc 'rvm install 2.1.0'
bash -lc 'rvm --default 2.1.0'
sudo -u appa -H bash -lc 'rvm --default 2.1.0'
/usr/local/rvm/bin/rvm cleanup all

mkdir /gem_bundle
cp /build/Gemfile* /gem_bundle
cd /gem_bundle
/usr/local/rvm/bin/rvm-exec 2.1.0 bundle install --path=.
