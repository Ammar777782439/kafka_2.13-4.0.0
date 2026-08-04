# Comprehensive Production Deployment Guide: Apache Kafka 4.0.0 (KRaft Combined Node)

This document provides a step-by-step, production-ready operational guide for deploying **Apache Kafka 4.0.0** in **Combined Node mode (Broker + Controller on a single node)**, enabled with **SCRAM-SHA-512** SASL authentication and **SSL/TLS** network encryption.

---

> [!NOTE]
> This guide is specifically designed for **Kafka 4.0.0**, which operates 100% on **KRaft mode** with zero ZooKeeper dependency.

---

## 📋 Table of Contents
1. [Prerequisites & OS System Tuning](#1-prerequisites--os-system-tuning)
2. [Installing Java 17 & Kafka 4.0.0](#2-installing-java-17--kafka-400)
3. [SSL/TLS Certificate Setup & Developer Parameter Breakdown](#3-ssltls-certificate-setup--developer-parameter-breakdown)
4. [Creating the JAAS Authentication Configuration (`jaas.conf`)](#4-creating-the-jaas-authentication-configuration-jaasconf)
5. [Configuring Main Server Settings (`server-0.properties`)](#5-configuring-main-server-settings-server-0properties)
6. [KRaft Storage Initialization & Formatting](#6-kraft-storage-initialization--formatting)
7. [Systemd Service Setup (`kafka.service`)](#7-systemd-service-setup-kafkaservice)
8. [Client Configuration & SCRAM User Management](#8-client-configuration--scram-user-management)
9. [Troubleshooting & Verification Checklist](#9-troubleshooting--verification-checklist)

---

## 1. Prerequisites & OS System Tuning

### A. Memory Requirements (RAM):
- Minimum Recommended System RAM: **16 GB RAM** or higher.
- JVM Heap Size: Set between **4 GB and 8 GB** (`KAFKA_HEAP_OPTS="-Xms8g -Xmx8g"`), leaving the remaining memory for Linux **OS Page Cache** (which Kafka heavily relies on for high throughput).

### B. Operating System Limits (`limits.conf`):
Edit `/etc/security/limits.conf` on your Linux server and append the following lines:
```text
kafka  soft  nofile  100000
kafka  hard  nofile  100000
kafka  soft  nproc   65536
kafka  hard  nproc   65536
```

---

## 2. Installing Java 17 & Kafka 4.0.0

```bash
# 1. Update package repositories and install OpenJDK 17
sudo apt update && sudo apt install -y openjdk-17-jdk

# 2. Verify Java installation
java -version

# 3. Download and extract Apache Kafka 4.0.0 (Example deployment path: /opt/kafka)
sudo mkdir -p /opt/kafka
sudo tar -xzf kafka_2.13-4.0.0.tgz -C /opt/
sudo mv /opt/kafka_2.13-4.0.0/* /opt/kafka/
cd /opt/kafka
```

---

## 3. SSL/TLS Certificate Setup & Developer Parameter Breakdown

### Option (A): Existing Production Java KeyStores (JKS / PKCS12)
Place your existing Java KeyStore files in the designated directory (e.g., `/opt/kafka/config/kraft/ssl/server`):
- **`kafka.server.keystore.jks`**: Contains the server private key and public certificate.
- **`kafka.server.truststore.jks`**: Contains the Root CA certificate.

---

### Option (B): Raw Certificate Files (PEM / CRT / KEY)
If your DevOps/Security team provides raw PEM files (`ca.crt`, `server.crt`, `server.key`), convert them to Java KeyStore (`.jks`) format:

```bash
# 1. Bundle Public Certificate & Private Key into a PKCS12 container
openssl pkcs12 -export \
  -in server.crt \
  -inkey server.key \
  -out server.p12 \
  -name localhost \
  -CAfile ca.crt \
  -caname CARoot \
  -passout pass:kafkasslpass

# 2. Convert the PKCS12 bundle into kafka.server.keystore.jks
keytool -importkeystore \
  -deststorepass kafkasslpass \
  -destkeypass kafkasslpass \
  -destkeystore kafka.server.keystore.jks \
  -srckeystore server.p12 \
  -srcstoretype PKCS12 \
  -srcstorepass kafkasslpass \
  -alias localhost

# 3. Create kafka.server.truststore.jks and import the Root CA certificate
keytool -keystore kafka.server.truststore.jks \
  -alias CARoot \
  -import \
  -file ca.crt \
  -storepass kafkasslpass \
  -noprompt
```

#### 🔍 Developer-Oriented Parameter Breakdown:

##### 1. Command `openssl pkcs12 -export`:
> **Developer Concept:** The Java JVM cannot consume standalone raw private key files directly at runtime in SSL channels. This command bundles the certificate, private key, and CA chain into a unified container (`PKCS12`), similar to bundling `.class` files into a single `.jar` artifact.

* `-in server.crt`: **(Public Certificate)** The public key certificate visible to clients during TLS handshake.
* `-inkey server.key`: **(Private Key)** The secret server private key used for signatures and decryption (never shared).
* `-out server.p12`: **(Output Bundle)** The target output PKCS12 file path.
* `-name localhost`: **(Alias Variable)** Key identifier alias used by Java to lookup the key entry inside the KeyStore.
* `-CAfile ca.crt`: **(Chain of Trust)** The root Certificate Authority file used to build the certificate chain.
* `-caname CARoot`: **(CA Alias)** Alias for the Root CA entry inside the PKCS12 bundle.
* `-passout pass:kafkasslpass`: **(Encryption Password)** Password used to encrypt the PKCS12 bundle.

##### 2. Command `keytool -importkeystore`:
> **Developer Concept:** Converts the standard PKCS12 container format into a native Java KeyStore (`.jks`) consumed by Java's `SSLEngine` network layer.

* `-destkeystore`: **(Target JKS File)** Path of the output `.jks` file consumed by Kafka.
* `-deststorepass` & `-destkeypass`: **(Access Passwords)** Credentials for Java to decrypt and unlock the KeyStore and private keys at runtime.
* `-srckeystore` & `-srcstoretype`: **(Source Parameters)** Specifies input PKCS12 container file and type.

---

### Option (C): Generating Fresh Self-Signed Certificates (Dev / Testing)
You can execute the included certificate script:
```bash
cd /opt/kafka/config/kraft
bash certfcat.sh
```

---

## 4. Creating the JAAS Authentication Configuration (`jaas.conf`)

Create the JAAS configuration file at `/opt/kafka/config/jaas.conf`:

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

## 5. Configuring Main Server Settings (`server-0.properties`)

Create or update `/opt/kafka/config/kraft/server-0.properties`:

> [!IMPORTANT]
> Replace `YOUR_SERVER_IP` with the actual public/private IP of your server (e.g., `192.168.168.25`).

```properties
############################# KRaft & Role Settings #############################
# Combined Node mode (Broker + Controller on 1 instance)
process.roles=broker,controller
node.id=0

# Internal Controller Quorum Address
controller.quorum.voters=0@127.0.0.1:9093

############################# Listeners & Security #############################
# Endpoints: 9094 for client traffic via SASL_SSL, 9093 for internal KRaft CONTROLLER
listeners=SASL_SSL://0.0.0.0:9094,CONTROLLER://127.0.0.1:9093
advertised.listeners=SASL_SSL://YOUR_SERVER_IP:9094

inter.broker.listener.name=SASL_SSL
controller.listener.names=CONTROLLER

# Listener Protocol Map
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
super.users=User:admin;User:ANONYMOUS;User:controller;User:ammar

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

## 6. KRaft Storage Initialization & Formatting

> [!CAUTION]
> The `format` command initializes the cluster metadata directory and must only be executed during initial setup.

```bash
cd /opt/kafka

# 1. Clean existing log directories (if any)
rm -rf /opt/kafka/logs/kafka-data-0

# 2. Generate a random Cluster UUID (Note: In Kafka 4.0.0, use 'random-uuid')
KAFKA_CLUSTER_ID=$(./bin/kafka-storage.sh random-uuid)
echo "Generated Cluster ID: $KAFKA_CLUSTER_ID"

# 3. Format metadata directory and register system SCRAM user
./bin/kafka-storage.sh format \
  --cluster-id $KAFKA_CLUSTER_ID \
  --config ./config/kraft/server-0.properties \
  --add-scram 'SCRAM-SHA-512=[name=controller,password=controller-password]'
```

---

## 7. Systemd Service Setup (`kafka.service`)

Create the systemd service file at `/etc/systemd/system/kafka.service`:

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

Enable and start the system service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable kafka
sudo systemctl start kafka
sudo systemctl status kafka
```

---

## 8. Client Configuration & SCRAM User Management

### A. Client Configuration File (`client-ssl.properties`):
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

### B. Adding Application Users (Example: `app_user`):
```bash
/opt/kafka/bin/kafka-configs.sh --bootstrap-server YOUR_SERVER_IP:9094 \
  --command-config /opt/kafka/config/kraft/client-ssl.properties \
  --alter \
  --add-config 'SCRAM-SHA-512=[password=AppSecretPass123]' \
  --entity-type users --entity-name app_user
```

### C. Granting Fine-Grained Permissions via ACLs (Without Making Them Super Users):
Following the Principle of Least Privilege, normal application users are granted explicit topic and consumer group permissions via Kafka ACLs rather than granting them full cluster administrator (Super User) access:

```bash
# 1. Grant Producer permissions (Write & Describe) on a specific topic
/opt/kafka/bin/kafka-acls.sh --bootstrap-server YOUR_SERVER_IP:9094 \
  --command-config /opt/kafka/config/kraft/client-ssl.properties \
  --add --allow-principal User:app_user \
  --operation Write --operation Describe \
  --topic my-topic

# 2. Grant Consumer permissions (Read & Describe) on a topic and Consumer Group
/opt/kafka/bin/kafka-acls.sh --bootstrap-server YOUR_SERVER_IP:9094 \
  --command-config /opt/kafka/config/kraft/client-ssl.properties \
  --add --allow-principal User:app_user \
  --operation Read --operation Describe \
  --topic my-topic \
  --group my-group

# 3. List all configured ACLs across the cluster
/opt/kafka/bin/kafka-acls.sh --bootstrap-server YOUR_SERVER_IP:9094 \
  --command-config /opt/kafka/config/kraft/client-ssl.properties \
  --list
```

---

## 9. Troubleshooting & Verification Checklist

| Symptom / Error | Root Cause | Resolution |
| :--- | :--- | :--- |
| `java: not found` | OpenJDK 17+ not installed | Run `sudo apt install -y openjdk-17-jdk` |
| `invalid choice: 'random-cluster-id'` | Legacy command flag in Kafka 4.0.0 | Use `random-uuid` subcommand in `kafka-storage.sh` |
| `SSLHandshakeException: certificate_expired` | Expired SSL certificates | Extend validity days in `certfcat.sh` (e.g. 3650) & re-generate JKS |
| `CLUSTER_AUTHORIZATION_FAILED` | `User:ANONYMOUS` missing from `super.users` for PLAINTEXT CONTROLLER | Add `User:ANONYMOUS` to `super.users` in `server-0.properties` |
| `Connection refused` on port 9094 | Incorrect IP in `advertised.listeners` or firewall blocked | Verify `advertised.listeners` IP matches host and allow port 9094 in firewall |

---
**Verified and validated for Apache Kafka 4.0.0.**
