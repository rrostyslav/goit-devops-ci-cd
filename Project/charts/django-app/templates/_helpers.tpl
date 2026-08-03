{{/*
Коротке ім'я чарта.
*/}}
{{- define "django-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Повне ім'я ресурсів: "<реліз>-<чарт>", або просто "<реліз>", якщо ім'я релізу
вже містить назву чарта.
*/}}
{{- define "django-app.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "django-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Загальні лейбли.
*/}}
{{- define "django-app.labels" -}}
helm.sh/chart: {{ include "django-app.chart" . }}
{{ include "django-app.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Лейбли-селектори (незмінні між релізами).
*/}}
{{- define "django-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "django-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Імена ресурсів із змінними середовища.
*/}}
{{- define "django-app.configMapName" -}}
{{ include "django-app.fullname" . }}-config
{{- end }}

{{- define "django-app.secretName" -}}
{{ include "django-app.fullname" . }}-secret
{{- end }}

{{/*
Джерела змінних середовища. Спільні для контейнера застосунку й для
initContainer з міграціями — обидва мають бачити однакову конфігурацію,
інакше міграції поїдуть в одну базу, а застосунок — в іншу.

Порядок має значення: у Kubernetes при збігу ключів виграє останнє джерело
в списку. Тому extraEnvFrom стоїть у кінці — саме так пароль із зовнішнього
Secret (наприклад, від RDS) перекриває значення з values.yaml, не змушуючи
переписувати сам чарт.
*/}}
{{- define "django-app.envFrom" -}}
- configMapRef:
    name: {{ include "django-app.configMapName" . }}
- secretRef:
    name: {{ include "django-app.secretName" . }}
{{- with .Values.extraEnvFrom }}
{{ toYaml . | trim }}
{{- end }}
{{- end }}

{{/*
Вбудований PostgreSQL.
*/}}
{{- define "django-app.postgresName" -}}
{{ include "django-app.fullname" . }}-postgres
{{- end }}

{{- define "django-app.postgresSelectorLabels" -}}
app.kubernetes.io/name: {{ include "django-app.name" . }}-postgres
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
