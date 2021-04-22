# Dockerfile YouTube-DL install (run from /port/docker/file)
FROM debian

#Set Language and Location
ENV LANG=en_US.UTF-8  
ENV LANGUAGE=en_US:en  
ENV LC_ALL=en_US.UTF-8  

#Install Tools
RUN apt-get update -y && apt-get upgrade -y && apt-get install nano apt-utils locales -y --allow-unauthenticated && sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen && locale-gen && locale-gen en_US.UTF-8 
RUN apt-get install curl apt-transport-https wget net-tools perl -y --allow-unauthenticated && update-locale LANG=en_US.UTF-8 && update-locale LANGUAGE=en_US:en && update-locale LC_ALL=en_US.UTF-8 

#Install YouTube-DL dependencies
RUN apt-get update -y && apt-get install -y --allow-unauthenticated build-essential net-tools libmp3lame-dev libvorbis-dev libtheora-dev libspeex-dev yasm pkg-config libx264-dev ffmpeg apache2 curl python python-dev python-minimal python-pip

#Get YouTube-DL
RUN curl -L https://yt-dl.org/downloads/latest/youtube-dl -o /usr/local/bin/youtube-dl && chmod a+rx /usr/local/bin/youtube-dl 

#Get youtube filelist
RUN touch /root/findYouTube.sh

#Health Check
HEALTHCHECK CMD curl --fail http://youtube.com/ || exit 1

#Starting container
ENTRYPOINT ["sh", "/root/findYouTube.sh"]
