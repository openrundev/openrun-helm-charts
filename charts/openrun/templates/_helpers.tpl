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

{{/*
Returns the secret name for external database credentials.
When existingSecretName is provided, uses that; otherwise generates a name.
*/}}
{{- define "openrun.externalDatabaseSecretName" -}}
  {{- if .Values.externalDatabase.existingSecretName -}}
    {{- .Values.externalDatabase.existingSecretName -}}
  {{- else -}}
    {{- printf "%s-external-db" (include "openrun.fullname" .) -}}
  {{- end -}}
{{- end -}}

{{/*
Returns the secret name and keys for database credentials.
Works for both embedded postgres and external database.
Returns a dict with: secretName, usernameKey, passwordKey
*/}}
{{- define "openrun.databaseCredentialsInfo" -}}
  {{- $info := dict -}}
  {{- if .Values.postgres.enabled -}}
    {{- $_ := set $info "secretName" (include "openrun.postgresAppSecretName" .) -}}
    {{- $_ := set $info "usernameKey" (default "username" .Values.postgres.appUser.usernameKey) -}}
    {{- $_ := set $info "passwordKey" (default "password" .Values.postgres.appUser.passwordKey) -}}
  {{- else if .Values.externalDatabase.enabled -}}
    {{- $_ := set $info "secretName" (include "openrun.externalDatabaseSecretName" .) -}}
    {{- $_ := set $info "usernameKey" (default "username" .Values.externalDatabase.usernameKey) -}}
    {{- $_ := set $info "passwordKey" (default "password" .Values.externalDatabase.passwordKey) -}}
  {{- else -}}
    {{- fail "Either postgres.enabled or externalDatabase.enabled must be true" -}}
  {{- end -}}
  {{- $info | toYaml -}}
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

{{- define "openrun.dbInitMarkerName" -}}
  {{- printf "%s-db-init-complete" (include "openrun.fullname" .) -}}
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

{{- define "openrun.adminCredentials" -}}
  {{- $security := .Values.config.security | default (dict) -}}
  {{- if not $security }}
    {{- $_ := set .Values.config "security" (dict) -}}
    {{- $security = .Values.config.security -}}
  {{- end -}}
  {{- $cacheKey := "_computedAdminCredentials" -}}
  {{- if not (hasKey $security $cacheKey) -}}
    {{- if $security.adminPasswordBcrypt }}
      {{- $_ := set $security $cacheKey (dict "password" "" "bcrypt" $security.adminPasswordBcrypt "autoGenerated" false) -}}
    {{- else if $security.adminPassword }}
      {{- $plain := $security.adminPassword -}}
      {{- $hash := bcrypt $plain -}}
      {{- $_ := set $security $cacheKey (dict "password" $plain "bcrypt" $hash "autoGenerated" false) -}}
    {{- else }}
      {{- $plain := randAlphaNum 32 -}}
      {{- $hash := bcrypt $plain -}}
      {{- $_ := set $security $cacheKey (dict "password" $plain "bcrypt" $hash "autoGenerated" true) -}}
    {{- end -}}
  {{- end -}}
  {{- $creds := index $security $cacheKey -}}
  {{- printf "password: %s\nbcrypt: %s\nautoGenerated: %t" $creds.password $creds.bcrypt $creds.autoGenerated -}}
{{- end -}}

{{/*
Builds a database connection string using OpenRun secret provider syntax.
Instead of embedding credentials, uses {{secret "SECRET_NAME" "KEY"}} references.
Accepts optional "database" parameter to override the database name.
*/}}
{{- define "openrun.databaseConnectionWithSecrets" -}}
  {{- $ctx := index . "context" -}}
  {{- $database := (index . "database") | default "" -}}
  {{- $credInfo := include "openrun.databaseCredentialsInfo" $ctx | fromYaml -}}
  {{- $secretName := $credInfo.secretName -}}
  {{- $usernameKey := $credInfo.usernameKey -}}
  {{- $passwordKey := $credInfo.passwordKey -}}
  {{- $host := "" -}}
  {{- $port := 5432 -}}
  {{- $dbName := "" -}}
  {{- $sslMode := "disable" -}}
  {{- $parameters := "" -}}
  {{- if $ctx.Values.postgres.enabled -}}
    {{- $host = include "openrun.postgresHostname" $ctx -}}
    {{- $port = 5432 -}}
    {{- $dbName = default "openrun" $ctx.Values.postgres.database -}}
    {{- $sslMode = default "disable" $ctx.Values.config.metadata.sslMode -}}
    {{- $parameters = $ctx.Values.config.metadata.parameters -}}
  {{- else if $ctx.Values.externalDatabase.enabled -}}
    {{- $host = required "externalDatabase.host is required" $ctx.Values.externalDatabase.host -}}
    {{- $port = default 5432 $ctx.Values.externalDatabase.port -}}
    {{- $dbName = required "externalDatabase.database is required" $ctx.Values.externalDatabase.database -}}
    {{- $sslMode = default "disable" $ctx.Values.externalDatabase.sslMode -}}
    {{- $parameters = $ctx.Values.externalDatabase.parameters -}}
  {{- end -}}
  {{- if $database -}}
    {{- $dbName = $database -}}
  {{- end -}}
  {{- $userRef := printf "{{secret \"%s\" \"%s\" | pathEscape}}" $secretName $usernameKey -}}
  {{- $passRef := printf "{{secret \"%s\" \"%s\" | pathEscape}}" $secretName $passwordKey -}}
  {{- if $parameters -}}
    {{- printf "postgres://%s:%s@%s:%v/%s?%s" $userRef $passRef $host $port $dbName $parameters -}}
  {{- else -}}
    {{- printf "postgres://%s:%s@%s:%v/%s?sslmode=%s" $userRef $passRef $host $port $dbName $sslMode -}}
  {{- end -}}
{{- end -}}
