#!/usr/bin/env bash

set -o nounset \
    -o verbose \
    -o xtrace

[ -f /etc/confluent/docker/apply-mesos-overrides ] && \
	. /etc/confluent/docker/apply-mesos-overrides

set -o errexit

echo "===> ENV Variables ..."
env | sort

echo "===> User"
id

echo "===> Configuring ..."
/etc/confluent/docker/configure

if [[ ! -v CONNECT_TASK_NAME ]]; then
   CONNECT_TASK_NAME=kafka-connect-task-name
fi

if [[ ! -v KAFKA_TOPICS ]]; then
   KAFKA_TOPICS=topictest
fi

if [[ ! -v KAFKA_TOPIC_REPLICATION_FACTOR ]]; then
   KAFKA_TOPIC_REPLICATION_FACTOR=1
fi

if [[ ! -v KAFKA_TOPIC_PARTITIONS ]]; then
   KAFKA_TOPIC_PARTITIONS=1
fi

if [[ ! -v KAFKA_TOPICS ]]; then
   KAFKA_TOPICS=topictest
fi

if [[ ! -v ELASTICSEARCH_HOSTS ]]; then
   ELASTICSEARCH_HOSTS=localhost:9300
fi

if [[ ! -v ELASTICSEARCH_CLUSTER_NAME ]]; then
   ELASTICSEARCH_CLUSTER_NAME=elasticsearch
fi

if [[ ! -v ELASTICSEARCH_INDEX ]]; then
   ELASTICSEARCH_INDEX=connect-index
fi

if [[ ! -v ELASTICSEARCH_MAPPING_TYPE ]]; then
   ELASTICSEARCH_MAPPING_TYPE=mapping-v1
fi

if [[ ! -v ELASTICSEARCH_BULK_SIZE ]]; then
   ELASTICSEARCH_BULK_SIZE=250
fi

if [[ ! -v ELASTICSEARCH_ID_FIELD ]]; then
   ELASTICSEARCH_ID_FIELD=id
fi

if [[ ! -v ELASTICSEARCH_ACTION_TYPE ]]; then
   ELASTICSEARCH_ACTION_TYPE=insert
fi

if [[ ! -v CONNECT_CONVERTER_ENABLE_SCHEMAS ]]; then
   CONNECT_CONVERTER_ENABLE_SCHEMAS=false
fi
if [[ ! -v CONNECT_INTERNAL_CONVERTER_ENABLE_SCHEMAS ]]; then
   CONNECT_INTERNAL_CONVERTER_ENABLE_SCHEMAS=false
fi

CONNECT_CONF_FILE=/etc/kafka-connect/kafka-connect.properties

if [[ "${CONNECT_CONVERTER_ENABLE_SCHEMAS}" == "false" ]]; then
  sed -i "s|key.converter.schemas.enable=true*|key.converter.schemas.enable=false|" $CONNECT_CONF_FILE
  sed -i "s|value.converter.schemas.enable=true*|value.converter.schemas.enable=false|" $CONNECT_CONF_FILE
  echo "key.converter.schemas.enable=false" >> $CONNECT_CONF_FILE
  echo "value.converter.schemas.enable=false" >> $CONNECT_CONF_FILE
fi

if [[ "${CONNECT_INTERNAL_CONVERTER_ENABLE_SCHEMAS}" == "false" ]]; then
  sed -i "s|internal.key.converter.schemas.enable=true*|internal.key.converter.schemas.enable=false|" $CONNECT_CONF_FILE
  sed -i "s|internal.value.converter.schemas.enable=true*|internal.value.converter.schemas.enable=false|" $CONNECT_CONF_FILE
  echo "internal.key.converter.schemas.enable=false" >> $CONNECT_CONF_FILE
  echo "internal.value.converter.schemas.enable=false" >> $CONNECT_CONF_FILE
fi

echo "===> Running preflight checks ... "
/etc/confluent/docker/ensure

echo "===> Creating topics in Kafka"
topics=$(echo $KAFKA_TOPICS | tr "," "\n")
for topic in $topics
do
   echo "===> Creating topic $topic in Kafka"
   /usr/bin/kafka-topics --create --zookeeper $CONNECT_ZOOKEEPER_CONNECT --replication-factor $KAFKA_TOPIC_REPLICATION_FACTOR --partitions $KAFKA_TOPIC_PARTITIONS --topic $topic || echo "The topic $topic exists"
done

echo "===> Launching Kafka Connect ... "
exec /etc/confluent/docker/launch &

echo "===> Waiting for TCP connection to Kafka Connect ... "
while ! nc -w 1 127.0.0.1 8083
do
  sleep 1s
done
echo -n "done!"
echo "===> Kafka Connect Up"

echo "===> Sending tasks to Kafka Connect ..."
TASK_FILE=/etc/kafka-connect-tasks/elasticsearch-task.json

echo "===> Applying configuration to ${TASK_FILE}"
sed -i "s|\"name\":\"kafka.*|\"name\":\"${CONNECT_TASK_NAME}\",|" $TASK_FILE
sed -i "s|\"topics.*|\"topics\":\"${KAFKA_TOPICS}\",|" $TASK_FILE
sed -i "s|\"action.type.*|\"action.type\":\"${ELASTICSEARCH_ACTION_TYPE}\",|" $TASK_FILE
sed -i "s|\"elasticsearch.hosts.*|\"elasticsearch.hosts\":\"${ELASTICSEARCH_HOSTS}\",|" $TASK_FILE
sed -i "s|\"elasticsearch.cluster.name.*|\"elasticsearch.cluster.name\":\"${ELASTICSEARCH_CLUSTER_NAME}\",|" $TASK_FILE
sed -i "s|\"elasticsearch.index.*|\"elasticsearch.index\":\"${ELASTICSEARCH_INDEX}\",|" $TASK_FILE
sed -i "s|\"elasticsearch.mapping.type.*|\"elasticsearch.mapping.type\":\"${ELASTICSEARCH_MAPPING_TYPE}\",|" $TASK_FILE
sed -i "s|\"elasticsearch.id.field.*|\"elasticsearch.id.field\":\"${ELASTICSEARCH_ID_FIELD}\",|" $TASK_FILE
sed -i "s|\"elasticsearch.bulk.size.*|\"elasticsearch.bulk.size\":\"${ELASTICSEARCH_BULK_SIZE}\"|" $TASK_FILE

echo "===> Sending task to Kafka Connect ... "
curl -H "Content-Type: application/json; charset=UTF-8" -X POST http://localhost:8083/connectors -d @${TASK_FILE}

tail -f /dev/null
