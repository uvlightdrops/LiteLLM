# LiteLLM Kubernetes - Troubleshooting Guide

## Inhaltsverzeichnis

1. [Pod & Deployment Issues](#pod--deployment-issues)
2. [Networking & Ingress](#networking--ingress)
3. [Storage & PVC](#storage--pvc)
4. [Secrets & Configuration](#secrets--configuration)
5. [Performance & Autoscaling](#performance--autoscaling)
6. [Certificate Issues](#certificate-issues)
7. [Debug Tools](#debug-tools)

## Pod & Deployment Issues

### Problem: Pod bleibt im "Pending" Status

**Ursachen & Lösungen:**

```bash
# 1. Ressourcen nicht verfügbar
kubectl describe pod -n litellm POD_NAME
# Achte auf "Insufficient cpu/memory"

# Lösung: Requests reduzieren oder Nodes hinzufügen
kubectl top nodes  # Verfügbare Ressourcen zeigen
kubectl edit deployment -n litellm litellm-api
# deployment.spec.template.spec.containers[0].resources.requests anpassen
kubectl apply -f <datei>

# 2. PVC nicht verfügbar
kubectl get pvc -n litellm
# Status sollte "Bound" sein, nicht "Pending"

# 3. Image nicht vorhanden
kubectl get pods -n litellm -o jsonpath='{.items[0].status.containerStatuses[0].imageID}'
# Sollte echtes Image zeigen, nicht Error

# Lösung: Correct Image Tag
python k8s/k8s_fill_config.py dev
kubectl apply -f k8s/generated/cf-dev/deploy-litellm-api.yaml
```

### Problem: Pod läuft, aber Ready=0/1

**Ursachen & Lösungen:**

```bash
# 1. Readiness Probe schlägt fehl
kubectl logs -n litellm POD_NAME | tail -50

# Prüfe: /health Endpoint erreichbar?
kubectl exec -it -n litellm POD_NAME -- curl http://localhost:8000/health

# Lösung: Health-Check Einstellungen anpassen
kubectl edit deployment -n litellm litellm-api
# deployment.spec.template.spec.containers[0].readinessProbe.initialDelaySeconds erhöhen

# 2. Application startet nicht
# Schau in Logs für Fehler:
kubectl logs -n litellm POD_NAME --previous  # Crashloop?
```

### Problem: Pod crasht immer wieder (CrashLoopBackOff)

```bash
# 1. Logs anschauen
kubectl logs -n litellm POD_NAME --previous

# Häufige Fehler:
# - Missing Environment Variables
# - Database Connection Failed
# - Invalid Config Files

# 2. Debug: Pod an geben
kubectl run -it --rm debug \
  --image=busybox \
  --restart=Never \
  -- sh

# Im Debug Pod:
wget -qO- http://litellm-api:8000/health

# 3. Temporär Readiness Probe deaktivieren
kubectl edit deployment -n litellm litellm-api
# readinessProbe.enabled: false

# Fix Problem, dann wieder aktivieren
```

### Problem: ImagePullBackOff

```bash
# 1. Image nicht gefunden
kubectl describe pod -n litellm POD_NAME
# Schau auf "Failed to pull image" Fehler

# 2. Registry Credentials fehlerhaft
kubectl get secret -n litellm litellm-registry-secret -o yaml

# 3. Image Tag korrekt?
python k8s/k8s_fill_config.py dev
# IMAGE_TAG sollte existierendes Tag sein
```

## Networking & Ingress

### Problem: Pod kann Datenbankserver nicht erreichen

```bash
# 1. Externe Host erreichbar?
kubectl exec -it -n litellm POD_NAME -- \
  curl postgresql://postgres-dev:5432

# 2. DNS in Pod funktioniert?
kubectl exec -it -n litellm POD_NAME -- nslookup postgres-dev
# Sollte IP-Adresse auflösen

# 3. Firewall/Network Policy?
kubectl get networkpolicies -n litellm

# Lösung: Externe Service erstellen
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: external-postgres
  namespace: litellm
spec:
  type: ExternalName
  externalName: postgres.example.com  # Externe Host
  ports:
  - port: 5432
EOF
```

### Problem: Ingress zeigt keine EXTERNAL-IP

```bash
# 1. NGINX Controller installiert?
kubectl get svc -n ingress-nginx
# Sollte "ingress-nginx-controller" mit EXTERNAL-IP zeigen

# 2. LoadBalancer verfügbar?
kubectl describe svc -n ingress-nginx ingress-nginx-controller
# Wenn Type=LoadBalancer, aber EXTERNAL-IP=<pending>
# → LoadBalancer nicht in Cluster verfügbar

# Lösung: NodePort statt LoadBalancer (Dev)
kubectl edit svc -n ingress-nginx ingress-nginx-controller
# spec.type: NodePort

# 3. Dann mit Node-IP zugreifen
kubectl get nodes -o wide
# curl http://NODE_EXTERNAL_IP:PORT
```

### Problem: HTTPS wird zu HTTP umgeleitet

```bash
# 1. TLS-Secret existiert?
kubectl get secret -n litellm
# Sollte "litellm-tls" zeigen

# 2. Zertifikat gültig?
kubectl describe certificate -n litellm
# Status sollte "Ready True" sein

# 3. Ingress TLS-Konfiguration korrekt?
kubectl get ingress -n litellm -o yaml | grep -A5 "tls:"

# Lösung: Annotation zur Force-HTTPS hinzufügen
kubectl annotate ingress -n litellm litellm-api-ingress \
  nginx.ingress.kubernetes.io/force-ssl-redirect=true \
  --overwrite
```

### Problem: 502 Bad Gateway von Ingress

```bash
# 1. Backend Service läuft?
kubectl get svc -n litellm
kubectl get endpoints -n litellm

# 2. Service Selector korrekt?
kubectl get svc -n litellm litellm-api -o yaml | grep selector
kubectl get pods -n litellm --show-labels

# Sollten Labels matchen!

# 3. Pod Port korrekt?
kubectl get svc -n litellm litellm-api -o yaml
# targetPort sollte Service Port matchen
```

## Storage & PVC

### Problem: PVC bleibt "Pending"

```bash
# 1. StorageClass existiert?
kubectl get storageclass
# Sollte mindestens eine zeigen

# 2. Provisioner verfügbar?
kubectl describe storageclass fast-storage
# Provisioner sollte "ready" sein

# 3. Namespace hat Zugriff?
kubectl get resourcequotas -n litellm

# Lösung: Storage-Klasse in Config korrigieren
python k8s/k8s_fill_config.py dev
# values_resources.yaml: storageClassName anpassen

# Oder Default StorageClass setzen
kubectl patch storageclass fast-storage \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### Problem: Pod kann PVC nicht mounten

```bash
# 1. PVC gelöscht worden?
kubectl get pvc -n litellm

# 2. Provisioning-Fehler?
kubectl describe pvc -n litellm litellm-data-pvc
# Events Section zeigt Fehler

# 3. Zugriff auf Mounted Volume?
kubectl exec -it -n litellm POD_NAME -- ls -la /app/data/
# Permission Denied?
```

## Secrets & Configuration

### Problem: Platzhalter nicht ersetzt

```bash
# 1. Secrets haben noch ${...}?
kubectl get secret -n litellm litellm-secrets -o jsonpath='{.data.litellm-master-key}' | base64 -d
# Sollte echten Wert zeigen, nicht "${LITELLM_MASTER_KEY}"

# 2. Value-Store Datei korrekt?
ls -la ~/.litellm/k8s-secrets/values_creds_dev.yaml
chmod 600 ~/.litellm/k8s-secrets/values_creds_dev.yaml

# 3. Config neu generieren
rm -rf k8s/generated/cf-dev/
python k8s/k8s_fill_config.py dev
# Neu deployen
kubectl apply -f k8s/generated/cf-dev/secrets-litellm.yaml
```

### Problem: Umgebungsvariablen in Pod nicht gesetzt

```bash
# 1. Secret in Deployment referenziert?
kubectl get deployment -n litellm litellm-api -o yaml | grep -A10 "env:"

# 2. Secret Key stimmt?
kubectl get secret -n litellm litellm-secrets -o yaml
# Schlüssel sollten in Deployment referenziert sein

# 3. In laufendem Pod prüfen
kubectl exec -it -n litellm POD_NAME -- env | grep LITELLM
```

### Problem: ConfigMap nicht aktualisiert

```bash
# 1. ConfigMap hat neue Inhalte?
kubectl get configmap -n litellm litellm-config -o yaml

# 2. Pod liest alte Version (Cache)?
# → Pod neu starten erzwingt Reload
kubectl rollout restart deployment -n litellm litellm-api

# 3. Pod-Mount korrekt?
kubectl exec -it -n litellm POD_NAME -- cat /app/config/config.yaml
```

## Performance & Autoscaling

### Problem: HPA funktioniert nicht

```bash
# 1. Metriken verfügbar?
kubectl get hpa -n litellm
# Sollte TARGETS zeigen (z.B. "50%/70%")
# Wenn "<unknown>" → Metriken fehlen

# 2. Metrics Server installiert?
kubectl get deployment -n kube-system metrics-server

# Wenn nicht:
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# 3. Resource Requests definiert?
# HPA braucht requests, um Prozente zu berechnen
kubectl get deployment -n litellm litellm-api -o yaml | grep -A5 "requests:"

# Sollte cpu: und memory: zeigen

# Lösung: Resources anpassen
python k8s/k8s_fill_config.py dev
# values_resources.yaml: requests erhöhen
```

### Problem: Pods skalieren zu aggressiv oder zu langsam

```bash
# 1. HPA Konfiguration anpassen
kubectl edit hpa -n litellm litellm-api-hpa

# Skalierungsverhalten:
spec:
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        averageUtilization: 50  # Erhöhen für weniger Scaling

# 2. Stabilisierungszeit
behavior:
  scaleDown:
    stabilizationWindowSeconds: 300  # 5 Minuten warten
  scaleUp:
    stabilizationWindowSeconds: 0    # Sofort hochfahren
```

### Problem: Pods sind langsam/Timeouts

```bash
# 1. Ressourcen-Limits zu niedrig?
kubectl top pods -n litellm
# Sollte unter Limits sein

# 2. CPU/Memory Requests vs. Limit
kubectl get deployment -n litellm litellm-api -o yaml | grep -A4 "resources:"

# Wenn Limit zu nah an Request:
# → Pod wird gedrosselt (CPU) oder gekilled (Memory)

# 3. Node-Überlastung?
kubectl top nodes
# Sollte <80% sein
```

## Certificate Issues

### Problem: TLS Certificate bleibt "Pending"

```bash
# 1. cert-manager läuft?
kubectl get pods -n cert-manager
# Sollte cert-manager pods zeigen

# 2. Certificate Order Details
kubectl describe certificate -n litellm litellm-tls

# 3. ClusterIssuer erreichbar?
kubectl describe clusterissuer letsencrypt-prod
# Status sollte Ready: True sein

# 4. DNS Challenge blockiert?
# Let's Encrypt braucht HTTP-01 (Port 80) Challenge
# Oder DNS-01 (DNS-Einträge)

# Logs prüfen:
kubectl logs -n cert-manager -l app=cert-manager | grep "litellm-tls"
```

### Problem: Self-signed cert wird verwendet statt Let's Encrypt

```bash
# 1. Staging (self-signed) vs. Prod (real)
kubectl get certificate -n litellm -o yaml | grep clusterIssuerName

# Sollte "letsencrypt-prod" sein (Prod), nicht "letsencrypt-staging"

# 2. Existierendes Secret blockiert?
kubectl delete secret -n litellm litellm-tls
# cert-manager erstellt new

# 3. ClusterIssuer neu erstellen (Prod)
kubectl delete clusterissuer letsencrypt-prod
kubectl apply -f - << 'EOF'
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

## Debug Tools

### kubectl Port-Forward

```bash
# API direkt vom Laptop testen
kubectl port-forward -n litellm svc/litellm-api 8000:8000
# Dann: curl http://localhost:8000/health
```

### Debug Container starten

```bash
# Alpine + curl + dig für Debugging
kubectl run -it --rm debug \
  --image=alpine:latest \
  --restart=Never \
  -- sh

# Im Container:
apk add --no-cache curl dnsutils
curl http://litellm-api:8000/health
nslookup postgres-dev
```

### Logs mit Timestamps

```bash
# Letzte 100 Zeilen mit Zeit
kubectl logs -n litellm POD_NAME --timestamps=true | tail -100

# Seit vor 1 Stunde
kubectl logs -n litellm POD_NAME --since=1h

# Multiple Pods
kubectl logs -n litellm -l app=litellm-api --all-containers=true
```

### Events Timeline

```bash
# Was ist in Cluster passiert (sortiert)
kubectl get events -n litellm --sort-by='.lastTimestamp'

# Live Events beobachten
kubectl get events -n litellm -w
```

### YAML Inspektion

```bash
# Deployment komplett mit Defaults
kubectl get deployment -n litellm litellm-api -o yaml

# Nur Spec
kubectl get deployment -n litellm litellm-api -o jsonpath='{.spec}'

# Nur Status
kubectl get pods -n litellm -o jsonpath='{.items[0].status}'
```

### Resource Limits prüfen

```bash
# Cluster-Limits
kubectl describe resourcequota -n litellm

# Node Ressourcen
kubectl describe nodes | grep -A5 "Allocated resources"

# Pod Requests/Limits
kubectl get pods -n litellm -o jsonpath='{.items[0].spec.containers[0].resources}'
```

---

**Weitere Hilfe:**
→ [Monitoring & Logging](./kubernetes-monitoring.md)

**Generelle Issues?**
→ [Setup Anleitung](./kubernetes-setup.md)
