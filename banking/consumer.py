from kafka import KafkaConsumer
import psycopg2
import json
import os

# Kafka and Database Configuration
KAFKA_BROKER = os.getenv("KAFKA_BROKER", "b-1.bankingkafkacluster.0ctw8k.c18.kafka.us-east-1.amazonaws.com:9092,b-2.bankingkafkacluster.0ctw8k.c18.kafka.us-east-1.amazonaws.com
:9092")
KAFKA_TOPIC = "transactions"

DB_HOST = os.getenv("DB_HOST", "banking-db.cr4gwkce03c9.us-east-1.rds.amazonaws.com:5432")
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

# Create transactions table if it does not exist
cursor.execute("""
    CREATE TABLE IF NOT EXISTS transactions (
        id SERIAL PRIMARY KEY,
        from_account VARCHAR(255),
        to_account VARCHAR(255),
        amount DECIMAL,
        currency VARCHAR(10),
        timestamp TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
    );
""")
conn.commit()

# Initialize Kafka Consumer
consumer = KafkaConsumer(
    KAFKA_TOPIC,
    bootstrap_servers=KAFKA_BROKER,
    value_deserializer=lambda v: json.loads(v.decode('utf-8')),
    group_id="transaction-consumer-group"  # Optional: manage consumer group offset
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
        # Optional: Implement retry logic here

# Close DB connection (Runs infinitely unless interrupted)
cursor.close()
conn.close()
