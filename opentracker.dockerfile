#FROM debian
FROM debian:stable-slim

#Set Language and Location
ENV LANG=en_US.UTF-8  
ENV LANGUAGE=en_US:en  
ENV LC_ALL=en_US.UTF-8  

#Install Tools
RUN apt-get update -y && apt-get upgrade -y && apt-get install nano apt-utils locales -y --allow-unauthenticated && sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen && locale-gen && locale-gen en_US.UTF-8 
RUN apt-get install curl apt-transport-https wget net-tools perl git file build-essential xz-utils -y --allow-unauthenticated && update-locale LANG=en_US.UTF-8 && update-locale LANGUAGE=en_US:en && update-locale LC_ALL=en_US.UTF-8 

# install dependencies
RUN apt-get install gcc make g++ zlib1g-dev libowfat-dev -y --allow-unauthenticated 

##Get libowfat
##RUN wget https://www.fefe.de/libowfat/libowfat-0.33.tar.xz && tar -xf libowfat-0.33.tar.xz && chmod -R 777 /libowfat-0.33 && ls -al
##RUN echo "\n\n****** Cat makefile ******\n\n" && cd libowfat-0.33 && ls -al && cat -n /libowfat-0.33/Makefile && echo "\n\n****** Cat makefile ******\n\n\n" 
###RUN ls -al && cd libowfat-0.33 && ls -al && /libowfat-0.33/Makefile
##RUN ls -al && cd libowfat-0.33 && ls -al && make && make install
#RUN cvs -d :pserver:cvs@cvs.fefe.de:/cvs -z9 co libowfat
#RUN echo "\n\n****** Cat makefile ******\n\n" && cd libowfat && ls -al && cat -n /libowfat/Makefile && echo "\n\n****** Cat makefile ******\n\n\n" && cp -r /opt/diet/include/libowfat /tmp/libowfat && cp -r /tmp/libowfat /opt/diet/include/libowfat/libowfat
##RUN ls -al && cd libowfat && ls -al && /libowfat/Makefile
#RUN ls -al && cd libowfat && ls -al && make && make install

#Get opentracker
RUN pwd && ls -al && git clone git://erdgeist.org/opentracker && chmod -R 777 /opentracker && ls -al
RUN echo "\n\n****** Cat makefile ******\n\n" && cd opentracker && cat -n /opentracker/Makefile && echo "\n\n****** Cat makefile ******\n\n\n" 
#RUN sed -i 's!#FEATURES+=-DWANT_ACCESSLIST_WHITE!FEATURES+=-DWANT_ACCESSLIST_WHITE!g' /opentracker/Makefile
#RUN sed -i 's!#FEATURES+=-DWANT_LOG_NETWORKS!FEATURES+=-DWANT_LOG_NETWORKS!g' /opentracker/Makefile
RUN sed -i 's!PREFIX?=\.\.!# PREFIX?=\.\.!g;s!LIBOWFAT_HEADERS=$(PREFIX)/libowfat!# LIBOWFAT_HEADERS=$(PREFIX)/libowfat!g;s!LIBOWFAT_LIBRARY=$(PREFIX)/libowfat!# LIBOWFAT_LIBRARY=$(PREFIX)/libowfat!g;s!# PREFIX?=/opt/diet!PREFIX?=/usr!g;s!LIBOWFAT_LIBRARY=$(PREFIX)/libowfat!# LIBOWFAT_LIBRARY=$(PREFIX)/libowfat!g;s!LIBOWFAT_HEADERS=$(PREFIX))/include/libowfat!# LIBOWFAT_HEADERS=$(PREFIX))/include/libowfat!g;7s!# LIBOWFAT_HEADERS=$(PREFIX)/include!LIBOWFAT_HEADERS=$(PREFIX)/include!g;8s!# LIBOWFAT_LIBRARY=$(PREFIX)/lib!LIBOWFAT_LIBRARY=$(PREFIX)/lib!g' /opentracker/Makefile
RUN echo "\n\n****** Cat makefile ******\n\n" && cd opentracker && cat -n /opentracker/Makefile && echo "\n\n****** Cat makefile ******\n\n\n" 
RUN cd opentracker && pwd && ls -al && make && make install

#Health Check
HEALTHCHECK CMD curl --fail http://youtube.com/ || exit 1

#Starting container
WORKDIR /opentracker
#ENTRYPOINT ["opentracker", "-f /opentracker/opentracker.conf"]
#ENTRYPOINT ["opentracker", "-i 172.16.248.11 -p 8060,7070,8061 -P 8060"]
ENTRYPOINT ["sh","/script/makethemagic.sh"]
#ENTRYPOINT ["sh","/bin/bash"]
