# Synthetic "purchased / approved" golden base for lineage lab.
FROM alpine:3.20

LABEL org.opencontainers.image.title="acme-golden-base" \
      com.acme.image.role="golden-base" \
      com.acme.image.golden="true" \
      com.acme.image.foo="bar"

RUN echo "acme-golden-base-v1" > /etc/acme-golden-marker \
 && apk add --no-cache ca-certificates

CMD ["cat", "/etc/acme-golden-marker"]
