# Dockerfile YouTube-DL install (run from /port/docker/file)
#FROM ubuntu
FROM phusion/baseimage:0.11

#ENV LANG en_US.UTF-8  
#ENV LANGUAGE en_US:en  
#ENV LC_ALL en_US.UTF-8  
ENV TZ='US/Eastern'
## ENV LD_LIBRARY_PATH=. ./bedrock_server
## install bash and other stuff
##RUN apt-get update -y && apt-get upgrade -y && apt-get install curl nano apt-transport-https apt-utils wget net-tools perl locales gnupg gnupg2 gnupg1 sudo unzip glibc-source glibc-doc -y && locale-gen en_US.UTF-8 && wget https://minecraft.azureedge.net/bin-linux/bedrock-server-1.17.31.01.zip && unzip bedrock-server-1.8.1.2.zip -d /minecraft && echo cd /minecraft > StartBedford.sh && echo LD_LIBRARY_PATH=. ./bedrock_server >> StartBedford.sh 
##RUN apt-get update -y && apt-get upgrade -y && apt-get install curl nano apt-transport-https apt-utils wget net-tools locales unzip glibc-source glibc-doc -y && locale-gen en_US.UTF-8 && wget https://minecraft.azureedge.net/bin-linux/bedrock-server-1.17.31.01.zip && unzip bedrock-server-1.8.1.2.zip -d /minecraft && echo cd /minecraft > StartBedford.sh && echo LD_LIBRARY_PATH=. ./bedrock_server >> StartBedford.sh 
##RUN sed -i 's/^#\s*\(deb.*main restricted\)$/\1/g' /etc/apt/sources.list && sed -i 's/^#\s*\(deb.*universe\)$/\1/g' /etc/apt/sources.list && sed -i 's/^#\s*\(deb.*multiverse\)$/\1/g' /etc/apt/sources.list && apt-get update && dpkg-divert --local --rename --add /sbin/initctl && ln -sf /bin/true /sbin/initctl && dpkg-divert --local --rename --add /usr/bin/ischroot && ln -sf /bin/true /usr/bin/ischroot && apt-get update -y && apt-get upgrade -y && apt-get install curl nano apt-transport-https apt-utils wget net-tools locales unzip glibc-source glibc-doc ca-certificates software-properties-common language-pack-en -y && apt-get dist-upgrade -y --no-install-recommends -o Dpkg::Options::="--force-confold" && locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8 LC_CTYPE=en_US.UTF-8 && wget https://minecraft.azureedge.net/bin-linux/bedrock-server-1.8.1.2.zip && unzip bedrock-server-1.8.1.2.zip -d /minecraft && echo cd /minecraft > StartBedford.sh && echo LD_LIBRARY_PATH=. ./bedrock_server >> StartBedford.sh 
#RUN apt-get update -y && apt-get upgrade -y && apt-get install curl nano wget unzip -y && wget https://minecraft.azureedge.net/bin-linux/bedrock-server-1.8.1.2.zip && unzip bedrock-server-1.8.1.2.zip -d /minecraft && echo cd /minecraft > StartBedford.sh && echo LD_LIBRARY_PATH=. ./bedrock_server >> StartBedford.sh 
#RUN echo $TZ > /etc/timezone && apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y tzdata && rm /etc/localtime && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime &&  dpkg-reconfigure -f noninteractive tzdata && apt-get clean
#CMD bash -C './StartBedford.sh';'bash'

ENV ZIPFILE=bedrock-server-$VERSION_NUMBER.zip
ENV BEDROCK_DOWNLOAD_ZIP=https://minecraft.azureedge.net/bin-linux/$ZIPFILE

# Use baseimage-docker's init system.
CMD ["/sbin/my_init"]

# ...put your own build instructions here...
RUN apt-get update && apt-get -y install unzip libcurl4 curl nano libssl-dev && echo $TZ > /etc/timezone && apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y tzdata && rm /etc/localtime && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime &&  dpkg-reconfigure -f noninteractive tzdata && apt-get clean && useradd -ms /bin/bash bedrock && su - bedrock -c "mkdir -p bedrock_server/data/worlds" && chown -R bedrock:bedrock /home/bedrock/bedrock_server/data/worlds && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

EXPOSE 19132/udp

# Entry
COPY startup.sh /home/bedrock
COPY startup2.sh /home/bedrock
RUN ["chmod", "+x", "/home/bedrock/startup.sh"] && ["chmod", "+x", "/home/bedrock/startup2.sh"]

# If you enable the USER below, there will be permission issues with shared volumes
# USER bedrock

# Added bash so you can drop to a shell to resolve errors
#ENTRYPOINT /home/bedrock/startup.sh && /bin/bash

#RUN cd /home/bedrock/bedrock_server && curl --fail -O $BEDROCK_DOWNLOAD_ZIP && unzip -n $ZIPFILE

ENTRYPOINT /home/bedrock/startup2.sh && /bin/bash


