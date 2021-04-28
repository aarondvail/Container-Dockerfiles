#Setting ARCH type argument
ARG ARCH
FROM ${ARCH}alpine
RUN apk --no-cache add dnsmasq
EXPOSE 53 53/udp
ENTRYPOINT ["dnsmasq", "-k"]
