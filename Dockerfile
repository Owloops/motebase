FROM scratch
COPY motebase-bin /motebase
EXPOSE 8080
ENTRYPOINT ["/motebase", "--host", "0.0.0.0", "--port", "8080"]
