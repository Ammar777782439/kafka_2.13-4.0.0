# Kafka KRaft Management Scripts with SSL Support

This directory contains scripts to manage Kafka with KRaft mode and SSL support.

## Available Scripts

### 1. Start Kafka (`start-kafka.sh`)

Used to start a single Kafka broker with the appropriate configuration.

```bash
# Make the script executable
chmod +x scripts/start-kafka.sh

# Start Kafka using server-1.properties configuration
./scripts/start-kafka.sh 1
```

### 2. Stop Kafka (`stop-kafka.sh`)

Used to safely stop the Kafka service.

```bash
# Make the script executable
chmod +x scripts/stop-kafka.sh

# Stop Kafka
./scripts/stop-kafka.sh
```

### 3. Start All Brokers (`start-all-brokers.sh`)

Script to start all three Kafka brokers at once.

```bash
# Make the script executable
chmod +x scripts/start-all-brokers.sh

# Start all brokers
./scripts/start-all-brokers.sh
```

### 4. Stop All Brokers (`stop-all-brokers.sh`)

Script to stop all Kafka brokers at once.

```bash
# Make the script executable
chmod +x scripts/stop-all-brokers.sh

# Stop all brokers
./scripts/stop-all-brokers.sh
```

### 5. Topic Management (`manage-topics.sh`)

Comprehensive script for managing Kafka topics with support for both regular and SSL connections.

```bash
# Make the script executable
chmod +x scripts/manage-topics.sh

# View available commands
./scripts/manage-topics.sh

# List topics
./scripts/manage-topics.sh list

# List topics via SSL
./scripts/manage-topics.sh list-ssl

# Create a new topic (3 partitions and 3 replication factor)
./scripts/manage-topics.sh create my-topic 3 3

# Create a new topic via SSL
./scripts/manage-topics.sh create-ssl my-ssl-topic 3 3

# Show topic details
./scripts/manage-topics.sh describe my-topic

# Delete a topic
./scripts/manage-topics.sh delete my-topic
```

## Important Notes

- These scripts assume Kafka is installed at `/home/ammar/kafka_2.13-4.0.0`
- Port 9092 is used for regular connections and port 9094 for SSL connections
- The `kafka_server.jaas` file is used for authentication when starting Kafka
- The `client-ssl.properties` file is used for SSL connections

## Making All Scripts Executable

You can make all scripts executable with a single command:

```bash
chmod +x scripts/*.sh
```
