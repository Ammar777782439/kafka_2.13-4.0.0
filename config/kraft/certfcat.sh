#!/bin/bash
set -e

# ====== Adjustable Settings ======
PASSWORD="kafkasslpass"
VALIDITY_DAYS=365
SAN_HOSTS_DNS="edg"
SAN_HOSTS_IP="192.168.168.44"
BASE_DIR="./ssl"
# =================================

# Be sure to quote variables that represent paths.
mkdir -p "$BASE_DIR/ca" "$BASE_DIR/server" "$BASE_DIR/client" "$BASE_DIR/pem"


echo "[+] Create CA certificate"
openssl req -new -x509 \
  -keyout "$BASE_DIR/ca/ca-key.pem" \
  -out "$BASE_DIR/ca/ca-cert.pem" \
  -days $VALIDITY_DAYS \
  -subj "/C=US/ST=State/L=City/O=MyOrg/OU=MyUnit/CN=ca.kafka" \
  -passout pass:$PASSWORD


echo "[+] Create keystore for server (keytool genkeypair)"
keytool -genkeypair \
  -keystore "$BASE_DIR/server/kafka.server.keystore.jks" \
  -alias localhost \
  -keyalg RSA \
  -keysize 2048 \
  -validity $VALIDITY_DAYS \
  -storepass $PASSWORD \
  -keypass $PASSWORD \
  -dname "CN=kafka, OU=None, O=None, L=None, S=None, C=None"

echo "[+] Create OpenSSL config file with SAN for server CSR"

cat > "$BASE_DIR/server/openssl-san.cnf" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = kafka

[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $SAN_HOSTS_DNS
IP.1 = $SAN_HOSTS_IP
EOF

echo "[+] Generate CSR from keystore"
keytool -keystore "$BASE_DIR/server/kafka.server.keystore.jks" \
  -alias localhost \
  -certreq \
  -file "$BASE_DIR/server/server-cert-sign-request.csr" \
  -storepass $PASSWORD

echo "[+] Sign server CSR with CA, including SAN extension"
openssl x509 -req \
  -in "$BASE_DIR/server/server-cert-sign-request.csr" \
  -CA "$BASE_DIR/ca/ca-cert.pem" \
  -CAkey "$BASE_DIR/ca/ca-key.pem" \
  -CAcreateserial \
  -out "$BASE_DIR/server/server-cert-signed.pem" \
  -days $VALIDITY_DAYS \
  -passin pass:$PASSWORD \
  -extensions v3_req \
  -extfile "$BASE_DIR/server/openssl-san.cnf"

echo "[+] Import CA certificate into server keystore"
keytool -keystore "$BASE_DIR/server/kafka.server.keystore.jks" \
  -alias CARoot \
  -import \
  -file "$BASE_DIR/ca/ca-cert.pem" \
  -storepass $PASSWORD \
  -noprompt

echo "[+] Import signed server certificate into keystore"
keytool -keystore "$BASE_DIR/server/kafka.server.keystore.jks" \
  -alias localhost \
  -import \
  -file "$BASE_DIR/server/server-cert-signed.pem" \
  -storepass $PASSWORD \
  -noprompt

echo "[+] Create keystore for client"
keytool -genkeypair \
  -keystore "$BASE_DIR/client/kafka.client.keystore.jks" \
  -alias localhost \
  -keyalg RSA \
  -keysize 2048 \
  -validity $VALIDITY_DAYS \
  -storepass $PASSWORD \
  -keypass $PASSWORD \
  -dname "CN=client, OU=None, O=None, L=None, S=None, C=None"

echo "[+] Create CSR for client"
keytool -keystore "$BASE_DIR/client/kafka.client.keystore.jks" \
  -alias localhost \
  -certreq \
  -file "$BASE_DIR/client/client-cert-sign-request.csr" \
  -storepass $PASSWORD

echo "[+] Sign client CSR with CA"
openssl x509 -req \
  -in "$BASE_DIR/client/client-cert-sign-request.csr" \
  -CA "$BASE_DIR/ca/ca-cert.pem" \
  -CAkey "$BASE_DIR/ca/ca-key.pem" \
  -CAcreateserial \
  -out "$BASE_DIR/client/client-cert-signed.pem" \
  -days $VALIDITY_DAYS \
  -passin pass:$PASSWORD

echo "[+] Import CA certificate into client keystore"
keytool -keystore "$BASE_DIR/client/kafka.client.keystore.jks" \
  -alias CARoot \
  -import \
  -file "$BASE_DIR/ca/ca-cert.pem" \
  -storepass $PASSWORD \
  -noprompt

echo "[+] Import signed client certificate into keystore"
keytool -keystore "$BASE_DIR/client/kafka.client.keystore.jks" \
  -alias localhost \
  -import \
  -file "$BASE_DIR/client/client-cert-signed.pem" \
  -storepass $PASSWORD \
  -noprompt

echo "[+] Create truststores and import CA certificate"
keytool -keystore "$BASE_DIR/server/kafka.server.truststore.jks" \
  -alias CARoot \
  -import \
  -file "$BASE_DIR/ca/ca-cert.pem" \
  -storepass $PASSWORD \
  -noprompt

keytool -keystore "$BASE_DIR/client/kafka.client.truststore.jks" \
  -alias CARoot \
  -import \
  -file "$BASE_DIR/ca/ca-cert.pem" \
  -storepass $PASSWORD \
  -noprompt

echo "[+] Convert certificates to PEM format for Python"

cp "$BASE_DIR/ca/ca-cert.pem" "$BASE_DIR/pem/ca.pem"

keytool -exportcert -file "$BASE_DIR/pem/client.der" -keystore "$BASE_DIR/client/kafka.client.keystore.jks" -storepass $PASSWORD -alias localhost
openssl x509 -inform der -in "$BASE_DIR/pem/client.der" -out "$BASE_DIR/pem/client.pem"

keytool -importkeystore \
  -srckeystore "$BASE_DIR/client/kafka.client.keystore.jks" \
  -destkeystore "$BASE_DIR/pem/client.p12" \
  -deststoretype PKCS12 \
  -srcstorepass $PASSWORD \
  -deststorepass $PASSWORD \
  -srcalias localhost

openssl pkcs12 -in "$BASE_DIR/pem/client.p12" -nocerts -nodes -out "$BASE_DIR/pem/client.key" -passin pass:$PASSWORD

echo "[+] Create Python Kafka SSL config file"
cat > "$BASE_DIR/pem/kafka_ssl_config.py" << EOF
ssl_config = {
    'bootstrap.servers': '127.0.0.1:9094',
    'security.protocol': 'SSL',
    'ssl.ca.location': '$(pwd)/$BASE_DIR/pem/ca.pem',
    'ssl.certificate.location': '$(pwd)/$BASE_DIR/pem/client.pem',
    'ssl.key.location': '$(pwd)/$BASE_DIR/pem/client.key',
    'ssl.key.password': '$PASSWORD'
}
EOF

echo "[✓] Certificates created successfully with SAN!"
echo "[i] PEM files are in $(pwd)/$BASE_DIR/pem/"
echo "[i] Python SSL config file created at $(pwd)/$BASE_DIR/pem/kafka_ssl_config.py"
