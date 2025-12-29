
#!/bin/bash
set -euo pipefail

# ===== Parámetros =====
BACKUP_ROOT="${HOME}/backup-yamls-$(date +%Y%m%d)"
# Excluir namespaces del sistema (opcional). Puede dejarse vacío: EXCLUDE_NAMESPACES=()
NS_RESOURCES=("deploy" "svc" "configmap" "ingress" "daemonset" "statefulset" "networkpolicy")
EXCLUDE_NAMESPACES=("kube-system" "kube-public" "kube-node-lease")
# Recurso CLUSTER-SCOPED a respaldar
CLUSTER_RESOURCES=("ingressclass")
# ======================

echo "Creando carpeta de backup: ${BACKUP_ROOT}"
mkdir -p "${BACKUP_ROOT}"

# ===== Verificaciones previas =====
if ! command -v kubectl >/dev/null 2>&1; then
  echo "❌ kubectl no está instalado o no está en PATH."
  exit 1
fi

if ! command -v kubectl-neat >/dev/null 2>&1; then
  echo "❌ kubectl-neat no está instalado o no está en PATH."
  echo "   Instalación (ejemplo):"
  echo "   go install github.com/itaysk/kubectl-neat@latest && ln -s \$(go env GOPATH)/bin/kubectl-neat /usr/local/bin/kubectl-neat"
  exit 1
fi

# Comprobar acceso al clúster
kubectl cluster-info >/dev/null

# ===== Utilidades =====
in_array() {
  local needle="$1"; shift
  for elem in "$@"; do
    [[ "$elem" == "$needle" ]] && return 0
  done
  return 1
}

# Mapeo de prefijos de archivo por tipo
file_prefix_for_kind() {
  case "$1" in
    deploy)        echo ""        ;;  # sin prefijo para mantener compatibilidad
    svc)           echo "svc-"    ;;
    configmap)     echo "cm-"     ;;
    ingress)       echo "ing-"    ;;
    daemonset)     echo "ds-"     ;;
    statefulset)   echo "sts-"    ;;
    networkpolicy) echo "netpol-" ;;
    ingressclass)  echo "ingclass-" ;;
    *)             echo ""        ;;
  esac
}

# ===== Obtener todos los namespaces =====
echo "Obteniendo namespaces..."
mapfile -t NAMESPACES < <(kubectl get ns -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

# ===== Backup de recursos NAMESPACE-SCOPED =====
for ns in "${NAMESPACES[@]}"; do
  if in_array "$ns" "${EXCLUDE_NAMESPACES[@]}"; then
    echo "⏭️  Omitiendo namespace excluido: $ns"
    continue
  fi

  NS_DIR="${BACKUP_ROOT}/${ns}"
  mkdir -p "${NS_DIR}"
  echo "📁 Procesando namespace: ${ns}"

  for kind in "${NS_RESOURCES[@]}"; do
    # Listar recursos del tipo en el namespace (si el tipo no existe o no hay objetos, continuar).
    mapfile -t items < <(kubectl get "$kind" -n "$ns" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)

    if [[ ${#items[@]} -eq 0 ]]; then
      echo "   ➖ No se encontraron ${kind} en ${ns}"
      continue
    fi

    echo "   ➕ Respaldando ${kind} (${#items[@]} elementos) en ${ns}..."
    prefix="$(file_prefix_for_kind "$kind")"

    for name in "${items[@]}"; do
      outfile="${NS_DIR}/${prefix}${name}.yaml"
      if kubectl get "$kind" "$name" -n "$ns" -o yaml 2>/dev/null | kubectl-neat > "$outfile"; then
        echo "      ✔ ${kind}/${name} → $(basename "$outfile")"
      else
        echo "      ❌ Error exportando ${kind}/${name} en ${ns}"
      fi
    done
  done
done

# ===== Backup de recursos CLUSTER-SCOPED =====
CLUSTER_DIR="${BACKUP_ROOT}/_cluster-scoped"
mkdir -p "${CLUSTER_DIR}"
echo "🌐 Procesando recursos cluster-scoped..."

for ckind in "${CLUSTER_RESOURCES[@]}"; do
  # Listar objetos cluster-scoped
  mapfile -t citems < <(kubectl get "$ckind" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)

  if [[ ${#citems[@]} -eq 0 ]]; then
    echo "   ➖ No se encontraron ${ckind} a nivel de clúster"
    continue
  fi

  echo "   ➕ Respaldando ${ckind} (${#citems[@]} elementos) a nivel de clúster..."
  cprefix="$(file_prefix_for_kind "$ckind")"

  for cname in "${citems[@]}"; do
    coutfile="${CLUSTER_DIR}/${cprefix}${cname}.yaml"
    if kubectl get "$ckind" "$cname" -o yaml 2>/dev/null | kubectl-neat > "$coutfile"; then
      echo "      ✔ ${ckind}/${cname} → $(basename "$coutfile")"
    else
      echo "      ❌ Error exportando ${ckind}/${cname}"
    fi
  done
done

# ===== Comprimir resultado =====
echo "🎁 Comprimiendo backup en: ${BACKUP_ROOT}.tar.gz"
tar -czf "${BACKUP_ROOT}.tar.gz" -C "${BACKUP_ROOT}" .

echo "✅ Backup completado."
echo "   Carpeta: ${BACKUP_ROOT}"
echo "   Archivo: ${BACKUP_ROOT}.tar.gz"
# Recursos NAMESPACE-SCOPED a respaldar
