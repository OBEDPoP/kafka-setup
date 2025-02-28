from kafka import KafkaConsumer
import psycopg2
import json
import os

# Kafka and Database Configuration
KAFKA_BROKER = os.getenv("KAFKA_BROKER", "${aws_msk_cluster.kafka.bootstrap_brokers}")
KAFKA_TOPIC = "transactions"

DB_HOST = os.getenv("DB_HOST", "${aws_db_instance.rds.endpoint}")
DB_NAME = "transactions_db"
DB_USER = "kafka_user"
DB_PASSWORD = "kafka_pass"

# Connect to PostgreSQL
conn = psycopg2.connect(
    dbname=DB_NAME,
    user=DB_USER,
    password=DB_PASSWORD,
    host=DB_HOST
)
cursor = conn.cursor()

# Initialize Kafka Consumer
consumer = KafkaConsumer(
    KAFKA_TOPIC,
    bootstrap_servers=KAFKA_BROKER,
    value_deserializer=lambda v: json.loads(v.decode('utf-8'))
)

# Process messages
for message in consumer:
    transaction = message.value
    try:
        cursor.execute(
            "INSERT INTO transactions (from_account, to_account, amount, currency) VALUES (%s, %s, %s, %s)",
            (transaction['from_account'], transaction['to_account'], transaction['amount'], transaction['currency'])
        )
        conn.commit()
        print(f"Stored transaction: {transaction}")
    except Exception as e:
        print(f"Error storing transaction: {str(e)}")

# Close DB connection (Runs infinitely unless interrupted)
cursor.close()
conn.close()
