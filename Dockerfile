FROM scratch
ARG TARGETARCH
COPY motebase-bin-linux_${TARGETARCH} /motebase
EXPOSE 8080
ENTRYPOINT ["/motebase", "--host", "0.0.0.0", "--port", "8080"]
