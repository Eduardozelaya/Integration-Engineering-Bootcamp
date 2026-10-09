# syntax=docker/dockerfile:1
# ACE 12.0.12.27 (modo developer) + cliente MQ 9.4.0.26 + application OrderProcessing (P5-1b).
# Contem o produto IBM sob licenca de desenvolvedor: NAO publicar em registro publico.
# Construida por scripts/build-ace-image.sh, que aponta os contextos nomeados:
#   acesrc   -> instalacao do ACE fora do git (~/ace/ace-12.0.12.27)
#   mqclient -> cliente MQ redistribuivel fora do git (~/mqclient)
FROM ubuntu:22.04

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Runtime do ACE, sem o Toolkit (pasta tools: 1,9 GB)
COPY --from=acesrc server  /opt/ibm/ace-12/server
COPY --from=acesrc common  /opt/ibm/ace-12/common
COPY --from=acesrc license /opt/ibm/ace-12/license
COPY --from=acesrc ace     /opt/ibm/ace-12/ace
RUN /opt/ibm/ace-12/ace make registry global accept license silently \
 && useradd --create-home --gid mqbrkrs aceuser

# Cliente MQ (sem ele: BIP2684E, exp P5-1a)
COPY --from=mqclient . /opt/mqm-client/
ENV MQ_INSTALLATION_PATH=/opt/mqm-client \
    LD_LIBRARY_PATH=/opt/mqm-client/lib64

USER aceuser
WORKDIR /home/aceuser
COPY --chown=aceuser:mqbrkrs app.bar start.sh /home/aceuser/
RUN bash -c '. /opt/ibm/ace-12/server/bin/mqsiprofile > /dev/null \
      && mqsicreateworkdir /home/aceuser/ace-server \
      && ibmint deploy --input-bar-file /home/aceuser/app.bar --output-work-directory /home/aceuser/ace-server' \
 && mkdir -p /home/aceuser/trace \
 && chmod +x /home/aceuser/start.sh

EXPOSE 7600 7800
CMD ["/home/aceuser/start.sh"]
