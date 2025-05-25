#!/bin/bash

# Script to start all Kafka brokers (1, 2, 3)

KAFKA_HOME="/home/ammar/kafka_2.13-4.0.0"
START_SCRIPT="$KAFKA_HOME/scripts/start-kafka.sh"
STOP_SCRIPT="$KAFKA_HOME/scripts/stop-kafka.sh"

echo "Starting all Kafka brokers..."

# Check if scripts exist
if [ ! -f "$START_SCRIPT" ]; then
  echo "Error: Start script $START_SCRIPT does not exist"
  exit 1
fi

# First stop any running Kafka instances
if [ -f "$STOP_SCRIPT" ]; then
  echo "Stopping any running Kafka instances..."
  $STOP_SCRIPT
  sleep 5
else
  echo "Warning: Stop script not found, attempting to kill Kafka processes manually"
  pkill -f "kafka\.Kafka" || true
  sleep 5
fi

# Start broker 1
echo "Starting broker 1..."
$START_SCRIPT 1
sleep 5

# Start broker 2
echo "Starting broker 2..."
$START_SCRIPT 2
sleep 5

# Start broker 3
echo "Starting broker 3..."
$START_SCRIPT 3

echo "All brokers started. To check status use: ps aux | grep kafka"
