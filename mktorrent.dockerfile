#FROM debian
FROM debian:stable-slim

#Set Language and Location
ENV LANG=en_US.UTF-8  
ENV LANGUAGE=en_US:en  
ENV LC_ALL=en_US.UTF-8  
ENV PATH="/opt/mktorrent/bin:$PATH"

#Install Tools
RUN apt-get update -y && apt-get upgrade -y && apt-get install nano apt-utils locales -y --allow-unauthenticated && sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen && locale-gen && locale-gen en_US.UTF-8 
RUN apt-get install curl apt-transport-https wget net-tools perl git file build-essential xz-utils -y --allow-unauthenticated && update-locale LANG=en_US.UTF-8 && update-locale LANGUAGE=en_US:en && update-locale LC_ALL=en_US.UTF-8 

# install dependencies
RUN apt-get install -y openssl libssl-dev

# Get mktorrent installed
RUN mkdir /Workspace && cd /Workspace && git clone https://github.com/pobrn/mktorrent.git && mkdir /opt/mktorrent && cd /Workspace/mktorrent && make PREFIX=/opt/mktorrent USE_PTHREADS=1 USE_OPENSSL=1 USE_LONG_OPTIONS=1 && make install PREFIX=/opt/mktorrent USE_PTHREADS=1 USE_OPENSSL=1 USE_LONG_OPTIONS=1

#Health Check
HEALTHCHECK CMD curl --fail http://youtube.com/ || exit 1

#Starting container
#ENTRYPOINT ["sh","/config/makethemagic.sh"]
#ENTRYPOINT ["sh","/bin/bash"]
