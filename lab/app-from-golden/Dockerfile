# Application image intentionally built on the golden base.
# GOLDEN_IMAGE is supplied by lab/scripts/01-build-push.sh
ARG GOLDEN_IMAGE=tomjpd2.jfrog.io/lineage-docker-local/golden-base:1.0.0
FROM ${GOLDEN_IMAGE}

LABEL org.opencontainers.image.title="acme-app-from-golden" \
      com.acme.image.role="app" \
      com.acme.image.expected_base="golden"

RUN echo "app-from-golden" > /opt/app.txt \
 && echo "built-on-golden" >> /opt/app.txt

CMD ["cat", "/opt/app.txt"]
