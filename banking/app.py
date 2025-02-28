from flask import Flask, request, jsonify
from kafka import KafkaProducer
import json
import os

app = Flask(__name__)

# Kafka Configuration
KAFKA_BROKER = os.getenv("KAFKA_BROKER", "${aws_msk_cluster.kafka.bootstrap_brokers}")
KAFKA_TOPIC = "transactions"

# Initialize Kafka Producer
producer = KafkaProducer(
    bootstrap_servers=KAFKA_BROKER,
    value_serializer=lambda v: json.dumps(v).encode('utf-8')
)

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
    return jsonify({"status": "API is running"}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
