# 🚀 k0s HomeLab - Lenovo M80q Edition

![Status](https://img.shields.io/badge/Status-Production-green)
![Kubernetes](https://img.shields.io/badge/k0s-v1.30+-blue)
![GitOps](https://img.shields.io/badge/GitOps-Flux_v2-purple)

Un clúster de Kubernetes ligero, seguro y totalmente automatizado mediante **GitOps (Flux)**, diseñado para correr en un **Lenovo ThinkCentre M80q Gen 3**.

Este repositorio es la "Fuente de la Verdad". El estado del clúster se sincroniza automáticamente con el código aquí alojado.

---

## 🏗️ Arquitectura y Stack

### Hardware
*   **Nodo:** Lenovo ThinkCentre M80q (Intel Core i5-12th Gen).
*   **RAM:** 8 GB (Optimizado para bajo consumo).
*   **Almacenamiento:** NVMe 500GB (Expandido vía LVM).
*   **GPU:** Intel UHD 770 (Passthrough para transcodificación Jellyfin).

### Core Infraestructura
*   **Orquestador:** [k0s](https://k0sproject.io/) (Zero Friction Kubernetes).
*   **GitOps:** [Flux v2](https://fluxcd.io/) (Gestión declarativa).
*   **Red:**
    *   **MetalLB:** LoadBalancer capa 2.
    *   **Ingress NGINX:** Controlador de entrada HTTP/HTTPS.
    *   **Tailscale:** VPN Mesh, Subnet Router y Exit Node.
    *   **Cloudflare Tunnel:** Acceso externo seguro (CG-NAT bypass).
*   **Seguridad:**
    *   **Sealed Secrets:** Gestión de secretos encriptados en Git.
    *   **Network Policies:** Zero Trust (Bloqueo de tráfico lateral por defecto).
    *   **Cert-Manager:** Certificados autofirmados para dominio `.lan`.
*   **Almacenamiento:**
    *   **Local Path Provisioner:** Para PVCs dinámicos (configuraciones).
    *   **HostPath Manual:** Para media masiva (`/data/multimedia`).

### Aplicaciones (Media Stack)
*   **Servidor:** Jellyfin (Aceleración Hardware Intel QSV).
*   **Peticiones:** Jellyseerr.
*   **Automatización (*Arrs):** Radarr, Sonarr, Lidarr, Readarr, Bazarr, Prowlarr.
*   **Descargas:** qBittorrent + FlareSolverr.
*   **Utilidades:** FileBrowser, AdGuard Home (DNS & AdBlock).

---

## 📂 Estructura del Repositorio

Seguimos el estándar de separación entre Infraestructura y Aplicaciones:

```text
k0s-homelab-flux/
├── clusters/
│   └── lenovo-m80q/           # Definición del clúster y dependencias
├── infrastructure/            # Capa 1: Cimientos (Se instala primero)
│   ├── controllers/           # Ingress, Cert-Manager, Sealed-Secrets
│   ├── network/               # MetalLB, Cloudflare Tunnel
│   ├── storage/               # PVs Manuales
│   └── hardware/              # Drivers GPU, NFD
└── apps/                      # Capa 2: Servicios (Dependen de Infra)
    ├── dns/                   # AdGuard / CoreDNS
    └── downloads/             # Stack Multimedia completo
        ├── configs/           # Variables de entorno y Políticas de Red
        ├── media-server/      # Jellyfin, Jellyseerr
        ├── downloaders/       # qBittorrent
        └── arrs/              # Radarr, Sonarr, etc.
```

---

## 🛠️ Prerrequisitos (Antes del Bootstrap)

Antes de lanzar Flux en un nodo limpio, asegúrate de preparar el sistema operativo:

### 1. Preparar Disco y Permisos
El sistema usa una carpeta física para persistencia de medios.
```bash
# Crear estructura
sudo mkdir -p /data/multimedia/{torrents,media/movies,media/tv,media/music,media/books}

# Asignar permisos al usuario 1000 (standard k8s user)
sudo chown -R 1000:1000 /data/multimedia
sudo chmod -R 777 /data/multimedia
```

### 2. Configurar Módulos del Kernel
Necesario para el networking de Kubernetes.
```bash
sudo tee /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
# (Asegurar también net.ipv4.ip_forward = 1 en sysctl)
```

### 3. Instalar Herramientas CLI
Necesitarás `kubectl`, `flux` y `kubeseal` en tu máquina de administración.

---

## 🚀 Instalación (Bootstrap)

Para restaurar el clúster desde cero:

1.  **Instalar k0s** en el nodo.
2.  **Ejecutar Bootstrap de Flux:**
    ```bash
    export GITHUB_TOKEN=ghp_TU_TOKEN
    flux bootstrap github \
      --owner=TU_USUARIO \
      --repository=k0s-homelab-flux \
      --branch=main \
      --path=./clusters/lenovo-m80q \
      --personal
    ```
3.  **Restaurar Llave Maestra de Secretos:**
    Flux instalará el controlador de Sealed Secrets, pero no podrá descifrar tus contraseñas hasta que restaures la `master-key`.
    ```bash
    kubectl apply -f master-key-backup.yaml
    kubectl delete pod -n kube-system -l name=sealed-secrets-controller
    ```

---

## 🔐 Gestión de Secretos

**NUNCA** subas credenciales en texto plano.
Para añadir un nuevo secreto (ej. API Key):

1.  Crea el secreto en local:
    ```bash
    kubectl create secret generic my-secret --from-literal=key=value --dry-run=client -o yaml > secret.yaml
    ```
2.  Cífralo con `kubeseal`:
    ```bash
    kubeseal < secret.yaml > sealed-secret.yaml --format=yaml
    ```
3.  Sube `sealed-secret.yaml` al repositorio.

---

## 🌐 Accesos y Red

| Servicio | URL Local (.lan) | URL Externa | Notas |
| :--- | :--- | :--- | :--- |
| **Jellyfin** | `https://jellyfin.lan` | `https://ver.tudominio.com` | HTTPS Auto-firmado |
| **Jellyseerr** | `https://pedir.lan` | `https://pedir.tudominio.com` | Peticiones |
| **Sonarr** | `https://sonarr.lan` | VPN Only | Solo interno |
| **Radarr** | `https://radarr.lan` | VPN Only | Solo interno |
| **qBittorrent**| `https://bajar.lan` | VPN Only | Solo interno |

*Nota: Los dominios `.lan` requieren configurar el DNS en el router apuntando a la IP de AdGuard/CoreDNS (LoadBalancer).*

---

## 🚑 Solución de Problemas Comunes

### Jellyfin no arranca / GPU Locked
Si Jellyfin se queda en `Pending` y el PVC en `Pending`:
```bash
# Matar el pod viejo que retiene la GPU
kubectl delete pod -n downloads -l app=jellyfin --force --grace-period=0
```
*El despliegue usa estrategia `Recreate`, pero a veces requiere ayuda manual.*

### El disco parece lleno (Evicted Pods)
Si Kubernetes mata pods por `DiskPressure` aunque haya espacio:
1.  Verificar espacio real: `df -h`
2.  Si es un problema de LVM en Ubuntu:
    ```bash
    sudo lvextend -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv
    sudo resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv
    ```
3.  Limpiar pods muertos:
    ```bash
    kubectl get pods -A | grep Evicted | awk '{print $1 " " $2}' | xargs -L1 kubectl delete pod -n
    ```

### Forzar Sincronización de Flux
Si has hecho un push y no quieres esperar 10 minutos:
```bash
flux reconcile kustomization apps --with-source
```

---

> **Nota:** Este sistema utiliza **Hardlinks** entre `/data/torrents` y `/data/media`. Si cambias la configuración de almacenamiento, asegúrate de que ambas carpetas residan en el mismo sistema de ficheros físico para evitar duplicidad de datos.

## ⚙️ Ampliación de Almacenamiento (Migración a USB/LVM)

Si el disco interno se queda pequeño, este es el procedimiento para añadir múltiples discos USB y fusionarlos en un único volumen lógico (LVM). Esto permite mantener la estructura `/data` intacta para que los **Hardlinks** sigan funcionando.

⚠️ **ADVERTENCIA:** Este proceso **BORRA** todos los datos de los discos USB nuevos.

### 1. Detener Aplicaciones
Es vital detener todo uso del disco antes de migrar datos.
```bash
kubectl scale deploy -n downloads --replicas=0 --all
```

### 2. Identificar Discos
Conecta los USBs y busca sus identificadores (ej. `sdb`, `sdc`).
```bash
lsblk
```

### 3. Crear el "Super-Disco" LVM
Ejemplo asumiendo `/dev/sdb` y `/dev/sdc`:

```bash
# 1. Crear Volúmenes Físicos
sudo pvcreate /dev/sdb /dev/sdc

# 2. Crear Grupo de Volúmenes (Pool)
sudo vgcreate usb-pool /dev/sdb /dev/sdc

# 3. Crear Volumen Lógico (Usando el 100% del espacio)
sudo lvcreate -l 100%FREE -n gran-almacen usb-pool

# 4. Formatear en EXT4
sudo mkfs.ext4 /dev/usb-pool/gran-almacen
```

### 4. Migración de Datos (Rsync)
Movemos los datos del disco interno al nuevo array USB sin perder permisos.

```bash
# Montar temporalmente
sudo mkdir -p /mnt/nuevo_usb
sudo mount /dev/usb-pool/gran-almacen /mnt/nuevo_usb

# Copiar datos (Puede tardar horas según el tamaño)
sudo rsync -avh --progress /data/multimedia/ /mnt/nuevo_usb/

# Verificar
ls -la /mnt/nuevo_usb
```

### 5. El "Cambiazo" (Montaje Definitivo)
Sustituimos la carpeta del sistema por el montaje de los USBs.

```bash
# 1. Desmontar temporal
sudo umount /mnt/nuevo_usb

# 2. (Opcional) Borrar datos viejos del disco interno para liberar espacio
# ¡Solo si el paso anterior fue exitoso!
# sudo rm -rf /data/multimedia/*

# 3. Configurar montaje automático
echo "/dev/usb-pool/gran-almacen  /data/multimedia  ext4  defaults,noatime  0  0" | sudo tee -a /etc/fstab

# 4. Aplicar montaje
sudo mount -a

# 5. Verificar que /data/multimedia ahora tiene el tamaño de los USBs
df -h | grep multimedia
```

### 6. Reactivación
Restauramos permisos y encendemos el clúster.

```bash
# Asegurar permisos correctos
sudo chown -R 1000:1000 /data/multimedia
sudo chmod -R 777 /data/multimedia

# Encender las apps
kubectl scale deploy -n downloads --replicas=1 --all
```

> **Nota:** Si en el futuro compras otro disco USB, solo tienes que hacer `vgextend`, `lvextend` y `resize2fs` para sumarlo al grupo sin formatear lo existente.

### 🧹 Mantenimiento y Operaciones

#### Actualizar Aplicaciones
Gracias a GitOps, no usas comandos manuales. Para actualizar una versión (ej. Jellyfin):
1.  Edita el archivo `apps/downloads/media-server/jellyfin.yaml` en tu PC.
2.  Cambia la etiqueta de la imagen: `image: jellyfin/jellyfin:10.9.0` (o `latest`).
3.  Haz `git commit` y `git push`.
4.  Flux detectará el cambio y actualizará el pod automáticamente.

#### Reiniciar el Nodo (Lenovo)
Para evitar corrupción de bases de datos SQLite:
```bash
# 1. Detener k0s suavemente
sudo k0s stop

# 2. Reiniciar sistema
sudo reboot

# 3. Al volver, verificar montajes ANTES de que arranque todo
df -h | grep multimedia
```

#### Liberar Espacio en Disco (Emergency Cleanup)
Si el disco del sistema se llena y Kubernetes entra en pánico (`Evicted`):
```bash
# Limpiar imágenes de contenedores no usadas
sudo k0s ctr images prune --all

# Comando "Lanzallamas": Borrar pods zombis/evicted
kubectl get pods -A --no-headers | grep -v "Running" | awk '{print $1 " " $2}' | xargs -L1 kubectl delete pod -n --force --grace-period=0
```

---

## 💾 Backup y Restauración

### Estrategia de Copias
*   **Código (Configuración):** Está todo en este repositorio de GitHub.
*   **Datos (Estado de Apps):** Están en `/data/multimedia/config`.
*   **Medios (Películas/Series):** Están en `/data/multimedia`.

### Script de Backup Manual
Ejecutar en el nodo antes de cambios grandes:
```bash
# Comprime todas las configs (Jellyfin Users, Radarr DB, etc.)
sudo tar -czvf backup-config-$(date +%F).tar.gz /data/multimedia/config
```

### Procedimiento de Restauración (Disaster Recovery)
Si el servidor explota y tienes que formatear:
1.  Instalar Ubuntu + LVM (¡Expandir LVM al 100%!).
2.  Recuperar datos: Copiar el backup `.tar.gz` y descomprimir en `/data/multimedia/config`.
3.  Instalar k0s y Flux (ver sección Instalación).
4.  Aplicar la `master-key` de Sealed Secrets.
5.  **Esperar.** Flux reinstalará todas las aplicaciones y estas encontrarán sus datos en la carpeta descomprimida como si nada hubiera pasado.

---

## 📝 Cheatsheet (Comandos Útiles)

| Acción | Comando |
| :--- | :--- |
| **Ver todo el clúster** | `kubectl get pods -A` |
| **Ver logs de Jellyfin** | `kubectl logs -n downloads -l app=jellyfin -f` |
| **Entrar en consola de un pod** | `kubectl exec -it -n downloads deploy/radarr -- bash` |
| **Ver estado de Flux** | `flux get kustomizations` |
| **Forzar sincro Flux** | `flux reconcile source git flux-system` |
| **Ver uso de recursos** | `kubectl top pods -n downloads` |
| **Descifrar un secreto** | `kubeseal --recovery-unseal < secreto.yaml` |

---

## 📜 Licencia y Créditos

**Proyecto HomeLab Personal.**
Construido con la ayuda de:
*   [k0s](https://k0sproject.io/)
*   [FluxCD](https://fluxcd.io/)
*   [LinuxServer.io](https://www.linuxserver.io/) (Imágenes Docker)
*   [Jellyfin Project](https://jellyfin.org/)

> *"No hay lugar como 127.0.0.1"*
