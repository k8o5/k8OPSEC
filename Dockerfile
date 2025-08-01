# Verwende eine leichte Base-Image
FROM alpine:3.18

# Installiere OpenVPN, Easy-RSA und Bash für Skripte
RUN apk add --no-cache openvpn easy-rsa bash && \
    ln -s /usr/share/easy-rsa/easyrsa /usr/local/bin/easyrsa && \
    mkdir -p /etc/openvpn/server /etc/openvpn/easy-rsa /etc/openvpn/client

# Initialisiere PKI und generiere Zertifikate
RUN easyrsa init-pki && \
    easyrsa --batch build-ca nopass && \
    easyrsa --batch gen-dh && \
    easyrsa --batch build-server-full server nopass && \
    easyrsa --batch build-client-full client nopass && \
    openvpn --genkey secret /etc/openvpn/server/ta.key

# Erstelle Server-Konfiguration
RUN echo "port 443" > /etc/openvpn/server/server.conf && \
    echo "proto tcp" >> /etc/openvpn/server/server.conf && \
    echo "dev tun" >> /etc/openvpn/server/server.conf && \
    echo "ca /etc/openvpn/easy-rsa/pki/ca.crt" >> /etc/openvpn/server/server.conf && \
    echo "cert /etc/openvpn/easy-rsa/pki/issued/server.crt" >> /etc/openvpn/server/server.conf && \
    echo "key /etc/openvpn/easy-rsa/pki/private/server.key" >> /etc/openvpn/server/server.conf && \
    echo "dh /etc/openvpn/easy-rsa/pki/dh.pem" >> /etc/openvpn/server/server.conf && \
    echo "tls-auth /etc/openvpn/server/ta.key 0" >> /etc/openvpn/server/server.conf && \
    echo "server 10.8.0.0 255.255.255.0" >> /etc/openvpn/server/server.conf && \
    echo "push \"redirect-gateway def1 bypass-dhcp\"" >> /etc/openvpn/server/server.conf && \
    echo "push \"dhcp-option DNS 8.8.8.8\"" >> /etc/openvpn/server/server.conf && \
    echo "keepalive 10 120" >> /etc/openvpn/server/server.conf && \
    echo "user nobody" >> /etc/openvpn/server/server.conf && \
    echo "group nogroup" >> /etc/openvpn/server/server.conf

# Starte OpenVPN und generiere Client-Konfig dynamisch mit CODESPACE_NAME
CMD bash -c " \
    openvpn --config /etc/openvpn/server/server.conf & \
    sleep 5; \
    if [ -z \"\$CODESPACE_NAME\" ]; then \
        echo 'Error: CODESPACE_NAME not set. Set it when running the container.'; \
        exit 1; \
    fi; \
    REMOTE_HOST=\"\$CODESPACE_NAME.app.github.dev\"; \
    echo \"Client config generated at /etc/openvpn/client/client.ovpn with remote \$REMOTE_HOST 443\"; \
    (echo 'client'; \
     echo 'dev tun'; \
     echo 'proto tcp'; \
     echo \"remote \$REMOTE_HOST 443\"; \
     echo 'resolv-retry infinite'; \
     echo 'nobind'; \
     echo 'persist-key'; \
     echo 'persist-tun'; \
     echo 'remote-cert-tls server'; \
     echo 'tls-auth ta.key 1'; \
     echo 'key client.key'; \
     echo 'cert client.crt'; \
     echo 'ca ca.crt'; \
     echo 'verb 3') > /etc/openvpn/client/client.ovpn; \
    echo '<ca>' >> /etc/openvpn/client/client.ovpn; \
    cat /etc/openvpn/easy-rsa/pki/ca.crt >> /etc/openvpn/client/client.ovpn; \
    echo '</ca>' >> /etc/openvpn/client/client.ovpn; \
    echo '<cert>' >> /etc/openvpn/client/client.ovpn; \
    cat /etc/openvpn/easy-rsa/pki/issued/client.crt >> /etc/openvpn/client/client.ovpn; \
    echo '</cert>' >> /etc/openvpn/client/client.ovpn; \
    echo '<key>' >> /etc/openvpn/client/client.ovpn; \
    cat /etc/openvpn/easy-rsa/pki/private/client.key >> /etc/openvpn/client/client.ovpn; \
    echo '</key>' >> /etc/openvpn/client/client.ovpn; \
    echo '<tls-auth>' >> /etc/openvpn/client/client.ovpn; \
    cat /etc/openvpn/server/ta.key >> /etc/openvpn/client/client.ovpn; \
    echo '</tls-auth>' >> /etc/openvpn/client/client.ovpn; \
    tail -f /dev/null"
