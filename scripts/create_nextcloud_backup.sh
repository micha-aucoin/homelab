#!/bin/bash

kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
    name: nextcloud-db-backup-$(date +"%Y%m%d-%H%M%S")
    namespace: nextcloud
spec:
  cluster:
    name: nextcloud-db
  method: volumeSnapshot
EOF

kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
    name: nextcloud-data-backup-$(date +"%Y%m%d-%H%M%S")
    namespace: nextcloud
spec:
    volumeSnapshotClassName: longhorn-backup-vsc
    source:
        persistentVolumeClaimName: nextcloud-data-pvc
EOF
