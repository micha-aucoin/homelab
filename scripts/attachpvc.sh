#!/bin/bash

attachpvc() {
  POD=$1
  
  if [ -z "$POD" ]; then
    echo "Error: Pod name is required."
    exit 1
  fi

  PVC=$(kubectl get pod "$POD" -o jsonpath='{.spec.volumes[].persistentVolumeClaim.claimName}')
  
  if [ -z "$PVC" ]; then
    echo "Error: No PVC found in pod $POD."
    exit 1
  fi

  echo "Found PVC: $PVC for pod: $POD"

  kubectl apply -f- <<EOF
kind: Pod
apiVersion: v1
metadata:
  name: attachpvc
spec:
  volumes:
  - name: pvc
    persistentVolumeClaim:
      claimName: $PVC
  containers:
  - name: sh
    image: alpine
    volumeMounts:
    - name: pvc
      mountPath: /pvc
    stdin: true
    tty: true
EOF

  echo "Waiting for pod 'attachpvc' to be ready..."
  kubectl wait --for condition=Ready pod/attachpvc

  echo "Attaching to the pod's shell..."
  kubectl attach -ti attachpvc

  echo "Deleting temporary pod 'attachpvc'..."
  kubectl delete pod attachpvc
}

attachpvc "$1"

