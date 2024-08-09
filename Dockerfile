FROM alpine:latest
RUN apk --no-cache add bash bc drill \
    && mkdir /app \
    && wget https://github.com/LunarLaurus/dnsperftest/blob/master/dns-test-v2.sh -O /app/dns-test-v2.sh \
    && chmod +x /app/dns-test-v2.sh

ENTRYPOINT ["/app/dns-test-v2.sh"]
