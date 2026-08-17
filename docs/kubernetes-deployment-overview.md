# LiteLLM Kubernetes Deployment - Überblick

## Inhaltsverzeichnis

1. [Einführung](#einführung)
2. [Architektur-Überblick](#architektur-überblick)
3. [Komponenten](#komponenten)
4. [Umgebungen](#umgebungen)
5. [Sicherheitskonzept](#sicherheitskonzept)
6. [Dokumente in dieser Serie](#dokumente-in-dieser-serie)

## Einführung

Dieses Dokumenten-Set beschreibt das Kubernetes-Deployment von LiteLLM mit vollständiger Konfigurationsverwaltung durch das `yaml_config_support`-Framework.

**Ziele:**
- ✅ Wiederverwendbare, versionierbare Templates
- ✅ Strikte Trennung von öffentlichem Code und sensiblen Daten
- ✅ Umgebungsspezifische Konfigurationen (dev, staging, prod)
- ✅ Konsistente Konfigurationshandhabung über alle Umgebungen
- ✅ Zero-Trust Security Model

## Architektur-Überblick

### High-Level-Diagramm

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ Ingress (cert-manager + Let's Encrypt)               │   │
│  └──────────────┬───────────────────────────────────────┘   │
│                 │                                             │
│  ┌──────────────▼───────────────────────────────────────┐   │
│  │ Service (litellm-api)                                │   │
│  │ Type: ClusterIP, Port: 8000                          │   │
│  └──────────────┬───────────────────────────────────────┘   │
│                 │                                             │
│  ┌──────────────▼───────────────────────────────────────┐   │
│  │ Deployment (litellm-api)                             │   │
│  │ Replicas: {dev:1, staging:2, prod:3}               │   │
│  │ ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │   │
│  │ │ Pod 1       │  │ Pod 2       │  │ Pod N       │  │   │
│  │ │ LiteLLM API │  │ LiteLLM API │  │ LiteLLM API │  │   │
│  │ │ + Config    │  │ + Config    │  │ + Config    │  │   │
│  │ └─────────────┘  └─────────────┘  └─────────────┘  │   │
│  └──────────────┬───────────────────────────────────────┘   │
│                 │                                             │
│  ┌──────────────┴───────────────────────────────────────┐   │
│  │ ConfigMap + Secrets + PVC                            │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                               │
│  ┌───────────────────────────────────────────────────────┐   │
│  │ HorizontalPodAutoscaler (CPU/Memory-based)           │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### Externe Abhängigkeiten

```
┌─────────────────────────────────────────────────────┐
│ Externe Services (außerhalb K8s)                   │
├─────────────────────────────────────────────────────┤
│                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────┐  │
│  │ PostgreSQL   │  │ Redis Cache  │  │ S3 Store │  │
│  │ (Database)   │  │ (Optional)   │  │ (Logs)   │  │
│  └──────────────┘  └──────────────┘  └──────────┘  │
│                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────┐  │
│  │ OpenAI API   │  │ Anthropic    │  │ Sentry   │  │
│  │              │  │ (and more)   │  │ (Errors) │  │
│  └──────────────┘  └──────────────┘  └──────────┘  │
│                                                      │
│  ┌──────────────┐  ┌──────────────┐                │
│  │ cert-manager │  │ Monitoring   │                │
│  │ ClusterIssuer│  │ (Datadog)    │                │
│  └──────────────┘  └──────────────┘                │
│                                                      │
└─────────────────────────────────────────────────────┘
```

## Komponenten

### 1. Deployment (`deploy-litellm-api.yaml`)

Das zentrale Deployment, das LiteLLM-Pod-Replikationen verwaltet.

**Features:**
- RollingUpdate-Strategie (zero-downtime deployments)
- Pod Security Context (non-root, read-only filesystem wo möglich)
- Liveness- und Readiness-Probes
- Resource Requests/Limits
- Volume-Mounts für Config und Daten

**Konfigurierbar:**
- `deployment.replicas`
- `deployment.strategy`
- `resources.{requests,limits}`
- `livenessProbe.{initialDelaySeconds,periodSeconds}`
- `readinessProbe.{initialDelaySeconds,periodSeconds}`

### 2. Service (`service-litellm-api.yaml`)

Exponiert die LiteLLM API innerhalb des Clusters.

**Typ:** ClusterIP (intern)
**Port:** 8000 (HTTP)

### 3. Ingress (`ingress-litellm-api.yaml`)

Externe HTTP/HTTPS-Exposition mit automatischem TLS.

**Features:**
- NGINX Ingress Controller
- cert-manager Integration
- Let's Encrypt Zertifikate
- Rate Limiting (prod: 500 req/s)
- Proxy Timeouts (600s)

**Konfigurierbar:**
- `ingress.hosts[].host` (FQDN)
- `ingress.annotations.cert-manager.io/cluster-issuer`
- `ingress.tls` (TLS-Secrets)

### 4. ConfigMap (`configmap-litellm.yaml`)

Nicht-sensitive Konfiguration:
- `config.yaml` - LiteLLM-Konfiguration
- `litellm-config.json` - Modellkonfiguration, API-Settings
- `prometheus.yaml` - Monitoring

### 5. Secret (`secrets-litellm.yaml`)

**Sensitive Daten** (werden durch Value-Store gefüllt):
- API Keys (OpenAI, Anthropic, etc.)
- Database Credentials
- JWT Secrets
- SMTP Credentials
- Sentry DSN
- Datadog Keys

**⚠️ NIEMALS direkt in Git commiten!**

### 6. PersistentVolumeClaim (`pvc-litellm-data.yaml`)

Persistenter Storage für Logs und lokale Caches.

**Konfigurierbar:**
- `persistentVolume.size` (5Gi dev, 20Gi staging, 100Gi prod)
- `persistentVolume.storageClassName`

### 7. RBAC (`rbac-litellm.yaml`)

Kubernetes Service Account und Rollen.

**Berechtigungen:**
- Read ConfigMaps
- Read Secrets
- Read Pods
- Minimal Privilege Principle

### 8. HorizontalPodAutoscaler (`hpa-litellm.yaml`)

Automatische Skalierung basierend auf Metriken.

**Metriken:**
- CPU Utilization
- Memory Utilization

**Limits pro Umgebung:**
- Dev: 1-2 Replicas
- Staging: 2-5 Replicas
- Prod: 3-10 Replicas

### 9. Namespace (`namespace.yaml`)

Logische Isolation im K8s-Cluster.

**Default:** `litellm`

## Umgebungen

### Development

- **Replicas:** 1
- **CPU/Memory:** 100m/256Mi requests, 500m/512Mi limits
- **Storage:** 5Gi local-storage
- **HPA:** 1-2 Pods, CPU Threshold 70%
- **Ingress:** `litellm-dev.local` (self-signed)
- **Zertifikat:** letsencrypt-staging (für Tests)

**Use Case:** Lokale Entwicklung, schnelle Iterationen, limitierte Ressourcen

### Staging

- **Replicas:** 2
- **CPU/Memory:** 250m/512Mi requests, 1000m/1Gi limits
- **Storage:** 20Gi fast-storage
- **HPA:** 2-5 Pods, CPU Threshold 60%
- **Ingress:** `${STAGING_HOST}` (Let's Encrypt)
- **Zertifikat:** letsencrypt-prod (gültiges Zertifikat)

**Use Case:** Pre-production Testing, Staging-Umgebung für QA, Performance-Tests

### Production

- **Replicas:** 3 (High Availability)
- **CPU/Memory:** 500m/1Gi requests, 2000m/2Gi limits
- **Storage:** 100Gi premium-storage
- **HPA:** 3-10 Pods, CPU Threshold 50%
- **Ingress:** `${PROD_HOST}` (Let's Encrypt)
- **Zertifikat:** letsencrypt-prod (gültiges Zertifikat)
- **Rate Limiting:** 500 req/s, 200 RPS
- **Monitoring:** Datadog, Sentry Integration

**Use Case:** Production-Workloads, Kundenverkehr, hohe Verfügbarkeit

## Sicherheitskonzept

### 1. Secret Management

**Problem:** API Keys, Passwörter, etc. dürfen nicht in Source Control sein.

**Lösung:** `yaml_config_support` Framework
- Templates mit Platzhaltern in Git
- Secret-Dateien im Value-Store (outside Git)
- Automatische Substitution beim Deployment

```
┌─────────────────────────────────┐
│ Public Git Repository           │
│  ├── k8s/prod/templates/*.yaml │
│  └── .gitignore (prod/generated/) │
└─────────────────────────────────┘
           ↓
         Füllung (python k8s_fill_config.py)
           ↓
┌─────────────────────────────────┐
│ Private Value-Store (~/dev_data/LiteLLM)│
│  ├── values_creds_prod.yaml    │
│  └── values_creds_staging.yaml │
└─────────────────────────────────┘
           ↓
        Merge & Render
           ↓
┌─────────────────────────────────┐
│ Generated k8s-Manifeste         │
│  └── k8s/prod/generated/cf-prod/ │
│      (NIEMALS in Git!)          │
└─────────────────────────────────┘
```

### 2. Pod Security Context

```yaml
securityContext:
  runAsNonRoot: true        # Kein root
  runAsUser: 1000           # Unprivileged User
  fsGroup: 1000             # Datei-Besitz
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: false  # Nur wo nötig writable
```

### 3. Network Security

- **Service:** Internal (ClusterIP)
- **Ingress:** HTTPS Only (TLS)
- **Rate Limiting:** DDoS-Mitigation
- **RBAC:** Minimal Privilege

### 4. API Key Management

**Separate Keys pro Umgebung:**
- Dev: Test-Keys (öffentliche Konten)
- Staging: Test-Keys (mögl. limitiert)
- Prod: Echte Production-Keys (stark geschützt)

**Rotation:**
- Regelmäßiger Wechsel (quarterly)
- Zero-downtime Rotation durch neue Secrets

### 5. Secret Rotation Workflow

```bash
# 1. Neue Secrets im Value-Store eintragen
vim ~/dev_data/LiteLLM/values_creds_prod.yaml

# 2. Neue Manifest-Dateien generieren
python k8s/k8s_fill_config.py prod

# 3. Secrets in K8s aktualisieren
kubectl apply -f k8s/prod/generated/cf-prod/secrets-*.yaml

# 4. Pods neu starten (automatisch durch Deployment)
kubectl rollout restart deployment/litellm-api -n litellm

# 5. Alt-Keys deaktivieren (bei API Providers)
```

## Dokumente in dieser Serie

| Dokument | Inhaltsbereich |
|----------|-----------------|
| **kubernetes-deployment-overview.md** | ← Sie sind hier: Gesamt-Überblick, Architektur |
| [kubernetes-setup.md](./kubernetes-setup.md) | Cluster-Setup, Prerequisites, Installation |
| [kubernetes-configuration.md](./kubernetes-configuration.md) | Detaillierte Konfigurationsoptionen |
| [kubernetes-deployment-guide.md](./kubernetes-deployment-guide.md) | Schritt-für-Schritt Deployment-Anleitung |
| [kubernetes-troubleshooting.md](./kubernetes-troubleshooting.md) | Häufige Probleme und Lösungen |
| [kubernetes-monitoring.md](./kubernetes-monitoring.md) | Monitoring, Logging, Health Checks |

## Quick Links

- **Dev manifests:** `k8s/dev/`
- **Templates:** `k8s/prod/templates/`
- **CLI-Wrapper:** `k8s/k8s_fill_config.py`
- **Generated Outputs:** `k8s/prod/generated/` (in .gitignore)
- **README:** `k8s/README.md`

---

**Nächste Schritte:**
→ [Cluster-Setup](./kubernetes-setup.md)
