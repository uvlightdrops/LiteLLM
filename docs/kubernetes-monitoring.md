# LiteLLM Kubernetes - Monitoring & Logging

## Inhaltsverzeichnis

1. [Health Checks](#health-checks)
2. [Logging Strategie](#logging-strategie)
3. [Prometheus Metriken](#prometheus-metriken)
4. [Datadog Integration](#datadog-integration)
5. [Sentry Error Tracking](#sentry-error-tracking)
6. [Performance Monitoring](#performance-monitoring)

## Health Checks

### Liveness Probe

**Was:** "Läuft der Pod noch oder ist er abgestürzt?"

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 30    # Warten bis erstem Check
  periodSeconds: 10          # Check alle 10 Sekunden
  failureThreshold: 3        # Nach 3x Fehler → Neustart
```

**Testen:**
```bash
kubectl exec -it -n litellm POD_NAME -- curl http://localhost:8000/health

# Sollte:
# HTTP 200
# {"status": "ok"}
```

### Readiness Probe

**Was:** "Ist der Pod bereit für Traffic?"

```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 10
  periodSeconds: 5           # Schneller als Liveness
  failureThreshold: 3
```

**Wirkung:**
- Wenn Readiness FALSE → Pod wird aus Service entfernt
- Ingress leitet keinen Traffic mehr hin
- Requests gehen zu anderen Pods

### Startup Probe (Optional)

```yaml
startupProbe:
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 0
  periodSeconds: 2
  failureThreshold: 30       # 60 Sekunden Startup-Zeit
```

**Für langsame Startups** (z.B. Model-Caching)

### Manuelles Health Check

```bash
# Alle Endpoints prüfen
curl -v http://litellm-api:8000/health
curl -v http://litellm-api:8000/models
curl -v http://litellm-api:8000/metrics

# Mit Auth
curl -H "Authorization: Bearer $MASTER_KEY" \
  http://litellm-api:8000/models
```

## Logging Strategie

### Log-Level Konfiguration

```yaml
# In values_onefitsall.yaml
env:
  LOG_LEVEL: ${LOG_LEVEL}
```

**Optionen:**
- `DEBUG` - Alles (sehr verbose)
- `INFO` - Normales Logging
- `WARNING` - Nur Warnungen
- `ERROR` - Nur Fehler

**Pro Umgebung:**
```
dev:    LOG_LEVEL: DEBUG
staging: LOG_LEVEL: INFO
prod:   LOG_LEVEL: WARNING
```

### Log Collection

```bash
# Aktuell laufende Logs
kubectl logs -n litellm -l app=litellm-api --tail=100

# Mit Timestamps
kubectl logs -n litellm -l app=litellm-api --timestamps=true

# Mehrere Pods parallel
kubectl logs -n litellm -l app=litellm-api -f

# Seit spezifischem Zeitpunkt
kubectl logs -n litellm -l app=litellm-api --since="2024-08-17T10:00:00Z"

# Alte Logs (vorheriger Start)
kubectl logs -n litellm POD_NAME --previous
```

### Structured Logging Export

```bash
# Zu JSON für externe Verarbeitung
kubectl logs -n litellm -l app=litellm-api -o json | \
  jq '.log' | grep ERROR

# Mit Kontext
kubectl logs -n litellm -l app=litellm-api \
  --kubeconfig=/path/to/kubeconfig \
  --namespace=litellm > /tmp/logs.txt
```

### Persistent Log Storage

```bash
# Logs in PVC speichern (optional)
kubectl describe pod -n litellm litellm-api-xxxxx | grep Mounts
# Sollte "/app/data" enthalten

# Logs aus PVC auslesen
kubectl exec -it -n litellm POD_NAME -- \
  find /app/data -name "*.log" -type f
```

## Prometheus Metriken

### Metric Endpoints

```bash
# Prometheus Metriken auslesen
curl http://litellm-api:8000/metrics

# Sollte zeigen:
# TYPE litellm_requests_total counter
# TYPE litellm_request_duration_seconds histogram
# TYPE litellm_model_cache_hits_total counter
```

### Prometheus Installation

```bash
# Helm hinzufügen
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Prometheus installieren
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values - << 'EOF'
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false
EOF
```

### ServiceMonitor für LiteLLM

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: litellm-api
  namespace: litellm
spec:
  selector:
    matchLabels:
      app: litellm-api
  endpoints:
  - port: http
    interval: 30s
    path: /metrics
```

### Wichtige Metriken

```
# Request-Volumen
litellm_requests_total{method="POST", endpoint="/chat/completions"}

# Latenz (P50, P95, P99)
litellm_request_duration_seconds{quantile="0.5"}
litellm_request_duration_seconds{quantile="0.95"}
litellm_request_duration_seconds{quantile="0.99"}

# Fehlerrate
litellm_request_errors_total{status="5xx"}

# Model-spezifische Metriken
litellm_model_requests_total{model="gpt-4"}
litellm_model_latency_seconds{model="gpt-4"}

# Cache Performance
litellm_model_cache_hits_total
litellm_model_cache_misses_total
```

### Alerts konfigurieren

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: litellm-alerts
  namespace: litellm
spec:
  groups:
  - name: litellm
    rules:
    - alert: HighErrorRate
      expr: |
        (rate(litellm_request_errors_total[5m]) / rate(litellm_requests_total[5m])) > 0.05
      for: 5m
      annotations:
        summary: "LiteLLM Error Rate > 5%"

    - alert: HighLatency
      expr: |
        histogram_quantile(0.95, rate(litellm_request_duration_seconds_bucket[5m])) > 2
      for: 10m
      annotations:
        summary: "LiteLLM P95 Latency > 2s"

    - alert: PodDown
      expr: |
        count(up{job="litellm-api"} == 1) < 1
      for: 2m
      annotations:
        summary: "No LiteLLM Pods Running"
```

## Datadog Integration

### Datadog Agent installieren

```bash
# Helm Chart
helm repo add datadog https://helm.datadoghq.com
helm repo update

helm install datadog-agent datadog/datadog \
  --namespace datadog \
  --create-namespace \
  --set datadog.apiKey=$DATADOG_API_KEY \
  --set datadog.appKey=$DATADOG_APP_KEY \
  --set clusterAgent.enabled=true
```

### APM (Application Performance Monitoring)

```yaml
# In Deployment ConfigMap
env:
- name: DD_TRACE_ENABLED
  value: "true"
- name: DD_AGENT_HOST
  valueFrom:
    fieldRef:
      fieldPath: status.hostIP
- name: DD_TRACE_AGENT_PORT
  value: "8126"
- name: DD_SERVICE
  value: "litellm-api"
- name: DD_ENV
  value: "production"
```

### Datadog Metrics

```bash
# Im Datadog Dashboard:
# - Request Rate (Requests/Sec)
# - Response Time (P50, P95, P99)
# - Error Rate
# - Pod Count
# - CPU/Memory Usage
# - Disk I/O
```

## Sentry Error Tracking

### Sentry SDK Integration

**LiteLLM sollte bereits Sentry haben, aber sicherstelle:**

```yaml
# In secrets-litellm.yaml
sentry-dsn: "https://key@sentry.example.com/project-id"
```

### Sentry Konfiguration in Code

```python
# In LiteLLM Config
import sentry_sdk

sentry_sdk.init(
    dsn=os.getenv("SENTRY_DSN"),
    environment=os.getenv("SENTRY_ENVIRONMENT"),
    traces_sample_rate=0.1,  # 10% Tracing
)
```

### Error Events

```bash
# Fehler-Dashboard zeigt:
# - Exception Type
# - Stack Trace
# - User Context
# - Breadcrumbs
# - Affected Users
```

### Alerts für kritische Errors

```bash
# In Sentry Dashboard konfigurieren:
# Alert wenn:
# - Error Rate > 5% einer Stunde
# - Neue Exception Typen
# - Error in kritischen Endpoints

# Webhook an Slack/PagerDuty
```

## Performance Monitoring

### HPA Metrik-Tracking

```bash
# Aktuelle HPA Entscheidungen
kubectl describe hpa -n litellm litellm-api-hpa

# Sollte zeigen:
# REFERENCE                     TARGETS         MINPODS MAXPODS REPLICAS AGE
# Deployment/litellm-api        45%/60%         2       10      5        2h
```

### Response Time Distribution

```bash
# Logs mit Latenz-Infos parsen
kubectl logs -n litellm -l app=litellm-api | \
  grep "duration:" | \
  awk '{print $NF}' | \
  sort -n | \
  awk '{sum+=$1; sumsq+=$1*$1} END {
    n = NR
    mean = sum/n
    stddev = sqrt((sumsq - sum*sum/n)/n)
    print "Mean:", mean, "ms"
    print "Stddev:", stddev, "ms"
  }'
```

### Resource Utilization

```bash
# CPU/Memory über Zeit (trend)
kubectl top pods -n litellm --containers | \
  awk '{print $1, $3, $4}' > /tmp/usage.txt

# Mit watch (Live Update)
watch 'kubectl top pods -n litellm | sort -k3 -rn'

# Pod-spezifische Trend
kubectl top pod -n litellm POD_NAME --containers
```

### Bottleneck Identification

```bash
# Langsame Request-Handler
kubectl logs -n litellm -l app=litellm-api | \
  grep "duration: [5-9][0-9][0-9]" | \
  awk -F'endpoint=' '{print $2}' | \
  cut -d' ' -f1 | \
  sort | uniq -c | sort -rn

# Welche Modelle sind langsam?
kubectl logs -n litellm -l app=litellm-api | \
  grep "model=" | \
  grep "duration:" | \
  awk -F'model=' '{print $2}' | \
  sort | uniq -c | sort -rn
```

### Alerting Rules

```yaml
# Kritische Schwellen
- Pod Response Time P95 > 2s
- Pod Error Rate > 5%
- Pod Memory > 80% Limit
- Pod CPU > 80% Limit
- Pod Restarts in 1h > 3
- All Pods Down
- Ingress Certificate expires < 7 Tage
```

---

**Back to:** [Deployment Guide](./kubernetes-deployment-guide.md)

**Questions?** → [Troubleshooting](./kubernetes-troubleshooting.md)
