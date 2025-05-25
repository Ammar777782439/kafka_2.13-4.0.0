#!/bin/bash

# Script to stop all Kafka brokers

KAFKA_HOME="/home/ammar/kafka_2.13-4.0.0"
SCRIPT_PATH="$KAFKA_HOME/scripts/stop-kafka.sh"

echo "Stopping all Kafka brokers..."

# Check if stop-kafka.sh script exists
if [ ! -f "$SCRIPT_PATH" ]; then
  echo "Error: Stop script $SCRIPT_PATH does not exist"
  exit 1
fi

# Stop all Kafka processes
$SCRIPT_PATH

# Ensure all processes are stopped
if pgrep -f "kafka\.Kafka" > /dev/null; then
  echo "Warning: Some Kafka processes are still running. Trying to force stop them..."
  pkill -f "kafka\.Kafka"
  sleep 3
  
  if pgrep -f "kafka\.Kafka" > /dev/null; then
    echo "Error: Failed to stop some Kafka processes"
  else
    echo "All Kafka processes successfully stopped"
  fi
else
  echo "All Kafka brokers successfully stopped"
fi
