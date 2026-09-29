{{/* 公共标签：每个资源都带，方便 `kubectl get -l` 筛选与 Helm 归属识别 */}}
{{- define "mall.labels" -}}
app.kubernetes.io/part-of: mall
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}
