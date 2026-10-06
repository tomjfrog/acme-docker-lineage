# Golden Alpine base: digest-pinned upstream + lab dummy CA (customer analog).
ARG BASE_IMAGE=alpine:3.20
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.title="acme-golden-alpine" \
      com.acme.image.role="golden-base" \
      com.acme.image.golden="true" \
      com.acme.image.family="alpine"

RUN echo "acme-golden-alpine-v1" > /etc/acme-golden-marker \
 && apk add --no-cache ca-certificates

COPY certs/acme-lab-root-ca.crt /usr/local/share/ca-certificates/acme-lab-root-ca.crt
RUN update-ca-certificates

CMD ["cat", "/etc/acme-golden-marker"]
