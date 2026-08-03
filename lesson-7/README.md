# Lesson 7 — Kubernetes (EKS) + ECR + Helm

Розгортання Django-застосунку з теми 4 у **Amazon EKS**: інфраструктура
описана Terraform, образ зберігається в **ECR**, а сам застосунок ставиться
в кластер **Helm-чартом** із Deployment, Service, HPA та ConfigMap.

Код продовжує ДЗ5: модулі `s3-backend`, `vpc` та `ecr` перенесені звідти,
до них додано модуль `eks`, а VPC отримала теги, без яких EKS не вміє
створювати балансувальники.

## Структура проєкту

```text
lesson-7/
├── main.tf                     # Провайдер та підключення усіх модулів
├── backend.tf                  # Бекенд для стейту (S3 + DynamoDB)
├── outputs.tf                  # Загальне виведення ресурсів
│
├── modules/
│   ├── s3-backend/             # S3-бакет і DynamoDB для стейту
│   │   ├── s3.tf
│   │   ├── dynamodb.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── vpc/                    # VPC, підмережі, IGW, NAT, маршрути
│   │   ├── vpc.tf              # + теги підмереж для EKS-балансувальників
│   │   ├── routes.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── ecr/                    # Реєстр Docker-образів
│   │   ├── ecr.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   └── eks/                    # Kubernetes-кластер
│       ├── eks.tf              # IAM-ролі, кластер, node group, add-ons
│       ├── variables.tf
│       └── outputs.tf
│
├── charts/
│   └── django-app/             # Helm-чарт застосунку
│       ├── templates/
│       │   ├── deployment.yaml # Django + envFrom (ConfigMap і Secret)
│       │   ├── service.yaml    # LoadBalancer
│       │   ├── configmap.yaml  # Несекретні змінні середовища
│       │   ├── secret.yaml     # Пароль БД і DJANGO_SECRET_KEY
│       │   ├── hpa.yaml        # Автоскейлер 2–6 подів при CPU > 70%
│       │   ├── postgres.yaml   # Демо-база (опційно)
│       │   ├── _helpers.tpl
│       │   └── NOTES.txt
│       ├── Chart.yaml
│       └── values.yaml
│
├── django-app/                 # Застосунок з теми 4 (джерело образу)
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── manage.py
│   └── myproject/
│
├── .gitignore
└── README.md
```

## Що створює Terraform

| Модуль | Ресурси |
|---|---|
| `s3-backend` | S3-бакет (версіювання, шифрування, блокування публічного доступу) + DynamoDB-таблиця `LockID` для блокування стейту. **Вимкнений**: бекенд уже створено в ДЗ5 |
| `vpc` | VPC `10.0.0.0/16`, 3 публічні + 3 приватні підмережі в трьох AZ, Internet Gateway, NAT Gateway, таблиці маршрутизації, теги для EKS |
| `ecr` | Репозиторій `django-app` зі скануванням образів при push, шифруванням і lifecycle-політикою на 10 останніх образів |
| `eks` | Кластер `lesson-7-eks`, IAM-ролі control plane і нод, керована node group у приватних підмережах, add-ons |

### Модуль `eks` детальніше

**IAM.** Роль control plane отримує `AmazonEKSClusterPolicy` і
`AmazonEKSVPCResourceController`. Роль воркер-нод — три обов'язкові політики:

| Політика | Навіщо |
|---|---|
| `AmazonEKSWorkerNodePolicy` | нода реєструється в кластері |
| `AmazonEKS_CNI_Policy` | VPC CNI видає подам IP-адреси |
| `AmazonEC2ContainerRegistryReadOnly` | kubelet тягне образи з ECR |

**Мережа.** Control plane бачить усі шість підмереж (публічні потрібні, щоб
Service типу LoadBalancer міг створити зовнішній балансувальник), воркер-ноди
живуть тільки в приватних і ходять у мережу через NAT Gateway.

**Node group.** `t3.small`, desired = 2, min = 2, **max = 3**. Верхня межа
навмисно більша за одиницю: якщо групу обмежити однією нодою, HPA
масштабуватиме поди в нікуди — вони назавжди зависнуть у статусі `Pending`.

**Add-ons.** `vpc-cni`, `kube-proxy`, `coredns` і **`metrics-server`**.
Останній обов'язковий: без нього HPA нема звідки брати метрики і
`kubectl get hpa` вічно показує `<unknown>/70%`.

**Доступ.** `authentication_mode = "API_AND_CONFIG_MAP"` і
`bootstrap_cluster_creator_admin_permissions = true` — той, хто виконав
`terraform apply`, одразу має права адміністратора, тож
`aws eks update-kubeconfig` працює без ручного редагування `aws-auth`.
Щоб видати доступ ще комусь (напр. IAM-ролі Jenkins у наступних темах),
передайте ARN у змінну `admin_principal_arns`.

**Версія Kubernetes.** `cluster_version` за замовчуванням `null` — AWS сам
підставляє поточну дефолтну версію. Так кластер ніколи не створюється на
версії, що вже перейшла в extended support (а це вшестеро дорожчий
control plane).

## Передумови

- [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.5.0`
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) з налаштованими обліковими даними
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/) `>= 3`
- Docker

## Крок 1. Інфраструктура

Бакет `rachynskyi-terraform-state` і таблиця `terraform-locks` створені ще в
ДЗ5 і живі, тому ДЗ7 просто пише свій стейт у той самий бакет під ключем
`lesson-7/terraform.tfstate`:

```bash
cd lesson-7
terraform init
terraform plan
terraform apply
```

<details>
<summary>Якщо бекенду ще не існує (розгортання з нуля)</summary>

`backend.tf` посилається на бакет, який створює цей самий код, — на першому
запуску виникає замкнене коло. Розривається воно у два етапи:

```bash
# 1) увімкніть create_state_backend = true у main.tf
#    і закоментуйте блок backend "s3" у backend.tf
terraform init
terraform apply -target=module.s3_backend

# 2) розкоментуйте блок backend "s3" і перенесіть стейт у S3
terraform init -migrate-state

# 3) решта інфраструктури
terraform apply
```

</details>

Створення кластера й node group займає **15–20 хвилин**.

Після завершення:

```bash
terraform output
```

## Крок 2. Доступ через kubectl

```bash
aws eks update-kubeconfig --region us-west-2 --name lesson-7-eks
# те саме одним рядком:
eval "$(terraform output -raw kubectl_config_command)"

kubectl get nodes
kubectl get pods -n kube-system
```

Очікувано: дві ноди у статусі `Ready`, у `kube-system` — `coredns`,
`aws-node`, `kube-proxy` та `metrics-server`.

## Крок 3. Образ Django в ECR

```bash
export AWS_REGION=us-west-2
export ECR_URL=$(terraform output -raw ecr_repository_url)

# авторизація Docker в ECR
aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS --password-stdin ${ECR_URL%%/*}

# збірка та завантаження
docker build -t ${ECR_URL}:latest ./django-app
docker push ${ECR_URL}:latest

# перевірка
aws ecr list-images --repository-name django-app --region $AWS_REGION
```

> Фігурні дужки в `${ECR_URL}:latest` обов'язкові. У zsh конструкція
> `$ECR_URL:latest` розбирається як модифікатор `:l` (нижній регістр) плюс
> текст `atest`, і образ отримує тег `django-appatest` — push падає з
> `repository ... does not exist`. Лапки від цього не рятують, дужки — так.

> Якщо ви на Apple Silicon чи іншій ARM-машині, збирайте під архітектуру нод:
> `docker build --platform linux/amd64 -t ${ECR_URL}:latest ./django-app`

## Крок 4. Встановлення Helm-чарта

```bash
helm upgrade --install django-app ./charts/django-app \
  --set image.repository=$ECR_URL \
  --set image.tag=latest
```

Перевірити, що саме буде застосовано, не встановлюючи:

```bash
helm template django-app ./charts/django-app
helm template django-app ./charts/django-app | kubectl apply --dry-run=client -f -
```

## Крок 5. Перевірка

```bash
kubectl get pods          # 2+ подів Running (не Pending)
kubectl get svc           # у LoadBalancer з'явився EXTERNAL-IP (1–3 хв)
kubectl get hpa           # у TARGETS реальний відсоток, а не <unknown>
kubectl get configmap django-app-config -o yaml
kubectl get secret django-app-secret
```

Відкрити застосунок:

```bash
export APP_HOST=$(kubectl get svc django-app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://$APP_HOST/
```

Відповідь показує ім'я пода, стан бази та значення змінних, що приїхали з
ConfigMap (значення з Secret позначені як `set`, самі значення не друкуються):

```json
{
  "app": "django-app",
  "pod": "django-app-7d9c...-x4k2p",
  "database": "ok",
  "config": {
    "DJANGO_ENV": "production",
    "POSTGRES_DB": "django_db",
    "POSTGRES_HOST": "django-app-postgres",
    "...": "..."
  },
  "secrets": { "POSTGRES_PASSWORD": "set", "DJANGO_SECRET_KEY": "set" }
}
```

### Перевірка автоскейлера під навантаженням

```bash
# в окремому терміналі — спостерігаємо
kubectl get hpa django-app -w

# генератор навантаження (запустіть 2–3 штуки паралельно)
kubectl run load-gen-1 --rm -it --image=busybox:1.36 --restart=Never -- \
  /bin/sh -c "while true; do wget -q -O- http://django-app/ >/dev/null; done"
```

Коли середня утилізація CPU перевищить 70 %, кількість реплік зросте в бік 6;
після зупинки генераторів HPA поверне її до 2 (з паузою ~5 хвилин на
стабілізацію).

## Helm-чарт

| Шаблон | Що робить |
|---|---|
| `deployment.yaml` | Django з ECR-образу; змінні середовища підключені цілими наборами через `envFrom` — з ConfigMap і з Secret; `resources.requests.cpu` задано (від нього HPA рахує утилізацію); liveness/readiness на `/healthz/` |
| `service.yaml` | `LoadBalancer`, порт 80 → 8000 |
| `hpa.yaml` | `autoscaling/v2`, 2–6 реплік, ціль — 70 % CPU |
| `configmap.yaml` | Несекретні змінні середовища з теми 4 |
| `secret.yaml` | `POSTGRES_PASSWORD` і `DJANGO_SECRET_KEY` |
| `postgres.yaml` | Демо-база (опційно, `postgres.enabled`) |

### Змінні середовища з теми 4

У темі 4 змінні жили в `docker-compose.yml`. Тут вони розділені за чутливістю:

| Змінна | Ресурс | Значення |
|---|---|---|
| `POSTGRES_DB` | ConfigMap | `django_db` |
| `POSTGRES_USER` | ConfigMap | `django_user` |
| `POSTGRES_HOST` | ConfigMap | сервіс `django-app-postgres` (у compose було `db`) |
| `POSTGRES_PORT` | ConfigMap | `5432` |
| `DJANGO_SETTINGS_MODULE` | ConfigMap | `myproject.settings` |
| `DJANGO_ENV` | ConfigMap | `production` |
| `DJANGO_DEBUG` | ConfigMap | `False` |
| `DJANGO_ALLOWED_HOSTS` | ConfigMap | `*` |
| `POSTGRES_PASSWORD` | **Secret** | `django_password` |
| `DJANGO_SECRET_KEY` | **Secret** | ключ Django |

Пароль і секретний ключ навмисно винесені в `Secret`, а не в `ConfigMap`:
вміст ConfigMap читає відкритим текстом будь-який workload у неймспейсі.
Механізм підключення до контейнера при цьому той самий — `envFrom`.

### Ключові значення `values.yaml`

```yaml
image:
  repository: <account>.dkr.ecr.us-west-2.amazonaws.com/django-app
  tag: "latest"

service:
  type: LoadBalancer
  port: 80
  targetPort: 8000

resources:
  requests:
    cpu: 100m          # без цього поля HPA показує <unknown>
    memory: 128Mi

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 6
  targetCPUUtilizationPercentage: 70
```

Імена `image.repository` та `image.tag` змінювати не можна — саме ці ключі
програмно оновлює пайплайн у наступних темах, а Argo CD читає їх під час
синхронізації.

### Вбудований PostgreSQL

`postgres.yaml` виходить за межі умови завдання: він потрібен, щоб застосунок
мав живу базу і на головній сторінці було видно `"database": "ok"` — тобто що
змінні з ConfigMap і Secret справді працюють. Дані зберігаються в `emptyDir`
і зникають разом з подом; PVC тут свідомо не використовується, бо в свіжому
EKS немає EBS CSI-драйвера і том вічно висів би в статусі `Pending`.
Для зовнішньої бази (RDS) поставте `postgres.enabled: false` і вкажіть хост
у `config.POSTGRES_HOST`.

## ⚠️ Вартість і видалення інфраструктури

Кластер коштує грошей навіть тоді, коли ним ніхто не користується:

| Ресурс | Приблизно |
|---|---|
| EKS control plane | $0.10/год (~$73/міс) |
| 2 × t3.small | ~$0.042/год |
| NAT Gateway + Elastic IP | ~$0.05/год (~$36/міс) |
| Classic Load Balancer | ~$0.025/год |

**Після кожної сесії гасіть кластер.** Спершу приберіть Helm-реліз — інакше
балансувальник, створений Kubernetes, залишиться в AWS сиротою, і Terraform
не зможе видалити VPC (балансувальник тримає підмережу):

```bash
helm uninstall django-app
kubectl get svc                # переконайтесь, що LoadBalancer зник
terraform destroy
```

`terraform destroy` тут безпечний: бакет зі стейтом і таблиця блокувань
цим кодом **не керуються** (`create_state_backend = false`), тож вони
залишаться на місці для наступних тем.

Якщо потрібно прибрати лише найдорожче, а ECR і мережу лишити:

```bash
terraform destroy -target=module.eks
```

## Корисні посилання

- [Horizontal Pod Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) — як HPA рахує утилізацію
- [HPA в Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/horizontal-pod-autoscaler.html)
- [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)
- [Helm chart template guide](https://helm.sh/docs/chart_template_guide/)
