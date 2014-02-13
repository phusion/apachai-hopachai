FROM phusion/baseimage:0.9.5
MAINTAINER Hongli Lai <hongli@phusion.nl>

ENV HOME /root

ADD . /build
RUN /build/basics.sh
RUN /build/ruby.sh
RUN apt-get clean && rm -rf /build /tmp/* /var/tmp/*

CMD ["/sbin/my_init"]
