#Setting ARCH type argument
#ARG ARCH
# Dockerfile YouTube-DL install (run from /port/docker/file)
FROM debian:bullseye-slim
#FROM debian:buster-slim

#Set Language and Location
ENV LANG=en_US.UTF-8  
ENV LANGUAGE=en_US:en  
ENV LC_ALL=en_US.UTF-8  

#Install Tools
RUN apt-get update -y && apt-get upgrade -y && apt-get install -y nano

#Install YouTube-DL dependencies
#RUN apt-get install -y virtualbox virtualbox-ext-pack
RUN apt-get install -y virtualbox virtualbox-ext-pack


#Health Check
HEALTHCHECK CMD curl --fail http://youtube.com/ || exit 1

#Starting container
#ENTRYPOINT ["sh", "/root/findYouTube.sh"]
