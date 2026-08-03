# Модуль `rds` — універсальна база даних для AWS

Один модуль на два сценарії. `use_aurora = false` створює звичайну
`aws_db_instance`, `use_aurora = true` — Aurora-кластер із writer-інстансом.
В обох випадках модуль сам створює DB Subnet Group, Security Group і
Parameter Group, а порт, клас інстанса, родину parameter group і набір
параметрів виводить із обраного рушія.

Підтримувані рушії: **PostgreSQL**, **MySQL**, **Aurora PostgreSQL**,
**Aurora MySQL**.

## Швидкий старт

```hcl
module "rds" {
  source = "./modules/rds"

  name = "my-app-db"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  allowed_cidr_blocks = ["10.0.0.0/16"]
  database_name       = "appdb"
}
```

Цього достатньо: рештa — PostgreSQL 16.14 на `db.t3.micro`, порт 5432, сховище
20 ГБ з шифруванням, пароль генерує AWS Secrets Manager.

## Приклади використання

### Звичайна RDS PostgreSQL

```hcl
module "rds" {
  source = "./modules/rds"

  name           = "lesson-10-db"
  use_aurora     = false
  engine         = "postgres"
  engine_version = "16.14"
  instance_class = "db.t3.micro"
  multi_az       = false

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  allowed_cidr_blocks = ["10.0.0.0/16"]

  database_name   = "django_db"
  master_username = "django_user"

  allocated_storage = 20
  storage_type      = "gp3"

  skip_final_snapshot = true

  tags = {
    Project = "goit-ci-cd"
    Lesson  = "10"
  }
}
```

### Aurora PostgreSQL — кластер із writer'ом і reader'ом

```hcl
module "rds" {
  source = "./modules/rds"

  name           = "lesson-10-db"
  use_aurora     = true
  engine         = "aurora-postgresql"
  engine_version = "16.14"
  instance_class = "db.t4g.medium"
  multi_az       = true # → два інстанси: writer + reader

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  allowed_security_group_ids = [module.eks.node_security_group_id]

  database_name   = "django_db"
  master_username = "django_user"

  backup_retention_period = 7
  skip_final_snapshot     = false
}
```

Зверніть увагу: `allocated_storage` і `storage_type` тут не задані навмисно —
у Aurora сховище спільне для кластера й розширюється саме.

### MySQL із власними параметрами

```hcl
module "rds" {
  source = "./modules/rds"

  name           = "orders-db"
  engine         = "mysql"
  engine_version = "8.0.46"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  allowed_cidr_blocks = ["10.0.0.0/16"]

  parameters = {
    max_connections = { value = "300" }
    long_query_time = { value = "1", apply_method = "immediate" }
  }
}
```

## Що створює модуль

| Ресурс | `use_aurora = false` | `use_aurora = true` |
|---|---|---|
| `aws_db_subnet_group` | ✅ | ✅ |
| `aws_security_group` + правила | ✅ | ✅ |
| `aws_db_parameter_group` | ✅ | ✅ |
| `aws_db_instance` | ✅ | — |
| `aws_rds_cluster` | — | ✅ |
| `aws_rds_cluster_instance` | — | ✅ (1 або більше) |
| `aws_rds_cluster_parameter_group` | — | ✅ |

## Як змінити конфігурацію

### Змінити тип БД: звичайна RDS ↔ Aurora

Два рядки — `use_aurora` і `engine`. Вони мають бути узгоджені: рушій для
Aurora починається з `aurora-`. Неузгодженість модуль ловить ще на `plan`
і пояснює, що саме не так.

```hcl
# Було
use_aurora = false
engine     = "postgres"

# Стало
use_aurora     = true
engine         = "aurora-postgresql"
engine_version = "16.14"
```

Клас інстанса при цьому можна не чіпати: якщо `instance_class` не заданий,
модуль сам візьме `db.t4g.medium` замість `db.t3.micro`.

> ⚠️ Це не міграція, а заміна. Terraform знищить стару базу й створить нову —
> дані не переїжджають. Перед перемиканням зробіть знімок:
> `skip_final_snapshot = false`.

### Змінити рушій: PostgreSQL ↔ MySQL

```hcl
engine         = "mysql"
engine_version = "8.0.46"
```

Порт (3306), родина parameter group (`mysql8.0`) і набір базових параметрів
переключаться самі. Останнє важливе: `log_statement` і `work_mem` існують
лише в PostgreSQL, і для MySQL модуль підставить `slow_query_log` та
`long_query_time` замість них.

Актуальні версії свого регіону:

```bash
aws rds describe-db-engine-versions --engine mysql \
  --query 'DBEngineVersions[].EngineVersion' --output text
```

### Змінити клас інстанса

```hcl
instance_class = "db.t3.small"
```

`null` (за замовчуванням) означає «підбери сам»: `db.t3.micro` для звичайної
RDS, `db.t4g.medium` для Aurora. Спільного дефолту немає, бо `db.t3.micro`
для Aurora AWS не пропонує взагалі — найменший доступний клас там
`db.t3.medium`. Перевірити список:

```bash
aws rds describe-orderable-db-instance-options \
  --engine aurora-postgresql --engine-version 16.14 \
  --query 'OrderableDBInstanceOptions[].DBInstanceClass' --output text
```

### Увімкнути відмовостійкість

```hcl
multi_az = true
```

Механізм відрізняється, і це не деталь реалізації, а різна поведінка:

- **звичайна RDS** — синхронний standby в іншій зоні. Підключитись до нього
  не можна: він існує лише для автоматичного failover;
- **Aurora** — другий інстанс над спільним сховищем, доступний для читання
  через `reader_endpoint`. Кількість можна задати точно через
  `aurora_instance_count`.

В обох випадках вартість обчислень подвоюється.

### Змінити параметри БД

`parameters` доповнює і перекриває базовий набір:

```hcl
parameters = {
  max_connections = { value = "500" }
  work_mem        = { value = "16384", apply_method = "immediate" }
}
```

Щоб зібрати список з нуля — `use_default_parameters = false`.

`apply_method` за замовчуванням `pending-reboot`. Це не перестраховка:
`max_connections` у PostgreSQL — статичний параметр, і AWS відхиляє для нього
`immediate`. Які параметри існують для вашої родини й які з них статичні:

```bash
aws rds describe-engine-default-parameters --db-parameter-group-family postgres16 \
  --query "EngineDefaults.Parameters[?ParameterName=='work_mem']"
```

### Задати пароль вручну

За замовчуванням пароль генерує AWS і зберігає в Secrets Manager — у стейті
Terraform його немає взагалі. Щоб задати свій:

```hcl
password = var.db_password # передавайте через TF_VAR_db_password
```

## Змінні

### Ідентифікація

| Змінна | Тип | Дефолт | Опис |
|---|---|---|---|
| `name` | `string` | — (обов'язкова) | Базове ім'я БД і всіх супутніх ресурсів. Малі літери, цифри, дефіси |
| `tags` | `map(string)` | `{}` | Теги для всіх ресурсів модуля. Тег `Name` модуль проставляє сам |

### Вибір типу БД

| Змінна | Тип | Дефолт | Опис |
|---|---|---|---|
| `use_aurora` | `bool` | `false` | Головний перемикач: `true` — Aurora-кластер, `false` — одна інстанція |
| `engine` | `string` | `"postgres"` | `postgres`, `mysql`, `aurora-postgresql` або `aurora-mysql`. Має бути узгоджений з `use_aurora` |
| `engine_version` | `string` | `"16.14"` | Версія рушія. Має існувати для обраного `engine` |
| `instance_class` | `string` | `null` | Клас інстанса. `null` — `db.t3.micro` для RDS, `db.t4g.medium` для Aurora |
| `multi_az` | `bool` | `false` | Кілька зон доступності. Для RDS — standby, для Aurora — другий інстанс |
| `aurora_instance_count` | `number` | `null` | Кількість інстансів кластера (1–15). `null` — 2 при `multi_az`, інакше 1 |

### Мережа

| Змінна | Тип | Дефолт | Опис |
|---|---|---|---|
| `vpc_id` | `string` | — (обов'язкова) | VPC, у якій створюється security group |
| `subnet_ids` | `list(string)` | — (обов'язкова) | Підмережі для DB Subnet Group. Потрібні щонайменше дві в різних AZ |
| `allowed_cidr_blocks` | `list(string)` | `[]` | CIDR-блоки, яким дозволено підключення до порту БД |
| `allowed_security_group_ids` | `list(string)` | `[]` | Security group, яким дозволено підключення. Точніше за CIDR |
| `publicly_accessible` | `bool` | `false` | Публічний доступ з інтернету |
| `port` | `number` | `null` | Порт БД. `null` — 5432 для PostgreSQL, 3306 для MySQL |

### База та облікові дані

| Змінна | Тип | Дефолт | Опис |
|---|---|---|---|
| `database_name` | `string` | `"appdb"` | Ім'я бази всередині інстанса чи кластера |
| `master_username` | `string` | `"dbadmin"` | Логін майстер-користувача. `admin`, `root`, `postgres` зарезервовані AWS |
| `password` | `string` (sensitive) | `null` | Пароль. `null` — генерує AWS Secrets Manager |
| `manage_master_user_password` | `bool` | `true` | Довірити пароль Secrets Manager. Ігнорується, якщо задано `password` |

### Сховище (лише звичайна RDS)

| Змінна | Тип | Дефолт | Опис |
|---|---|---|---|
| `allocated_storage` | `number` | `20` | Початковий розмір сховища в ГБ. Мінімум 20 |
| `max_allocated_storage` | `number` | `100` | Межа автоматичного розширення. `0` вимикає розширення |
| `storage_type` | `string` | `"gp3"` | `gp2`, `gp3`, `io1` або `io2` |
| `storage_encrypted` | `bool` | `true` | Шифрування. Після створення БД його вже не увімкнути |
| `kms_key_id` | `string` | `null` | Власний ключ KMS. `null` — ключ AWS `aws/rds` |

### Параметри БД

| Змінна | Тип | Дефолт | Опис |
|---|---|---|---|
| `parameters` | `map(object({value, apply_method}))` | `{}` | Параметри рівня інстанса. Доповнюють і перекривають базовий набір |
| `cluster_parameters` | `map(object({value, apply_method}))` | `{}` | Параметри рівня кластера Aurora. Ігнорується при `use_aurora = false` |
| `use_default_parameters` | `bool` | `true` | Чи додавати базовий набір, підібраний під рушій |
| `parameter_group_family` | `string` | `null` | Родина parameter group. `null` — обчислюється з `engine` і `engine_version` |

### Резервні копії та експлуатація

| Змінна | Тип | Дефолт | Опис |
|---|---|---|---|
| `backup_retention_period` | `number` | `7` | Днів зберігання копій, 0–35. Для Aurora мінімум 1 |
| `backup_window` | `string` | `"03:00-04:00"` | Вікно копіювання в UTC |
| `maintenance_window` | `string` | `"Mon:04:00-Mon:05:00"` | Вікно обслуговування в UTC. Не має перетинатися з `backup_window` |
| `deletion_protection` | `bool` | `false` | Захист від видалення, зокрема через `terraform destroy` |
| `skip_final_snapshot` | `bool` | `true` | Не робити фінальний знімок при видаленні |
| `final_snapshot_identifier` | `string` | `null` | Ім'я фінального знімка. `null` — `<name>-final-snapshot` |
| `apply_immediately` | `bool` | `false` | Застосовувати зміни одразу, а не у вікні обслуговування |
| `auto_minor_version_upgrade` | `bool` | `true` | Автоматичне оновлення мінорної версії рушія |

### Спостережуваність

| Змінна | Тип | Дефолт | Опис |
|---|---|---|---|
| `performance_insights_enabled` | `bool` | `false` | Performance Insights. Недоступний на `db.t3.micro` |
| `enabled_cloudwatch_logs_exports` | `list(string)` | `null` | Логи в CloudWatch. `null` — модуль обере під рушій |

## Виводи

| Вивід | Опис |
|---|---|
| `is_aurora` | Що створено: `true` — Aurora, `false` — звичайна RDS |
| `identifier` | Ідентифікатор кластера або інстанса |
| `endpoint` | Хост для підключення (без порту) |
| `reader_endpoint` | Endpoint для читання. `null` для звичайної RDS |
| `instance_endpoints` | Адреси окремих інстансів Aurora |
| `port` | Порт БД |
| `database_name` | Ім'я бази |
| `master_username` | Логін майстер-користувача |
| `master_user_secret_arn` | ARN секрету з паролем. `null`, якщо пароль задано вручну |
| `password_command` | Готова команда, що друкує згенерований пароль |
| `connection_command` | Готова команда `psql` або `mysql` |
| `security_group_id` | ID security group бази |
| `db_subnet_group_name` | Ім'я DB Subnet Group |
| `parameter_group_name` | Ім'я DB Parameter Group |
| `cluster_parameter_group_name` | Ім'я Cluster Parameter Group. `null` для звичайної RDS |
| `parameter_group_family` | Обчислена родина parameter group |
| `instance_class` | Клас інстанса, що фактично застосовано |
| `applied_parameters` | Параметри, що потрапили в parameter group |

## Що модуль виводить сам

Таблиця нижче — фактичний результат `terraform plan` для чотирьох комбінацій.
Змінюються лише `use_aurora`, `engine` і `engine_version`; решта аргументів
однакова.

| `use_aurora` | `engine` | → родина | → клас | → порт | → базові параметри |
|---|---|---|---|---|---|
| `false` | `postgres` | `postgres16` | `db.t3.micro` | 5432 | `max_connections`, `log_statement`, `work_mem` |
| `true` | `aurora-postgresql` | `aurora-postgresql16` | `db.t4g.medium` | 5432 | ті самі три |
| `false` | `mysql` | `mysql8.0` | `db.t3.micro` | 3306 | `max_connections`, `slow_query_log`, `long_query_time` |
| `true` | `aurora-mysql` | `aurora-mysql8.0` | `db.t4g.medium` | 3306 | ті самі три |

## Три пастки, закладені в дизайн

Ці обмеження перевірені через AWS API, а не взяті з документації навмання.
Кожне з них ламає «наївний» універсальний модуль.

**1. `log_statement` і `work_mem` не існують у MySQL.**

```bash
aws rds describe-engine-default-parameters --db-parameter-group-family mysql8.0 \
  --query "EngineDefaults.Parameters[?ParameterName=='work_mem']"
# → []
```

Захардкоджений список із трьох параметрів валить `apply` на MySQL. Тому
базовий набір залежить від рушія.

**2. У cluster parameter group Aurora немає жодного з трьох параметрів.**

```bash
aws rds describe-engine-default-cluster-parameters \
  --db-parameter-group-family aurora-postgresql16 \
  --query "EngineDefaults.Parameters[?ParameterName=='max_connections']"
# → []
```

Інтуїція підказує «Aurora → cluster parameter group», але всі три параметри —
instance-level. Тому модуль чіпляє `aws_db_parameter_group` до інстансів
кластера, а кластерна група лишається для справді кластерних налаштувань.

**3. Для Aurora не існує класу `db.t3.micro`.**

```bash
aws rds describe-orderable-db-instance-options \
  --engine aurora-postgresql --engine-version 16.14 \
  --query 'OrderableDBInstanceOptions[].DBInstanceClass' --output text
# → db.t3.medium db.t3.large db.t4g.medium db.t4g.large ...
```

Єдиний спільний дефолт `instance_class` гарантовано зламав би одну з гілок,
тому дефолт обчислюється з `use_aurora`.

## Перевірки, що спрацьовують на `plan`

Модуль не дає дійти до AWS із конфігурацією, яка все одно буде відхилена:

- `use_aurora` і `engine` мають бути узгоджені;
- підмереж має бути щонайменше дві;
- має бути заданий бодай один механізм отримання пароля;
- `engine` — лише з підтримуваного списку;
- `apply_method` — лише `immediate` або `pending-reboot`;
- `master_username` — не зарезервоване AWS ім'я.

## Вимоги

| | Версія |
|---|---|
| Terraform | >= 1.5.0 |
| AWS provider | ~> 5.0 |
