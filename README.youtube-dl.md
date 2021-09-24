### Container-youtube-dl ###

I love DevOps. I love infrastructure as code. 

I came into DevOps several years ago, from the Ops side of the house. Most DevOps Engineers come from the Dev side of the house. While the Dev side has been a learning curve, other concepts have been easier to embrace becuase of the Ops side. One of those being Infrastructure as Code.

I have been running most (soon to be all) of my personal infrastructure in containers. Those containers that I can not find on the Hub, I will build and publish the images here. That being said, there are few things worth noting.

1. I am a fan of bind mounts.
	1. Minimizes harddrive use on hosts, by keeping applications containerized.
	2. Gives a central place for configuration (and other) files to backup, either in the cloud or onto physical media
2. I am not a Linux expert, but I am a big fan. There's a HUGE story there. Let's just say I am a casualty of the OS Wars from years past (HINT: Vista).
	1. My host WAS CentOS, but IBM/Redhat decided to drop that like a hot potato, so I'm rebuilding on Debian (thank you, Raspberry Pi Foundation).
	2. I held out hope for Windows, that maybe they could rekindle that spark that was there before. Especially when they announced 2016 Nano Edition, but that was dashed when I heard that it wouldn't quite work right in a container.
3. I like using shell scripts to execute my containers, which I structured like my old CMD files from my windows days. Below is my shell script example.
4. I am a fan of StaticIP's. While DNS, NetBIOS, and WINS makes it so static IPs aren't necessary, it's an extra point of failure that I just bypass. Yes it's more work on me, but hey... It's my box :).
```
ContainerName=***OBVIOUS***
ImageName=***From_Docker_Hub***
ContainerIP="*** StaticIP mentioned above ***"
ContainerPorts="*** In here I put the Ports specific to this container***"
DockerDataHome=***/path/to/datahome***
ContDataHome=$DockerDataHome/$ContainerName/
ContainerMounts="*** In here I put the Switches and Bindmount specific to this container***"
DefaultMounts="*** In here I put the Switches specific to ALL containers (i.e. Timezone stuff)***"
mkdir -p $ContDataHome
docker container stop $ContainerName
docker container rm $ContainerName
docker run -d --name $ContainerName --restart unless-stopped --ip $ContainerIP $DefaultMounts $ContainerMounts $ContainerPorts --network=MyGeneric -e TZ=America/New_York $ImageName
```

This container is a real simple YouTube-DL container running on Debian (latest). The Dockerfile as below.
```
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
ENTRYPOINT ["/bin/bash", "/root/findYouTube.sh"]
```

and given the above shell scripts, there are the two pertainant for this container:
```
ContainerPorts=""
```
and 
```
ContainerMounts="-v /fileshare:/fileshare:rw -v /opt/port/YouTube-DL/findYouTube.sh:/root/findYouTube.sh "
```

No Ports are necessary, as there's no inbound connections. 
fileshare bind mount is where the files go from my findYouTube.sh script. Line examples
```
# Video Example - refer to https://github.com/ytdl-org/youtube-dl/blob/master/README.md#readme for documentation help
youtube-dl -ciw -f best -o '/fileshare/YouTube/%(title)s.%(ext)s' https://SOME.YOUTU.BE.VIDEO.LINK
# Audio Example - refer to https://github.com/ytdl-org/youtube-dl/blob/master/README.md#readme for documentation help
youtube-dl --extract-audio --audio-format mp3 -o '/fileshare/YouTube/%(title)s.%(ext)s' https://SOME.YOUTU.BE.VIDEO.LINK
```

The script will run everytime the container starts so I remove (or comment out) the links once I verify the downloads
