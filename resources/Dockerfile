FROM base
MAINTAINER Hongli Lai <hongli@phusion.nl>

# https://github.com/dotcloud/docker/issues/1024
RUN dpkg-divert --local --rename --add /sbin/initctl
RUN ln -s /bin/true /sbin/initctl

RUN echo force-unsafe-io > /etc/dpkg/dpkg.cfg.d/02apt-speedup

RUN apt-get update
RUN apt-get install -y build-essential nano curl git python
RUN apt-get install -y apache2-mpm-worker apache2-threaded-dev libcurl4-openssl-dev
RUN apt-get clean

RUN adduser --disabled-password --gecos "Apachai Hopachai" appa
RUN usermod -a -G sudo appa
RUN echo appa:appa | chpasswd
RUN sed -i -E 's/^%sudo\tALL=\(ALL:ALL\) ALL$/%sudo  ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers
RUN echo "127.0.1.1 apachai-hopachai" >> /etc/hosts
RUN curl -L https://get.rvm.io | sudo -u appa sudo bash -s stable
RUN usermod -a -G rvm appa
RUN sudo -u appa -H bash -lc 'rvm install 1.8.7'
RUN sudo -u appa -H bash -lc 'rvm install 1.9.3'
RUN sudo -u appa -H bash -lc 'rvm install 2.0.0'
RUN bash -lc 'rvm --default 1.9.3'
RUN sudo -u appa -H bash -lc 'rvm --default 1.9.3'
RUN /usr/local/rvm/bin/rvm cleanup all
ADD bootstrap.rb /bootstrap.rb
RUN chmod +x /bootstrap.rb
