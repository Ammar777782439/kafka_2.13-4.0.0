#!/bin/bash
set -e

# ====== Adjustable Settings ======

PASSWORD="kafkasslpass"
VALIDITY_DAYS=365
SAN_HOSTS="dns:localhost,ip:127.0.0.1"  # Modify this according to your network (eg: dns:localhost,ip:192.168.1.100)
BASE_DIR="./ssl"
# ===================================

mkdir -p $BASE_DIR/ca $BASE_DIR/server $BASE_DIR/client $BASE_DIR/pem

echo "[+] Create CA certificate"
openssl req -new -x509 \
  -keyout $BASE_DIR/ca/ca-key \
  -out $BASE_DIR/ca/ca-cert \
  -days $VALIDITY_DAYS \
  -subj "/CN=ca.kafka" \
  -passout pass:$PASSWORD

echo "[+] Create keystore for server"

keytool -keystore $BASE_DIR/server/kafka.server.keystore.jks \
  -alias localhost \
  -validity $VALIDITY_DAYS \
  -genkey \
  -keyalg RSA \
  -storepass $PASSWORD \
  -keypass $PASSWORD \
  -dname "CN=kafka, OU=None, O=None, L=None, S=None, C=None" \
  -ext san=${SAN_HOSTS}

echo "[+] Create keystore for client"

keytool -keystore $BASE_DIR/client/kafka.client.keystore.jks \
  -alias localhost \
  -validity $VALIDITY_DAYS \
  -genkey \
  -keyalg RSA \
  -storepass $PASSWORD \
  -keypass $PASSWORD \
  -dname "CN=client, OU=None, O=None, L=None, S=None, C=None"

echo "[+] Server Certificate Signature"
keytool -keystore $BASE_DIR/server/kafka.server.keystore.jks \
  -alias localhost \
  -certreq \
  -file $BASE_DIR/server/server-cert-sign-request \
  -storepass $PASSWORD

openssl x509 -req \
  -CA $BASE_DIR/ca/ca-cert \
  -CAkey $BASE_DIR/ca/ca-key \
  -in $BASE_DIR/server/server-cert-sign-request \
  -out $BASE_DIR/server/server-cert-signed \
  -days $VALIDITY_DAYS \
  -CAcreateserial \
  -passin pass:$PASSWORD

echo "[+] Client Certificate Signature"
keytool -keystore $BASE_DIR/client/kafka.client.keystore.jks \
  -alias localhost \
  -certreq \
  -file $BASE_DIR/client/client-cert-sign-request \
  -storepass $PASSWORD

openssl x509 -req \
  -CA $BASE_DIR/ca/ca-cert \
  -CAkey $BASE_DIR/ca/ca-key \
  -in $BASE_DIR/client/client-cert-sign-request \
  -out $BASE_DIR/client/client-cert-signed \
  -days $VALIDITY_DAYS \
  -CAcreateserial \
  -passin pass:$PASSWORD

echo "[+] Import CA certificate into keystores"
keytool -keystore $BASE_DIR/server/kafka.server.keystore.jks \
  -alias CARoot \
  -import \
  -file $BASE_DIR/ca/ca-cert \
  -storepass $PASSWORD \
  -noprompt

keytool -keystore $BASE_DIR/client/kafka.client.keystore.jks \
  -alias CARoot \
  -import \
  -file $BASE_DIR/ca/ca-cert \
  -storepass $PASSWORD \
  -noprompt

echo "[+] Import signed certificates into keystores"
keytool -keystore $BASE_DIR/server/kafka.server.keystore.jks \
  -alias localhost \
  -import \
  -file $BASE_DIR/server/server-cert-signed \
  -storepass $PASSWORD \
  -noprompt

keytool -keystore $BASE_DIR/client/kafka.client.keystore.jks \
  -alias localhost \
  -import \
  -file $BASE_DIR/client/client-cert-signed \
  -storepass $PASSWORD \
  -noprompt

echo "[+] Create truststore and import CA certificate"
keytool -keystore $BASE_DIR/server/kafka.server.truststore.jks \
  -alias CARoot \
  -import \
  -file $BASE_DIR/ca/ca-cert \
  -storepass $PASSWORD \
  -noprompt

keytool -keystore $BASE_DIR/client/kafka.client.truststore.jks \
  -alias CARoot \
  -import \
  -file $BASE_DIR/ca/ca-cert \
  -storepass $PASSWORD \
  -noprompt

echo "[+] Convert certificates to PEM format for use with Python"
# Copy CA certificate to PEM directory
cp $BASE_DIR/ca/ca-cert $BASE_DIR/pem/ca.pem

# Export client certificate in DER format
keytool -exportcert -file $BASE_DIR/pem/client.der -keystore $BASE_DIR/client/kafka.client.keystore.jks -storepass $PASSWORD -alias localhost
# Convert client certificate from DER to PEM
openssl x509 -inform der -in $BASE_DIR/pem/client.der -out $BASE_DIR/pem/client.pem

# Export client private key
keytool -importkeystore \
  -srckeystore $BASE_DIR/client/kafka.client.keystore.jks \
  -destkeystore $BASE_DIR/pem/client.p12 \
  -deststoretype PKCS12 \
  -srcstorepass $PASSWORD \
  -deststorepass $PASSWORD \
  -srcalias localhost

# Export private key from PKCS12 to PEM
openssl pkcs12 -in $BASE_DIR/pem/client.p12 -nocerts -nodes -out $BASE_DIR/pem/client.key -passin pass:$PASSWORD

echo "[+] Create Python configuration file for connecting to Kafka via SSL"
cat > $BASE_DIR/pem/kafka_ssl_config.py << EOF
# SSL configuration for connecting to Kafka from Python
ssl_config = {
    'bootstrap.servers': '${SAN_HOSTS##*:}:9094',  # Use IP from SAN_HOSTS
    'security.protocol': 'SSL',
    'ssl.ca.location': '$(pwd)/$BASE_DIR/pem/ca.pem',
    'ssl.certificate.location': '$(pwd)/$BASE_DIR/pem/client.pem',
    'ssl.key.location': '$(pwd)/$BASE_DIR/pem/client.key',
    'ssl.key.password': '$PASSWORD'
}
EOF

echo "[✓] Certificates created successfully!"
echo "[✓] Certificates converted to PEM format for use with Python!"
echo "[i] PEM files are located in: $(pwd)/$BASE_DIR/pem/"
echo "[i] You can use the configuration file: $(pwd)/$BASE_DIR/pem/kafka_ssl_config.py"