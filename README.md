# Postgres Forward Pod

## Set up a forwarder-pod

This will create a new pod with the sole purpose to connect to the database via port forwarding from local to this pod:

```bash
export NAMESPACE=...
# find this value either in the database configuration in Argo CD or via inspecting the output of 'kubectl -n $NAMESPACE describe configmap'
export DATABASE_HOST=...

# cd into this repository

# create the pod
envsubst < manifest.yaml | kubectl apply -n $NAMESPACE -f -

# port mapping example: 5000:5432
kubectl port-forward postgres-forward-pod <local-port>:<remote-port> -n $NAMESPACE
```

## Connect to the database

Now you need to retrieve the username and password to access the database via the forwarded port:

```bash
# see available secrets
kubectl -n $NAMESPACE get secret
# use the desired secret name to retrieve it
kubectl -n $NAMESPACE get secret <secret-name> -o jsonpath='{.data}'
```

This gives you something like: `{"db.password":"","db.user":""}`, which now needs to be decoded:

```bash
echo "<db.user>" | base64 --decode
echo "<db.password>" | base64 --decode
# note that the last "%" is not part of the decoded string
```

Now you have the credentials and can connect to the database by using the UI in IntelliJ or via command line:

```bash
# 'brew install postgresql' if you don't have psql yet
# example for local-port from above: 5000
PGPASSWORD=<password> psql -U <username> -h localhost -d <databasename> -p <local-port>
```

## Shut down the forwarder-pod

Once you are done, it's important you remember to shut down the pod you created:

```bash
envsubst < manifest.yaml | kubectl delete -n $NAMESPACE -f -
```
