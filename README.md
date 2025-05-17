# Apache Kafka Setup and SSL Configuration Guide

This guide explains how to install and run Apache Kafka with SSL support for secure encrypted communication.

## Prerequisites

- Linux OS or Windows with WSL
- Java 11 or higher
- At least 1 GB of free disk space
- Python 3.x (for clients)
- `confluent-kafka` Python library (for clients)

## 1. Kafka Installation

### Download and Extract Kafka

```bash
# Download Kafka
wget https://downloads.apache.org/kafka/4.0.0/kafka_2.13-4.0.0.tgz

# Extract the archive
tar -xzf kafka_2.13-4.0.0.tgz

# Navigate to the Kafka directory
cd kafka_2.13-4.0.0
```

## 2. SSL Certificate Setup

### Run the Certificate Generation Script

```bash
# Navigate to the config directory
cd config/kraft

# Edit the certfcat.sh script to set your Kafka server's IP address in SAN_HOSTS
nano certfcat.sh

# Run the certificate script
./certfcat.sh
```

> **Important:** Make sure the `SAN_HOSTS` variable in `certfcat.sh` includes your IP address.
> Example: `SAN_HOSTS="dns:localhost,ip:192.168.1.100"`

### Certificate Locations

Certificates will be generated in these directories:

- `ssl/ca`: CA certificates
- `ssl/server`: Server certificates
- `ssl/client`: Client certificates
- `ssl/pem`: PEM-formatted certificates (for Python use)

## 3. Kafka Configuration and Startup

### Format Kafka Storage

```bash
./bin/kafka-storage.sh format -t $(cat config/kraft/server-1.properties | grep node.id | cut -d= -f2)-$(date +%s) -c ./config/kraft/server-1.properties
```

### Start Kafka Server

```bash
bin/kafka-server-start.sh config/kraft/server-1.properties
```

### Check Kafka Status

```bash
# Kafka processes
ps aux | grep kafka

# Kafka logs
tail -f logs/server.log
```

## 4. Working with Kafka Topics

### Create a Topic

```bash
./bin/kafka-topics.sh --create --topic ssl-test-topic --bootstrap-server localhost:9094 --command-config ./config/kraft/client-ssl.properties --partitions 3 --replication-factor 1
```

### List Topics

```bash
./bin/kafka-topics.sh --list --bootstrap-server localhost:9094 --command-config ./config/kraft/client-ssl.properties
```

### Send Messages to Topic

```bash
./bin/kafka-console-producer.sh --topic ssl-test-topic --bootstrap-server localhost:9094 --producer.config ./config/kraft/client-ssl.properties
```

### Consume Messages from Topic

```bash
./bin/kafka-console-consumer.sh --topic ssl-test-topic --from-beginning --bootstrap-server localhost:9094 --consumer.config ./config/kraft/client-ssl.properties
```

## 5. Using Kafka with Python

### Copy PEM Certificates to Python Project

```bash
cp config/kraft/ssl/pem/ca.pem /path/to/python/project/
cp config/kraft/ssl/pem/client.pem /path/to/python/project/
cp config/kraft/ssl/pem/client.key /path/to/python/project/
cp config/kraft/ssl/pem/kafka_ssl_config.py /path/to/python/project/
```

### Python Producer Example

```python
from confluent_kafka import Producer
from kafka_ssl_config import ssl_config

producer = Producer(ssl_config)

def delivery_report(err, msg):
    if err is not None:
        print(f"Delivery failed: {err}")
    else:
        print(f"Message delivered to {msg.topic()} [{msg.partition()}]")

producer.produce('ssl-test-topic', key='key', value='message value', callback=delivery_report)
producer.flush()
```

### Python Consumer Example

```python
from confluent_kafka import Consumer
from kafka_ssl_config import ssl_config

consumer_config = ssl_config.copy()
consumer_config.update({
    'group.id': 'my-group',
    'auto.offset.reset': 'earliest'
})

consumer = Consumer(consumer_config)
consumer.subscribe(['ssl-test-topic'])

try:
    while True:
        msg = consumer.poll(1.0)
        if msg is None:
            continue
        if msg.error():
            print(f"Error: {msg.error()}")
            continue
        print(f"Received message: {msg.value().decode('utf-8')}")
except KeyboardInterrupt:
    pass
finally:
    consumer.close()
```

## 6. Using Kafka on Windows

### Copy PEM Certificates to Windows

```bash
cp config/kraft/ssl/pem/ca.pem /mnt/c/Users/YourUsername/path/to/project/
cp config/kraft/ssl/pem/client.pem /mnt/c/Users/YourUsername/path/to/project/
cp config/kraft/ssl/pem/client.key /mnt/c/Users/YourUsername/path/to/project/
cp config/kraft/ssl/pem/kafka_ssl_config_windows.py /mnt/c/Users/YourUsername/path/to/project/
```

### Update Windows Paths

Edit `kafka_ssl_config_windows.py` to use Windows paths:

```python
ssl_config = {
    'bootstrap.servers': 'YOUR_IP:9094',
    'security.protocol': 'SSL',
    'ssl.ca.location': 'C:/path/to/ca.pem',
    'ssl.certificate.location': 'C:/path/to/client.pem',
    'ssl.key.location': 'C:/path/to/client.key',
    'ssl.key.password': 'kafkasslpass'
}
```

## 7. Stop Kafka Server

```bash
./bin/kafka-server-stop.sh
```

## Troubleshooting

### Issue: Cannot connect via SSL

1. Check if Kafka is running:
   ```bash
   ps aux | grep kafka
   ```
2. Check Kafka logs:
   ```bash
   tail -f logs/server.log
   ```
3. Ensure port 9094 is open:
   ```bash
   netstat -tulpn | grep 9094
   ```
4. Check SSL config in `server-1.properties`

### Issue: SSL certificate error in Python

- Verify paths in the Python config file.
- Make sure the password in the config matches the one used during certificate creation.