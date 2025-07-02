#!/bin/bash
# Kafka Failure Test Script (Fixed Broker Count)
# Version 2.3 - Production Ready

KAFKA_HOME="/opt/kafka"
BIN_DIR="$KAFKA_HOME/bin"
CONFIG_DIR="$KAFKA_HOME/config/kraft"
LOG_DIR="$KAFKA_HOME/logs"
NODES=("server-0" "server-1" "server-2")
HEAP_OPTS="-Xmx2G -Xms2G"
JAAS_FILE="$CONFIG_DIR/kafka_server_jaas.conf"
BOOTSTRAP_SERVER="192.168.168.44:9094"
CLIENT_CONFIG="$CONFIG_DIR/client-sasl-ssl-admin.properties"
TEST_TOPIC="failure-test-topic-$(date +%s)"

# Function to select random broker
select_random_broker() {
    local rand_index=$((RANDOM % ${#NODES[@]}))
    echo ${NODES[$rand_index]}
}

# Function to check cluster health
check_cluster_health() {
    echo "Checking cluster health..."
    
    # 1. Check active brokers - FIXED COUNT METHOD
    echo "Running broker API versions check..."
    local active_brokers=$("$BIN_DIR"/kafka-broker-api-versions.sh \
        --bootstrap-server "$BOOTSTRAP_SERVER" \
        --command-config "$CLIENT_CONFIG" 2>/dev/null | grep -c "id: [0-9]")
    
    # 2. Check under-replicated partitions
    echo "Running topic health check..."
    local under_replicated=$("$BIN_DIR"/kafka-topics.sh --bootstrap-server "$BOOTSTRAP_SERVER" \
        --command-config "$CLIENT_CONFIG" --describe --under-replicated-partitions 2>/dev/null | wc -l)
    
    # 3. Check controller status
    echo "Running controller check..."
    local controller_id=$("$BIN_DIR"/kafka-metadata-quorum.sh describe \
        --bootstrap-server "$BOOTSTRAP_SERVER" 2>/dev/null | grep "Leader" | awk '{print $2}')
    
    echo "Active Brokers: $active_brokers"
    echo "Under-Replicated Partitions: $under_replicated"
    echo "Controller ID: $controller_id"
    
    if [ "$under_replicated" -eq 0 ] && [ "$active_brokers" -eq 3 ]; then
        echo "✅ Cluster is healthy"
        return 0
    else
        echo "⚠️ Cluster health issues detected"
        return 1
    fi
}


# Function to create test topic
create_test_topic() {
    echo "Creating test topic: $TEST_TOPIC"
    "$BIN_DIR"/kafka-topics.sh --create \
        --topic "$TEST_TOPIC" \
        --partitions 3 \
        --replication-factor 3 \
        --bootstrap-server "$BOOTSTRAP_SERVER" \
        --command-config "$CLIENT_CONFIG"
    
    # Produce test messages
    echo "Producing test messages..."
    for i in {1..10}; do
        echo "message-$i" | "$BIN_DIR"/kafka-console-producer.sh \
            --topic "$TEST_TOPIC" \
            --bootstrap-server "$BOOTSTRAP_SERVER" \
            --producer.config "$CLIENT_CONFIG"
    done
}

# Function to monitor consumer lag
monitor_consumer_lag() {
    local group_id="failure-test-group-$(date +%s)"
    
    # Start consumer in background
    "$BIN_DIR"/kafka-console-consumer.sh \
        --topic "$TEST_TOPIC" \
        --bootstrap-server "$BOOTSTRAP_SERVER" \
        --consumer.config "$CLIENT_CONFIG" \
        --group "$group_id" \
        --from-beginning > /dev/null &
    local consumer_pid=$!
    
    # Monitor lag
    echo "Monitoring consumer lag..."
    for i in {1..10}; do
        lag_info=$("$BIN_DIR"/kafka-consumer-groups.sh --bootstrap-server "$BOOTSTRAP_SERVER" \
            --command-config "$CLIENT_CONFIG" --describe --group "$group_id" 2>/dev/null)
        
        total_lag=0
        while read -r line; do
            if [[ $line == *"LAG"* ]]; then
                lag=$(echo "$line" | awk '{print $6}')
                total_lag=$((total_lag + lag))
            fi
        done <<< "$lag_info"
        
        echo "Consumer Lag: $total_lag messages"
        sleep 5
    done
    
    # Cleanup consumer
    kill "$consumer_pid" 2>/dev/null
    "$BIN_DIR"/kafka-consumer-groups.sh --bootstrap-server "$BOOTSTRAP_SERVER" \
        --command-config "$CLIENT_CONFIG" --delete --group "$group_id" 2>/dev/null
}

# Main failure test
echo "Starting Kafka Failure Test"
echo "=========================="

# Step 0: Verify client config exists
if [ ! -f "$CLIENT_CONFIG" ]; then
    echo "❌ Client config missing: $CLIENT_CONFIG"
    echo "Creating temporary client config..."
    
    cat > "$CLIENT_CONFIG" <<EOF
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required \
  username="admin" \
  password="admin-secret";
EOF
fi

# Step 1: Initial cluster health check
echo "Step 1: Checking initial cluster health"
if check_cluster_health; then
    echo "✅ Initial cluster health check passed"
else
    echo "❌ Initial cluster health check failed"
    
    # Run manual checks
    echo "Running manual health checks:"
    echo "1. Listing topics:"
    "$BIN_DIR"/kafka-topics.sh --list \
        --bootstrap-server "$BOOTSTRAP_SERVER" \
        --command-config "$CLIENT_CONFIG"
    
    echo "2. Broker API versions:"
    "$BIN_DIR"/kafka-broker-api-versions.sh \
        --bootstrap-server "$BOOTSTRAP_SERVER" \
        --command-config "$CLIENT_CONFIG"
    
    echo "3. Network connectivity:"
    nc -zv 192.168.168.44 9094
    
    exit 1
fi

# Step 2: Create test topic
echo "Step 2: Creating test topic"
create_test_topic

# Step 3: Select random broker to fail
broker_to_fail=$(select_random_broker)
broker_config="$CONFIG_DIR/$broker_to_fail.properties"
broker_id=$(grep "node.id" "$broker_config" | cut -d'=' -f2)

echo "Step 3: Selected broker $broker_id ($broker_to_fail) for failure simulation"

# Step 4: Get broker PID
broker_pid=$(ps aux | grep "$broker_config" | grep -v grep | awk '{print $2}')
if [ -z "$broker_pid" ]; then
    echo "❌ Broker $broker_id is not running"
    exit 1
fi

echo "Stopping broker $broker_id (PID: $broker_pid)..."
kill -STOP "$broker_pid"
echo "✅ Broker $broker_id stopped (SIGSTOP)"

# Step 5: Monitor cluster response
echo "Step 4: Monitoring cluster recovery (60 seconds)"
for i in {1..6}; do
    echo "--- Check $i ($((i*10)) seconds) ---"
    check_cluster_health
    sleep 10
done

# Step 6: Monitor consumer during failure
echo "Step 5: Monitoring consumer lag during failure"
monitor_consumer_lag

# Step 7: Restart the broker
echo "Step 6: Restarting broker $broker_id..."
kill -CONT "$broker_pid"
echo "✅ Broker $broker_id restarted (SIGCONT)"

# Step 8: Verify full recovery
echo "Step 7: Verifying full recovery (waiting 30 seconds)"
sleep 30
if check_cluster_health; then
    echo "✅ Cluster fully recovered"
else
    echo "❌ Cluster recovery failed"
fi

# Step 9: Cleanup
echo "Step 8: Cleaning up test resources"
echo "Deleting test topic..."
"$BIN_DIR"/kafka-topics.sh --delete \
    --topic "$TEST_TOPIC" \
    --bootstrap-server "$BOOTSTRAP_SERVER" \
    --command-config "$CLIENT_CONFIG" 2>/dev/null

echo "🔥 Failure test completed successfully!"
