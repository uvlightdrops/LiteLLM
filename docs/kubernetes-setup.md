# LiteLLM Kubernetes Setup - Schritt-für-Schritt

## Inhaltsverzeichnis

1. [Prerequisites](#prerequisites)
2. [Cluster-Vorbereitung](#cluster-vorbereitung)
3. [yaml_config_support Installation](#yaml_config_support-installation)
4. [Value-Store Setup](#value-store-setup)
5. [Erste Konfigurationen](#erste-konfigurationen)
6. [Validierung](#validierung)

## Prerequisites

### Kubernetes Cluster

**Unterstützte Versionen:** Kubernetes 1.24+

**Erforderliche Komponenten:**
- kubectl CLI (1.24+) installiert
- Zugriff auf Cluster (kubeconfig konfiguriert)
- Helm (optional, aber empfohlen)

**Verfügbare Cluster-Optionen:**

```bash
# 1. Lokale Entwicklung: Minikube
minikube start --cpus=4 --memory=8192 --disk-size=50G
kubectl config use-context minikube

# 2. Docker Desktop Kubernetes
# → Settings → Kubernetes → Enable Kubernetes

# 3. Public Cloud: EKS (AWS)
aws eks create-cluster --name litellm-prod --version 1.28 ...

# 4. Public Cloud: AKS (Azure)
az aks create --resource-group mygroup --name litellm-prod ...

# 5. Public Cloud: GKE (Google)
gcloud container clusters create litellm-prod --num-nodes=3 ...

# 6. Self-Hosted: kubeadm
kubeadm init --pod-network-cidr=10.244.0.0/16
```

### Lokale Tools

```bash
# kubectl - Cluster-Verwaltung
kubectl version --client

# Optional aber empfohlen: Helm für Add-ons
helm version

# Optional: kubectx für Context-Switching
# https://github.com/ahmetb/kubectx
```

### DNS & TLS

**Production Requirements:**

- Domain registriert (z.B. `litellm.example.com`)
- DNS A-Record zeigt auf Ingress Controller
- **cert-manager** für automatische TLS-Zertifikate
- ClusterIssuer für Let's Encrypt konfiguriert

**Development:** Kann mit `/etc/hosts` und self-signed Certs getestet werden

## Cluster-Vorbereitung

### 1. NGINX Ingress Controller installieren

```bash
# Helm Repository hinzufügen
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# NGINX Ingress installieren (alle Namespaces)
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer
```

**Verifizieren:**
```bash
kubectl get svc -n ingress-nginx
# Sollte "ingress-nginx-controller" mit EXTERNAL-IP zeigen
```

### 2. cert-manager für TLS-Zertifikate

```bash
# Helm Repository
helm repo add jetstack https://charts.jetstack.io
helm repo update

# cert-manager mit CRDs installieren
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true
```

**Verifizieren:**
```bash
kubectl get crd | grep certmanager.k8s.io
# Sollte 3 CRDs zeigen (Certificate, ClusterIssuer, CertificateRequest)
```

### 3. ClusterIssuer für Let's Encrypt konfigurieren

**Development (self-signed):**
```bash
cat << 'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

**Production:**
```bash
cat << 'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

**Verifizieren:**
```bash
kubectl get clusterissuer
# Sollte beide IssuER zeigen (Ready: True)
```

### 4. Optional: Persistent Volume Storage

Falls keine Standard-StorageClass existiert:

```bash
# Für Minikube
minikube addons enable storage-provisioner

# Für kubeadm (local-path-provisioner)
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml

# Verifizieren
kubectl get storageclass
```

## yaml_config_support Installation

### 1. Repository Klonen/Kopieren

Der `yaml_config_support` sollte sich im Parent-Verzeichnis befinden:

```bash
# Falls noch nicht vorhanden
cd ~/dev_flow
git clone <yaml_config_support_repo>
# oder
cp -r yaml_config_support ~/dev_flow/

# Verifizieren
ls ~/dev_flow/yaml_config_support/
# Sollte: yaml_config_support/, tests/, docs/, requirements.txt zeigen
```

### 2. Python-Dependencies installieren

```bash
cd ~/dev_flow/yaml_config_support
python -m pip install -r requirements.txt

# Oder in venv
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 3. Installation verifizieren

```bash
python -c "from yaml_config_support.k8sValuesFill import K8sValuesFill; print('OK')"
# Sollte "OK" ausgeben (keine Fehler)
```

## Value-Store Setup

Der **Value-Store** enthält alle sensiblen Daten. Er ist **nicht in Git** und lokal auf dem Deployment-Rechner.

### 1. Value-Store Verzeichnis erstellen

```bash
# Sicheres Verzeichnis mit restriktiven Permissions
mkdir -p ~/dev_data/LiteLLM
chmod 700 ~/dev_data/LiteLLM

# Verifizieren
ls -ld ~/dev_data/LiteLLM
# Sollte: drwx------ zeigen (nur Owner read/write/execute)
```

### 2. Environment-spezifische Credential-Dateien

**Dateistruktur:**
```
~/dev_data/LiteLLM/
├── values_creds_dev.yaml      # Dev Secrets
├── values_creds_staging.yaml  # Staging Secrets
└── values_creds_prod.yaml     # Production Secrets (SEHR SICHER!)
```

### 3. Development Secrets füllen

```bash
cat > ~/dev_data/LiteLLM/values_creds_dev.yaml << 'EOF'
secrets:
  litellmMasterKey: "dev-master-key-12345"
  databasePassword: "dev-db-pass-insecure"
  databaseUrl: "postgresql://litellm:dev-db-pass-insecure@postgres-dev:5432/litellm_dev"
  
  apiKeys:
    openai:
      key: "sk-proj-dev-test-key-not-real"
    anthropic:
      key: "sk-ant-dev-test-key-not-real"
    
  auth:
    jwtSecret: "dev-jwt-secret-change-this"
    jwtAlgorithm: "HS256"
    
  sentry:
    dsn: "https://examplePublicKey@o0.ingest.sentry.io/0"
    environment: "development"

imagePullSecrets:
  - name: litellm-registry-secret
    registry: "registry.dev.local"
    username: "devuser"
    password: "dev-registry-pass"
    email: "dev@example.com"
EOF

chmod 600 ~/dev_data/LiteLLM/values_creds_dev.yaml
```

### 4. Production Secrets füllen (SEHR SICHER!)

```bash
# Mit externem Editor (sicherer als echo)
$EDITOR ~/dev_data/LiteLLM/values_creds_prod.yaml
```

**Template (kopieren + ausfüllen):**
```yaml
secrets:
  litellmMasterKey: "REAL-MASTER-KEY-HERE"
  databasePassword: "REAL-DB-PASSWORD-HERE"
  databaseUrl: "postgresql://litellm:PASSWORD@postgres.example.com:5432/litellm_prod"
  
  apiKeys:
    openai:
      key: "sk-proj-REAL-KEY-HERE"
    anthropic:
      key: "sk-ant-REAL-KEY-HERE"
    # ... weitere API Keys ...
    
  auth:
    jwtSecret: "REAL-JWT-SECRET-GENERATE-WITH-openssl-rand-32"
    jwtAlgorithm: "HS256"
    
  sentry:
    dsn: "https://REAL-SENTRY-DSN@sentry.example.com"
    environment: "production"

imagePullSecrets:
  - name: litellm-registry-secret
    registry: "registry.prod.example.com"
    username: "prod-user"
    password: "REAL-REGISTRY-PASSWORD"
    email: "prod@example.com"
```

**Permissions setzen:**
```bash
chmod 600 ~/dev_data/LiteLLM/values_creds_{staging,prod}.yaml

# Verifizieren (sollte alle -rw------- sein)
ls -l ~/dev_data/LiteLLM/
```

### 5. .gitignore Schutz

Stelle sicher, dass Value-Store nie in Git landet:

```bash
# Lokal (Pro-Tipp)
echo ~/dev_data/ >> ~/.gitignore_global
git config --global core.excludesfile ~/.gitignore_global

# Im Repository
echo "dev_data/" >> /path/to/your/repo/.gitignore
```

## Erste Konfigurationen

### 1. CLI-Wrapper testen

```bash
cd /home/flow/dev_ldbv/LiteLLM
python k8s/k8s_fill_config.py --help
# Sollte Help-Text zeigen
```

### 2. Development Config anwenden

```bash
kubectl apply -f k8s/dev/
```

### 3. Production Config generieren

```bash
python k8s/k8s_fill_config.py prod

# Ausgabe sollte sein:
# Füllen der LiteLLM K8s-Konfigurationen für Umgebung: prod
# ...
# ✓ Konfiguration erfolgreich gefüllt!
#   Ergebnis: k8s/prod/generated/cf-prod/updated_values-prod.yaml
```

### 4. Generated Files inspizieren

```bash
ls -la k8s/prod/generated/cf-prod/
# Sollte folgende Dateien enthalten:
# - deploy-litellm-api.yaml
# - service-litellm-api.yaml
# - ingress-litellm-api.yaml
# - configmap-litellm.yaml
# - secrets-litellm.yaml
# - pvc-litellm-data.yaml
# - hpa-litellm.yaml
# - rbac-litellm.yaml
# - namespace.yaml
```

### 5. Secrets verifizieren (WICHTIG!)

```bash
# Generated Secret inspizieren (NIEMALS in Git!)
cat k8s/prod/generated/cf-prod/secrets-litellm.yaml | head -20

# Sollte tatsächliche Secrets (NICHT Platzhalter) enthalten:
# litellm-master-key: "dev-master-key-12345"
# database-url: "postgresql://..."
# KEIN: "litellm-master-key: ${LITELLM_MASTER_KEY}"
```

## Validierung

### 1. Kubectl Verbindung prüfen

```bash
kubectl cluster-info
# Sollte Cluster Info + CA Certificate ausgeben

kubectl get nodes
# Sollte Cluster-Nodes zeigen
```

### 2. Namespaces vorbereiten

```bash
# Namespace erzeugen (optional, wird auch durch YAML gemacht)
kubectl apply -f k8s/prod/generated/cf-prod/namespace.yaml

# Verifizieren
kubectl get ns | grep litellm
```

### 3. YAML-Syntax validieren

```bash
# Alle YAMLs validieren (ohne deploy)
kubectl apply -f k8s/prod/generated/cf-prod/ --dry-run=client -v=6

# Sollte "success" ausgeben, KEINE Fehler
```

### 4. Ingress DNS konfigurieren

**Development (lokal):**
```bash
# Ingress IP finden
kubectl get ingress -n litellm
# EXTERNAL-IP kopieren

# /etc/hosts eintrag (macOS/Linux)
echo "127.0.0.1 litellm-dev.local" >> /etc/hosts

# Windows (C:\Windows\System32\drivers\etc\hosts)
# 127.0.0.1 litellm-dev.local
```

**Production:**
```bash
# Ingress IP finden
kubectl get ingress -n litellm
# EXTERNAL-IP kopieren

# DNS-Eintrag im Provider:
# A Record: litellm.example.com → [EXTERNAL-IP]
```

### 5. Storage-Klasse verifizieren

```bash
kubectl get storageclass

# Sollte mindestens eine Klasse zeigen, z.B.:
# NAME                 PROVISIONER
# fast-storage         pd.csi.storage.gke.io
# standard (default)   kubernetes.io/aws-ebs
```

## Next Steps

✅ Setup abgeschlossen!

→ [Konfiguration Details](./kubernetes-configuration.md)

→ [Deployment Anleitung](./kubernetes-deployment-guide.md)

---

**Probleme?** → [Troubleshooting Guide](./kubernetes-troubleshooting.md)
