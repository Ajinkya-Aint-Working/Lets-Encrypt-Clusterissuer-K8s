# Lets-Encrypt-Clusterissuer-K8s

# HTTPS with cert-manager + GKE Gateway API (Autopilot)

This README documents the **complete, end-to-end setup** for enabling **HTTPS using Let’s Encrypt**
on **GKE Autopilot** with **Gateway API**, a **static global IP**, and **cert-manager**.

It is written as a **production runbook** and includes all commands, YAMLs, and verification steps.

---

## Architecture Overview

```
Internet
  |
DNS (test.solvox.ai -> Static Global IP)
  |
GKE Gateway (HTTP :80)
  |
HTTPRoute (cert-manager ACME solver)
  |
Solver Service (cert-manager namespace)
  |
Let's Encrypt
  |
TLS Certificate Secret
```

---

## Prerequisites

- GKE **Autopilot** cluster
- Gateway API enabled
- Global **external static IP** reserved
- DNS `A` record pointing to the static IP
- `kubectl` and `helm`

---

## 1. Install cert-manager (REQUIRED)

### Add Helm repo

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
```

### Install cert-manager with required flags

> ⚠️ `--enable-gateway-api` is **mandatory** for HTTP-01 with Gateway API.

```bash
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --timeout 10m \
  --set crds.enabled=true \
  --set startupapicheck.enabled=true \
  --set extraArgs[0]=--enable-gateway-api \
  --set global.leaderElection.namespace=cert-manager \
  --set resources.requests.cpu=100m \
  --set resources.requests.memory=128Mi \
  --set resources.limits.cpu=100m \
  --set resources.limits.memory=128Mi \
  --set webhook.resources.requests.cpu=100m \
  --set webhook.resources.requests.memory=128Mi \
  --set webhook.resources.limits.cpu=100m \
  --set webhook.resources.limits.memory=128Mi \
  --set cainjector.resources.requests.cpu=100m \
  --set cainjector.resources.requests.memory=128Mi \
  --set cainjector.resources.limits.cpu=100m \
  --set cainjector.resources.limits.memory=128Mi
```

### Verify pods

```bash
kubectl get pods -n cert-manager
```

All pods must be `Running`.

---

## 2. Verify cert-manager Webhook

### Check CA bundle injection

```bash
kubectl get validatingwebhookconfigurations cert-manager-webhook   -o jsonpath='{.webhooks[0].clientConfig.caBundle}' | wc -c
```

✅ Output must be **greater than 0**.

### View full webhook YAML

```bash
kubectl get validatingwebhookconfigurations cert-manager-webhook -o yaml
```

---

## 3. Create Gateway with Static IP

### `gateway.yaml`

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: solvox-gateway-ip
  namespace: gateway-system
spec:
  gatewayClassName: gke-l7-global-external-managed
  addresses:
    - type: NamedAddress
      value: solvox-gateway-ip
  listeners:
    - name: http
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: All
```

Apply:

```bash
kubectl apply -f gateway.yaml
```

Verify static IP binding:

```bash
kubectl describe gateway solvox-gateway-ip -n gateway-system | grep -A3 Addresses
```

---

## 4. Create ClusterIssuer (Let’s Encrypt)

### `cluster-issuer.yaml`

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: ajinkya.acharekar@finrius.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - http01:
          gatewayHTTPRoute:
            parentRefs:
              - kind: Gateway
                name: solvox-gateway-ip
                namespace: gateway-system
```

Apply and verify:

```bash
kubectl apply -f cluster-issuer.yaml
kubectl get clusterissuer letsencrypt-prod
```

Expected:

```
READY=True
```

---

## 5. Why ReferenceGrant is REQUIRED on GKE

On GKE Gateway API:

- ACME **HTTPRoute** runs in `gateway-system`
- ACME **solver Service** runs in `cert-manager`
- Gateway API **blocks cross-namespace backends by default**

Without a ReferenceGrant:
- Solver HTTPRoute appears briefly
- Gateway rejects it
- cert-manager deletes it
- Challenge stays `pending` forever

This is **expected behavior**, not a bug.

---

## 6. Create ReferenceGrant (MANDATORY)

> GKE currently supports ReferenceGrant only in **v1beta1**

### `referencegrant-acme.yaml`

```yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-cert-manager-acme
  namespace: cert-manager
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      namespace: gateway-system
  to:
    - group: ""
      kind: Service
```

Apply:

```bash
kubectl apply -f referencegrant-acme.yaml
kubectl get referencegrant -n cert-manager
```

---

## 7. Create Certificate

### `certificate.yaml`

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-solvox-ai
  namespace: gateway-system
spec:
  secretName: test-solvox-ai-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - test.solvox.ai
```

Apply:

```bash
kubectl apply -f certificate.yaml
```

---

## 8. Verify Certificate Issuance

```bash
kubectl get certificate -n gateway-system
kubectl describe certificate test-solvox-ai -n gateway-system
```

### ACME Challenge

```bash
kubectl get challenges.acme.cert-manager.io -n gateway-system
kubectl describe challenge -n gateway-system
```

Expected flow:

```
pending -> valid
```

---

## 9. Verify Solver HTTPRoute

```bash
kubectl get httproute -n gateway-system
kubectl describe httproute -n gateway-system
```

Expected:

```
Accepted: True
Programmed: True
```

---

## 10. Verify TLS Secret (Final Proof)

```bash
kubectl get secret test-solvox-ai-tls -n gateway-system
```

Inspect certificate:

```bash
kubectl get secret test-solvox-ai-tls -n gateway-system   -o jsonpath='{.data.tls\.crt}' | base64 --decode | openssl x509 -text -noout
```

Issuer must be **Let’s Encrypt**.

---

## Debug Cheat Sheet

```bash
kubectl get clusterissuer
kubectl get certificate -A
kubectl get challenges -A
kubectl get httproute -A
kubectl get validatingwebhookconfigurations cert-manager-webhook -o yaml
```

---

## Production Checklist

- cert-manager installed
- Gateway API enabled
- Static IP bound
- Webhook trusted
- ReferenceGrant applied
- Solver HTTPRoute stable
- Certificate READY=True

---

## GKE-Specific Notes

- `--enable-gateway-api` is mandatory
- ReferenceGrant is required on GKE
- Static IP must be bound at Gateway creation
- ReferenceGrant is **v1beta1**
