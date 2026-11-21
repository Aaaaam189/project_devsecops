{{/*
Name of the resource. Uses the release name (helm install <name> ...)
so e.g. `helm install auth-service k3d/charts/service -f
values/auth.yaml` produces a Deployment/Service both named
"auth-service", matching the Service name every other service's
SPRING_DATASOURCE_URL / *_SERVICE_URL already expects (same hostnames
as the docker-compose.yml container_names).
*/}}
{{- define "service.name" -}}
{{- .Values.nameOverride | default .Release.Name -}}
{{- end -}}

{{/*
Common labels applied to every object this chart creates.
*/}}
{{- define "service.labels" -}}
app.kubernetes.io/name: {{ include "service.name" . }}
app.kubernetes.io/part-of: foundersync
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels — must be a strict subset of service.labels and must
never change across upgrades, since Deployment selectors are immutable.
*/}}
{{- define "service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "service.name" . }}
{{- end -}}
