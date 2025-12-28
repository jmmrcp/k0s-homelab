# Bucle mágico para arreglar permisos de todos los PVCs en 'downloads'
for volume in $(kubectl get pvc -n downloads -o jsonpath='{.items[*].spec.volumeName}'); do
  # Averiguar la ruta real en el disco
  path=$(kubectl get pv $volume -o jsonpath='{.spec.hostPath.path}')
  
  # Si la carpeta existe, cambiamos el dueño
  if [ -d "$path" ]; then
    echo "🔧 Arreglando permisos en: $path"
    sudo chown -R 1000:1000 "$path"
    sudo chmod -R 775 "$path"
  fi
done