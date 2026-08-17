# LiteLLM Kubernetes - Konfigurationshandbuch

## Inhaltsverzeichnis

1. [Basis-Template: values_onefitsall.yaml](#basis-template-values_onefitsallYaml)
2. [Credentials: values_creds_*.yaml](#credentials-values_creds_yaml)
3. [Ressourcen: values_resources.yaml](#ressourcen-values_resourcesyaml)
4. [Ingress: values_ingress.yaml](#ingress-values_ingressyaml)
5. [Platzhalter Referenz](#platzhalter-referenz)
6. [Umgebungsspezifische Anpassungen](#umgebungsspezifische-anpassungen)

## Basis-Template: values_onefitsall.yaml

Das Haupttemplate definiert alle Basis-Konfigurationen mit Platzhaltern.

### Namespace & Image

```yaml
namespace: litellm

image:
  repository: litellm              # Docker Image Name
  tag: ${IMAGE_TAG}                # Version (z.B. "v0.3.0", "latest")
  pullPolicy: IfNotPresent         # Always, IfNotPresent, Never
  pullSecrets: []
```

**Beispiele:**
```bash
# Development
IMAGE_TAG=latest

# Staging
IMAGE_TAG=v0.3.5-staging

# Production
IMAGE_TAG=v0.3.5
```

### Deployment Strategie

```yaml
deployment:
  name: litellm-api
  replicas: ${REPLICAS}            # Initiale Pod-Anzahl
  strategy:
    type: RollingUpdate             # Auswahl: RollingUpdate, Recreate
    rollingUpdate:
      maxSurge: 1                    # Zusätzliche Pods während Update
      maxUnavailable: 0              # Zero-Downtime Updates
```

**Use Cases:**
- `maxUnavailable: 0` → Zero-Downtime (prod)
- `maxUnavailable: 1` → Schneller (dev/staging)

### Resource Management

```yaml
resources:
  requests:
    cpu: ${CPU_REQUEST}             # Garantierte CPU
    memory: ${MEMORY_REQUEST}       # Garantierter RAM
  limits:
    cpu: ${CPU_LIMIT}               # Maximum CPU
    memory: ${MEMORY_LIMIT}         # Maximum RAM
```

**Faustregel:**
```
requests = basis workload
limits = burst capacity (2-4x requests)

Beispiel:
requests.cpu: 100m   (0.1 CPUs)
limits.cpu: 500m     (0.5 CPUs)
```

**Umgebungen:**
```
Dev:        100m/256Mi req, 500m/512Mi limit
Staging:    250m/512Mi req, 1000m/1Gi limit
Production: 500m/1Gi req, 2000m/2Gi limit
```

### Service Konfiguration

```yaml
service:
  type: ClusterIP                  # Nur Cluster-intern
  port: 8000                       # Externer Port (von außen)
  targetPort: 8000                 # Container Port
  name: litellm-api
```

**Port-Zuordnung:**
```
Client → Ingress (443/80) 
       → Service (:8000) 
       → Pod (:8000, LiteLLM)
```

### Ingress Konfiguration

```yaml
ingress:
  enabled: ${INGRESS_ENABLED}       # true/false
  className: nginx                  # Ingress Controller
  annotations:
    cert-manager.io/cluster-issuer: ${CERT_ISSUER}
  hosts:
    - host: ${INGRESS_HOST}         # FQDN
      paths:
        - path: /                   # Alle Requests
          pathType: Prefix
  tls:
    - secretName: litellm-tls
      hosts:
        - ${INGRESS_HOST}
```

**Beispiele:**

Development:
```yaml
ingress:
  enabled: true
  hosts:
    - host: litellm-dev.local
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-staging
```

Production:
```yaml
ingress:
  enabled: true
  hosts:
    - host: api.litellm.com
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
```

### Liveness & Readiness Probes

```yaml
livenessProbe:
  enabled: true
  httpGet:
    path: /health                   # Health-Check Endpoint
    port: 8000
  initialDelaySeconds: 30           # Warten bis erstem Check
  periodSeconds: 10                 # Check-Intervall

readinessProbe:
  enabled: true
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 10
  periodSeconds: 5
```

**Unterschied:**
- **livenessProbe:** Pod läuft? → Neustart wenn nicht
- **readinessProbe:** Bereit für Traffic? → Ausschließen wenn nicht

### Security Context

```yaml
podSecurityContext:
  runAsNonRoot: true                # Kein root
  runAsUser: 1000                   # Unprivileged User-ID
  fsGroup: 1000                     # File Group

securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: false
  capabilities:
    drop:
      - ALL                         # Keine Capabilities
```

## Credentials: values_creds_*.yaml

Sensitive Daten für jede Umgebung.

**Dateien:**
- `values_creds_dev.yaml` (in Value-Store)
- `values_creds_staging.yaml` (in Value-Store)
- `values_creds_prod.yaml` (in Value-Store)

### Struktur

```yaml
secrets:
  litellmMasterKey: "actual-key-here"
  databasePassword: "actual-password"
  databaseUrl: "postgresql://user:pass@host:5432/db"
  
  apiKeys:
    openai:
      key: "sk-proj-..."
    anthropic:
      key: "sk-ant-..."
    cohere:
      key: "..."
    azure:
      key: "..."
      endpoint: "https://..."
  
  auth:
    jwtSecret: "long-random-secret-string"
    jwtAlgorithm: "HS256"
  
  smtp:
    host: "smtp.example.com"
    port: 587
    username: "noreply@example.com"
    password: "smtp-password"
    fromEmail: "api@example.com"
  
  sentry:
    dsn: "https://key@sentry.example.com/123"
    environment: "production"
  
  datadog:
    apiKey: "dd_api_key_here"
    appKey: "dd_app_key_here"

imagePullSecrets:
  - name: litellm-registry-secret
    registry: "registry.example.com"
    username: "user"
    password: "password"
    email: "user@example.com"
```

### JWT Secret generieren

```bash
# Sichere Random-String generieren (Production)
openssl rand -base64 32
# Beispiel: "bR9kL2mN7pQ4vX8wZ1aB3cD5eF6gH9iJ"
```

### API-Keys pro Umgebung

**Development:**
- Test/Sandbox-Keys verwenden
- Kostenlose Trial-Accounts
- Limitierte Rate Limits ok

**Staging:**
- Test-Keys (möglich)
- Oder niedrige Quotas aus Prod-Keys
- Nicht mit echtem Traffic

**Production:**
- Echte Production-Keys
- Maximale Security
- Rotation regelmäßig

## Ressourcen: values_resources.yaml

Umgebungsspezifische Ressourcen-Definitionen.

### Struktur

```yaml
dev:
  deployment:
    replicas: 1
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi
  persistentVolume:
    size: 5Gi
    storageClassName: local-storage
  HPA_MIN_REPLICAS: 1
  HPA_MAX_REPLICAS: 2
  HPA_CPU_THRESHOLD: 70
  HPA_MEMORY_THRESHOLD: 80

staging:
  deployment:
    replicas: 2
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 1Gi
  # ...

prod:
  # ...
```

### CPU/Memory Sizing

**Requests (garantiert):**
```
Pro LiteLLM Instance (ca.):
  CPU: 100-500m (0.1-0.5 CPUs)
  Memory: 256-1024Mi (256MB-1GB)

Abhängig von:
- Anzahl Modelle im Cache
- Request-Volumen
- Model-Komplexität
```

**Limits (Maximum):**
```
Sollten sein:
  2-4x der Requests
  
Nicht zu hoch setzen:
  ⚠ Cluster-Stabilität
  ⚠ Node-Ressourcen
```

**Empfehlung für verschiedene Umgebungen:**
```
DEVELOPMENT:
  requests: 100m CPU, 256Mi RAM
  limits: 500m CPU, 512Mi RAM
  → Schnell iterativ, resource-arm

STAGING:
  requests: 250m CPU, 512Mi RAM
  limits: 1000m CPU, 1Gi RAM
  → Realistische Last-Tests

PRODUCTION:
  requests: 500m CPU, 1Gi RAM
  limits: 2000m CPU, 2Gi RAM
  → Reserve für Bursts
```

### Autoscaling Konfiguration

```yaml
HPA_MIN_REPLICAS: 2         # Mindestens 2 Pods
HPA_MAX_REPLICAS: 10        # Maximal 10 Pods
HPA_CPU_THRESHOLD: 50       # Scale bei 50% CPU
HPA_MEMORY_THRESHOLD: 60    # Scale bei 60% Memory
```

**Skalierungslogik:**
```
Pod 1: 100m request
Threshold: 50% = 50m actual

Bei Überschreitung:
  Scale Up (add Pod)
  
Nach Unterschreitung:
  Scale Down (remove Pod) nach 300s
```

## Ingress: values_ingress.yaml

Environment-spezifische Ingress-Konfigurationen.

```yaml
dev:
  ingress:
    enabled: true
    className: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-staging  # Self-signed
    hosts:
      - host: litellm-dev.local
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: litellm-dev-tls
        hosts:
          - litellm-dev.local

prod:
  ingress:
    enabled: true
    className: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod    # Gültig
      nginx.ingress.kubernetes.io/rate-limit: "500"
      nginx.ingress.kubernetes.io/limit-rps: "200"
    hosts:
      - host: api.litellm.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: litellm-prod-tls
        hosts:
          - api.litellm.com
```

### Rate Limiting

```yaml
# Production: Schutz vor Missbrauch
annotations:
  nginx.ingress.kubernetes.io/rate-limit: "500"    # 500 req/sec global
  nginx.ingress.kubernetes.io/limit-rps: "200"     # 200 req/sec per IP
```

## Platzhalter Referenz

### Aus values_onefitsall.yaml

| Platzhalter | Beschreibung | Beispiel |
|-------------|-------------|---------|
| `${IMAGE_TAG}` | Docker Tag | `latest`, `v0.3.5` |
| `${REPLICAS}` | Initial Pods | `1`, `2`, `3` |
| `${CPU_REQUEST}` | Min CPU | `100m`, `500m` |
| `${CPU_LIMIT}` | Max CPU | `500m`, `2000m` |
| `${MEMORY_REQUEST}` | Min RAM | `256Mi`, `1Gi` |
| `${MEMORY_LIMIT}` | Max RAM | `512Mi`, `2Gi` |
| `${INGRESS_ENABLED}` | Ingress an? | `true`, `false` |
| `${INGRESS_HOST}` | Hostname | `litellm.example.com` |
| `${CERT_ISSUER}` | TLS Issuer | `letsencrypt-prod` |
| `${LOG_LEVEL}` | Log Level | `DEBUG`, `INFO`, `WARNING` |
| `${STORAGE_CLASS}` | Storage Typ | `fast-storage`, `standard` |
| `${PVC_SIZE}` | Disk Größe | `5Gi`, `100Gi` |
| `${PVC_ENABLED}` | Storage an? | `true`, `false` |

### Aus values_creds_*.yaml (Secrets)

| Platzhalter | Beschreibung |
|-------------|-------------|
| `${LITELLM_MASTER_KEY_*}` | LiteLLM Master Key |
| `${DATABASE_URL_*}` | DB Connection String |
| `${OPENAI_API_KEY_*}` | OpenAI API Key |
| `${ANTHROPIC_API_KEY_*}` | Anthropic API Key |
| `${AZURE_API_KEY_*}` | Azure OpenAI Key |
| `${JWT_SECRET_*}` | JWT Secret |
| `${SMTP_*}` | Mail Server Config |
| `${SENTRY_DSN_*}` | Error Tracking |
| `${DATADOG_API_KEY_*}` | Monitoring API Key |
| `${REGISTRY_*}` | Docker Registry |

## Umgebungsspezifische Anpassungen

### Development

**Fokus:** Schnelle Entwicklung, minimale Ressourcen

```bash
# Generieren
python k8s/k8s_fill_config.py dev

# Features
- 1 Pod
- Staging TLS-Zertifikat
- Local Storage
- Minimal Resources
- No Rate Limiting
```

### Staging

**Fokus:** Realistisches Testing vor Production

```bash
# Generieren
python k8s/k8s_fill_config.py staging

# Features
- 2 Pods (HA Testing)
- Production TLS-Zertifikat
- Fast Storage
- Moderate Resources
- Autoscaling 2-5 Pods
```

### Production

**Fokus:** Maximale Verfügbarkeit und Performance

```bash
# Generieren
python k8s/k8s_fill_config.py prod

# Features
- 3 Pods (High Availability)
- Production TLS-Zertifikat
- Premium Storage
- High Resources
- Autoscaling 3-10 Pods
- Rate Limiting aktiviert
- Monitoring (Datadog, Sentry)
```

---

**Nächste Schritte:**
→ [Deployment Anleitung](./kubernetes-deployment-guide.md)

**Probleme?**
→ [Troubleshooting](./kubernetes-troubleshooting.md)
