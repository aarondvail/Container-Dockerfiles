FROM debian:stable-slim

# example 4.15.0: calibre_version="version=4.15.0"
# example latest: calibre_version=""
ARG calibre_version
ENV calibre_version=$calibre_version TZ=America/New_York

LABEL maintainer="aarondvail"   description="calibre-server"

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone 

#COPY calibre/calibre-entrypoint.sh /opt/calibre/
COPY calibre/calibre-entrypoint.sh /

#RUN mkdir -p /calibre-lib && mkdir -p /calibre-config && chgrp -R 100 /calibre-lib && chgrp -R 100 /calibre-config && chmod -R 755 /calibre-lib && chmod -R 755 /calibre-config && chmod 755 /opt/calibre/calibre-entrypoint.sh
RUN mkdir -p /calibre-lib && mkdir -p /calibre-config && chgrp -R 100 /calibre-lib && chgrp -R 100 /calibre-config && chmod -R 755 /calibre-lib && chmod -R 755 /calibre-config && chmod 755 /calibre-entrypoint.sh

#RUN echo 'path-exclude /usr/share/doc/*' >/etc/dpkg/dpkg.cfg.d/docker-minimal && echo 'path-exclude /usr/share/man/*' >>/etc/dpkg/dpkg.cfg.d/docker-minimal && echo 'path-exclude /usr/share/groff/*' >>/etc/dpkg/dpkg.cfg.d/docker-minimal && echo 'path-exclude /usr/share/info/*' >>/etc/dpkg/dpkg.cfg.d/docker-minimal && echo 'path-exclude /usr/share/lintian/*' >>/etc/dpkg/dpkg.cfg.d/docker-minimal && echo 'path-exclude /usr/share/linda/*' >>/etc/dpkg/dpkg.cfg.d/docker-minimal && echo 'path-exclude /usr/share/locale/*' >>/etc/dpkg/dpkg.cfg.d/docker-minimal && echo 'path-include /usr/share/locale/en*' >>/etc/dpkg/dpkg.cfg.d/docker-minimal
RUN echo 'path-exclude /usr/share/man/*' >/etc/dpkg/dpkg.cfg.d/docker-minimal && apt-get update && apt-get -y install apt-utils wget python3 xz-utils imagemagick xdg-utils && apt-get -y install --no-install-recommends libnss3 sqlite3 python3-pyqt5 python3-xdg bash-completion libegl1 libopengl0 qt5-image-formats-plugins qtwayland5 python3-pyqt5-dbg sqlite3-doc qttranslations5-l10n libqt5svg5 qt5-gtk-platformtheme libqt5sql5-sqlite libqt5sql5-psql libwacom-bin && apt-get clean 

RUN rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/src/* && mkdir -p /usr/share/desktop-directories

RUN wget -nv -O- https://download.calibre-ebook.com/linux-installer.sh | sh /dev/stdin ${calibre_version} && rm /tmp/calibre* -Rf 2>&1 >/dev/null

WORKDIR /opt/calibre

VOLUME ["/calibre-lib", "/calibre-config"]

EXPOSE 8080

ENV PORT=8080 PREFIX="/" LIBRARY="/calibre-lib" USERDB="server-users.sqlite" AUTH="disable-auth" AUTH_USER="root" AUTH_PASSWORD="root" BANAFTER=5 BANFOR=30 AJAXTIMEOUT=60 TIMEOUT=120 NUMPERPAGE=50 MAXOPDS=30 OTHERPARAM= CALIBRE_OVERRIDE_LANG="en" CALIBRE_CONFIG_DIRECTORY="/calibre-config/calibre"

ENTRYPOINT "/calibre-entrypoint.sh"
CMD [""]