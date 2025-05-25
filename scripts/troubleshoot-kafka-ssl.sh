#!/bin/bash

# Script to troubleshoot Kafka SSL configuration

KAFKA_HOME="/home/ammar/kafka_2.13-4.0.0"
NODE_ID=1
CONFIG_FILE="$KAFKA_HOME/config/kraft/server-$NODE_ID.properties"
JAAS_FILE="$KAFKA_HOME/config/kraft/kafka_server.jaas"
SSL_SERVER_DIR="$KAFKA_HOME/config/kraft/ssl/server"
SSL_CLIENT_DIR="$KAFKA_HOME/config/kraft/ssl/client"

# Print system information
echo "==== System Information ===="
echo "Hostname: $(hostname)"
echo "IP Address: $(hostname -I)"
echo "Java Version: $(java -version 2>&1 | head -n 1)"
echo "Kafka Version: 2.13-4.0.0"
echo

# Stop any running Kafka instances
echo "==== Stopping any running Kafka instances ===="
$KAFKA_HOME/bin/kafka-server-stop.sh
sleep 5
pkill -f "kafka\.Kafka" || true
sleep 2
echo

# Verify SSL certificates
echo "==== Verifying SSL Certificates ===="
if [ -f "$SSL_SERVER_DIR/kafka.server.keystore.jks" ]; then
  echo "✓ Server keystore found: $SSL_SERVER_DIR/kafka.server.keystore.jks"
  # List certificates in keystore
  echo "   Certificates in server keystore:"
  keytool -list -v -keystore "$SSL_SERVER_DIR/kafka.server.keystore.jks" -storepass kafkasslpass | grep "Alias" | head -n 3
else
  echo "✗ Server keystore NOT found: $SSL_SERVER_DIR/kafka.server.keystore.jks"
fi

if [ -f "$SSL_SERVER_DIR/kafka.server.truststore.jks" ]; then
  echo "✓ Server truststore found: $SSL_SERVER_DIR/kafka.server.truststore.jks"
  # List certificates in truststore
  echo "   Certificates in server truststore:"
  keytool -list -v -keystore "$SSL_SERVER_DIR/kafka.server.truststore.jks" -storepass kafkasslpass | grep "Alias" | head -n 3
else
  echo "✗ Server truststore NOT found: $SSL_SERVER_DIR/kafka.server.truststore.jks"
fi

if [ -f "$SSL_CLIENT_DIR/kafka.client.keystore.jks" ]; then
  echo "✓ Client keystore found: $SSL_CLIENT_DIR/kafka.client.keystore.jks"
else
  echo "✗ Client keystore NOT found: $SSL_CLIENT_DIR/kafka.client.keystore.jks"
fi

if [ -f "$SSL_CLIENT_DIR/kafka.client.truststore.jks" ]; then
  echo "✓ Client truststore found: $SSL_CLIENT_DIR/kafka.client.truststore.jks"
else
  echo "✗ Client truststore NOT found: $SSL_CLIENT_DIR/kafka.client.truststore.jks"
fi
echo

# Check JAAS configuration
echo "==== Checking JAAS Configuration ===="
if [ -f "$JAAS_FILE" ]; then
  echo "✓ JAAS file found: $JAAS_FILE"
  echo "   JAAS file contents:"
  cat "$JAAS_FILE"
else
  echo "✗ JAAS file NOT found: $JAAS_FILE"
  echo "   Creating default JAAS file..."
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
  echo "   Created JAAS file with default configuration"
fi
echo

# Check server properties
echo "==== Checking Server Properties ===="
if [ -f "$CONFIG_FILE" ]; then
  echo "✓ Server properties file found: $CONFIG_FILE"
  echo "   SSL-related configuration:"
  grep -E "ssl\.|security\.|listeners|advertised" "$CONFIG_FILE"
else
  echo "✗ Server properties file NOT found: $CONFIG_FILE"
fi
echo

# Check client SSL properties
CLIENT_SSL_CONFIG="$KAFKA_HOME/config/kraft/client-ssl.properties"
echo "==== Checking Client SSL Properties ===="
if [ -f "$CLIENT_SSL_CONFIG" ]; then
  echo "✓ Client SSL properties file found: $CLIENT_SSL_CONFIG"
  echo "   Client SSL configuration:"
  cat "$CLIENT_SSL_CONFIG"
else
  echo "✗ Client SSL properties file NOT found: $CLIENT_SSL_CONFIG"
fi
echo

# Check network connectivity
echo "==== Checking Network Connectivity ===="
echo "Checking if ports are in use:"
netstat -tulpn 2>/dev/null | grep -E '9092|9094|9095|9097|9098|9100' || echo "No Kafka ports currently in use"
echo

echo "==== Troubleshooting Complete ===="
echo "Based on the above information, check for any issues with SSL certificates, JAAS configuration, or server properties."
echo "To start Kafka with SSL enabled, run: ./scripts/start-all-brokers.sh"
echo "To test SSL connectivity, run: ./scripts/manage-topics.sh list-ssl"
