# Synthetic "purchased / approved" golden base for lineage lab.
FROM alpine:3.20

LABEL org.opencontainers.image.title="acme-golden-base" \
      com.acme.image.role="golden-base" \
      com.acme.image.golden="true" \
      com.acme.image.foo="bar"

RUN echo "acme-golden-base-v1" > /etc/acme-golden-marker \
 && apk add --no-cache ca-certificates

# Dedicated COPY layer = stable blob fingerprint for the lab CA (do not generate the cert here).
COPY certs/acme-lab-root-ca.crt /usr/local/share/ca-certificates/acme-lab-root-ca.crt
RUN update-ca-certificates

CMD ["cat", "/etc/acme-golden-marker"]
