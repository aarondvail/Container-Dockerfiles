FROM debian:stable-slim

LABEL maintainer="aarondvail"   description="meshtastic-bridge"

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone 

git clone https://github.com/jp-bennett/meshtastic-bridge

