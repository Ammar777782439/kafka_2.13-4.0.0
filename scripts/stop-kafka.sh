#!/bin/bash

# Script to stop Kafka

KAFKA_HOME="/home/ammar/kafka_2.13-4.0.0"

echo "Stopping Kafka..."
$KAFKA_HOME/bin/kafka-server-stop.sh

echo "Waiting for processes to stop..."
sleep 5

# Check Kafka status
if pgrep -f "kafka\.Kafka" > /dev/null; then
  echo "Warning: Kafka is still running. You may need to stop it manually."
  echo "Use: pkill -f 'kafka\.Kafka'"
else
  echo "Kafka stopped successfully."
fi
