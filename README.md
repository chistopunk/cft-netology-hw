# Домашнее задание к занятию «Очереди RabbitMQ» — Чередниченко Владислав

## Стенд

| Параметр | Значение |
|---|---|
| Гипервизор | VMware Workstation (хост Windows 11) |
| ОС виртуальных машин | Debian 13 (trixie) |
| Ноды | `rmq01` — 192.168.88.183, `rmq02` — 192.168.88.181 |
| RabbitMQ | 3.13.7 на Erlang 26.2.5.16, Docker-образ `rabbitmq:3.13-management` |
| Клиент | Python 3.13 + pika 1.4.4 (в venv) |

> **Почему RabbitMQ 3.13 в Docker, а не пакет из репозитория Debian.**
> В Debian 13 штатный пакет `rabbitmq-server` версии 4.0.5. Начиная с RabbitMQ 4.0 зеркалирование
> классических очередей (политики `ha-mode`) удалено, поэтому политику `ha-all` из задания 3 в нём
> создать нельзя. Ветка 3.13 эту функцию ещё поддерживает, поэтому она запущена в контейнере
> с сетью хоста (`--network host`): так нода видна в сети как сама ВМ, и кластеризация работает
> без проброса портов.

---

## Задание 1. Установка RabbitMQ

> Создайте виртуальную машину и установите RabbitMQ. Добавьте management plug-in и зайдите в веб-интерфейс.

### Решение

Имя хоста задано до запуска RabbitMQ, потому что из него формируется имя ноды `rabbit@rmq01`:

```bash
sudo hostnamectl set-hostname rmq01
```

Установка Docker и запуск RabbitMQ:

```bash
sudo apt update
sudo apt install -y docker.io
sudo systemctl enable --now docker

sudo docker run -d --name rabbitmq \
  --network host \
  --restart unless-stopped \
  --ulimit nofile=65536:65536 \
  -v rabbitmq-data:/var/lib/rabbitmq \
  -e RABBITMQ_DEFAULT_USER=admin \
  -e RABBITMQ_DEFAULT_PASS='<PASSWORD>' \
  rabbitmq:3.13-management
```

Management plug-in и проверка:

```bash
sudo docker exec rabbitmq rabbitmq-plugins enable rabbitmq_management
sudo docker exec rabbitmq rabbitmq-plugins list -e
sudo docker exec rabbitmq rabbitmqctl version
```

Веб-интерфейс доступен по адресу `http://192.168.88.183:15672`, вход под пользователем `admin`
(встроенный `guest` пускает только с localhost).

<img width="2560" height="1675" alt="telegram-cloud-photo-size-2-5434153989575483522-w" src="https://github.com/user-attachments/assets/470c5cce-1ad6-4e02-a606-a4f368879121" />

---

## Задание 2. Отправка и получение сообщений

> Используя скрипты producer.py и consumer.py, проведите тестовую отправку и получение сообщения.

### Решение

Окружение Python:

```bash
sudo apt install -y python3-venv
python3 -m venv ~/rmq-venv
source ~/rmq-venv/bin/activate
pip install pika
```

В скриптах `localhost` заменён на IP-адрес ноды и добавлена авторизация под `admin`.
Для закрепления материала изменены название очереди (`netology` вместо `hello`) и текст сообщения.

<details>
<summary><code>producer.py</code></summary>

```python
#!/usr/bin/env python3
import pika

HOST = '192.168.88.183'
credentials = pika.PlainCredentials('admin', '<PASSWORD>')

connection = pika.BlockingConnection(pika.ConnectionParameters(host=HOST, credentials=credentials))
channel = connection.channel()
channel.queue_declare(queue='netology')
channel.basic_publish(exchange='', routing_key='netology', body='Hello Netology')
print(" [x] Sent 'Hello Netology'")
connection.close()
```

</details>

<details>
<summary><code>consumer.py</code></summary>

```python
#!/usr/bin/env python3
import pika

HOST = '192.168.88.183'
credentials = pika.PlainCredentials('admin', '<PASSWORD>')

connection = pika.BlockingConnection(pika.ConnectionParameters(host=HOST, credentials=credentials))
channel = connection.channel()
channel.queue_declare(queue='netology')

def callback(ch, method, properties, body):
    print(f" [x] Received {body!r}")

channel.basic_consume(queue='netology', on_message_callback=callback, auto_ack=True)
print(' [*] Waiting for messages. To exit press CTRL+C')
try:
    channel.start_consuming()
except KeyboardInterrupt:
    channel.stop_consuming()
    connection.close()
```

</details>

Отправка сообщения:

```bash
python producer.py
```

<img width="2560" height="1675" alt="telegram-cloud-photo-size-2-5436405789389168906-w" src="https://github.com/user-attachments/assets/6785f0a5-b389-4617-8276-e6b9c0c29685" />

Получение сообщения:

```bash
python consumer.py
```

<img width="2560" height="1589" alt="telegram-cloud-photo-size-2-5436405789389168907-w" src="https://github.com/user-attachments/assets/4cc12afd-24a4-4cea-8425-2dfec1685b78" />

---

## Задание 3. Подготовка HA-кластера

> Создайте вторую виртуальную машину, установите RabbitMQ, объедините машины в кластер
> и создайте политику ha-all на все очереди.

### 3.1. Вторая виртуальная машина

ВМ `rmq02` создана полным клоном `rmq01` (VMware Workstation: **VM → Manage → Clone → Create a full clone**)
с новым MAC-адресом. На клоне изменены идентификаторы машины:

```bash
sudo docker rm -f rabbitmq                    # контейнер был создан под именем rmq01
sudo hostnamectl set-hostname rmq02
sudo rm -f /etc/machine-id /var/lib/dhcpcd/duid
sudo systemd-machine-id-setup                 # новый machine-id, чтобы DHCP выдал другой IP
sudo reboot
```

Том `rabbitmq-data` склонирован вместе с ВМ, поэтому Erlang cookie на обеих нодах совпадает.
Проверка (хеши должны быть одинаковыми):

```bash
sudo md5sum /var/lib/docker/volumes/rabbitmq-data/_data/.erlang.cookie
```

### 3.2. Файл hosts

На обеих машинах добавлены записи нод, строка `127.0.1.1 <hostname>` удалена:

```bash
$ cat /etc/hosts
127.0.0.1 localhost
192.168.88.183 rmq01
192.168.88.181 rmq02
```

Машины пингуются по имени: `ping rmq01` с `rmq02` и `ping rmq02` с `rmq01`.

### 3.3. Объединение в кластер

На `rmq02` запущен такой же контейнер, как в задании 1, затем нода присоединена к `rmq01`:

```bash
# выполняется только на rmq02
sudo docker exec rabbitmq rabbitmqctl stop_app
sudo docker exec rabbitmq rabbitmqctl reset
sudo docker exec rabbitmq rabbitmqctl join_cluster rabbit@rmq01
sudo docker exec rabbitmq rabbitmqctl start_app
```

<img width="2560" height="1675" alt="telegram-cloud-photo-size-2-5436405789389169020-w" src="https://github.com/user-attachments/assets/fadb0094-2a89-498e-b037-3f6a0e8727b6" />

### 3.4. Политика ha-all

```bash
sudo docker exec rabbitmq rabbitmqctl set_policy --apply-to queues ha-all ".*" \
  '{"ha-mode":"all","ha-sync-mode":"automatic"}'
```

- `".*"` — политика применяется ко всем очередям;
- `ha-mode: all` — очередь зеркалируется на все ноды кластера;
- `ha-sync-mode: automatic` — новые зеркала автоматически синхронизируются с основной копией.

<img width="2560" height="1675" alt="telegram-cloud-photo-size-2-5436405789389168962-w" src="https://github.com/user-attachments/assets/94fcfd0c-b4a1-4541-8f0b-daafe2560fd5" />

> Предупреждение «Deprecated features are being used» в веб-интерфейсе связано с этой политикой:
> в RabbitMQ 3.13 зеркалирование классических очередей помечено устаревшим (в 4.0 удалено).

### 3.5. Статус кластера

```bash
sudo docker exec rabbitmq rabbitmqctl cluster_status
```

Обе ноды присутствуют в разделах **Disk Nodes** и **Running Nodes**.
Имя кластера явно не задавалось, поэтому каждая нода показывает своё имя по умолчанию.

<img width="2560" height="1658" alt="telegram-cloud-photo-size-2-5436405789389168958-w" src="https://github.com/user-attachments/assets/6558e7d3-077c-4b26-b71f-860d2155c435" />

<img width="2560" height="1658" alt="telegram-cloud-photo-size-2-5436405789389168959-w" src="https://github.com/user-attachments/assets/e24e398e-36f0-4442-913b-2ec3bc0d1078" />

### 3.6. Проверка сообщения на обеих нодах

Сообщение отправлено через `rmq01`, затем прочитано через `rabbitmqadmin` на каждой ноде:

```bash
python producer.py
sudo docker exec rabbitmq rabbitmqadmin -u admin -p '<PASSWORD>' get queue=netology
```

`get` по умолчанию возвращает сообщение в очередь, поэтому на второй ноде оно отображается
с флагом `redelivered = True`.

<img width="2560" height="1658" alt="telegram-cloud-photo-size-2-5436405789389168973-w" src="https://github.com/user-attachments/assets/cdca5f53-8317-4c6f-83d5-a594b6a229b3" />

<img width="2560" height="1658" alt="telegram-cloud-photo-size-2-5436405789389168974-w" src="https://github.com/user-attachments/assets/7325aa4e-ef51-41bd-a729-b609d7c9697e" />

### 3.7. Отказ ноды

Нода `rmq01`, к которой подключались скрипты, остановлена. Остановлен только контейнер RabbitMQ,
сама ВМ продолжает работать. В `consumer.py` адрес подключения изменён на ноду `rmq02`,
а запускается скрипт там же, где и раньше, на ВМ `rmq01`:

```bash
sudo docker stop rabbitmq                                   # на rmq01
sed -i 's/192.168.88.183/192.168.88.181/' consumer.py
python consumer.py
```

Consumer подключился к ноде `rmq02` и получил сообщение: благодаря политике `ha-all` копия очереди
на второй ноде стала основной, и сообщение не потерялось.

<img width="2560" height="1658" alt="telegram-cloud-photo-size-2-5436405789389169001-w" src="https://github.com/user-attachments/assets/ed3f2099-ba93-4071-872f-fecf5919cd57" />
