#!/usr/bin/env bash
# ==============================================================================
# Script: convert_pem_to_jks.sh
# Description: Converts raw PEM certificates (server.crt, server.key, ca.crt)
#              into Java KeyStore (.jks) files for Apache Kafka.
# ==============================================================================
set -e

SERVER_CRT="${1:-server.crt}"
SERVER_KEY="${2:-server.key}"
CA_CRT="${3:-ca.crt}"
PASSWORD="${4:-kafkasslpass}"
OUTPUT_DIR="${5:-./ssl/server}"

if [ ! -f "$SERVER_CRT" ] || [ ! -f "$SERVER_KEY" ] || [ ! -f "$CA_CRT" ]; then
  echo "❌ Error: Missing required certificate files."
  echo "Usage: bash $0 <SERVER_CRT> <SERVER_KEY> <CA_CRT> [PASSWORD] [OUTPUT_DIR]"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "[+] Converting raw PEM (cert & key) to PKCS12 bundle..."
openssl pkcs12 -export \
  -in "$SERVER_CRT" \
  -inkey "$SERVER_KEY" \
  -out "$OUTPUT_DIR/server.p12" \
  -name localhost \
  -CAfile "$CA_CRT" \
  -caname CARoot \
  -passout "pass:$PASSWORD"

echo "[+] Importing PKCS12 into kafka.server.keystore.jks..."
keytool -importkeystore \
  -deststorepass "$PASSWORD" \
  -destkeypass "$PASSWORD" \
  -destkeystore "$OUTPUT_DIR/kafka.server.keystore.jks" \
  -srckeystore "$OUTPUT_DIR/server.p12" \
  -srcstoretype PKCS12 \
  -srcstorepass "$PASSWORD" \
  -alias localhost \
  -noprompt

echo "[+] Importing CA certificate into kafka.server.truststore.jks..."
keytool -keystore "$OUTPUT_DIR/kafka.server.truststore.jks" \
  -alias CARoot \
  -import \
  -file "$CA_CRT" \
  -storepass "$PASSWORD" \
  -noprompt

# Clean up temporary PKCS12 file
rm -f "$OUTPUT_DIR/server.p12"

echo "======================================================================"
echo "[✓] KeyStore and TrustStore generated successfully!"
echo "📍 KeyStore:   $OUTPUT_DIR/kafka.server.keystore.jks"
echo "📍 TrustStore: $OUTPUT_DIR/kafka.server.truststore.jks"
echo "======================================================================"
