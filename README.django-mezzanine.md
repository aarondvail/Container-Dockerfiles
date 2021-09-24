### Container-django-mezzanine ###

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


This container is a Django with Mezzanine (Basically a python CMS) container running on the python container, for DEV purposes only (See BELOW). The Dockerfile as below.
```
# Dockerfile DJango install (run from /port/docker/file)
FROM python
# Set the locale
RUN apt-get clean && apt-get update && apt-get install -y locales && sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && dpkg-reconfigure --frontend=noninteractive locales && update-locale LANG=en_US.UTF-8 && pip install --upgrade pip
ENV LANG=en_US.UTF-8  
ENV LANGUAGE=en_US:en  
ENV LC_ALL=en_US.UTF-8  
RUN pip3 install psycopg2 virtualenv django djangocms-installer 
RUN pip3 install mezzanine mezzanine-theme-moderna cartridge

#Health Check
HEALTHCHECK CMD curl --fail https://127.0.0.1:8000/ || exit 1
 
ENTRYPOINT ["/bin/bash", "/var/www/django/start-mezzanine.sh"]
```

and given the above shell scripts, there are the two pertainant for this container:
```
ContainerPorts="-p 8000:8000"
```
and 
```
ContainerMounts="-v $ContDataHome/django/:/var/www/django -v $ContDataHome/moderna/:/usr/local/lib/python3.8/site-packages/moderna/ -v $ContDataHome/templates/:/usr/local/lib/python3.8/site-packages/mezzanine/core/templates/ -v $ContDataHome/static/:/usr/local/lib/python3.8/site-packages/mezzanine/core/static/"
```

I know the bind mounts are over kill and I need to purge from time to time for updates, BUT this allows me to make changes to ANYTHING as I add specific files to SCM.
