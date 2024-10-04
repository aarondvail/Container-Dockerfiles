# Dockerfile YouTube-DL install (run from /port/docker/file)
FROM debian
#FROM ubuntu
#FROM ubuntu:21.10
#FROM ubuntu:16.04
#FROM phusion/baseimage:0.11

ARG VERSION_NUMBER
ENV DEBIAN_FRONTEND=teletype
ENV LANG en_US.UTF-8  
ENV LANGUAGE en_US:en  
ENV LC_ALL en_US.UTF-8  
ENV TZ='US/Eastern'
ENV ZIPFILE=bedrock-server-$VERSION_NUMBER.zip
ENV BEDROCK_DOWNLOAD_ZIP=https://www.minecraft.net/bedrockdedicatedserver/bin-linux/$ZIPFILE

## Use baseimage-docker's init system.
##CMD ["/sbin/my_init"]

# ...put your own build instructions here...
RUN rm -fr /var/lib/apt/lists && rm -fr /var/cache/apt
#RUN cp  /etc/apt/sources.list /etc/apt/sources.list.bak && sudo sed -i -re 's/([a-z]{2}\.)?archive.ubuntu.com|security.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list
RUN apt-get update && apt-get upgrade -y 
RUN apt-get -y install curl nano wget unzip libcurl4 libssl-dev 
#RUN echo $TZ > /etc/timezone 
#RUN echo "deb http://security.ubuntu.com/ubuntu impish-security main" | sudo tee /etc/apt/sources.list.d/impish-security.list && sudo apt-get update && sudo apt-get install libssl1.1 
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y tzdata && rm /etc/localtime && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime 
RUN dpkg-reconfigure -f noninteractive tzdata && apt-get clean && useradd -ms /bin/bash bedrock 
RUN wget --no-check-certificate --auth-no-challenge --force-directories $BEDROCK_DOWNLOAD_ZIP && unzip $ZIPFILE -d /home/bedrock/bedrock_server && chown -R bedrock:bedrock /home/bedrock/bedrock_server && su - bedrock -c "mkdir -p bedrock_server/data/worlds" && chown -R bedrock:bedrock /home/bedrock/bedrock_server/data/worlds && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

EXPOSE 19132/udp

# Entry
COPY minecraftbedrock/startup2.sh /home/bedrock
RUN ["chmod", "+x", "/home/bedrock/startup2.sh"]

ENTRYPOINT /home/bedrock/startup2.sh && /bin/bash
