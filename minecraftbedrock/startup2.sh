#!/bin/sh

#ZIPFILE=$(basename $BEDROCK_DOWNLOAD_ZIP)

cd /home/bedrock/bedrock_server
#curl --fail -O $BEDROCK_DOWNLOAD_ZIP
#unzip -n $ZIPFILE

LD_LIBRARY_PATH=. ./bedrock_server
