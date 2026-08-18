# Application image deliberately NOT built on the golden base.
FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="acme-app-non-golden" \
      com.acme.image.role="app" \
      com.acme.image.expected_base="non-golden"

RUN echo "app-non-golden" > /opt/app.txt \
 && echo "built-on-debian" >> /opt/app.txt

CMD ["cat", "/opt/app.txt"]
