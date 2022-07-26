# Postgres Forward Pod

```bash
export DATABASE_HOST=...
export NAMESPACE=...
export KUBECONFIG=...
envsubst < manifest.yaml | kubectl apply -n $NAMESPACE -f -
kubectl port-forward postgres-forward-pod 5432:5432 -n $NAMESPACE
```

You can now connect using psql:

```bash
PGPASSWORD=... psql -U <database_user> -h localhost -d <database>
```

**Don't forget to shutdown the pod when done:**

```bash
envsubst < manifest.yaml | kubectl delete -n $NAMESPACE -f -
```
