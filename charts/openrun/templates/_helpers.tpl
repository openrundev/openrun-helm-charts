{{- define "openrun.name" -}}
  {{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "openrun.fullname" -}}
  {{- if .Values.fullnameOverride -}}
    {{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
  {{- else -}}
    {{- $name := default .Chart.Name .Values.nameOverride -}}
    {{- if contains $name .Release.Name -}}
      {{- .Release.Name | trunc 63 | trimSuffix "-" -}}
    {{- else -}}
      {{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{- define "openrun.chart" -}}
  {{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" -}}
{{- end -}}

{{- define "openrun.labels" -}}
helm.sh/chart: {{ include "openrun.chart" . | quote }}
app.kubernetes.io/name: {{ include "openrun.name" . | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service | quote }}
{{- end -}}

{{- define "openrun.selectorLabels" -}}
app.kubernetes.io/name: {{ include "openrun.name" . | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
{{- end -}}

{{- define "openrun.serviceAccountName" -}}
  {{- if .Values.serviceAccount.create -}}
    {{- default (printf "%s-sa" (include "openrun.fullname" .)) .Values.serviceAccount.name -}}
  {{- else -}}
    {{- default "default" .Values.serviceAccount.name -}}
  {{- end -}}
{{- end -}}

{{- define "openrun.configSecretName" -}}
  {{- if .Values.openrunConfigSecret.name -}}
    {{- .Values.openrunConfigSecret.name -}}
  {{- else -}}
    {{- printf "%s-config" (include "openrun.fullname" .) -}}
  {{- end -}}
{{- end -}}

{{- define "openrun.appsNamespace" -}}
  {{- printf "%s-apps" .Release.Namespace -}}
{{- end -}}

{{- define "openrun.postgresClusterName" -}}
  {{- if .Values.postgres.clusterName -}}
    {{- .Values.postgres.clusterName -}}
  {{- else -}}
    {{- printf "%s-db" (include "openrun.fullname" .) -}}
  {{- end -}}
{{- end -}}

{{- define "openrun.postgresInitConfigName" -}}
  {{- printf "%s-initdb" (include "openrun.postgresClusterName" .) -}}
{{- end -}}

{{- define "openrun.postgresLabels" -}}
{{ include "openrun.labels" . }}
app.kubernetes.io/component: postgres
{{- end -}}

{{- define "openrun.postgresSelectorLabels" -}}
{{ include "openrun.selectorLabels" . }}
app.kubernetes.io/component: postgres
{{- end -}}

{{- define "openrun.postgresAppSecretName" -}}
  {{- if .Values.postgres.appUser.existingSecretName -}}
    {{- .Values.postgres.appUser.existingSecretName -}}
  {{- else -}}
    {{- printf "%s-app" (include "openrun.postgresClusterName" .) -}}
  {{- end -}}
{{- end -}}

{{- define "openrun.postgresSuperuserSecretName" -}}
  {{- if .Values.postgres.superuser.existingSecretName -}}
    {{- .Values.postgres.superuser.existingSecretName -}}
  {{- else -}}
    {{- printf "%s-superuser" (include "openrun.postgresClusterName" .) -}}
  {{- end -}}
{{- end -}}

{{- define "openrun.registryServiceName" -}}
  {{- printf "%s-registry" (include "openrun.fullname" .) -}}
{{- end -}}

{{- define "openrun.registryDataPVCName" -}}
  {{- printf "%s-data" (include "openrun.registryServiceName" .) -}}
{{- end -}}

{{- define "openrun.registryAuthSecretName" -}}
  {{- if .Values.registry.auth.secretName -}}
    {{- .Values.registry.auth.secretName -}}
  {{- else -}}
    {{- printf "%s-registry-auth" (include "openrun.fullname" .) -}}
  {{- end -}}
{{- end -}}

{{- define "openrun.registryLabels" -}}
{{ include "openrun.labels" . }}
app.kubernetes.io/component: registry
{{- end -}}

{{- define "openrun.registrySelectorLabels" -}}
{{ include "openrun.selectorLabels" . }}
app.kubernetes.io/component: registry
{{- end -}}

{{- define "openrun.registryHostname" -}}
  {{- printf "%s.%s.svc.cluster.local" (include "openrun.registryServiceName" .) .Release.Namespace -}}
{{- end -}}

{{- define "openrun.postgresPrimaryDatabase" -}}
  {{- default "openrun" .Values.config.metadata.database -}}
{{- end -}}

{{- define "openrun.postgresExtraDatabases" -}}
  {{- $dbs := list (default "openrun" .Values.config.metadata.database) (default "openrun_audit" .Values.config.metadata.auditDatabase) -}}
  {{- $seen := dict -}}
  {{- $result := list -}}
  {{- range $db := $dbs }}
    {{- if and $db (ne $db "") -}}
      {{- if not (hasKey $seen $db) -}}
        {{- $_ := set $seen $db true -}}
        {{- $result = append $result $db -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
  {{- join " " $result -}}
{{- end -}}

{{- define "openrun.registryUrl" -}}
  {{- if and .Values.registry.enabled (not .Values.config.registry.url) -}}
    {{- printf "%s:%v" (include "openrun.registryHostname" .) (.Values.registry.service.port | default 5000) -}}
  {{- else -}}
    {{- .Values.config.registry.url -}}
  {{- end -}}
{{- end -}}

{{- define "openrun.postgresHostname" -}}
  {{- printf "%s.%s.svc.cluster.local" (include "openrun.postgresClusterName" .) .Release.Namespace -}}
{{- end -}}

{{- define "openrun.databaseSettings" -}}
  {{- $db := dict }}
  {{- if .Values.postgres.enabled -}}
    {{- $_ := set $db "host" (include "openrun.postgresHostname" .) -}}
    {{- $_ := set $db "port" 5432 -}}
    {{- $_ := set $db "database" (default "openrun" .Values.postgres.database) -}}
    {{- $_ := set $db "username" (default "openrun" .Values.postgres.appUser.username) -}}
    {{- $password := .Values.postgres.appUser.password -}}
    {{- if not $password -}}
      {{- $secret := (lookup "v1" "Secret" .Release.Namespace (include "openrun.postgresAppSecretName" .)) -}}
      {{- if and $secret $secret.data -}}
        {{- $_ = set $db "password" ((index $secret.data (default "password" .Values.postgres.appUser.passwordKey)) | b64dec) -}}
      {{- else -}}
        {{- $_ = set $db "password" "openrun" -}}
      {{- end -}}
    {{- else -}}
      {{- $_ = set $db "password" $password -}}
    {{- end -}}
  {{- else if .Values.externalDatabase.enabled -}}
    {{- $_ := set $db "host" (required "externalDatabase.host is required" .Values.externalDatabase.host) -}}
    {{- $_ := set $db "port" (default 5432 .Values.externalDatabase.port) -}}
    {{- $_ := set $db "database" (required "externalDatabase.database is required" .Values.externalDatabase.database) -}}
    {{- if .Values.externalDatabase.existingSecretName -}}
      {{- $extSecret := lookup "v1" "Secret" .Release.Namespace .Values.externalDatabase.existingSecretName -}}
      {{- if not $extSecret -}}
        {{- fail (printf "external database secret %s not found" .Values.externalDatabase.existingSecretName) -}}
      {{- end -}}
      {{- $_ = set $db "username" ((index $extSecret.data (default "username" .Values.externalDatabase.usernameKey)) | b64dec) -}}
      {{- $_ = set $db "password" ((index $extSecret.data (default "password" .Values.externalDatabase.passwordKey)) | b64dec) -}}
    {{- else -}}
      {{- $_ := set $db "username" (required "externalDatabase.username is required" .Values.externalDatabase.username) -}}
      {{- $_ := set $db "password" (required "externalDatabase.password is required" .Values.externalDatabase.password) -}}
    {{- end -}}
    {{- $_ := set $db "sslMode" (default "disable" .Values.externalDatabase.sslMode) -}}
    {{- $_ := set $db "parameters" .Values.externalDatabase.parameters -}}
  {{- else -}}
    {{- fail "Either postgres.enabled or externalDatabase.enabled must be true" -}}
  {{- end -}}
  {{- if not (hasKey $db "sslMode") -}}
    {{- $_ := set $db "sslMode" (default "disable" .Values.config.metadata.sslMode) -}}
  {{- end -}}
  {{- if not (hasKey $db "parameters") -}}
    {{- $_ := set $db "parameters" .Values.config.metadata.parameters -}}
  {{- end -}}
  {{- $db | toYaml -}}
{{- end -}}

{{- define "openrun.databaseConnectionFor" -}}
  {{- $ctx := index . "context" -}}
  {{- $database := (index . "database") | default "" -}}
  {{- $db := include "openrun.databaseSettings" $ctx | fromYaml -}}
  {{- if $database -}}
    {{- $_ := set $db "database" $database -}}
  {{- end -}}
  {{- $user := $db.username | urlquery -}}
  {{- $pass := $db.password | urlquery -}}
  {{- $params := $db.parameters -}}
  {{- if $params -}}
    {{- printf "postgres://%s:%s@%s:%v/%s?%s" $user $pass $db.host $db.port $db.database $params -}}
  {{- else -}}
    {{- printf "postgres://%s:%s@%s:%v/%s?sslmode=%s" $user $pass $db.host $db.port $db.database ($db.sslMode | default "disable") -}}
  {{- end -}}
{{- end -}}

{{- define "openrun.databaseConnectionString" -}}
  {{- include "openrun.databaseConnectionFor" (dict "context" .) -}}
{{- end -}}
