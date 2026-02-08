#!/bin/bash
set -e

# ====== إعدادات هامة (عدلها حسب الملفات التي استستلمها) ======
PASSWORD="kafkasslpass"
BASE_DIR="./ssl"

# نضع أسماء الملفات التي استلمتها هنا بالضبط
RECEIVED_CERT="server.crt"       # ملف الشهادة
RECEIVED_KEY="server.key"        # ملف المفتاح الخاص (ضروري جداً)
# ==========================================================

echo "---[1] تنظيف الملفات القديمة (إذا وجدت) ---"
rm -f "$BASE_DIR/server/kafka.server.keystore.jks"
rm -f "$BASE_DIR/server/kafka.server.truststore.jks"
rm -f "$BASE_DIR/client/kafka.client.truststore.jks"
mkdir -p "$BASE_DIR/server" "$BASE_DIR/client" "$BASE_DIR/pem"

echo "---[2] دمج الشهادة والمفتاح في ملف PKCS12 ---"
# هذه الخطوة تدمج المفتاح والشهادة في علبة واحدة يفهمها كافكا
openssl pkcs12 -export \
  -in "$BASE_DIR/$RECEIVED_CERT" \
  -inkey "$BASE_DIR/$RECEIVED_KEY" \
  -out "$BASE_DIR/server/keystore.p12" \
  -name localhost \
  -passout pass:$PASSWORD

echo "---[3] تحويل PKCS12 إلى Java Keystore (JKS) ---"
keytool -importkeystore \
  -srckeystore "$BASE_DIR/server/keystore.p12" \
  -srcstoretype PKCS12 \
  -srcstorepass $PASSWORD \
  -destkeystore "$BASE_DIR/server/kafka.server.keystore.jks" \
  -deststorepass $PASSWORD \
  -noprompt

echo "---[4] إنشاء Truststore (لكي يثق الجميع بهذه الشهادة) ---"
# بما أنها غير موقعة، يجب إضافتها يدوياً للموثوقين
keytool -import \
  -file "$BASE_DIR/$RECEIVED_CERT" \
  -alias server-cert \
  -keystore "$BASE_DIR/client/kafka.client.truststore.jks" \
  -storepass $PASSWORD \
  -noprompt

# نسخ نفس التراست ستور للسيرفر أيضاً (للاتصال بين البروكرات)
cp "$BASE_DIR/client/kafka.client.truststore.jks" "$BASE_DIR/server/kafka.server.truststore.jks"

echo "---[5] تجهيز ملفات PEM للعملاء (Python/Go) ---"
# ننسخ الشهادة فقط للعملاء
cp "$BASE_DIR/$RECEIVED_CERT" "$BASE_DIR/pem/ca.pem"

echo "============================================="
echo "✅ تم الاستيراد بنجاح!"
echo "1. ملف الهوية: $BASE_DIR/server/kafka.server.keystore.jks"
echo "2. ملف الثقة (Java): $BASE_DIR/client/kafka.client.truststore.jks"
echo "3. ملف الثقة (Python): $BASE_DIR/pem/ca.pem"
echo "============================================="
