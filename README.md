Tienes toda la razón. Han cambiado muchas cosas desde la primera versión: ahora tienes un **clúster híbrido (LAN + Nube)**, usas **RDT-Client** en lugar de qBittorrent, has configurado **LVM** para discos USB y hemos simplificado el Ingress a **HTTP**.

Aquí tienes el **README.md 2.0 Definitivo**, actualizado con la arquitectura real que tienes funcionando ahora mismo.

Copia y pega esto en tu archivo `README.md`.

***

```markdown
# ☁️🏠 k0s HomeLab - Hybrid Cluster Edition

![Status](https://img.shields.io/badge/Status-Production-green)
![Nodes](https://img.shields.io/badge/Nodes-3_(2_LAN_+_1_Cloud)-blue)
![GitOps](https://img.shields.io/badge/GitOps-Flux_v2-purple)
![Storage](https://img.shields.io/badge/Storage-LVM_500GB+-orange)

Infraestructura de nube privada híbrida orquestada con **k0s** y gestionada declarativamente con **Flux**. Combina la potencia local (Lenovo M80q) con la accesibilidad de la nube (Oracle OCI), unidos mediante **Tailscale**.

---

## 🏗️ Arquitectura del Clúster

### Nodos (Topology)
*   **`srv-lan-1` (Controller + Worker):** Nodo Principal en casa.
    *   *Hardware:* Lenovo M80q (i5-12th Gen, 8GB RAM).
    *   *Roles:* Base de Datos (etcd), Almacenamiento Masivo (USB/LVM), GPU (Transcodificación).
*   **`srv-lan-2` (Worker):** Nodo Secundario en casa.
    *   *Roles:* Cargas de trabajo redundantes.
*   **`srv-oci-1` (Worker):** Nodo en la Nube (Oracle Cloud).
    *   *Conexión:* Vía Tailscale VPN.
    *   *Roles:* Aplicaciones ligeras, Edge, Monitorización externa.

### Stack Tecnológico
*   **GitOps:** Flux v2 (Sincronización automática con este repositorio).
*   **Red:**
    *   **Tailscale:** Mesh VPN, Subnet Router y Exit Node.
    *   **MetalLB:** Balanceador de carga L2 (LAN).
    *   **Ingress NGINX:** Acceso HTTP local (`.lan`).
    *   **Cloudflare Tunnel:** Acceso HTTPS externo (`.com`) sin abrir puertos.
    *   **Network Policies:** Zero Trust (Bloqueo de tráfico lateral por defecto).
*   **Almacenamiento:**
    *   **Local Path Provisioner:** Configs dinámicas.
    *   **LVM + HostPath:** Almacenamiento masivo en `/data/multimedia` (srv-lan-1).
*   **Media Stack:**
    *   **Servidor:** Jellyfin (Aceleración Intel QSV).
    *   **Peticiones:** Jellyseerr.
    *   **Descargas:** RDT-Client (TorBox/Debrid) + FlareSolverr + RSSHub.
    *   **Automatización:** Stack *Arr (Radarr, Sonarr, Lidarr, Prowlarr, Bazarr).

---

## 🛠️ Prerrequisitos del Nodo Principal (`srv-lan-1`)

Antes de lanzar el clúster, el sistema operativo debe estar preparado:

### 1. Configuración de Red (Kernel)
Vital para que Kubernetes y Tailscale funcionen.
```bash
# Cargar módulos
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay && sudo modprobe br_netfilter

# Configurar sysctl
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system
```

### 2. Almacenamiento LVM (Discos USB)
Para permitir expansión futura sin perder datos:
```bash
# 1. Crear Grupo y Volumen (ej. con /dev/sdb)
sudo pvcreate /dev/sdb
sudo vgcreate usb-pool /dev/sdb
sudo lvcreate -l 100%FREE -n gran-almacen usb-pool
sudo mkfs.ext4 /dev/usb-pool/gran-almacen

# 2. Montar en /data/multimedia
sudo mkdir -p /data/multimedia
echo "/dev/usb-pool/gran-almacen /data/multimedia ext4 defaults,noatime,nofail 0 0" | sudo tee -a /etc/fstab
sudo mount -a

# 3. Permisos (Usuario 1000)
sudo chown -R 1000:1000 /data/multimedia
sudo chmod -R 775 /data/multimedia
```

---

## 🚀 Instalación y Recuperación (Disaster Recovery)

Si el servidor se quema y hay que reinstalar desde cero:

### 1. Instalar k0s
```bash
curl -sSLf https://get.k0s.sh | sudo sh
sudo k0s install controller --enable-worker
sudo k0s start
```

### 2. Bootstrap de Flux
Conecta el clúster con este repositorio.
```bash
export GITHUB_TOKEN=ghp_TU_TOKEN...
export GITHUB_USER=TU_USUARIO

flux bootstrap github \
  --owner=$GITHUB_USER \
  --repository=k0s-homelab \
  --branch=main \
  --path=./clusters/lenovo-m80q \
  --personal
```

### 3. Restaurar Secretos (CRÍTICO)
Flux instalará el controlador, pero no podrá descifrar los secretos (Token Cloudflare, etc.) sin la llave maestra original.
```bash
# Subir la llave de backup al servidor y aplicar
kubectl apply -f master-key-backup.yaml
# Reiniciar controlador para que lea la llave
kubectl delete pod -n kube-system -l name=sealed-secrets-controller
```

### 4. Sincronización Forzada
```bash
flux reconcile kustomization apps --with-source
```

---

## 🌐 Guía de Acceso

| Servicio | URL Local (Casa/VPN) | URL Externa (Pública) | Descripción |
| :--- | :--- | :--- | :--- |
| **Jellyseerr** | `http://pedir.lan` | `https://pedir.tudominio.com` | Solicitar contenido |
| **Jellyfin** | `http://jellyfin.lan` | `https://ver.tudominio.com` | Ver contenido |
| **FileBrowser**| `http://archivos.lan` | - | Gestión de ficheros |
| **Sonarr** | `http://sonarr.lan` | - | Gestión Series |
| **Radarr** | `http://radarr.lan` | - | Gestión Películas |
| **RDT-Client** | `http://rdt.lan` | - | Cliente Descargas |
| **AdGuard** | `http://192.168.18.210` | - | DNS & AdBlock |

*Nota: Para que los dominios `.lan` funcionen, el DNS del router o de Tailscale debe apuntar a la IP de AdGuard Home (`192.168.18.210`).*

---

## 🚑 Solución de Problemas Frecuentes

### 1. Flux se queda bloqueado ("Reconciliation failed")
Si Flux falla por culpa del Ingress NGINX, suele ser el Webhook de validación.
**Solución:**
```bash
kubectl delete validatingwebhookconfigurations ingress-nginx-admission
flux reconcile kustomization apps --with-source
```

### 2. Apps en `CrashLoopBackOff` (Permisos / SQLite Locked)
Si una app no arranca tras actualizar, suele ser por permisos en `/config` o base de datos bloqueada.
**Solución:**
```bash
# 1. Asegurar permisos en el host
sudo chown -R 1000:1000 /opt/local-path-provisioner/
# 2. Reiniciar todos los pods para romper bloqueos
kubectl delete pod -n downloads --all
```

### 3. El nodo marca "DiskPressure" (Evicted)
Si el disco del sistema (`/`) se llena.
**Solución:**
```bash
# Limpiar imágenes docker viejas
sudo k0s ctr images prune --all
# Borrar pods muertos
kubectl get pods -A | grep Evicted | awk '{print $1 " " $2}' | xargs -L1 kubectl delete pod -n
```

---

## 💾 Gestión de Backups

Los datos importantes no están en Kubernetes, están en el disco físico.

*   **Configuraciones (DBs):** `/data/multimedia/config` (si se movieron ahí) o en los volúmenes `local-path`.
*   **Medios:** `/data/multimedia`.

**Script rápido de Backup:**
```bash
# Hacer backup de las configuraciones críticas
sudo tar -czvf backup-configs-$(date +%F).tar.gz /opt/local-path-provisioner
```

---

> **Nota:** Este repositorio utiliza **Sealed Secrets**. No editar los secretos manualmente en Git. Usar `kubeseal` para generar nuevos secretos cifrados.
```
