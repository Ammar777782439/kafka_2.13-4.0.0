#!/bin/bash

# Script to start a single Kafka broker with SSL for testing

KAFKA_HOME="/home/ammar/kafka_2.13-4.0.0"
NODE_ID=1
CONFIG_FILE="$KAFKA_HOME/config/kraft/server-$NODE_ID.properties"
JAAS_FILE="$KAFKA_HOME/config/kraft/kafka_server.jaas"

# Stop any running Kafka instances
echo "Stopping any running Kafka instances..."
$KAFKA_HOME/bin/kafka-server-stop.sh
sleep 5
pkill -f "kafka\.Kafka" || true
sleep 2

# Verify SSL certificates
echo "Verifying SSL certificates..."
if [ ! -f "$KAFKA_HOME/config/kraft/ssl/server/kafka.server.keystore.jks" ]; then
  echo "Error: Server keystore not found"
  exit 1
fi

if [ ! -f "$KAFKA_HOME/config/kraft/ssl/server/kafka.server.truststore.jks" ]; then
  echo "Error: Server truststore not found"
  exit 1
fi

# Create JAAS file if it doesn't exist
if [ ! -f "$JAAS_FILE" ]; then
  echo "Creating JAAS file at $JAAS_FILE"
  cat > "$JAAS_FILE" << EOF
KafkaServer {
  org.apache.kafka.common.security.plain.PlainLoginModule required
  username="admin"
  password="admin-secret"
  user_admin="admin-secret"
  user_client1="client1-secret";
};
EOF
  chmod 600 "$JAAS_FILE"
fi

# Start Kafka with verbose output
echo "Starting Kafka broker $NODE_ID with SSL enabled..."
echo "Using JAAS file: $JAAS_FILE"
echo "Using config file: $CONFIG_FILE"

# Run Kafka in foreground mode for debugging
KAFKA_OPTS="-Djava.security.auth.login.config=$JAAS_FILE" \
$KAFKA_HOME/bin/kafka-server-start.sh $CONFIG_FILE
