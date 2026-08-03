# Протокол перевірки — фактичні виводи з розгорнутого стенду

Усе нижче — реальний вивід команд після `terraform apply` у регіоні `us-west-2`,
акаунт `918349930062`, гілка `final-project`, папка `Project/`.
Terraform v1.15.8, Kubernetes v1.36 (EKS).

## 1. Розгортання

```console
$ terraform apply
Apply complete! Resources: 59 added, 0 changed, 0 destroyed.
```

```console
$ kubectl get nodes
NAME                                       STATUS   ROLES    AGE   VERSION
ip-10-0-4-16.us-west-2.compute.internal    Ready    <none>   13m   v1.36.2-eks-bca9cf6
ip-10-0-5-245.us-west-2.compute.internal   Ready    <none>   13m   v1.36.2-eks-bca9cf6
ip-10-0-6-211.us-west-2.compute.internal   Ready    <none>   13m   v1.36.2-eks-bca9cf6
```

```console
$ kubectl get pods -A
NAMESPACE     NAME                                                        READY   STATUS    RESTARTS   AGE
argocd        argocd-application-controller-0                             1/1     Running   0          10m
argocd        argocd-applicationset-controller-5478ffb8-l87rc             1/1     Running   0          10m
argocd        argocd-redis-78f9b798dd-dcdbh                               1/1     Running   0          10m
argocd        argocd-repo-server-6bff8d675f-45mb4                         1/1     Running   0          10m
argocd        argocd-server-7bbbbdd894-jvsb6                              1/1     Running   0          10m
django-app    django-app-56c889b7c6-mzp66                                 1/1     Running   0          114s
django-app    django-app-56c889b7c6-nfpxd                                 1/1     Running   0          99s
jenkins       jenkins-0                                                   2/2     Running   0          11m
kube-system   aws-node-284zg                                              2/2     Running   0          12m
kube-system   aws-node-w96nx                                              2/2     Running   0          12m
kube-system   aws-node-xmb4l                                              2/2     Running   0          12m
kube-system   coredns-6d9864d4bb-d79f8                                    1/1     Running   0          12m
kube-system   coredns-6d9864d4bb-jpwtw                                    1/1     Running   0          12m
kube-system   ebs-csi-controller-6fd5c895c9-x22fn                         6/6     Running   0          12m
kube-system   ebs-csi-controller-6fd5c895c9-zd2pg                         6/6     Running   0          12m
kube-system   ebs-csi-node-5rhfr                                          3/3     Running   0          12m
kube-system   ebs-csi-node-6vbqz                                          3/3     Running   0          12m
kube-system   ebs-csi-node-lxvkb                                          3/3     Running   0          12m
kube-system   kube-proxy-l4njx                                            1/1     Running   0          12m
kube-system   kube-proxy-zhppc                                            1/1     Running   0          12m
kube-system   kube-proxy-zkzkp                                            1/1     Running   0          12m
kube-system   metrics-server-fdbf976b5-dfxc6                              1/1     Running   0          12m
kube-system   metrics-server-fdbf976b5-jb4fq                              1/1     Running   0          12m
monitoring    alertmanager-kube-prometheus-stack-alertmanager-0           2/2     Running   0          9m30s
monitoring    grafana-857889b957-fgp6n                                    3/3     Running   0          9m36s
monitoring    kube-prometheus-stack-kube-state-metrics-7c7857ff84-2k922   1/1     Running   0          9m36s
monitoring    kube-prometheus-stack-operator-6f6757fccd-m7rsx             1/1     Running   0          9m36s
monitoring    kube-prometheus-stack-prometheus-node-exporter-dws4g        1/1     Running   0          9m36s
monitoring    kube-prometheus-stack-prometheus-node-exporter-hsd7f        1/1     Running   0          9m36s
monitoring    kube-prometheus-stack-prometheus-node-exporter-m7cbq        1/1     Running   0          9m36s
monitoring    prometheus-kube-prometheus-stack-prometheus-0               2/2     Running   0          9m29s
```

PVC Jenkins прив'язаний — тобто EBS CSI-драйвер і дефолтний StorageClass `gp3`
працюють:

```console
$ kubectl get pvc -n jenkins
NAME      STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
jenkins   Bound    pvc-b2871ef6-b06f-4221-a30b-bb0b7a72b9ed   8Gi        RWO            gp3            12m
```

## 2. Сервіси, до яких звертається умова завдання

```console
$ kubectl get svc -A | grep -vE "^kube-system|^default"
NAMESPACE     NAME                                             TYPE           CLUSTER-IP       EXTERNAL-IP                                                               PORT(S)
argocd        argocd-applicationset-controller                 ClusterIP      172.20.164.232   <none>                                                                    7000/TCP
argocd        argocd-redis                                     ClusterIP      172.20.47.56     <none>                                                                    6379/TCP
argocd        argocd-repo-server                               ClusterIP      172.20.130.211   <none>                                                                    8081/TCP
argocd        argocd-server                                    ClusterIP      172.20.253.252   <none>                                                                    80/TCP,443/TCP
django-app    django-app                                       LoadBalancer   172.20.217.172   a4f5b6494a37847f48f7178b15a9ec7b-2067591945.us-west-2.elb.amazonaws.com   80:32466/TCP
jenkins       jenkins                                          ClusterIP      172.20.131.48    <none>                                                                    8080/TCP
jenkins       jenkins-agent                                    ClusterIP      172.20.136.61    <none>                                                                    50000/TCP
monitoring    alertmanager-operated                            ClusterIP      None             <none>                                                                    9093/TCP,9094/TCP,9094/UDP
monitoring    grafana                                          ClusterIP      172.20.152.59    <none>                                                                    80/TCP
monitoring    kube-prometheus-stack-alertmanager               ClusterIP      172.20.99.33     <none>                                                                    9093/TCP,8080/TCP
monitoring    kube-prometheus-stack-kube-state-metrics         ClusterIP      172.20.17.231    <none>                                                                    8080/TCP
monitoring    kube-prometheus-stack-operator                   ClusterIP      172.20.45.34     <none>                                                                    443/TCP
monitoring    kube-prometheus-stack-prometheus                 ClusterIP      172.20.24.14     <none>                                                                    9090/TCP,8080/TCP
monitoring    kube-prometheus-stack-prometheus-node-exporter   ClusterIP      172.20.102.232   <none>                                                                    9100/TCP
monitoring    prometheus-operated                              ClusterIP      None             <none>                                                                    9090/TCP
```

Три команди з умови працюють дослівно — імена сервісів і порти збігаються:

```bash
kubectl port-forward svc/jenkins 8080:8080 -n jenkins          # → http://localhost:8080
kubectl port-forward svc/argocd-server 8081:443 -n argocd      # → https://localhost:8081
kubectl port-forward svc/grafana 3000:80 -n monitoring         # → http://localhost:3000
```

`svc/grafana` називається саме так завдяки `grafana.fullnameOverride` у
`modules/monitoring/values.yaml`; без цього підчарт назвав би сервіс
`<реліз>-grafana`. Argo CD віддає HTTPS (`server.insecure` не вмикали), тому
порт 443 з команди умови справді відповідає — сертифікат самопідписаний,
`subject: O=Argo CD`.

## 3. CI/CD-цикл

Дві збірки джоби `django-app-ci`, обидві успішні:

```json
{"builds":[{"number":2,"result":"SUCCESS"},{"number":1,"result":"SUCCESS"}]}
```

Збірка #1 дала тег `1`, який у `values.yaml` уже стояв, тож пайплайн чесно
пропустив коміт («values.yaml не змінився — коміт не потрібен»). Повний цикл
з передачею через Git показує збірка #2:

```console
[2026-08-03T20:22:45.211Z] Збираю 918349930062.dkr.ecr.us-west-2.amazonaws.com/django-app:2
[2026-08-03T20:22:57.618Z] image.tag оновлено на 2
[2026-08-03T20:22:59.837Z] Запушено у гілку final-project
```

Образи в ECR:

```console
$ aws ecr describe-images --repository-name django-app --region us-west-2 \
    --query 'sort_by(imageDetails,&imagePushedAt)[*].[imageTags[0],imagePushedAt]' --output table
------------------------------------------------
|                DescribeImages                |
+--------+-------------------------------------+
|  1     |  2026-08-03T23:20:19.203000+03:00   |
|  latest|  2026-08-03T23:22:56.224000+03:00   |
+--------+-------------------------------------+
```

Argo CD побачив коміт Jenkins і розгорнув його. У полі `revision` — той самий
`d00360e`, що його запушив пайплайн:

```console
$ kubectl get application django-app -n argocd \
    -o jsonpath='sync={.status.sync.status} health={.status.health.status} revision={.status.sync.revision}'
sync=Synced health=Healthy revision=d00360eb48ee7615c86bf120fe7027393f055338

$ kubectl get application django-app -n argocd -o jsonpath='{range .status.history[*]}{.revision}  {.deployedAt}{"\n"}{end}'
5f8cf14a239b21a247cdce612e7b6f758cb189cf  2026-08-03T20:15:12Z   # перший деплой, тег 1
d00360eb48ee7615c86bf120fe7027393f055338  2026-08-03T20:23:16Z   # коміт від Jenkins, тег 2

$ kubectl get deploy django-app -n django-app -o jsonpath='{.spec.template.spec.containers[0].image}'
918349930062.dkr.ecr.us-west-2.amazonaws.com/django-app:2
```

Ланцюжок замкнено: **Jenkins зібрав → запушив у ECR → змінив `image.tag` у Git →
Argo CD побачив коміт → розгорнув новий образ у кластері.**

## 4. Застосунок і RDS

```console
$ curl http://a4f5b6494a37847f48f7178b15a9ec7b-2067591945.us-west-2.elb.amazonaws.com/
{
  "app": "django-app",
  "pod": "django-app-56c889b7c6-mzp66",
  "database": "ok",
  "config": {
    "DJANGO_ENV": "production",
    "DJANGO_DEBUG": "False",
    "DJANGO_ALLOWED_HOSTS": "*",
    "DJANGO_SETTINGS_MODULE": "myproject.settings",
    "POSTGRES_DB": "django_db",
    "POSTGRES_USER": "django_user",
    "POSTGRES_HOST": "final-project-db.cp6mgs2oaj1v.us-west-2.rds.amazonaws.com",
    "POSTGRES_PORT": "5432"
  },
  "secrets": {
    "POSTGRES_PASSWORD": "set",
    "DJANGO_SECRET_KEY": "set"
  }
}
```

`"database": "ok"` разом із `POSTGRES_HOST`, що вказує на endpoint RDS, — це і є
доказ, що застосунок працює зі справжньою керованою базою, а не з подом-сусідом.
Поди в стані `1/1 Running` означають додатково, що відпрацював initContainer з
`manage.py migrate`: у базу не просто «достукались», у ній створено схему.

Параметри бази — результат умовної логіки модуля `rds`:

```console
$ terraform output rds_is_aurora
false
$ terraform output rds_endpoint
"final-project-db.cp6mgs2oaj1v.us-west-2.rds.amazonaws.com"
$ terraform output rds_instance_class
"db.t3.micro"
$ terraform output rds_parameter_group_family
"postgres16"
$ terraform output rds_applied_parameters
tomap({
  "log_statement" = { "apply_method" = "immediate",      "value" = "ddl"  }
  "max_connections" = { "apply_method" = "pending-reboot", "value" = "100" }
  "work_mem" = { "apply_method" = "immediate",      "value" = "4096" }
})
```

## 5. Автоскейлер

```console
$ kubectl get hpa -n django-app
NAME         REFERENCE               TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
django-app   Deployment/django-app   cpu: 1%/70%   2         6         2          10m
```

У колонці TARGETS — реальний відсоток, а не `<unknown>`: metrics-server стоїть
add-on'ом у модулі `eks`, а `resources.requests.cpu` заданий у чарті.

## 6. Моніторинг

Prometheus скрапить 23 таргети, **усі UP**:

```console
$ curl -s 'http://localhost:9090/api/v1/targets?state=active' | jq '.data.activeTargets | group_by(.health) | map({(.[0].health): length}) | add'
{"up": 23}
```

Жодного DOWN, бо в `modules/monitoring/values.yaml` навмисно вимкнені
`kubeControllerManager`, `kubeScheduler`, `kubeEtcd` і `kubeProxy`: у EKS панель
керування тримає AWS і її метрики ззовні недоступні — з ними в списку назавжди
висіли б чотири мертві таргети.

Grafana: datasource підключений автоматично, дашборди імпортовані.

```console
$ curl -s -u admin:*** http://localhost:3000/api/datasources | jq -r '.[] | "\(.name) \(.type) \(.url) default=\(.isDefault)"'
Alertmanager alertmanager http://kube-prometheus-stack-alertmanager.monitoring:9093/ default=false
Prometheus   prometheus   http://kube-prometheus-stack-prometheus.monitoring:9090/   default=true

$ curl -s -u admin:*** 'http://localhost:3000/api/search?type=dash-db&limit=200' | jq length
25
```

Серед 25 дашбордів — ті, що показують саме цей стенд:

- Kubernetes / Compute Resources / Cluster
- Kubernetes / Compute Resources / Namespace (Pods) — неймспейс `django-app`
- Kubernetes / Compute Resources / Node (Pods)
- Node Exporter / Nodes

## 7. Знищення

Після зняття цього протоколу інфраструктуру погашено:

```bash
terraform destroy
```

S3-бакет зі стейтом і DynamoDB-таблиця лишились: модуль `s3-backend` у цьому
проєкті вимкнений (`create_state_backend = false`), тож `destroy` їх не чіпає.
