FROM debian:stable-slim

RUN curl https://i.opentakserver.io/debian_installer -L | bash - | tee ~/ots_debian_installer.log
