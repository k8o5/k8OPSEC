# Stage 1: Build stage (minimal, to reduce final image size and attack surface)
FROM alpine:latest AS builder
RUN apk add --no-cache wireguard-tools bash

# Stage 2: Runtime stage (secure, minimal base image)
FROM linuxserver/wireguard:latest

# Copy tools from builder stage
COPY --from=builder /usr/bin/wg /usr/bin/wg
COPY --from=builder /usr/bin/wg-quick /usr/bin/wg-quick
COPY --from=builder /bin/bash /bin/bash

# Set secure environment variables (defaults; override at runtime with -e flags or secrets)
ENV PUID=1000 \
    PGID=1000 \
    TZ=Etc/UTC \
    SERVERPORT=51820 \
    PEERS=1 \
    PEERDNS=1.1.1.1 \
    INTERNAL_SUBNET=10.13.13.0 \
    ALLOWEDIPS=0.0.0.0/0 \
    LOG_CONFS=false  # Set to true for auditing, false for minimal logs

# Embed custom entrypoint logic directly (for ephemeral key generation)
RUN echo '#!/bin/bash' > /entrypoint.sh && \
    echo 'set -e' >> /entrypoint.sh && \
    echo 'if [ ! -f /config/wg0.conf ]; then' >> /entrypoint.sh && \
    echo '  echo "Generating secure WireGuard configs..."' >> /entrypoint.sh && \
    echo '  mkdir -p /config' >> /entrypoint.sh && \
    echo '  wg genkey | tee /config/server.key | wg pubkey > /config/server.pub' >> /entrypoint.sh && \
    echo '  SERVER_PRIVATE_KEY=$(cat /config/server.key)' >> /entrypoint.sh && \
    echo '  SERVER_PUBLIC_KEY=$(cat /config/server.pub)' >> /entrypoint.sh && \
    echo '  echo "[Interface]" > /config/wg0.conf' >> /entrypoint.sh && \
    echo '  echo "Address = ${INTERNAL_SUBNET}/24" >> /config/wg0.conf' >> /entrypoint.sh && \
    echo '  echo "PrivateKey = $SERVER_PRIVATE_KEY" >> /config/wg0.conf' >> /entrypoint.sh && \
    echo '  echo "ListenPort = $SERVERPORT" >> /config/wg0.conf' >> /entrypoint.sh && \
    echo '  for i in $(seq 1 $PEERS); do' >> /entrypoint.sh && \
    echo '    wg genkey | tee /config/peer$i.key | wg pubkey > /config/peer$i.pub' >> /entrypoint.sh && \
    echo '    PEER_PRIVATE_KEY=$(cat /config/peer$i.key)' >> /entrypoint.sh && \
    echo '    PEER_PUBLIC_KEY=$(cat /config/peer$i.pub)' >> /entrypoint.sh && \
    echo '    echo "" >> /config/wg0.conf' >> /entrypoint.sh && \
    echo '    echo "[Peer]" >> /config/wg0.conf' >> /entrypoint.sh && \
    echo '    echo "PublicKey = $PEER_PUBLIC_KEY" >> /config/wg0.conf' >> /entrypoint.sh && \
    echo '    echo "AllowedIPs = ${INTERNAL_SUBNET}.$((i+1))/32" >> /config/wg0.conf' >> /entrypoint.sh && \
    echo '    echo "[Interface]" > /config/peer$i.conf' >> /entrypoint.sh && \
    echo '    echo "Address = ${INTERNAL_SUBNET}.$((i+1))/32" >> /config/peer$i.conf' >> /entrypoint.sh && \
    echo '    echo "PrivateKey = $PEER_PRIVATE_KEY" >> /entrypoint.sh && \
    echo '    echo "DNS = $PEERDNS" >> /config/peer$i.conf' >> /entrypoint.sh && \
    echo '    echo "" >> /config/peer$i.conf' >> /entrypoint.sh && \
    echo '    echo "[Peer]" >> /config/peer$i.conf' >> /entrypoint.sh && \
    echo '    echo "PublicKey = $SERVER_PUBLIC_KEY" >> /config/peer$i.conf' >> /entrypoint.sh && \
    echo '    echo "Endpoint = YOUR_SERVER_IP:$SERVERPORT" >> /config/peer$i.conf  # Replace YOUR_SERVER_IP at runtime' >> /entrypoint.sh && \
    echo '    echo "AllowedIPs = $ALLOWEDIPS" >> /config/peer$i.conf' >> /entrypoint.sh && \
    echo '    echo "PersistentKeepalive = 25" >> /config/peer$i.conf' >> /entrypoint.sh && \
    echo '  done' >> /entrypoint.sh && \
    echo '  if [ "$LOG_CONFS" != "true" ]; then rm -f /config/*.key; fi  # Clean up keys for OPSEC' >> /entrypoint.sh && \
    echo 'fi' >> /entrypoint.sh && \
    echo 'exec /init' >> /entrypoint.sh && \
    chmod +x /entrypoint.sh

# Harden the container
USER 1000:1000  # Run as non-root for least privilege
HEALTHCHECK --interval=30s --timeout=10s CMD wg show || exit 1

# Expose minimal port
EXPOSE 51820/udp

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
