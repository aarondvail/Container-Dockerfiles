#Setting ARCH type argument
ARG ARCH=
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
