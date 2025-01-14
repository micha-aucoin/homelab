(
    printf '%s\t%s\t%s\t%s\t%s\n' 'Namespace' 'BackupName' 'PVName' 'PVCName'
    kubectl get backups.longhorn.io -A -o=json | jq -r '
        .items[] |
        [
            .metadata.namespace,
            .metadata.name,
            (.spec.labels.KubernetesStatus | fromjson.pvName),
            (.spec.labels.KubernetesStatus | fromjson.pvcName)
        ] | @tsv
    '
) | column -t

