# Crear directorio si no existe
mkdir -p infrastructure/controllers

# 1. Ingress NGINX
wget -O infrastructure/controllers/ingress-nginx.yaml https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/cloud/deploy.yaml

# 2. Cert-Manager
wget -O infrastructure/controllers/cert-manager.yaml https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml

# 3. Sealed Secrets
wget -O infrastructure/controllers/sealed-secrets.yaml https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.0/controller.yaml

# 4. MetalLB
wget -O infrastructure/controllers/metallb-install.yaml https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml