#!/bin/bash

# Script to initialize Kafka in KRaft mode
# This script should be run only once before starting Kafka for the first time

KAFKA_HOME="/home/ammar/kafka_2.13-4.0.0"
CLUSTER_ID=$(${KAFKA_HOME}/bin/kafka-storage.sh random-uuid)
LOG_DIRS_1="/home/ammar/kafka_data/broker1_4.0.0"
LOG_DIRS_2="/home/ammar/kafka_data/broker2_4.0.0"
LOG_DIRS_3="/home/ammar/kafka_data/broker3_4.0.0"
SERVER_PROPS_1="${KAFKA_HOME}/config/kraft/server-1.properties"
SERVER_PROPS_2="${KAFKA_HOME}/config/kraft/server-2.properties"
SERVER_PROPS_3="${KAFKA_HOME}/config/kraft/server-3.properties"

echo "Initializing Kafka in KRaft mode with cluster ID: ${CLUSTER_ID}"

# Create log directories if they don't exist
mkdir -p ${LOG_DIRS_1}
mkdir -p ${LOG_DIRS_2}
mkdir -p ${LOG_DIRS_3}

# Clean up existing metadata files if they exist
echo "Cleaning up existing metadata files..."
rm -f ${LOG_DIRS_1}/meta.properties
rm -f ${LOG_DIRS_2}/meta.properties
rm -f ${LOG_DIRS_3}/meta.properties

# Format the log directories for each broker
echo "Formatting log directory for broker 1..."
${KAFKA_HOME}/bin/kafka-storage.sh format -t ${CLUSTER_ID} -c ${SERVER_PROPS_1}

echo "Formatting log directory for broker 2..."
${KAFKA_HOME}/bin/kafka-storage.sh format -t ${CLUSTER_ID} -c ${SERVER_PROPS_2}

echo "Formatting log directory for broker 3..."
${KAFKA_HOME}/bin/kafka-storage.sh format -t ${CLUSTER_ID} -c ${SERVER_PROPS_3}

echo "Kafka initialization complete. You can now start the brokers using start-all-brokers.sh"
