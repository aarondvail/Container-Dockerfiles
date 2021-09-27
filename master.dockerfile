#FROM eclipse-temurin:8u302-b08-jdk-focal as jre-build

FROM debian:bullseye-20210902-slim

RUN apt-get update && \
    apt-get install -y git curl gpg unzip libfreetype6 libfontconfig1 && \
    rm -rf /var/lib/apt/lists/*

ENV LANG C.UTF-8

ARG TARGETARCH
ARG GIT_LFS_VERSION=2.13.3
RUN apt-get update && apt-get upgrade -y && apt-get install -y git curl dpkg gpg tar wget && rm -rf /var/lib/apt/lists/*
RUN wget -q -O - https://pkg.jenkins.io/debian/jenkins.io.key | apt-key add - && echo "deb https://pkg.jenkins.io/debian binary/" >> /etc/apt/sources.list && apt-get update && apt-get upgrade -y && mkdir -p /usr/share/man/man1

# required for multi-arch support, revert to package cloud after:
# https://github.com/git-lfs/git-lfs/issues/4546
COPY jenkins/git_lfs_pub.gpg /tmp/git_lfs_pub.gpg
#RUN GIT_LFS_ARCHIVE="git-lfs-linux-${TARGETARCH}-v${GIT_LFS_VERSION}.tar.gz" \
#    GIT_LFS_RELEASE_URL="https://github.com/git-lfs/git-lfs/releases/download/v${GIT_LFS_VERSION}/${GIT_LFS_ARCHIVE}"\
#    set -x; curl --fail --silent --location --show-error --output "/tmp/${GIT_LFS_ARCHIVE}" "${GIT_LFS_RELEASE_URL}" && \
#    curl --fail --silent --location --show-error --output "/tmp/git-lfs-sha256sums.asc" https://github.com/git-lfs/git-lfs/releases/download/v${GIT_LFS_VERSION}/sha256sums.asc && \
#    gpg --no-tty --import /tmp/git_lfs_pub.gpg && \
#    gpg -d /tmp/git-lfs-sha256sums.asc | grep "${GIT_LFS_ARCHIVE}" | (cd /tmp; sha256sum -c ) && \
#    mkdir -p /tmp/git-lfs && \
#    tar xzvf "/tmp/${GIT_LFS_ARCHIVE}" -C /tmp/git-lfs && \
#    bash -x /tmp/git-lfs/install.sh && \
#    rm -rf /tmp/git-lfs*

ARG user=jenkins
ARG group=jenkins
ARG uid=1000
ARG gid=1000
ARG http_port=8080
ARG agent_port=50000
ARG JENKINS_HOME=/var/jenkins_home
ARG REF=/usr/share/jenkins/ref

ENV JENKINS_HOME $JENKINS_HOME
ENV JENKINS_SLAVE_AGENT_PORT ${agent_port}
ENV REF $REF

# Jenkins is run with user `jenkins`, uid = 1000
# If you bind mount a volume from the host or a data container,
# ensure you use the same uid
RUN mkdir -p $JENKINS_HOME \
  && chown ${uid}:${gid} $JENKINS_HOME \
  && groupadd -g ${gid} ${group} \
  && useradd -d "$JENKINS_HOME" -u ${uid} -g ${gid} -m -s /bin/bash ${user}

# Jenkins home directory is a volume, so configuration and build history
# can be persisted and survive image upgrades
VOLUME $JENKINS_HOME

# $REF (defaults to `/usr/share/jenkins/ref/`) contains all reference configuration we want
# to set on a fresh new installation. Use it to bundle additional plugins
# or config file with your custom jenkins Docker image.
RUN mkdir -p ${REF}/init.groovy.d

# Use tini as subreaper in Docker container to adopt zombie processes
ARG TINI_VERSION=v0.19.0
COPY jenkins/tini_pub.gpg "${JENKINS_HOME}/tini_pub.gpg"
RUN cat ${JENKINS_HOME}/tini_pub.gpg
#RUN echo curl -fsSL "https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-static-${TARGETARCH}" -o /sbin/tini 
#RUN curl -fsSL "https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-static-${TARGETARCH}" -o /sbin/tini 
#RUN curl -fsSL "https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-static-${TARGETARCH}.asc" -o /sbin/tini.asc 
#RUN gpg --no-tty --import "${JENKINS_HOME}/tini_pub.gpg" 
#RUN gpg --verify /sbin/tini.asc 
#RUN rm -rf /sbin/tini.asc /root/.gnupg 
#RUN chmod +x /sbin/tini

### differentiating at this point
## jenkins version being bundled in this docker image
#ARG JENKINS_VERSION
#ENV JENKINS_VERSION ${JENKINS_VERSION:-2.303}

## jenkins.war checksum, download will be validated using it
#ARG JENKINS_SHA=4dfe49cd7422ec4317a7c7a7c083f40fa475a58a7747bd94187b2cf222006ac0

## Can be used to customize where jenkins.war get downloaded from
#ARG JENKINS_URL=https://repo.jenkins-ci.org/public/org/jenkins-ci/main/jenkins-war/${JENKINS_VERSION}/jenkins-war-${JENKINS_VERSION}.war

## could use ADD but this one does not check Last-Modified header neither does it allow to control checksum
## see https://github.com/docker/docker/issues/8331
#RUN curl -fsSL ${JENKINS_URL} -o /usr/share/jenkins/jenkins.war && echo "${JENKINS_SHA}  /usr/share/jenkins/jenkins.war" | sha256sum -c -
#RUN apt-get install -y tini jenkins python3 qemu git-lfs openjdk-11-jdk
RUN apt-get install -y jenkins 
RUN apt-get install -y python3 
RUN apt-get install -y qemu 
RUN apt-get install -y git-lfs 
RUN apt-get install -y default-jdk

ENV JENKINS_UC https://updates.jenkins.io
ENV JENKINS_UC_EXPERIMENTAL=https://updates.jenkins.io/experimental
ENV JENKINS_INCREMENTALS_REPO_MIRROR=https://repo.jenkins-ci.org/incrementals
RUN chown -R ${user} "$JENKINS_HOME" "$REF"

ARG PLUGIN_CLI_VERSION=2.9.3
ARG PLUGIN_CLI_URL=https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/${PLUGIN_CLI_VERSION}/jenkins-plugin-manager-${PLUGIN_CLI_VERSION}.jar
RUN curl -fsSL ${PLUGIN_CLI_URL} -o /opt/jenkins-plugin-manager.jar

# for main web interface:
EXPOSE ${http_port}

# will be used by attached agents:
EXPOSE ${agent_port}

ENV COPY_REFERENCE_FILE_LOG $JENKINS_HOME/copy_reference_file.log

ENV JAVA_HOME=/opt/java/openjdk
ENV PATH "${JAVA_HOME}/bin:${PATH}"
#COPY --from=jre-build /opt/java/openjdk $JAVA_HOME

USER ${user}

COPY jenkins/jenkins-support /usr/local/bin/jenkins-support
COPY jenkins/jenkins.sh /usr/local/bin/jenkins.sh
COPY jenkins/tini-shim.sh /bin/tini
COPY jenkins/jenkins-plugin-cli.sh /bin/jenkins-plugin-cli

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/jenkins.sh"]

# from a derived Dockerfile, can use `RUN install-plugins.sh active.txt` to setup $REF/plugins from a support bundle
COPY jenkins/install-plugins.sh /usr/local/bin/install-plugins.sh

# metadata labels
LABEL \
    org.opencontainers.image.vendor="Jenkins project" \
    org.opencontainers.image.title="Official Jenkins Docker image" \
    org.opencontainers.image.description="The Jenkins Continuous Integration and Delivery server" \
    org.opencontainers.image.version="${JENKINS_VERSION}" \
    org.opencontainers.image.url="https://www.jenkins.io/" \
    org.opencontainers.image.source="https://github.com/jenkinsci/docker" \
    org.opencontainers.image.licenses="MIT"