# Домашнее задание к занятию «ELK» — Чередниченко Владислав

## Стенд

- ВМ: Debian 13, 2 vCPU, 8 ГБ RAM, IP `192.168.88.183`
- Elastic Stack **8.19.23** (Elasticsearch, Kibana, Logstash, Filebeat), nginx 1.26.3
- Один узел (single-node). Встроенная безопасность (TLS и авторизация) отключена, потому что стенд учебный и Elasticsearch слушает только `localhost`.

### Подготовка: подключение репозитория Elastic

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl gnupg ca-certificates

curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg

# зеркало Яндекса (официальный адрес: https://artifacts.elastic.co/packages/8.x/apt)
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://mirror.yandex.ru/mirrors/elastic/8/ stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list

sudo apt update
```

---

### Задание 1. Elasticsearch

> Установите и запустите Elasticsearch, после чего поменяйте параметр cluster_name на случайный.
> Приведите скриншот команды `curl -X GET 'localhost:9200/_cluster/health?pretty'`, сделанной на сервере с установленным Elasticsearch. Где будет виден нестандартный cluster_name.

#### Решение

1. Установка:

```bash
sudo apt install -y elasticsearch
```

2. Изменения в `/etc/elasticsearch/elasticsearch.yml`. Имя кластера сгенерировано случайно, API доступен только локально, security отключён, чтобы запрос из задания выполнялся без авторизации:

```yaml
cluster.name: cluster-ro5w80qs

http.host: 127.0.0.1

xpack.security.enabled: false
xpack.security.enrollment.enabled: false
xpack.security.http.ssl:
  enabled: false
```

3. Ограничение памяти JVM в `/etc/elasticsearch/jvm.options.d/heap.options`:

```
-Xms2g
-Xmx2g
```

4. Запуск и проверка:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now elasticsearch
curl -X GET 'localhost:9200/_cluster/health?pretty'
```

![Задание 1](<img width="2560" height="1589" alt="telegram-cloud-photo-size-2-5418359612416664796-w" src="https://github.com/user-attachments/assets/4c79ac3a-a1b9-4fcd-82ec-deff4ada4556" />
)

---

### Задание 2. Kibana

> Установите и запустите Kibana.
> Приведите скриншот интерфейса Kibana на странице `http://<ip вашего сервера>:5601/app/dev_tools#/console`, где будет выполнен запрос `GET /_cluster/health?pretty`.

#### Решение

1. Установка:

```bash
sudo apt install -y kibana
```

2. Изменения в `/etc/kibana/kibana.yml`:

```yaml
server.host: "0.0.0.0"
elasticsearch.hosts: ["http://localhost:9200"]
```

3. Запуск:

```bash
sudo systemctl enable --now kibana
```

4. В браузере открыта страница `http://192.168.88.183:5601/app/dev_tools#/console` и выполнен запрос `GET /_cluster/health?pretty`.

![Задание 2](<img width="2560" height="1675" alt="telegram-cloud-photo-size-2-5418359612416664817-w" src="https://github.com/user-attachments/assets/c4420747-740e-48ad-9784-9d26c4375d97" />
)

---

### Задание 3. Logstash

> Установите и запустите Logstash и Nginx. С помощью Logstash отправьте access-лог Nginx в Elasticsearch.
> Приведите скриншот интерфейса Kibana, на котором видны логи Nginx.

#### Решение

1. Установка nginx и генерация трафика:

```bash
sudo apt install -y nginx
for i in $(seq 1 10); do curl -s -o /dev/null localhost/; done
curl -s -o /dev/null localhost/nonexistent
```

2. Установка Logstash. Пользователь `logstash` добавлен в группу `adm`, чтобы у него было право читать `/var/log/nginx/access.log`:

```bash
sudo apt install -y logstash
sudo usermod -aG adm logstash
```

3. Пайплайн `/etc/logstash/conf.d/nginx.conf`:

```ruby
input {
  file {
    path => "/var/log/nginx/access.log"
    start_position => "beginning"
    sincedb_path => "/var/lib/logstash/sincedb_nginx"
  }
}

filter {
  grok {
    match => { "message" => "%{COMBINEDAPACHELOG}" }
  }
  date {
    match => [ "timestamp", "dd/MMM/yyyy:HH:mm:ss Z" ]
  }
}

output {
  elasticsearch {
    hosts => ["http://localhost:9200"]
    index => "nginx-logstash-%{+YYYY.MM.dd}"
  }
}
```

4. Проверка конфигурации, запуск и проверка индекса:

```bash
sudo -u logstash /usr/share/logstash/bin/logstash --path.settings /etc/logstash -t
sudo systemctl enable --now logstash
curl 'localhost:9200/_cat/indices/nginx-*?v'
```

5. В Kibana создан Data View `nginx-logstash` (index pattern `nginx-logstash-*`, time field `@timestamp`). Логи открыты в Discover, в колонки вынесены поля, которые разобрал grok: `source.address`, `url.original`, `http.response.status_code`.

![Задание 3](<img width="2560" height="1675" alt="telegram-cloud-photo-size-2-5418359612416664835-w" src="https://github.com/user-attachments/assets/6079c6a9-d3c2-49eb-a3b1-cb3a2953a7c7" />
)

---

### Задание 4. Filebeat

> Установите и запустите Filebeat. Переключите поставку логов Nginx с Logstash на Filebeat.
> Приведите скриншот интерфейса Kibana, на котором видны логи Nginx, которые были отправлены через Filebeat.

#### Решение

1. Logstash остановлен и убран из автозапуска:

```bash
sudo systemctl disable --now logstash
```

2. Установка Filebeat:

```bash
sudo apt install -y filebeat
```

3. Конфигурация `/etc/filebeat/filebeat.yml`. Filebeat читает access-лог и отправляет его напрямую в Elasticsearch:

```yaml
filebeat.inputs:
  - type: filestream
    id: nginx-access
    enabled: true
    paths:
      - /var/log/nginx/access.log

output.elasticsearch:
  hosts: ["http://localhost:9200"]
```

4. Проверка и запуск:

```bash
sudo filebeat test config
sudo filebeat test output
sudo systemctl enable --now filebeat
```

5. Сгенерированы «меченые» запросы, чтобы отличать записи, пришедшие после переключения:

```bash
for i in $(seq 1 5); do curl -s -o /dev/null localhost/filebeat-test; done
```

6. В Kibana создан Data View `filebeat` (index pattern `filebeat-*`, time field `@timestamp`). В Discover видно `agent.type: filebeat`, путь `/var/log/nginx/access.log` и строки nginx, в том числе запросы `/filebeat-test`.

> Filebeat передаёт строку лога целиком в поле `message`, без разбора на поля. Поэтому в `@timestamp` записано время чтения строки, а не время из лога. В задании 3 время из лога извлекал фильтр `date` в Logstash.

![Задание 4](<img width="2560" height="1675" alt="telegram-cloud-photo-size-2-5418359612416664855-w" src="https://github.com/user-attachments/assets/376ae1bc-991d-4431-ab0d-c6002ca89764" />
)
