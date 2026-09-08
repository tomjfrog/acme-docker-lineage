# Application image intentionally built on the golden base.
# GOLDEN_IMAGE is supplied by lab/scripts/01-build-push.sh
ARG GOLDEN_IMAGE=tomjpd2.jfrog.io/lineage-docker-local/golden-base:1.0.0
FROM ${GOLDEN_IMAGE}

ARG GITHUB_RUN_NUMBER=0
ARG GITHUB_RUN_ID=0

LABEL org.opencontainers.image.title="acme-app-from-golden" \
      com.acme.image.role="app" \
      com.acme.image.expected_base="golden" \
      com.acme.ci.github_run_number="${GITHUB_RUN_NUMBER}" \
      com.acme.ci.github_run_id="${GITHUB_RUN_ID}"

RUN echo "app-from-golden" > /opt/app.txt \
 && echo "built-on-golden" >> /opt/app.txt

CMD ["cat", "/opt/app.txt"]
