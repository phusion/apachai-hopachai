FROM phusion/passenger-ruby21:0.9.6

ENV HOME /root

ADD . /app
RUN /app/setup && apt-get clean

CMD ["/sbin/my_init"]
