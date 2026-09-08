# Application image deliberately NOT built on the golden base.
FROM debian:bookworm-slim

ARG GITHUB_RUN_NUMBER=0
ARG GITHUB_RUN_ID=0

LABEL org.opencontainers.image.title="acme-app-non-golden" \
      com.acme.image.role="app" \
      com.acme.image.expected_base="non-golden" \
      com.acme.ci.github_run_number="${GITHUB_RUN_NUMBER}" \
      com.acme.ci.github_run_id="${GITHUB_RUN_ID}"

RUN echo "app-non-golden" > /opt/app.txt \
 && echo "built-on-debian" >> /opt/app.txt

CMD ["cat", "/opt/app.txt"]
