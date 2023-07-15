FROM debian:bookworm

LABEL maintainer="Aaron D. Vail <aarondvail@gmail.com>"

# Make sure the package repository is up to date. 
RUN apt-get update && apt-get -qy full-upgrade && apt-get install -qy git nano 
# Install a basic SSH server 
RUN apt-get install -qy openssh-server 
RUN sed -i 's|session    required     pam_loginuid.so|session    optional     pam_loginuid.so|g' /etc/pam.d/sshd && mkdir -p /var/run/sshd

# Install JDK 17 
RUN apt-get install -qy openjdk-17-jdk
# Install JDK 11 
RUN apt-get install -qy openjdk-11-jdk
# Install JDK 8 # Install maven
RUN apt-get install -qy openjdk-8-jdk && apt-get install -qy maven 
# Install Python
RUN apt-get install -qy python3 python3-dev 

# Cleanup old packages
RUN apt-get -qy autoremove
# Add user jenkins to the image
RUN adduser --quiet jenkins
# Set password for the jenkins user (you may want to alter this).
RUN echo "jenkins:jenkins" | chpasswd && mkdir /home/jenkins/.m2

#ADD settings.xml /home/jenkins/.m2/
# Copy authorized keys
# COPY .ssh/authorized_keys /home/jenkins/.ssh/authorized_keys

RUN chown -R jenkins:jenkins /home/jenkins/.m2/ && chown -R jenkins:jenkins /home/jenkins/.ssh/

# Standard SSH port
EXPOSE 22

CMD ["/usr/sbin/sshd", "-D"]
