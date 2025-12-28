# 🚀 k0s HomeLab - Lenovo M80q Edition

![Status](https://img.shields.io/badge/Status-Production-green)
![Kubernetes](https://img.shields.io/badge/k0s-v1.30+-blue)
![GitOps](https://img.shields.io/badge/GitOps-Flux_v2-purple)

Un clúster de Kubernetes ligero, seguro y totalmente automatizado mediante **GitOps (Flux)**, diseñado para correr en un **Lenovo ThinkCentre M80q Gen 3**.

Este repositorio es la "Fuente de la Verdad". El estado del clúster se sincroniza automáticamente con el código aquí alojado.

---

## 🏗️ Arquitectura y Stack

### Hardware
*   **Nodo:** Lenovo ThinkCentre M80q (Intel Core i5-12500T).
*   **RAM:** 8 GB - 16 GB (Optimizado para bajo consumo).
*   **Almacenamiento:** NVMe 500GB (Expandido vía LVM + USB Externos).
*   **GPU:** Intel UHD 770 (Passthrough para transcodificación Jellyfin vía Intel QuickSync).

### Core Infraestructura
*   **Orquestador:** [k0s](https://k0sproject.io/) (Zero Friction Kubernetes).
*   **GitOps:** [Flux v2](https://fluxcd.io/) (Gestión declarativa de manifiestos).
*   **Red:**
    *   **MetalLB:** LoadBalancer capa 2 (IPs locales para servicios).
    *   **Ingress NGINX:** Controlador de entrada HTTP/HTTPS.
    *   **Tailscale:** VPN Mesh para acceso remoto seguro y DNS interno.
    *   **Cloudflare Tunnel:** Acceso externo seguro para servicios públicos.
*   **Seguridad:**
    *   **Sealed Secrets:** Gestión de secretos encriptados en Git (Bitnami).
    *   **Network Policies:** Zero Trust (Aislamiento de namespaces).
    *   **Cert-Manager:** Certificados automáticos Let's Encrypt / Self-signed.
*   **Almacenamiento:**
    *   **Local Path Provisioner:** Para PVCs dinámicos (Configuraciones y DBs).
    *   **HostPath / LVM:** Para media masiva en `/data/multimedia`.

### Aplicaciones (Media Stack)
*   **Servidor:** Jellyfin (Aceleración Hardware Intel QSV).
*   **Peticiones:** Jellyseerr.
*   **Automatización (*Arrs):** Radarr, Sonarr, Lidarr, Prowlarr, Bazarr.
*   **Descargas:** qBittorrent + FlareSolverr.
*   **Utilidades:** FileBrowser, AdGuard Home.

---

## 📂 Estructura del Repositorio

```text
k0s-homelab-flux/
├── clusters/
│   └── lenovo-m80q/           # Definición del clúster (App de Apps)
├── infrastructure/            # Capa 1: Cimientos (Controladores)
│   ├── base/                  # Instalaciones genéricas
│   ├── networking/            # MetalLB, Ingress, Tailscale
│   ├── storage/               # StorageClasses y PVs manuales
│   └── configs/               # Cert-manager clusterissuers
└── apps/                      # Capa 2: Servicios de usuario
    ├── media/                 # Jellyfin, Jellyseerr
    ├── downloads/             # Arrs y qBittorrent
    └── networking/            # AdGuard Home, Cloudflare Tunnel
```

---

## 🛠️ Prerrequisitos (Preparación del Nodo)

Antes de instalar Kubernetes, prepara el sistema base (Ubuntu/Debian):

### 1. Preparar Estructura de Datos
Para que los **Hardlinks** funcionen (evitando duplicar espacio en disco), todo debe estar en la misma partición.
```bash
# Crear estructura base
sudo mkdir -p /data/multimedia/{torrents,media,config}
sudo mkdir -p /data/multimedia/media/{movies,tv,music,books}

# Permisos (UID 1000 es el estándar en contenedores linuxserver.io)
sudo chown -R 1000:1000 /data/multimedia
sudo chmod -R 775 /data/multimedia
```

### 2. Optimización del Kernel
```bash
sudo tee /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# Configurar reenvío de IP para networking
sudo tee /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system
```

### 3. Drivers de GPU (Intel QuickSync)
Asegúrate de que el usuario del clúster tenga acceso a los dispositivos de renderizado.
```bash
# Verificar presencia de drivers
ls -l /dev/dri
# El grupo suele ser 'render' o 'video'. ID usualmente 107 o 44.
```

---

## 🚀 Instalación (Bootstrap)

1.  **Instalar k0s** (Usando [k0sctl](https://github.com/k0sproject/k0sctl) o manual).
2.  **Bootstrap de Flux:**
    ```bash
    export GITHUB_TOKEN=ghp_tu_token_aqui
    flux bootstrap github \
      --owner=TU_USUARIO \
      --repository=k0s-homelab-flux \
      --branch=main \
      --path=./clusters/lenovo-m80q \
      --personal
    ```
3.  **Restaurar Llave Maestra de Sealed Secrets:**
    *Sin este paso, Flux no podrá descifrar tus contraseñas.*
    ```bash
    kubectl apply -f master-key-backup.yaml
    # Reiniciar el controlador para que cargue la llave
    kubectl delete pod -n kube-system -l app.kubernetes.io/name=sealed-secrets
    ```

---

## 🔐 Gestión de Secretos

Usamos `kubeseal` para poder subir secretos a Git de forma segura.

1.  **Crear el secreto localmente:**
    ```bash
    kubectl create secret generic qbit-creds --from-literal=password=admin123 -n downloads --dry-run=client -o yaml > secret.yaml
    ```
2.  **Cifrar:**
    ```bash
    kubeseal < secret.yaml > sealed-secret.yaml --format=yaml
    ```
3.  **Aplicar y subir:** Borra `secret.yaml` y haz commit de `sealed-secret.yaml`.

---

## 🌐 Tabla de Accesos

| Servicio | URL Local | Acceso Externo | Propósito |
| :--- | :--- | :--- | :--- |
| **Jellyfin** | `jellyfin.lan` | `ver.midominio.com` | Media Player |
| **qBittorrent**| `bajar.lan` | VPN Only | Descargas |
| **Sonarr/Radarr**| `series.lan` / `pelis.lan` | VPN Only | Gestión de Media |
| **AdGuard** | `dns.lan` | Local Only | Bloqueo de publicidad |

---

## ⚙️ Ampliación de Almacenamiento (LVM + USB)

Si te quedas sin espacio en el NVMe, usa este procedimiento para sumar discos USB sin romper los hardlinks.

1.  **Preparar Discos:** `sudo pvcreate /dev/sdb`
2.  **Crear/Extender Grupo:** `sudo vgcreate data-pool /dev/sdb`
3.  **Crear Volumen:** `sudo lvcreate -l 100%FREE -n multimedia data-pool`
4.  **Montar en `/data/multimedia`:** Configura en `/etc/fstab` para persistencia.
5.  **Migrar:** Si ya tenías datos, usa `rsync -avhP` antes del montaje definitivo.

---

## 🚑 Mantenimiento Rápido

### Forzar Sincronización de Flux
```bash
flux reconcile kustomization apps --with-source
```

### Limpieza de Imágenes (Espacio en disco)
```bash
sudo k0s ctr images prune --all
```

### Si Jellyfin falla al acceder a la GPU
A veces el dispositivo `/dev/dri/renderD128` queda bloqueado por un proceso zombie:
```bash
kubectl rollout restart deployment jellyfin -n media
```

### Backup de Bases de Datos
Los Arrs usan SQLite. Es recomendable ejecutar el backup interno de cada app hacia `/config/backups`, que ya está mapeado en `/data/multimedia/config`.

---

> **Nota Final:** Este repositorio implementa una política de **Hardlinks**. Para que el movimiento de archivos entre `torrents/` y `media/` sea instantáneo y no consuma doble espacio, ambos deben colgar del mismo volumen lógico y el mismo punto de montaje en Kubernetes.