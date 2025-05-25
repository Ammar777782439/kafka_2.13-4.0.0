# سكربتات إدارة Kafka KRaft مع دعم SSL

هذا المجلد يحتوي على سكربتات لتسهيل إدارة Kafka الذي يعمل بوضع KRaft مع دعم SSL.

## السكربتات المتوفرة

### 1. تشغيل Kafka (`start-kafka.sh`)

يستخدم لتشغيل Kafka مع تحديد ملف التكوين المناسب.

```bash
# جعل السكربت قابل للتنفيذ
chmod +x scripts/start-kafka.sh

# تشغيل Kafka باستخدام ملف التكوين server-1.properties
./scripts/start-kafka.sh 1
```

### 2. إيقاف Kafka (`stop-kafka.sh`)

يستخدم لإيقاف خدمة Kafka بأمان.

```bash
# جعل السكربت قابل للتنفيذ
chmod +x scripts/stop-kafka.sh

# إيقاف Kafka
./scripts/stop-kafka.sh
```

### 3. إدارة المواضيع (`manage-topics.sh`)

سكربت شامل لإدارة مواضيع Kafka مع دعم الاتصال العادي والاتصال المشفر (SSL).

```bash
# جعل السكربت قابل للتنفيذ
chmod +x scripts/manage-topics.sh

# عرض قائمة المواضيع
./scripts/manage-topics.sh list

# عرض قائمة المواضيع عبر SSL
./scripts/manage-topics.sh list-ssl

# إنشاء موضوع جديد (3 أقسام و 3 عوامل تكرار)
./scripts/manage-topics.sh create my-topic 3 3

# إنشاء موضوع جديد عبر SSL
./scripts/manage-topics.sh create-ssl my-ssl-topic 3 3

# عرض تفاصيل موضوع
./scripts/manage-topics.sh describe my-topic

# حذف موضوع
./scripts/manage-topics.sh delete my-topic
```

## جعل السكربتات قابلة للتنفيذ

يمكنك جعل جميع السكربتات قابلة للتنفيذ بأمر واحد:

```bash
chmod +x scripts/*.sh
```

## ملاحظات هامة

- تفترض هذه السكربتات أن Kafka مثبت في المسار `/home/ammar/kafka_2.13-4.0.0`
- تستخدم المنفذ 9092 للاتصال العادي والمنفذ 9094 للاتصال المشفر (SSL)
- تستخدم ملف `kafka_server.jaas` للمصادقة عند تشغيل Kafka
- تستخدم ملف `client-ssl.properties` للاتصال عبر SSL
