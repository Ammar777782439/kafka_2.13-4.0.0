# الدليل الشامل والنهائي لتثبيت وإعداد Apache Kafka 4.0.0 (KRaft Combined Node) - باللغة العربية

يقدم هذا المستند الدليل التشغيلي المتكامل لنشر **Apache Kafka 4.0.0** في وضع **العقدة المدمجة (Combined Node: Broker + Controller)** مع تفعيل أمان **SCRAM-SHA-512** للمصادقة وتشفير **SSL/TLS** للاتصالات الشبكية.

---

> [!NOTE]
> هذا الدليل مصمم للإصدار **Kafka 4.0.0** الذي يعتمد 100% على نظام **KRaft** بدون الحاجة مطلقاً لـ ZooKeeper.

---

## 📋 الفهرس
1. [المتطلبات الأساسية وتحسين النظام (Prerequisites & OS Tuning)](#1-المتطلبات-الأساسية-وتحسين-النظام)
2. [تثبيت Java 17 وباقة Kafka 4.0.0](#2-تثبيت-java-17-وباقة-kafka-400)
3. [إعداد شهادات التشفير SSL/TLS وشرحها برمجيين](#3-إعداد-شهادات-التشفير-ssltls-وشرحها-برمجياً)
4. [إنشاء ملف الهوية والمصادقة `jaas.conf`](#4-إنشاء-ملف-الهوية-والمصادقة-jaasconf)
5. [تكوين ملف إعدادات كافكا الرئيسي `server-0.properties`](#5-تكوين-ملف-إعدادات-كافكا-الرئيسي-server-0properties)
6. [تهيئة مساحة التخزين (KRaft Storage Formatting)](#6-تهيئة-مساحة-التخزين-kraft-storage-formatting)
7. [إعداد خدمة التشغيل التلقائي `systemd`](#7-إعداد-خدمة-التشغيل-التلقائي-systemd)
8. [إدارة المستخدمين وإعدادات العميل (Clients & User Management)](#8-إدارة-المستخدمين-وإعدادات-العميل)
9. [قائمة التحقق وحل المشاكل (Troubleshooting)](#9-قائمة-التحقق-وحل-المشاكل)

---

## 1. المتطلبات الأساسية وتحسين النظام

### أ. الذاكرة (RAM):
- ذاكرة النظام الأدنى الموصى بها: **16GB RAM** أو أكثر.
- ذاكرة الـ JVM للـ Java تكون ما بين **4GB إلى 8GB** لترك باقي الذاكرة لنظام التشغيل كـ **Linux Page Cache**.

### ب. ضبط حدود نظام التشغيل (OS Limits):
افتح ملف `/etc/security/limits.conf` على سيرفر Linux وأضف السطور التالية لضمان فتح عدد كافٍ من الأنساق والملفات:
```text
kafka  soft  nofile  100000
kafka  hard  nofile  100000
kafka  soft  nproc   65536
kafka  hard  nproc   65536
```

---

## 2. تثبيت Java 17 وباقة Kafka 4.0.0

```bash
# 1. تحديث حزم النظام وتثبيت OpenJDK 17
sudo apt update && sudo apt install -y openjdk-17-jdk

# 2. التحقق من تثبيت جافا
java -version

# 3. تحميل واستخراج Kafka 4.0.0 (مثال على المسار /opt/kafka)
sudo mkdir -p /opt/kafka
sudo tar -xzf kafka_2.13-4.0.0.tgz -C /opt/
sudo mv /opt/kafka_2.13-4.0.0/* /opt/kafka/
cd /opt/kafka
```

---

## 3. إعداد شهادات التشفير SSL/TLS وشرحها برمجياً

### الخيار (أ) - الموصى به للإنتاج: التوليد التلقائي الشامل من CA عبر `generate-kafka-certs.sh`
إذا كان يتوفر لديك فقط شهادة الـ CA ومفتاحها (`ca.crt` و `ca.key`)، فهذا هو السكربت الإنتاجي المعتمد لتوليد جميع شهادات السيرفر، العملاء، الـ JKS KeyStores، والـ TrustStores تلقائياً بضغطة زر واحدة:

#### الخطوات:
1. قم بفتح ملف الإعدادات `config.env` وتعديل مسارات الـ CA والـ IPs المطلوبة:
   ```properties
   CA_CERT=/etc/pki/ca.crt
   CA_KEY=/etc/pki/ca.key
   OUTPUT_DIR=/opt/kafka/certs
   SERVER_IP_1=192.168.168.25
   ```
2. قم بتشغيل السكربت التوليدي الإنتاجي:
   ```bash
   cd /opt/kafka/config/kraft
   bash generate-kafka-certs.sh
   ```
يقوم السكربت بالآتي تلقائياً:
- توليد `server.key` و `server.crt` وتوقيعها من الـ CA وإضافة الـ SAN IPs.
- توليد `client.key` و `client.crt` وتوقيعها من الـ CA.
- إنشاء `kafka.keystore.p12` و `kafka.keystore.jks` و `kafka.truststore.jks`.
- إنشاء ملف الإعدادات `client.properties` وملف البيان التوثيقي `manifest.json`.
- التحقق التلقائي من صحة سلسلة التشفير وقابلية الـ KeyStores للفتح في Java.

---

### الخيار (ب): إذا كانت البيئة لديها شهادات جاهزة لـ Java (JKS / PKCS12)
ضع ملفات الشهادات الجاهزة مباشرة في المجلد المخصص لها (مثلاً `/opt/kafka/config/kraft/ssl/server`):
- **`kafka.server.keystore.jks`**: يحتوي على مفتاح السيرفر وشهادة السيرفر.
- **`kafka.server.truststore.jks`**: يحتوي على شهادة المرجع المصدق (CA Truststore).

---

### الخيار (ج): إذا كانت لديك ملفات شهادات خام فقط للسيرفر (PEM / CRT / KEY)
في حال زودك فريق الأمان أو تم إصدار شهادات خام جاهزة للسيرفر والـ CA، يمكنك تشغيل سكربت التحويل السريع `convert_pem_to_jks.sh`:
```bash
cd /opt/kafka/config/kraft
bash convert_pem_to_jks.sh server.crt server.key ca.crt kafkasslpass ./ssl/server
```

#### 🔍 شرح باراميترات الخيارات من منظور مبرمج (Programmer's Perspective):

##### 1. أمر `openssl pkcs12 -export`:
> **الفكرة البرمجية:** بيئة Java لا تستطيع قراءة المفتاح الخاص والشهادة كملفات مستقيمة بشكل مباشر في كود التشفير، لذلك نستخدم هذا الأمر لدمج المفتاح الخاص والشهادة في ملف واحد يُسمى Bundle (صيغة PKCS12) مثل تجميع الكلاسات في ملف `.jar` واحد.

* `-in server.crt`: **(Public Key / Certificate)** مسار ملف الشهادة العامة للسيرفر التي يراها العميل عند الاتصال.
* `-inkey server.key`: **(Private Key)** مسار المفتاح الخاص السري الذي يُستخدم للتوقيع وتشفير البيانات (لا يُشارك مع أحد).
* `-out server.p12`: **(Output Bundle)** اسم ملف الحاوية المدمج النهائي المخرَج.
* `-name localhost`: **(Alias Variable)** اسم مستعار للمفتاح كـ (Key Identifier) لتستطيع جافا استدعائه بالاسم لاحقاً.
* `-CAfile ca.crt`: **(Chain of Trust)** مسار شهادة الجهة المصدرة (Root CA) لبناء سلسلة الثقة الكاملة.
* `-caname CARoot`: **(CA Alias)** اسم مستعار لشهادة الجهة المصدقة داخل الحاوية.
* `-passout pass:kafkasslpass`: **(Bundle Encryption Password)** كلمة السر المشفرة لحماية ملف الحاوية `server.p12`.

##### 2. أمر `keytool -importkeystore`:
> **الفكرة البرمجية:** تحويل الحاوية من صيغة Standard PKCS12 إلى صيغة Java KeyStore الخاصة ببيئة JVM لكي تتمكن مكتبات Java الشبكية من استهلاكها.

* `-destkeystore`: **(Target Path)** مسار واسم ملف الـ KeyStore النهائي المطلوب إنشاؤه للجافا.
* `-deststorepass` & `-destkeypass`: **(Access Control Passwords)** كلمات المرور لفتح وتفكيك الـ KeyStore والمفتاح داخل الجافا.
* `-srckeystore` & `-srcstoretype`: **(Source Parameters)** تحديد ملف المصدر ونوعه (`PKCS12`) المراد التحويل منه.

---

### الخيار (د): إذا كانت بيئة جديدة وتريد توليد شهادات تجريبية تلقائياً
يمكنك استخدام السكربت `certfcat.sh` مع التأكد من ضبط الـ IPs و Valid Days:
```bash
cd /opt/kafka/config/kraft
bash certfcat.sh
```

---

## 4. إنشاء ملف الهوية والمصادقة `jaas.conf`

أنشئ ملف المصادقة في المسار `/opt/kafka/config/jaas.conf`:

```bash
cat << 'EOF' > /opt/kafka/config/jaas.conf
KafkaServer {
    org.apache.kafka.common.security.scram.ScramLoginModule required
    username="controller"
    password="controller-password";
};
KafkaController {
    org.apache.kafka.common.security.scram.ScramLoginModule required
    username="controller"
    password="controller-password";
};
EOF
```

---

## 5. تكوين ملف إعدادات كافكا الرئيسي `server-0.properties`

قم بإنشاء أو تحديث الملف `/opt/kafka/config/kraft/server-0.properties`:

> [!IMPORTANT]
> استبدل `YOUR_SERVER_IP` بالـ IP الخاص بالسيرفر الحالي (مثال: `192.168.168.25`).

```properties
############################# KRaft & Role Settings #############################
# وضع العقدة المدمجة (Broker + Controller)
process.roles=broker,controller
node.id=0

# عنوان الـ Controller الداخلي
controller.quorum.voters=0@127.0.0.1:9093

############################# Listeners & Security #############################
# المنافذ المستمعة: 9094 للعملاء عبر SASL_SSL، و 9093 للتحكم الداخلي عبر CONTROLLER
listeners=SASL_SSL://0.0.0.0:9094,CONTROLLER://127.0.0.1:9093
advertised.listeners=SASL_SSL://YOUR_SERVER_IP:9094

inter.broker.listener.name=SASL_SSL
controller.listener.names=CONTROLLER

# خريطة بروتوكولات الأمان
listener.security.protocol.map=CONTROLLER:PLAINTEXT,SASL_SSL:SASL_SSL

############################# SSL Configuration #############################
ssl.keystore.location=/opt/kafka/config/kraft/ssl/server/kafka.server.keystore.jks
ssl.keystore.password=kafkasslpass
ssl.key.password=kafkasslpass
ssl.truststore.location=/opt/kafka/config/kraft/ssl/server/kafka.server.truststore.jks
ssl.truststore.password=kafkasslpass
ssl.client.auth=required
ssl.enabled.protocols=TLSv1.2,TLSv1.3

############################# SASL & SCRAM Configuration #############################
sasl.enabled.mechanisms=SCRAM-SHA-512
sasl.mechanism.inter.broker.protocol=SCRAM-SHA-512
sasl.mechanism.controller.protocol=SCRAM-SHA-512
controller.sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="controller" password="controller-password";

# Authorizer & Super Users
authorizer.class.name=org.apache.kafka.metadata.authorizer.StandardAuthorizer
allow.everyone.if.no.acl.found=true
super.users=User:admin;User:ANONYMOUS;User:controller

############################# Log Storage Basics #############################
log.dirs=/opt/kafka/logs/kafka-data-0
num.partitions=1
num.recovery.threads.per.data.dir=1

############################# Single Node Replication Settings #############################
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
default.replication.factor=1
min.insync.replicas=1

############################# Log Retention & Performance #############################
log.retention.hours=168
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000

num.network.threads=8
num.io.threads=16
socket.send.buffer.bytes=1048576
socket.receive.buffer.bytes=1048576
socket.request.max.bytes=104857600
```

---

## 6. تهيئة مساحة التخزين (KRaft Storage Formatting)

> [!CAUTION]
> أمر `format` يمسح بيانات المجلد المخزن، ويُنفذ مرة واحدة فقط عند تأسيس العنقود لأول مرة.

```bash
cd /opt/kafka

# 1. إزالة أي بيانات سابقة
rm -rf /opt/kafka/logs/kafka-data-0

# 2. توليد Cluster ID جديد (ملاحظة: الخيار في 4.0.0 هو random-uuid)
KAFKA_CLUSTER_ID=$(./bin/kafka-storage.sh random-uuid)
echo "Generated Cluster ID: $KAFKA_CLUSTER_ID"

# 3. تهيئة المجلد وتسجيل مستخدم SCRAM النظام
./bin/kafka-storage.sh format \
  --cluster-id $KAFKA_CLUSTER_ID \
  --config ./config/kraft/server-0.properties \
  --add-scram 'SCRAM-SHA-512=[name=controller,password=controller-password]'
```

---

## 7. إعداد خدمة التشغيل التلقائي `systemd`

قم بإنشاء الخدمة في `/etc/systemd/system/kafka.service`:

```ini
[Unit]
Description=Apache Kafka 4.0.0 Server (KRaft Combined Node)
After=network.target

[Service]
Type=simple
User=kafka
Group=kafka
Environment="KAFKA_OPTS=-Djava.security.auth.login.config=/opt/kafka/config/jaas.conf"
ExecStart=/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/kraft/server-0.properties
ExecStop=/opt/kafka/bin/kafka-server-stop.sh
Restart=always
RestartSec=10
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
```

تفعيل وتشغيل الخدمة:
```bash
sudo systemctl daemon-reload
sudo systemctl enable kafka
sudo systemctl start kafka
sudo systemctl status kafka
```

---

## 8. إدارة المستخدمين وإعدادات العميل

### أ. إعداد ملف العميل (`client-ssl.properties`):
```properties
security.protocol=SASL_SSL
bootstrap.servers=YOUR_SERVER_IP:9094
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="controller" password="controller-password";

ssl.keystore.location=/opt/kafka/config/kraft/ssl/client/kafka.client.keystore.jks
ssl.keystore.password=kafkasslpass
ssl.key.password=kafkasslpass

ssl.truststore.location=/opt/kafka/config/kraft/ssl/client/kafka.client.truststore.jks
ssl.truststore.password=kafkasslpass
```

### ب. إضافة مستخدم تطبيق جديد (مثال: المستخدم `app_user`):
```bash
/opt/kafka/bin/kafka-configs.sh --bootstrap-server YOUR_SERVER_IP:9094 \
  --command-config /opt/kafka/config/kraft/client-ssl.properties \
  --alter \
  --add-config 'SCRAM-SHA-512=[password=AppSecretPass123]' \
  --entity-type users --entity-name app_user
```

### ج. منح الصلاحيات الدقيقة للمستخدم عبر ACLs (بدون جعله Super User):
بناءً على مبدأ أقل الصلاحيات (Least Privilege)، يتم منح المستخدم العادي أذونات محددة للتوبيكات والـ Consumer Groups دون إضافته كـ Super User:

```bash
# 1. إعطاء المستخدم صلاحية الإرسال (Producer - Write & Describe) على توبيك معين
/opt/kafka/bin/kafka-acls.sh --bootstrap-server YOUR_SERVER_IP:9094 \
  --command-config /opt/kafka/config/kraft/client-ssl.properties \
  --add --allow-principal User:app_user \
  --operation Write --operation Describe \
  --topic my-topic

# 2. إعطاء المستخدم صلاحية القراءة (Consumer - Read & Describe) على التوبيك ومجموعة المستهلكين
/opt/kafka/bin/kafka-acls.sh --bootstrap-server YOUR_SERVER_IP:9094 \
  --command-config /opt/kafka/config/kraft/client-ssl.properties \
  --add --allow-principal User:app_user \
  --operation Read --operation Describe \
  --topic my-topic \
  --group my-group

# 3. عرض جميع أذونات الـ ACLs المسجلة في النظام
/opt/kafka/bin/kafka-acls.sh --bootstrap-server YOUR_SERVER_IP:9094 \
  --command-config /opt/kafka/config/kraft/client-ssl.properties \
  --list
```

---

## 9. قائمة التحقق وحل المشاكل

| المشكلة | السبب المحتمل | الحل |
| :--- | :--- | :--- |
| `java: not found` | عدم تثبيت Java 17 | `sudo apt install -y openjdk-17-jdk` |
| `invalid choice: 'random-cluster-id'` | استخدام أمر قديم | استخدم `random-uuid` في Kafka 4.0.0 |
| `SSLHandshakeException: certificate_expired` | شهادة SSL منتهية الصلاحية | تمديد أيام الصلاحية وإعادة توليد الشهادات |
| `CLUSTER_AUTHORIZATION_FAILED` | عدم إضافة `User:ANONYMOUS` في `super.users` عند استخدام CONTROLLER PLAINTEXT | إضافة `User:ANONYMOUS` لسطر `super.users` في `server-0.properties` |
| `Connection refused` على البورت 9094 | عنوان IP غير مطبق أو البورت مغلق بالـ Firewall | تأكد من `advertised.listeners` وسماح الـ Firewall للبورت 9094 |

---
**تم إعداد ودمج هذا المستند واختباره بنجاح على Apache Kafka 4.0.0.**
