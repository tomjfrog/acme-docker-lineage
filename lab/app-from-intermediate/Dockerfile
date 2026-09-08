# Multi-hop child: last FROM is the immediate parent (not golden-base).
# Workflow 03 parses this instruction (including ARG default), rewrites the
# registry host to JF_DOCKER_REGISTRY, then vets BuildKit SLSA against that
# catalog manifest. Local scripts may still pass --build-arg BASE_IMAGE.
ARG BASE_IMAGE=tomjpd2.jfrog.io/lineage-docker-local/payments-api:2.0.0
FROM ${BASE_IMAGE}

ARG GITHUB_RUN_NUMBER=0
ARG GITHUB_RUN_ID=0

LABEL org.opencontainers.image.title="acme-salestax-from-payments" \
      com.acme.image.role="app-multihop" \
      com.acme.image.expected_base="intermediate" \
      com.acme.ci.github_run_number="${GITHUB_RUN_NUMBER}" \
      com.acme.ci.github_run_id="${GITHUB_RUN_ID}"

RUN echo "app-from-intermediate" > /opt/app.txt \
 && echo "built-on-payments-api" >> /opt/app.txt

CMD ["cat", "/opt/app.txt"]
