FROM debian:latest

RUN apt-get -y update && \
    apt-get -y upgrade


WORKDIR /app

# setup perl dependencies
RUN apt-get install -y carton make gcc
# libemail-sender-perl provies Email::Sender::Transport::SMTP which will can used as a transport for email alerts
RUN apt-get install -y libemail-sender-perl
COPY cpanfile ./
RUN carton install

COPY lib ./lib
COPY bin ./bin/


EXPOSE 8080

ENV DISPATCHOULI_STDERR=1
CMD carton exec perl -I lib/ bin/promalertproxy -c config.toml