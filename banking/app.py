from flask import Flask, request, jsonify
from kafka import KafkaProducer, KafkaConsumer
from kafka.errors import KafkaError
import json
import os

app = Flask(__name__)

# Kafka Configuration
KAFKA_BROKER = os.getenv("b-1.bankingkafkacluster.0ctw8k.c18.kafka.us-east-1.amazonaws.com:9092,b-2.bankingkafkacluster.0ctw8k.c18.kafka.us-east-1.amazonaws.com
:9092")
KAFKA_TOPIC = "transactions"

# Initialize Kafka Producer
producer = KafkaProducer(
    bootstrap_servers=KAFKA_BROKER,
    value_serializer=lambda v: json.dumps(v).encode('utf-8')
)

# Function to check Kafka connection
def check_kafka_connection():
    try:
        # Trying to create a KafkaConsumer (a simple connection check)
        consumer = KafkaConsumer(bootstrap_servers=KAFKA_BROKER)
        consumer.close()
        return True
    except KafkaError as e:
        return False

@app.route('/transaction', methods=['POST'])
def create_transaction():
    try:
        data = request.get_json()
        required_fields = ["from_account", "to_account", "amount", "currency"]

        if not all(field in data for field in required_fields):
            return jsonify({"error": "Missing required fields"}), 400

        producer.send(KAFKA_TOPIC, data)
        producer.flush()

        return jsonify({"message": "Transaction sent successfully", "transaction": data}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/health', methods=['GET'])
def health_check():
    # Checking if Kafka is connected
    if check_kafka_connection():
        return jsonify({"status": "API is running", "kafka": "Connected"}), 200
    else:
        return jsonify({"status": "API is running", "kafka": "Disconnected"}), 500

if __name__ == '__main__':
    # Run the Flask app with production settings
    app.run(host='0.0.0.0', port=5000, debug=False)
