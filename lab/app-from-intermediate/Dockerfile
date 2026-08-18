# Multi-hop child: built FROM an intermediate app image (Bar), not directly FROM golden (Foo).
# SPEC: Fizz:v0.1 FROM Bar:v0.1 which itself was FROM golden Foo.
# BASE_IMAGE is supplied by lab/scripts/01-build-push.sh (payments-api / Bar).
ARG BASE_IMAGE=tomjpd2.jfrog.io/lineage-docker-local/payments-api:2.0.0
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.title="acme-app-from-intermediate" \
      com.acme.image.role="app-multihop" \
      com.acme.image.expected_base="intermediate"

RUN echo "app-from-intermediate" > /opt/fizz.txt \
 && echo "built-on-bar-not-directly-on-golden" >> /opt/fizz.txt

CMD ["cat", "/opt/fizz.txt"]
