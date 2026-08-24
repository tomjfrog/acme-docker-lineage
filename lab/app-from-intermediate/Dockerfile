# Multi-hop child: built FROM payments-api, not directly FROM golden-base.
# BASE_IMAGE is supplied by lab/scripts (payments-api).
ARG BASE_IMAGE=tomjpd2.jfrog.io/lineage-docker-local/payments-api:2.0.0
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.title="acme-app-from-intermediate" \
      com.acme.image.role="app-multihop" \
      com.acme.image.expected_base="intermediate"

RUN echo "app-from-intermediate" > /opt/app.txt \
 && echo "built-on-payments-api" >> /opt/app.txt

CMD ["cat", "/opt/app.txt"]
