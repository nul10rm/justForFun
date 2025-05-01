FROM dreamhackofficial/web3-base:2025-04-04

COPY ./deploy/config.yaml /app/
COPY ./deploy/remappings.txt /app/
COPY ./deploy/src/ /app/src/
COPY ./deploy/verifier.py /verifier.py

COPY ./deploy/script/ /app/script/
COPY ./private/flag.txt /app/
COPY ./deploy/build.sh /app/

RUN /app/build.sh
