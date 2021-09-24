### Container-DNSMasq ###

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

This container is a real simple DNSMasq container running on Alpine 3.12. The Dockerfile as below.
```
FROM alpine:3.12
RUN apk --no-cache add dnsmasq
EXPOSE 53 53/udp
ENTRYPOINT ["dnsmasq", "-k"]
```

and given the above shell scripts, there are the two pertainant for this container:
```
ContainerPorts="-p 53:53/tcp -p 53:53/udp"
```
and 
```
ContainerMounts="-v $ContDataHome/dnsmasq.conf:/etc/dnsmasq.conf -v $ContDataHome/dnsmasq.d/:/etc/dnsmasq.d/ -v $ContDataHome/log/DNSMasq.log:/var/log/dnsmasq.log"
```

Yes, I suspect port 53/tcp and 53/udp may be overkill....

For the DNSMasq.log, I enabled it in the dnsmasq.conf.
```
# For debugging purposes, log each DNS query as it passes through
# dnsmasq.
log-queries

# Log lots of extra information about DHCP transactions.
#log-dhcp

log-facility=/var/log/dnsmasq.log
```
