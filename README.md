# kafka-setup

# Banking Transaction System with Apache Kafka on AWS

## Overview
This project sets up a **banking transaction system** on **AWS** using **Apache Kafka**, a **PostgreSQL database (RDS)**, a **Flask application**, and a **Kafka GUI**. The infrastructure is deployed using **Terraform** following best practices.

## Architecture
✅ **AWS MSK (Managed Kafka Service)** – Kafka cluster management  
✅ **Amazon RDS (PostgreSQL)** – Stores transaction data  
✅ **Amazon EC2 (Flask API & Consumer Service)** – Runs the transaction app  
✅ **Kafka GUI (AKHQ)** – Provides a UI for managing Kafka topics  
✅ **Terraform** – Automates the deployment  

---

## 1️⃣ Setup Kafka (AWS MSK)
### **Create an MSK Cluster**
1. Go to **AWS MSK** → Create a new cluster.
2. Select **Provisioned** mode.
3. Choose **3 brokers** across **3 AZs**.
4. Set up **authentication** (IAM, SASL/SCRAM, or TLS).
5. Retrieve the **bootstrap server URL** after deployment.

---

## 2️⃣ Setup PostgreSQL (Amazon RDS)
### **Create an RDS PostgreSQL Instance**
1. Select **PostgreSQL**.
2. Choose an **instance size** (e.g., `db.t3.micro`).
3. Enable **public access** (for testing, restrict later).
4. Create a database named `transactions_db`.

### **Create Transactions Table**
```sql
CREATE TABLE transactions (
    id SERIAL PRIMARY KEY,
    from_account VARCHAR(50),
    to_account VARCHAR(50),
    amount DECIMAL(10,2),
    currency VARCHAR(10),
    timestamp TIMESTAMP DEFAULT NOW()
);
```

---

## 3️⃣ Deploy Application (Flask API on EC2)
### **Install Dependencies on EC2**
```sh
sudo yum update -y
sudo yum install python3 pip -y
pip install flask kafka-python psycopg2-binary
```

### **Deploy `app.py` (Flask API)**
```python
from flask import Flask, request, jsonify
from kafka import KafkaProducer
import json

app = Flask(__name__)

producer = KafkaProducer(
    bootstrap_servers='<MSK-BOOTSTRAP-SERVER>',
    value_serializer=lambda v: json.dumps(v).encode('utf-8')
)

@app.route('/transaction', methods=['POST'])
def send_transaction():
    data = request.json
    producer.send('transactions', data)
    return jsonify({"message": "Transaction sent!"}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
```

### **Test API**
```sh
curl -X POST http://<EC2-Public-IP>:5000/transaction -H "Content-Type: application/json" -d '{"from_account": "A123", "to_account": "B456", "amount": 500, "currency": "USD"}'
```

---

## 4️⃣ Setup Kafka Consumer
### **Deploy `transaction_consumer.py`**
```python
from kafka import KafkaConsumer
import psycopg2
import json

consumer = KafkaConsumer(
    'transactions',
    bootstrap_servers='<MSK-BOOTSTRAP-SERVER>',
    value_deserializer=lambda v: json.loads(v.decode('utf-8'))
)

conn = psycopg2.connect(
    dbname="transactions_db",
    user="kafka_user",
    password="kafka_pass",
    host="<RDS-ENDPOINT>"
)
cursor = conn.cursor()

for message in consumer:
    transaction = message.value
    cursor.execute(
        "INSERT INTO transactions (from_account, to_account, amount, currency) VALUES (%s, %s, %s, %s)",
        (transaction['from_account'], transaction['to_account'], transaction['amount'], transaction['currency'])
    )
    conn.commit()
```

---

## 5️⃣ Install Kafka GUI (AKHQ)
### **Deploy AKHQ on EC2**
```sh
docker run -d -p 8080:8080 \
    -e AKHQ_CONFIGURATION='
    akhq:
      connections:
        kafka-cluster:
          properties:
            bootstrap.servers: "<MSK-BOOTSTRAP-SERVER>"
    ' tchiotludo/akhq
```

### **Access Kafka UI:**  
Open `http://<EC2-Public-IP>:8080` in your browser.

---

## 6️⃣ Automate Deployment Using Terraform
### **Deploy the Entire Infrastructure with Terraform**
```sh
git clone https://github.com/OBEDPoP/kafka-setup.git
cd kafka-banking-terraform
terraform init
terraform apply -auto-approve
```

### **What Terraform Deploys:**
- **MSK Kafka Cluster**
- **PostgreSQL RDS Database**
- **EC2 Instance** (Flask API & Kafka Consumer)
- **AKHQ Kafka GUI**

### **Terraform Outputs:**
```sh
Outputs:
kafka_bootstrap_servers = "<MSK-BOOTSTRAP-SERVER>"
ec2_public_ip = "<EC2-PUBLIC-IP>"
rds_endpoint = "<RDS-ENDPOINT>"
```

---



