#!/bin/bash
set -e

# ====== إعدادات قابلة للتعديل ======
PASSWORD="kafkasslpass"
VALIDITY_DAYS=365
SAN_HOSTS="dns:localhost,ip:127.0.0.1"  # عدل هذا حسب شبكتك (مثلاً: dns:localhost,ip:192.168.1.100)
BASE_DIR="./ssl"
# ===================================

mkdir -p $BASE_DIR/ca $BASE_DIR/server $BASE_DIR/client

echo "[+] إنشاء شهادة CA"
openssl req -new -x509 \
  -keyout $BASE_DIR/ca/ca-key \
  -out $BASE_DIR/ca/ca-cert \
  -days $VALIDITY_DAYS \
  -subj "/CN=ca.kafka" \
  -passout pass:$PASSWORD

echo "[+] إنشاء keystore للسيرفر"
keytool -keystore $BASE_DIR/server/kafka.server.keystore.jks \
  -alias localhost \
  -validity $VALIDITY_DAYS \
  -genkey \
  -keyalg RSA \
  -storepass $PASSWORD \
  -keypass $PASSWORD \
  -dname "CN=kafka, OU=None, O=None, L=None, S=None, C=None" \
  -ext san=${SAN_HOSTS}

echo "[+] إنشاء keystore للعميل"
keytool -keystore $BASE_DIR/client/kafka.client.keystore.jks \
  -alias localhost \
  -validity $VALIDITY_DAYS \
  -genkey \
  -keyalg RSA \
  -storepass $PASSWORD \
  -keypass $PASSWORD \
  -dname "CN=client, OU=None, O=None, L=None, S=None, C=None"

echo "[+] توقيع شهادة السيرفر"
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

echo "[+] توقيع شهادة العميل"
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

echo "[+] استيراد شهادة CA في keystores"
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

echo "[+] استيراد الشهادات الموقعة في keystores"
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

echo "[+] إنشاء truststore واستيراد شهادة CA"
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

echo "[✓] تم إنشاء الشهادات بنجاح!"