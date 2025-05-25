#!/bin/bash

# Script to manage Kafka topics

KAFKA_HOME="/home/ammar/kafka_2.13-4.0.0"
HOST="172.23.38.230"
PLAIN_PORT="9092"
SSL_PORT="9094"
CLIENT_SSL_CONFIG="$KAFKA_HOME/config/kraft/client-ssl.properties"

function show_help {
  echo "Usage: $0 <command> [options]"
  echo ""
  echo "Available commands:"
  echo "  list                   List topics"
  echo "  list-ssl               List topics via SSL"
  echo "  create <name> [p] [r]  Create a new topic (p=partitions, r=replication factor)"
  echo "  create-ssl <name> [p] [r] Create a new topic via SSL"
  echo "  describe <name>        Show topic details"
  echo "  describe-ssl <name>    Show topic details via SSL"
  echo "  delete <name>          Delete a topic"
  echo "  delete-ssl <name>      Delete a topic via SSL"
  echo ""
  echo "Examples:"
  echo "  $0 list"
  echo "  $0 create my-topic 3 3"
  echo "  $0 describe-ssl my-topic"
  echo "  $0 delete my-topic"
}

if [ $# -lt 1 ]; then
  show_help
  exit 1
fi

COMMAND=$1
shift

case "$COMMAND" in
  list)
    echo "Listing topics..."
    echo "Connecting to $HOST:$PLAIN_PORT (timeout: 10s)..."
    timeout 10 $KAFKA_HOME/bin/kafka-topics.sh --list --bootstrap-server $HOST:$PLAIN_PORT
    if [ $? -eq 124 ]; then
      echo "Error: Connection timed out. Make sure Kafka is running and the port is correct."
      exit 1
    fi
    ;;
    
  list-ssl)
    echo "Listing topics via SSL..."
    echo "Connecting to $HOST:$SSL_PORT (timeout: 10s)..."
    # Check if the JAAS file path in client-ssl.properties needs to be updated
    if grep -q "jaas.conf" $CLIENT_SSL_CONFIG 2>/dev/null; then
      echo "Note: Using JAAS configuration from client-ssl.properties"
    else
      echo "Note: Using default JAAS configuration"
    fi
    
    timeout 10 $KAFKA_HOME/bin/kafka-topics.sh --list --bootstrap-server $HOST:$SSL_PORT --command-config $CLIENT_SSL_CONFIG
    if [ $? -eq 124 ]; then
      echo "Error: SSL connection timed out. Make sure Kafka is running with SSL enabled and certificates are correct."
      exit 1
    fi
    ;;
    
  create)
    if [ $# -lt 1 ]; then
      echo "Error: Topic name must be specified"
      show_help
      exit 1
    fi
    
    TOPIC_NAME=$1
    PARTITIONS=${2:-3}
    REPLICATION=${3:-3}
    
    echo "Creating topic $TOPIC_NAME with $PARTITIONS partitions and $REPLICATION replication factor..."
    $KAFKA_HOME/bin/kafka-topics.sh --create --topic $TOPIC_NAME \
      --bootstrap-server $HOST:$PLAIN_PORT \
      --partitions $PARTITIONS \
      --replication-factor $REPLICATION
    ;;
    
  create-ssl)
    if [ $# -lt 1 ]; then
      echo "Error: Topic name must be specified"
      show_help
      exit 1
    fi
    
    TOPIC_NAME=$1
    PARTITIONS=${2:-3}
    REPLICATION=${3:-3}
    
    echo "Creating topic $TOPIC_NAME via SSL with $PARTITIONS partitions and $REPLICATION replication factor..."
    $KAFKA_HOME/bin/kafka-topics.sh --create --topic $TOPIC_NAME \
      --bootstrap-server $HOST:$SSL_PORT \
      --command-config $CLIENT_SSL_CONFIG \
      --partitions $PARTITIONS \
      --replication-factor $REPLICATION
    ;;
    
  describe)
    if [ $# -lt 1 ]; then
      echo "Error: Topic name must be specified"
      show_help
      exit 1
    fi
    
    TOPIC_NAME=$1
    echo "Describing topic $TOPIC_NAME..."
    $KAFKA_HOME/bin/kafka-topics.sh --describe --topic $TOPIC_NAME \
      --bootstrap-server $HOST:$PLAIN_PORT
    ;;
    
  describe-ssl)
    if [ $# -lt 1 ]; then
      echo "Error: Topic name must be specified"
      show_help
      exit 1
    fi
    
    TOPIC_NAME=$1
    echo "Describing topic $TOPIC_NAME via SSL..."
    $KAFKA_HOME/bin/kafka-topics.sh --describe --topic $TOPIC_NAME \
      --bootstrap-server $HOST:$SSL_PORT \
      --command-config $CLIENT_SSL_CONFIG
    ;;
    
  delete)
    if [ $# -lt 1 ]; then
      echo "Error: Topic name must be specified"
      show_help
      exit 1
    fi
    
    TOPIC_NAME=$1
    echo "Deleting topic $TOPIC_NAME..."
    $KAFKA_HOME/bin/kafka-topics.sh --delete --topic $TOPIC_NAME \
      --bootstrap-server $HOST:$PLAIN_PORT
    ;;
    
  delete-ssl)
    if [ $# -lt 1 ]; then
      echo "Error: Topic name must be specified"
      show_help
      exit 1
    fi
    
    TOPIC_NAME=$1
    echo "Deleting topic $TOPIC_NAME via SSL..."
    $KAFKA_HOME/bin/kafka-topics.sh --delete --topic $TOPIC_NAME \
      --bootstrap-server $HOST:$SSL_PORT \
      --command-config $CLIENT_SSL_CONFIG
    ;;
    
  *)
    echo "Error: Unknown command: $COMMAND"
    show_help
    exit 1
    ;;
esac
