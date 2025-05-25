#!/bin/bash

# Script to start Kafka with KRaft and SSL support

# Check if node ID is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <node_id>"
  echo "Example: $0 1"
  exit 1
fi

NODE_ID=$1
KAFKA_HOME="/home/ammar/kafka_2.13-4.0.0"
CONFIG_FILE="$KAFKA_HOME/config/kraft/server-$NODE_ID.properties"

# Check if configuration file exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file $CONFIG_FILE does not exist"
  exit 1
fi

# Check if the metadata directory is initialized
LOG_DIRS=$(grep "log.dirs" "$CONFIG_FILE" | cut -d= -f2)
if [ ! -f "$LOG_DIRS/meta.properties" ]; then
  echo "Warning: Metadata directory not initialized. Run initialize-kafka.sh first."
  echo "Continuing anyway..."
fi

# Stop Kafka if it's running
echo "Checking Kafka status..."
if pgrep -f "kafka\.Kafka.*server-$NODE_ID\.properties" > /dev/null; then
  echo "Kafka broker $NODE_ID is already running. Stopping..."
  $KAFKA_HOME/bin/kafka-server-stop.sh
  sleep 5
  
  # Force kill if still running
  if pgrep -f "kafka\.Kafka.*server-$NODE_ID\.properties" > /dev/null; then
    echo "Kafka still running. Force killing..."
    pkill -f "kafka\.Kafka.*server-$NODE_ID\.properties"
    sleep 2
  fi
fi

# Start Kafka with JAAS authentication support
echo "Starting Kafka with configuration file $CONFIG_FILE..."

# Check if kafka_server.jaas exists, otherwise create a default one
JAAS_FILE="$KAFKA_HOME/config/kraft/kafka_server.jaas"
if [ ! -f "$JAAS_FILE" ]; then
  echo "JAAS file not found, creating a default one at $JAAS_FILE"
  mkdir -p "$(dirname "$JAAS_FILE")"
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

# Verify SSL certificates
SSL_KEYSTORE=$(grep "ssl.keystore.location" "$CONFIG_FILE" | cut -d= -f2)
SSL_TRUSTSTORE=$(grep "ssl.truststore.location" "$CONFIG_FILE" | cut -d= -f2)

if [ ! -f "$SSL_KEYSTORE" ]; then
  echo "Warning: SSL keystore not found at $SSL_KEYSTORE"
fi

if [ ! -f "$SSL_TRUSTSTORE" ]; then
  echo "Warning: SSL truststore not found at $SSL_TRUSTSTORE"
fi

# Set JVM options for better debugging
KAFKA_JVM_PERFORMANCE_OPTS="-Xmx1G -Xms1G"
KAFKA_JMX_OPTS="-Dcom.sun.management.jmxremote=true -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false"
KAFKA_LOG4J_OPTS="-Dlog4j2.configurationFile=$KAFKA_HOME/config/log4j2.yaml"
KAFKA_OPTS="-Djava.security.auth.login.config=$JAAS_FILE $KAFKA_JMX_OPTS $KAFKA_LOG4J_OPTS"

echo "Starting Kafka with the following options:"
echo "JAAS file: $JAAS_FILE"
echo "Config file: $CONFIG_FILE"
echo "SSL keystore: $SSL_KEYSTORE"
echo "SSL truststore: $SSL_TRUSTSTORE"

# Start Kafka in daemon mode
export KAFKA_OPTS
export KAFKA_JVM_PERFORMANCE_OPTS
$KAFKA_HOME/bin/kafka-server-start.sh -daemon $CONFIG_FILE

# Verify Kafka started successfully
sleep 5
if pgrep -f "kafka\.Kafka.*server-$NODE_ID\.properties" > /dev/null; then
  echo "Kafka broker $NODE_ID started successfully."
  echo "To check status use: ps aux | grep kafka"
  echo "To check logs use: tail -f $KAFKA_HOME/logs/server.log"
else
  echo "Error: Kafka broker $NODE_ID failed to start. Check logs for details."
  echo "Log file: $KAFKA_HOME/logs/server.log"
fi
