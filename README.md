# Postgres Forward Pod

## Everything put together in a script `access-db.sh`

Platform provides a script to generate credentials and spin up a forwarding pod, this script is called `access-db.sh`.

For each database to forward a separate config file with the following variables must be created:

```cfg
PROJECT_ID=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
INSTANCE_ID=eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee
KUBE_CONTEXT=dev
NAMESPACE=ris-staging
SUFFIX=janedoe
DATABASE_HOST=10.1.2.3
DATABASE_PORT=5432
DATABASE_LOCAL_PORT=50001
```

To start port forwarding run `./access-db.sh example-database.cfg`.

To end port forwarding simply `ctrl+c` the script.

If you simply wish to use `psql` then you can run `./access-db.sh example-database.cfg database-name` and it will open the `psql` shell for you and as before, once the shell exits, it will delete the temporary user and tear down the pod.

## Deprecated: `db-forward.sh`

All the steps above are combined into the script `db-forward.sh`.

For each database to forward a separate config file with the following variables must be created:

```cfg
KUBE_CONTEXT=dev
NAMESPACE=ris-staging
SUFFIX=janedoe
DATABASE_HOST=10.1.2.3
DATABASE_PORT=5432
DATABASE_LOCAL_PORT=50001
```

To start port forwarding run `./db-forward.sh example-database.cfg up`.

To end port forwarding run `./db-forward.sh example-database.cfg down`.

If you run `./db-forward.sh` without any parameter it does not only show usage information but also lists all processes identified as port forwards.

## Set up a forwarder-pod

At first login to the cluster `dsctl auth kube`.

This will create a new pod with the sole purpose to connect to the database via port forwarding from local to this pod:

```bash
export NAMESPACE=...
# either your name or the context/purpose of your action, e.g. migration.
export SUFFIX=...
# find this value either in the database configuration in Argo CD or via inspecting the output of 'kubectl -n $NAMESPACE describe configmap'
export DATABASE_HOST=...
# default for postgres is 5432, but could be something else
export DATABASE_PORT=...

# OR
cp .env.template .env
# fill in the vars in .env and run:
source .env && export $(cut -d= -f1 .env)

# cd into this repository

# create the pod
envsubst < manifest.yaml | kubectl apply -n $NAMESPACE -f -

# port mapping example: 5000:5432
kubectl port-forward postgres-forward-pod-$SUFFIX $DATABASE_LOCAL_PORT:$DATABASE_PORT -n $NAMESPACE

# check if your pod is up
kubectl get pods -n $NAMESPACE
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
# note the space in front of the following commands is on purpose
# to avoid an entry in the history. Please check afterwards by typing history
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

## Why using a forwarder-pod?

The command `kubectl port-forward` can only connect to pods. The other option to connect by a service is used as a pod selector and does not connect to a service at all. Therefore port-forwarding does not work with services of type `ExternalName` or by using a combination of `Service`and `EndpointSlice`. For details see the following sources:

- <https://stackoverflow.com/questions/51468491/how-kubectl-port-forward-works>
- <https://github.com/txn2/kubefwd/issues/35>
- <https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#create-connect-portforward-pod-v1-core>

## Git Hooks

For the provided Git hooks you will need to install [lefthook](https://github.com/evilmartians/lefthook/blob/master/docs/full_guide.md) (git hook manager) and [talisman](https://thoughtworks.github.io/talisman/docs) (secrets scanner):

```bash
brew install lefthook talisman node
lefthook install
```
