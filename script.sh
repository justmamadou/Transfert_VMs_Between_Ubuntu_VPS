#!/bin/bash

# Variables à personnaliser
DEST_VPS="user@destination_vps_ip"
VM_NAME="vm_name"  # Nom de votre VM
BACKUP_DIR="/tmp/vm_backup"
COMPRESS_LEVEL=3

echo "1. Arrêt de la VM..."
if virsh list | grep -q "$VM_NAME"; then
    virsh shutdown $VM_NAME
    while virsh list | grep -q "$VM_NAME"; do
        sleep 5
        echo "Attente de l'arrêt de la VM..."
    done
fi

echo "2. Préparation des répertoires..."
mkdir -p $BACKUP_DIR
ssh $DEST_VPS "mkdir -p $BACKUP_DIR"

echo "3. Sauvegarde des configurations..."
# Sauvegarder directement dans le répertoire
virsh dumpxml $VM_NAME > $BACKUP_DIR/${VM_NAME}.xml
virsh net-dumpxml default > $BACKUP_DIR/network.xml

echo "4. Transfert des configurations..."
scp $BACKUP_DIR/${VM_NAME}.xml $DEST_VPS:$BACKUP_DIR/
scp $BACKUP_DIR/network.xml $DEST_VPS:$BACKUP_DIR/

echo "5. Localisation et transfert du disque VM..."
VM_DISK=$(virsh domblklist $VM_NAME | grep vda | awk '{print $2}')
DISK_SIZE=$(du -h "$VM_DISK" | cut -f1)
echo "Taille du disque VM: $DISK_SIZE"

echo "6. Transfert du disque avec compression..."
if command -v pv >/dev/null 2>&1; then
    pv "$VM_DISK" | gzip -c$COMPRESS_LEVEL | ssh $DEST_VPS "gunzip -c > /var/lib/libvirt/images/${VM_NAME}.qcow2"
else
    echo "Installation de pv pour suivre la progression..."
    apt-get update && apt-get install -y pv
    pv "$VM_DISK" | gzip -c$COMPRESS_LEVEL | ssh $DEST_VPS "gunzip -c > /var/lib/libvirt/images/${VM_NAME}.qcow2"
fi

echo "7. Configuration sur le VPS destination..."
ssh $DEST_VPS << EOF
    echo "7.1 Configuration du réseau..."
    cp $BACKUP_DIR/network.xml /etc/libvirt/qemu/networks/
    virsh net-define $BACKUP_DIR/network.xml
    virsh net-start default 2>/dev/null || true
    virsh net-autostart default
    
    echo "7.2 Définition de la VM..."
    virsh define $BACKUP_DIR/${VM_NAME}.xml
    echo "7.3 Démarrage de la VM..."
    virsh start $VM_NAME
EOF

echo "8. Nettoyage..."
rm -rf $BACKUP_DIR
ssh $DEST_VPS "rm -rf $BACKUP_DIR"

echo "Transfert terminé! Vérification de l'état de la VM:"
ssh $DEST_VPS "virsh list --all | grep $VM_NAME"
