# LiteLLM Kubernetes - Deployment Guide

## Inhaltsverzeichnis

1. [Pre-Deployment Checks](#pre-deployment-checks)
2. [Konfiguration Generieren](#konfiguration-generieren)
3. [Deployment durchführen](#deployment-durchführen)
4. [Validierung](#validierung)
5. [Post-Deployment Verifikation](#post-deployment-verifikation)
6. [Updates & Rollbacks](#updates--rollbacks)

## Pre-Deployment Checks

### Checklist

```bash
# 1. Cluster-Verbindung
kubectl cluster-info
kubectl get nodes

# 2. NGINX Ingress Controller
kubectl get svc -n ingress-nginx
# Sollte "ingress-nginx-controller" mit EXTERNAL-IP zeigen

# 3. cert-manager
kubectl get crd | grep certmanager.k8s.io
# Sollte 3 CRDs zeigen

# 4. ClusterIssuer
kubectl get clusterissuer
# Sollte "letsencrypt-staging" und "letsencrypt-prod" zeigen (Ready: True)

# 5. StorageClass
kubectl get storageclass
# Sollte mindestens eine Klasse zeigen

# 6. Value-Store
ls -la ~/.litellm/k8s-secrets/
# Sollte values_creds_*.yaml Dateien enthalten

# 7. Templates
ls -la k8s/templates/ | grep -v "^d"
# Sollte 18 Dateien zeigen
```

### Namespace Planung

```bash
# Standard: "litellm" Namespace (empfohlen)
# Alternative: Pro-Umgebung separater Namespace

# Production Best Practice:
kubectl create namespace litellm-prod
kubectl create namespace litellm-staging
kubectl create namespace litellm-dev
```

## Konfiguration Generieren

### 1. Development Config

```bash
cd /home/flow/dev_ldbv/LiteLLM

python k8s/k8s_fill_config.py dev

# Ausgabe:
# Füllen der LiteLLM K8s-Konfigurationen für Umgebung: dev
# Template-Verzeichnis: k8s/templates
# Value-Store-Verzeichnis: ~/.litellm/k8s-secrets
# Ausgabeverzeichnis: k8s/generated
# 
# ✓ Konfiguration erfolgreich gefüllt!
#   Ergebnis: k8s/generated/cf-dev/updated_values-dev.yaml
```

### 2. Generated Files inspizieren

```bash
# Verifizieren, dass alle Dateien generiert wurden
ls -la k8s/generated/cf-dev/

# Sollte zeigen:
# -rw-r--r-- configmap-litellm.yaml
# -rw-r--r-- deploy-litellm-api.yaml
# -rw-r--r-- hpa-litellm.yaml
# -rw-r--r-- ingress-litellm-api.yaml
# -rw-r--r-- namespace.yaml
# -rw-r--r-- pvc-litellm-data.yaml
# -rw-r--r-- rbac-litellm.yaml
# -rw-r--r-- secrets-litellm.yaml
# -rw-r--r-- service-litellm-api.yaml
# -rw-r--r-- updated_values-dev.yaml
```

### 3. Secrets verifizieren (KRITISCH!)

```bash
# NIEMALS generierte Secrets in Git!
cat k8s/generated/cf-dev/secrets-litellm.yaml | head -20

# Sollte ECHTE Secrets enthalten, z.B.:
# litellm-master-key: "dev-master-key-12345"
# NICHT: "litellm-master-key: ${LITELLM_MASTER_KEY}"

# Verify: KEINE Platzhalter mehr?
grep -n '\${' k8s/generated/cf-dev/secrets-litellm.yaml
# Sollte KEINE Ausgabe zeigen!
```

### 4. YAML Syntax validieren

```bash
# Dry-run: Alle YAMLs überprüfen ohne anzuwenden
kubectl apply -f k8s/generated/cf-dev/ \
  --namespace litellm \
  --dry-run=client \
  -v=6

# Sollte "success" zeigen, KEINE Fehler
```

### 5. Custom Output Directory (Optional)

```bash
# Für sicheren Output-Pfad (z.B. /tmp, verschlüsselt)
python k8s/k8s_fill_config.py prod \
  --outdir /secure/k8s-output

# Ausgabe liegt dann in:
# /secure/k8s-output/cf-prod/
```

## Deployment durchführen

### 1. Namespace erstellen

```bash
# Option A: Über generierte YAML
kubectl apply -f k8s/generated/cf-dev/namespace.yaml

# Verifizieren
kubectl get namespaces | grep litellm
```

### 2. Secrets deployen (ZUERST!)

```bash
# Secrets müssen VOR anderen Ressourcen existieren
kubectl apply -f k8s/generated/cf-dev/secrets-litellm.yaml

# Verifizieren
kubectl get secrets -n litellm
# Sollte "litellm-secrets" zeigen
```

### 3. ConfigMap & RBAC deployen

```bash
# ConfigMap
kubectl apply -f k8s/generated/cf-dev/configmap-litellm.yaml

# RBAC (ServiceAccount + Roles)
kubectl apply -f k8s/generated/cf-dev/rbac-litellm.yaml

# Verifizieren
kubectl get configmap -n litellm
kubectl get serviceaccount -n litellm
kubectl get roles -n litellm
```

### 4. Persistent Volume Claim

```bash
kubectl apply -f k8s/generated/cf-dev/pvc-litellm-data.yaml

# Verifizieren
kubectl get pvc -n litellm
# Status sollte "Bound" sein
```

### 5. Deployment, Service, HPA

```bash
# Deployment (mit Pods)
kubectl apply -f k8s/generated/cf-dev/deploy-litellm-api.yaml

# Service (Load Balancing)
kubectl apply -f k8s/generated/cf-dev/service-litellm-api.yaml

# HorizontalPodAutoscaler
kubectl apply -f k8s/generated/cf-dev/hpa-litellm.yaml

# Verifizieren
kubectl get deployment -n litellm
kubectl get pods -n litellm
kubectl get svc -n litellm
kubectl get hpa -n litellm
```

### 6. Ingress (Letzter Schritt)

```bash
kubectl apply -f k8s/generated/cf-dev/ingress-litellm-api.yaml

# Verifizieren
kubectl get ingress -n litellm
```

### Alternative: All-in-One

```bash
# ACHTUNG: Nur wenn Pre-Checks ok!
kubectl apply -f k8s/generated/cf-dev/

# Überprüfung
kubectl get all -n litellm
```

## Validierung

### 1. Pods starten?

```bash
# Pods beobachten (Live)
kubectl logs -f -n litellm -l app=litellm-api

# Oder Status prüfen
kubectl get pods -n litellm -o wide

# Sollte zeigen:
# NAME                                  READY   STATUS    RESTARTS
# litellm-api-xxxxx                     1/1     Running   0
```

### 2. Service erreichbar?

```bash
# Port Forwarding zum Test
kubectl port-forward -n litellm svc/litellm-api 8000:8000

# In anderem Terminal:
curl http://localhost:8000/health
# Sollte HTTP 200 + Health Status zurückgeben
```

### 3. Ingress TLS Certificate

```bash
# Zertifikat Status
kubectl describe certificate -n litellm
# Status sollte "True" sein

# ODER: Warten auf cert-manager
kubectl get certificate -n litellm -w
# Sollte "READY True" zeigen
```

### 4. Load Test

```bash
# Kleine Last generieren
for i in {1..100}; do
  curl http://localhost:8000/models \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" &
done
wait

# HPA sollte Skalierung durchführen
kubectl get hpa -n litellm -w
```

## Post-Deployment Verifikation

### 1. Endpoints prüfen

```bash
# API Endpoints testen
MASTER_KEY="your-actual-master-key"
HOST="litellm.example.com"

# Health Check
curl https://$HOST/health

# Modelle auflisten
curl https://$HOST/models \
  -H "Authorization: Bearer $MASTER_KEY"

# Completion Test
curl https://$HOST/chat/completions \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

### 2. Logs inspizieren

```bash
# Aktuell laufende Logs
kubectl logs -n litellm -l app=litellm-api --tail=100

# Historische Logs (einige Zeit)
kubectl logs -n litellm -l app=litellm-api --since=1h

# Pod-spezifisch
kubectl logs -n litellm POD_NAME
```

### 3. Events anschauen

```bash
# Was ist passiert?
kubectl describe node
kubectl describe pod -n litellm litellm-api-xxxxx
kubectl describe ingress -n litellm
```

### 4. Storage Mounting

```bash
# PVC gemountet?
kubectl get pvc -n litellm -o wide

# In Pod prüfen
kubectl exec -it -n litellm POD_NAME -- ls -la /app/data
```

### 5. Metriken (HPA)

```bash
# Sind Metriken verfügbar?
kubectl top nodes
kubectl top pods -n litellm

# HPA Entscheidungen
kubectl describe hpa -n litellm litellm-api-hpa
```

## Updates & Rollbacks

### Image Update

```bash
# 1. Neue Config generieren
python k8s/k8s_fill_config.py dev

# 2. Deployment mit neuem Image updaten
kubectl apply -f k8s/generated/cf-dev/deploy-litellm-api.yaml

# 3. Rollout Status beobachten
kubectl rollout status -n litellm deployment/litellm-api

# Fortschritt (live)
kubectl get pods -n litellm -w
```

### Secret Update

```bash
# 1. Neue Secrets im Value-Store aktualisieren
vim ~/.litellm/k8s-secrets/values_creds_dev.yaml

# 2. Config neu generieren
python k8s/k8s_fill_config.py dev

# 3. Secrets in K8s aktualisieren
kubectl apply -f k8s/generated/cf-dev/secrets-litellm.yaml

# 4. Pods neu starten (automatisch durch Deployment)
kubectl rollout restart deployment/litellm-api -n litellm

# 5. Warten bis neue Pods laufen
kubectl rollout status -n litellm deployment/litellm-api
```

### Rollback bei Problem

```bash
# Rollout History prüfen
kubectl rollout history -n litellm deployment/litellm-api

# Zur vorherigen Version zurück
kubectl rollout undo -n litellm deployment/litellm-api

# Zu spezifischer Revision
kubectl rollout undo -n litellm deployment/litellm-api --to-revision=2
```

### Full Redeployment

```bash
# Alles löschen (gefährlich!)
kubectl delete namespace litellm

# Neu deployen
kubectl apply -f k8s/generated/cf-dev/

# Warten
kubectl get pods -n litellm -w
```

---

**Nächste Schritte:**
→ [Monitoring & Logging](./kubernetes-monitoring.md)

**Probleme?**
→ [Troubleshooting Guide](./kubernetes-troubleshooting.md)
