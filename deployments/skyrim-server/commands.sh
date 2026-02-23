kubectl apply -f skyrim-deployment.yaml

kubectl rollout restart deployment skyrim-server

kubectl expose deployment skyrim-server --type=NodePort --name=skyrim-service --port=10578 --protocol=UDP

kubectl delete service skyrim-service

kubectl get pods

kubectl logs -f deployment/skyrim-server

kubectl exec -it deployment/skyrim-server -- /bin/bash

kubectl rollout restart deployment skyrim-server

sudo du -sh /var/lib/rancher/k3s/storage/  # Verificar tamanho ocupado pelo volume no Pi
